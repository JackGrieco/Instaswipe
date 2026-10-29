# InstaSwipe – Design

Data: 2026-10-29 · Sostituisce, dove diverge, `InstaSwipe-spec.md` (brainstorming iniziale).

## Perché

Giacomo segue 5.622 account su Instagram e vuole ridurli drasticamente. Farlo dall'app di Instagram è insostenibile: l'interfaccia è scomoda e, soprattutto, **l'ordine della lista dei seguiti cambia da un giorno all'altro**, quindi ogni volta che riprende deve riscrollare fino a dove era arrivato.

InstaSwipe risolve esattamente questo: un ordine fisso, una decisione per account con uno swipe stile Tinder, e la certezza che ogni decisione resti salvata. Gli unfollow veri si fanno **a mano** su Instagram, partendo da un elenco pulito.

## Obiettivi

- Passare in rassegna tutti gli account seguiti, uno per card, in ordine fisso dal follow più vecchio al più recente.
- Decidere con uno swipe: destra = tengo, sinistra = tolgo.
- Interrompere e riprendere in qualsiasi momento esattamente dal punto in cui si era.
- Avere sempre a portata di mano l'elenco "Da togliere", con una spunta manuale "fatto" per ognuno.
- Non superare in modo inconsapevole il limite di circa 150 unfollow al giorno.

## Non-obiettivi

- Nessun unfollow automatico, nessun click automatizzato nella WebView, nessuna API non ufficiale, nessuno scraping massivo.
- Nessuna versione macOS o iPad: **solo iPhone** (decisione di Giacomo).
- Nessun multi-utente o multi-account Instagram, nessun backend.
- Nessuna statistica, categorizzazione automatica o "suggerimento" su chi togliere.

## Anti-obiettivi (cose che renderebbero l'app un fallimento anche se "funziona")

1. **Perdere progressi.** È la cosa più importante di tutta l'app. Testuale: "perdere i progressi dopo aver swipato mille persone… altrimenti lancio il telefono". Nessuna decisione deve andare persa per crash, chiusura forzata, spegnimento, aggiornamento dell'app da Xcode, reimport di un export nuovo o cancellazione dell'app.
2. Un'esperienza più lenta o macchinosa di Instagram stesso (card che si fanno attendere, swipe che litiga con lo scroll).
3. Farsi bloccare l'account da Instagram per comportamento anomalo.

## Vincoli

- Swift + SwiftUI, solo iOS. Giacomo ha un account Apple Developer a pagamento: firma normale, capability iCloud disponibile.
- Richieste a Instagram solo come normale caricamento di pagina: la card visibile più **al massimo la successiva** precaricata.
- Login a Instagram fatto una volta dentro l'app (cookie persistenti tramite `WKWebsiteDataStore.default()`).
- UI in italiano.
- L'export contiene dati personali di terzi: **la cartella `connections/` non va mai committata**, né usata così com'è come fixture dei test (vedi Test).

## Fonte dati: cosa c'è davvero nell'export

Export ufficiale Meta, formato JSON, cartella `connections/followers_and_following/`. Analizzato l'export reale di Giacomo (fatto il 2026-10-28):

- `following.json`: oggetto con chiave `relationships_following`, **6.079 voci**. Ogni voce ha `title` = username e `string_list_data` con **un solo elemento** contenente `href` e `timestamp`. **Non c'è `value`.** Gli `href` sono tutti nel formato `https://www.instagram.com/_u/<username>`. Nessun duplicato, nessun carattere non ASCII. Le date vanno dal 2015-02-06 al 2026-10-27. Le voci sono in ordine **dal più recente al più vecchio**.
- `followers_1.json`: **array** alla radice, 726 voci. Qui `title` è vuoto e lo username sta in `string_list_data[0].value`. 280 account sono reciproci.
- Altri file presenti ma non usati: `close_friends.json`, `recently_unfollowed_profiles.json`, `pending_follow_requests.json`, ecc.

**Discrepanza nota:** l'export elenca 6.079 seguiti, ma Instagram ne mostra 5.622. L'ipotesi è che i circa 450 di differenza siano account cancellati o disattivati, che restano nell'export ma non vengono contati.

Il parser resta tollerante come chiedeva la spec iniziale: radice oggetto o array; username da `title` oppure da `string_list_data[0].value`; `href` ricostruito se manca; `timestamp` opzionale; correzione del mojibake latin1→utf8 (non serve su questo export, ma costa poco). Cerca tutti i file `following*.json` e `followers*.json` (l'export può spezzarli in `_1`, `_2`, …).

**Foto profilo e nome non sono nell'export.** Arrivano dalla pagina del profilo (vedi Card).

## Modello dati

Estende quello della spec iniziale:

```swift
enum Decision: String, Codable { case pending, keep, remove }
enum Availability: String, Codable { case unknown, available, unavailable }

struct FollowedAccount: Codable, Identifiable {
    var id: String { username }
    let username: String
    let profileURL: URL            // forma _u/, apre l'app Instagram
    let followedSince: Date?
    var followsMe: Bool            // da followers*.json
    var displayName: String?       // letto dalla pagina profilo
    var availability: Availability
    var decision: Decision
    var decidedAt: Date?
    var unfollowedManually: Bool
    var unfollowedAt: Date?        // per il contatore giornaliero
    var stillInLatestExport: Bool  // false se sparito da un export successivo
}
```

Lo stato completo (account più metadati, tra cui la data di salvataggio e la versione dello schema) è un unico documento JSON, circa 1–2 MB.

## Persistenza (il cuore dell'app)

Requisito: dopo ogni decisione, prima di mostrare la card successiva, lo stato è su disco. Requisiti concreti:

- **Scrittura atomica** (file temporaneo + rename) dopo ogni decisione, ogni spunta "fatto", ogni annulla e ogni import. Un'interruzione a metà lascia la versione precedente intatta.
- **Due copie**: una locale in Application Support e una in **iCloud Drive**, in una cartella "InstaSwipe" visibile dall'app File (approvato da Giacomo). La copia iCloud è ciò che sopravvive alla cancellazione dell'app.
- **All'avvio**: se la copia locale manca o è illeggibile, si ripristina da iCloud. Se ci sono entrambe, si usa la più recente in base alla data di salvataggio interna. *(Scelta mia: un solo dispositivo, quindi non serve una vera risoluzione dei conflitti.)*
- **Copie di sicurezza a rotazione** nella cartella iCloud `Backups/`: una al giorno (tenute 14) più una ogni 100 decisioni (tenute 10). *(Numeri scelti da me.)*
- Formato JSON leggibile e versionato (`schemaVersion`), così lo stato si può ispezionare e recuperare anche a mano.
- Se iCloud non è disponibile (non loggato, disattivato), l'app funziona comunque in locale e mostra un avviso discreto ma persistente: "Le copie su iCloud sono disattivate".

## Schermate

Tre aree, raggiungibili sempre da una tab bar in basso: **Swipe**, **Da togliere**, più l'esportazione (vedi sotto). Prima di queste, alla prima apertura, c'è un piccolo percorso di avvio.

### Primo avvio

1. **Import**: si sceglie dall'app File la cartella dell'export (quella che contiene `followers_and_following/`, o la cartella stessa). Va bene anche selezionare direttamente i file JSON.
2. **Login a Instagram**: una WebView visibile su instagram.com per il login, fatto una sola volta. I cookie restano.
3. Si parte dalla prima card.

Dalle impostazioni si può **reimportare** un export più recente in qualsiasi momento.

### Reimport (merge)

Mai perdere decisioni. Il reimport avviene in **due passi** (*scelta mia*): prima l'app calcola il risultato e mostra un riepilogo ("N nuovi, M non più seguiti, K segnati come fatti"), poi lo applica solo dopo conferma. Prima di applicarlo salva una copia di sicurezza dedicata. Se l'export nuovo fa sparire più del 20% degli account attuali (per esempio un export con intervallo diverso da "Sempre"), il riepilogo lo segnala in modo evidente come probabile export incompleto.

Limite accettato: l'export non ha un ID stabile, quindi un account che ha **cambiato username** viene visto come uno sparito più uno nuovo `pending`. Il nuovo ricompare nello swipe e lo rivaluti. Il vecchio, se era `remove`, viene segnato fatto. Lo considero accettabile.

Regole:

- Account nuovi: aggiunti come `pending` al loro posto nell'ordine cronologico.
- Account già presenti: decisione, spunta e date restano invariate. `followsMe` viene aggiornato dal nuovo file dei follower.
- Account con `remove` che **non compaiono più** nel nuovo export: segnati automaticamente come `unfollowedManually = true` (*idea mia*), con `unfollowedAt` = data dell'import (non conta nel contatore di "oggi").
- Altri account che non compaiono più: `stillInLatestExport = false`, nascosti dallo swipe ma conservati.

### Swipe (design C, scelto da Giacomo)

Card essenziale, disegnata dall'app:

- In alto: contatore "1.240 / 5.622" più barra di avanzamento. Il totale è il numero di account da valutare, esclusi quelli "Spariti" e quelli non più nell'export.
- Card: **foto profilo grande**, **nome**, `@username`, "Lo segui dal …", etichetta **"Ti segue"** se reciproco. È solo un'etichetta: chi ti segue non viene trattato diversamente (decisione di Giacomo: "magari uno mi segue ma mi sta comunque sul cazzo").
- Sotto: ✕ (tolgo), ↺ (annulla), ♥ (tengo). Swipe sinistra/destra = ✕/♥.
- Tocco sulla card: si apre la pagina vera del profilo (WebView a schermo intero, chiudibile) per guardare meglio.
- **Annulla**: torna indietro di una decisione alla volta, anche più volte, risalendo in ordine di `decidedAt`. Lo stato annullato torna `pending` ed è salvato subito.
- Ordine: dal follow più vecchio al più recente, sempre lo stesso. Si riparte dal primo `pending` in quell'ordine.
- Quando i `pending` finiscono: schermata di fine con il riepilogo (tenuti / da togliere / spariti) e un invito ad andare su "Da togliere".

**Da dove arrivano foto e nome** (*scelta mia, approvata implicitamente col design C*): una `WKWebView` nascosta carica `https://www.instagram.com/<username>/` con la sessione dell'utente. A caricamento finito, l'app legge dalla pagina (solo lettura, nessun click) l'immagine profilo e il nome visualizzato, per esempio dai meta tag `og:image` e `og:title`. La tecnica precisa va verificata sul dispositivo reale perché Instagram può cambiarla. Si precarica solo la card successiva.

**Fallback obbligatorio**: se non si riescono a leggere foto e nome entro un tempo ragionevole, la card mostra comunque `@username`, la data del follow e "Ti segue", con un segnaposto al posto della foto. Il tocco apre comunque la pagina vera. Lo swipe non resta mai bloccato in attesa di Instagram.

**Account spariti** (*idea mia*): se la pagina è quella di "pagina non disponibile", l'account viene marcato `unavailable`, saltato senza chiedere niente e finisce nel filtro "Spariti" di "Da togliere". Precisazioni (*scelte mie*):

- Il riconoscimento deve essere **rigoroso**: si marca `unavailable` solo su un segnale positivo e specifico della pagina "non disponibile". Tutti gli altri casi (errore di rete, timeout, "riprova più tardi", pagina di login, HTML irriconoscibile) **non** marcano niente e mostrano la card di fallback.
- "Spariti" non è un verdetto definitivo. Un account `unavailable` mantiene `decision = pending`. Dal filtro "Spariti" si può decidere tengo/tolgo direttamente sulla riga, oppure "Riprova", che lo riporta a `unknown` e lo rimette nello swipe al suo posto.
- A ogni reimport gli account `unavailable` ancora presenti nell'export tornano `unknown`, così vengono ricontrollati alla prossima visita.

**Ritmo verso Instagram** (decisione di Giacomo: "non vorrei essere bannato", quindi tetto giornaliero):

- **Tetto giornaliero di caricamenti profilo**, predefinito **400 al giorno**, modificabile nelle impostazioni. Contano tutti i caricamenti di pagine profilo, precaricamenti e aperture a schermo intero compresi. Il contatore (data più numero) è persistito insieme allo stato, così chiudere e riaprire l'app non lo azzera.
- L'avanzamento mostra anche "Profili oggi: 312 / 400".
- **Raggiunto il tetto**, l'app smette di caricare profili e mostra "Per oggi basta, riprendi domani". Un pulsante secondario, con conferma, permette di continuare con le card di solo @username, senza caricare altro da Instagram (*scelta mia*). Non c'è modo di superare il tetto continuando a caricare profili, se non alzandolo dalle impostazioni.
- **Freno d'emergenza**: se una pagina caricata è di tipo "riprova più tardi", limitazione o verifica di sicurezza, l'app smette subito di caricare profili per il resto della giornata, indipendentemente dal tetto, e lo dice chiaramente.
- Con 400 al giorno i circa 5.600 account si finiscono in circa due settimane.

Le miniature lette durante lo swipe vengono salvate in locale (Caches o Application Support, piccole), per usarle nell'elenco senza ricaricare Instagram. Non vanno su iCloud: si possono sempre rigenerare.

Se la sessione Instagram scade (la pagina caricata è quella di login), l'app lo dice e mostra la WebView di login.

### Da togliere (sempre accessibile, chiesto da Giacomo)

- In alto: **"Oggi: N unfollow segnati"**. Oltre 150 diventa un avviso ben visibile, ma non blocca niente. Il conteggio usa `unfollowedAt` nel giorno locale corrente.
- Filtri: **Da fare** · **Fatti** · **Spariti**, con conteggi.
- Riga: miniatura, nome, `@username`, "ti segue" se vero, cerchio di spunta manuale.
- Tocco sulla riga: apre `profileURL` (forma `_u/`), che su iPhone apre direttamente l'app Instagram sul profilo.
- **Al ritorno nell'app** dopo aver aperto un profilo (*idea mia*): un foglio chiede "Hai tolto il follow a @…?" con *Sì, segna come fatto* · *Non ancora* · *Ho cambiato idea, lo tengo* (la decisione diventa `keep`).
- La spunta si può togliere: `unfollowedManually = false`, `unfollowedAt = nil`.
- **Cambiare idea su una decisione vecchia** (*scelta mia*): oltre ai tre filtri c'è un quarto filtro **Tenuti** e un campo di ricerca per username o nome su tutti gli account decisi. Su ogni riga si può cambiare la decisione (tengo ↔ tolgo, o rimettere `pending`). Annulla (↺) nello swipe agisce solo sulle decisioni prese dallo swipe, in ordine di `decidedAt`. Una modifica fatta dall'elenco aggiorna `decidedAt` e diventa quindi l'ultima da annullare.

### Esportazione CSV

Pulsante di condivisione (share sheet) con colonne: `username, link, data follow, decisione, fatto, ti segue`. *(Scelta mia: pulsante nella barra di "Da togliere" invece di una terza tab; i mockup mostravano una tab, va bene in entrambi i modi.)*

## Test

Seguendo le regole di Giacomo (TDD, copertura ≥ 80%), le priorità sono:

1. **Persistenza**: salva → "uccidi" → ricarica, stato identico. Scrittura interrotta → resta la versione precedente. Copia locale mancante → ripristino da iCloud (con il percorso iCloud simulato). Rotazione dei backup.
2. **Merge del reimport**: nessuna decisione persa; regole su account nuovi, spariti e `remove` scomparsi.
3. **Parser**: entrambe le forme (`following` come oggetto con `title`, `followers` come array con `value`), campi mancanti, mojibake, più file `_1`/`_2`. Le fixture sono **piccole e sintetiche**, con la stessa struttura dell'export reale ma username inventati.
4. Logica di swipe e annulla, contatori giornalieri (unfollow e caricamenti profilo, con cambio di giorno), tetto e freno d'emergenza, CSV.
5. Lettura di foto e nome dalla pagina: testata su HTML di esempio salvato. La verifica vera si fa a mano sul dispositivo.

## Cosa resta al costruttore

- Architettura interna, nomi dei tipi, struttura dei file (rispettando file piccoli e immutabilità dove ha senso).
- Versione minima di iOS (suggerimento: iOS 17, per `@Observable`).
- Animazioni dello swipe, haptics, colori, icona.
- Timeout del fallback della card e tecnica esatta per leggere foto e nome dalla pagina.
- Come mostrare l'avviso di iCloud disattivato e la sessione scaduta.

## Igiene del repository

- `.gitignore` con `connections/`, `.superpowers/` e i soliti file di Xcode e macOS (`.DS_Store`, `xcuserdata/`, `DerivedData/`).
