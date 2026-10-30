# Modalità Follower – Design

Data: 2026-10-30 · Estende `2026-10-29-instaswipe-design.md` (Swipe, Report unfollow, Import).

## Perché

Oggi InstaSwipe ripulisce solo chi *segui*. È arrivata la richiesta di fare lo stesso con chi *ti segue*: il caso tipico è un profilo privato che negli anni ha accettato richieste di persone che ora non vuole più tra i follower. Su Instagram toglierle una alla volta dalla lista follower è faticoso; con InstaSwipe si scorrono a carte come già si fa con i following.

## Obiettivi

- Una seconda modalità, **Follower**, che riusa tutto il flusso esistente (swipe, "ho il dubbio", annulla, lista "da togliere", CSV) sulla lista di chi ti segue.
- Passare da una modalità all'altra con un controllo a due segmenti **Following / Follower** in alto, sia nello swipe sia nella lista "da togliere".
- Le due liste restano collegate tramite lo username: rimuovere qualcuno dai follower aggiorna la sua carta Following (perde "ti segue").

## Non-obiettivi

- Nessuna rimozione automatica: come per l'unfollow, "Rimuovi follower" resta un tap dell'utente su Instagram (vincolo dello spec principale: niente automazione, niente API non ufficiali).
- Nessun redesign grafico: la UI definitiva verrà rifinita in seguito con Claude Design. Qui basta una UI funzionale coerente con il design system attuale (`Theme`, `Components`).
- Nessuna analisi del tipo "follower fantasma" (like, interazioni): l'unico dato è l'export.

## Anti-obiettivi

- Una decisione presa in una modalità che cambia la decisione dell'altra. L'unico effetto incrociato ammesso è il flag "ti segue" / "lo segui" descritto sotto.
- Perdere o corrompere lo stato esistente: i file `state.json` scritti dalle versioni precedenti devono continuare a decodificarsi (`Fixtures/state-v1.json`).
- Esporre di più l'account a blocchi di Instagram: le rimozioni contano nello stesso avviso giornaliero degli unfollow.

## Comportamento

### Dati e import

- L'export contiene già i file `followers*.json` e `ExportLocator` li trova. Oggi `ExportParser.parseFollowers` restituisce solo gli username e scarta il timestamp: va invece tenuto, perché è la data in cui la persona ha iniziato a seguirti.
- Lo stato salva una seconda lista, quella dei follower (in un file a parte, vedi "Protezione dalle build vecchie"), con per ognuno: username, link al profilo, "ti segue dal", decisione, data decisione, "fatto" (rimosso a mano) con data, presenza nell'ultimo export, disponibilità e nome visualizzato.
- **Ordine delle carte follower**: dal più vecchio al più recente per "ti segue dal", stessa regola di `AppState.reviewOrdered` (date mancanti in fondo, parità per username).
- **Reimport**: stessa logica di `MergeEngine` per i following, senza mai buttare decisioni. Chi non compare più tra i follower esce dalla pila (`stillInLatestExport = false`); se era segnato "tolgo" e non ancora fatto, viene segnato fatto automaticamente, come succede oggi con gli unfollow.
- **Chi torna a seguirti dopo essere stato rimosso** (deciso dall'utente): se una persona segnata "tolgo" e fatta ricompare in un export successivo con "ti segue dal" **successivo** alla data in cui è stata segnata rimossa, è un follower nuovo. Torna in pila come da decidere, la spunta "fatto" si azzera e la sua carta Following riprende "ti segue". Se invece la data non è successiva (export richiesto prima della rimozione) o manca, resta rimossa e fatta. Questa regola vale solo per i follower: i following mantengono la logica attuale di `MergeEngine.refreshed`.
- *(Mia scelta)* Se l'export importato **non contiene** file follower, la lista follower salvata resta com'è: non va interpretato come "non ti segue più nessuno". Per lo stesso motivo restano invariati anche i "ti segue" delle carte Following. Oggi `MergeEngine` li azzera tutti in questo caso: va corretto.
- Il riepilogo dell'import (`MergeSummaryView`) aggiunge le righe per i follower: nuovi follower, chi non ti segue più, quanti segnati fatti in automatico. *(Mia scelta)* L'avviso "import sospetto" si calcola anche per i follower, con la stessa soglia `Limits.reimportSuspiciousRatio`.
- **Stati esistenti senza lista follower**: chi aggiorna l'app ha già i following ma nessun follower salvato (il timestamp non era mai stato tenuto). In modalità Follower, con la lista vuota, si mostra un invito a reimportare l'export, con un pulsante che porta al reimport già presente nelle Impostazioni.
- Gli stati vecchi devono continuare a decodificarsi (`Fixtures/state-v1.json`).

### Protezione dalle build vecchie (deciso dall'utente)

- Un dispositivo con una build precedente, collegato allo stesso iCloud, non deve poter cancellare i dati dei follower. Oggi lo farebbe: decodifica `state.json` ignorando i campi che non conosce, poi lo risalva, e `FileStateStore.load` sceglie la copia con il `savedAt` più recente.
- Approccio deciso: i dati dei follower vivono **in un file separato** (es. `followers.json`) accanto a `state.json`, che le build vecchie non leggono e non scrivono. Il file segue le stesse regole di `state.json`: scrittura atomica, copia locale + mirror iCloud con scelta della più recente, quarantena se corrotto, backup giornalieri / a passi / pre-import, ripristino da backup.
- Un ripristino da backup riporta entrambi i file allo stesso momento, così le due liste restano coerenti.
- Le modifiche fatte da una build vecchia ai following restano valide. Per questo, ciò che collega le due liste ("ti segue" quando una persona è stata rimossa dai follower) non deve dipendere da un valore che una build vecchia può sovrascrivere in `state.json`: va ricalcolato dal file follower.
- Test: uno stato scritto "da una build vecchia" (senza follower) caricato insieme a un `followers.json` esistente non perde nessuna decisione sui follower.

### Collegamento tra le due liste (per username)

- Nella carta e nella riga Following, "ti segue" vale **falso** se la persona è stata segnata fatta (rimossa) nella lista follower. Togliendo la spunta "fatto", torna vero se la persona è ancora nell'ultimo export follower.
- *(Mia scelta, per simmetria)* Nella modalità Follower ogni carta mostra "lo segui", vero se la persona è nella lista following, è nell'ultimo export e non è segnata come unfollow fatto.
- Il filtro "Solo chi non ti segue" in modalità Following tiene conto di questo aggiornamento: chi hai appena rimosso dai follower ci rientra.
- *(Mia scelta)* Disponibilità e nome visualizzato sono proprietà del profilo, non della lista: quando un caricamento li scopre, valgono per entrambe le liste. Un profilo sparito è sparito ovunque.

### Selettore di modalità

- Controllo a due segmenti **Following / Follower** in cima allo swipe e in cima alla lista "da togliere".
- *(Mia scelta)* La modalità è **una sola per tutta l'app**: cambiandola nello swipe si cambia anche nella lista, e viceversa. È una preferenza di vista e si salva in `UserDefaults`, come `swipeScope`, fuori da `AppState` e dal mirror iCloud.

### Swipe in modalità Follower

- Stessi gesti: tengo / tolgo / ho il dubbio, e coda dei dubbi in fondo come oggi.
- Progresso, "annulla" e coda sono **separati per modalità**: annullare in Follower riporta indietro solo l'ultima decisione presa sui follower.
- Filtro **"Solo chi non segui"** (il corrispettivo di "Solo chi non ti segue"): mostra solo i follower che non ricambi. *(Mia scelta)* Ogni modalità ricorda il suo filtro separatamente.
- La carta mostra "ti segue dal …" al posto della data di follow e il badge "lo segui" quando serve.
- Le carte follower caricano il profilo come quelle following e consumano lo **stesso budget giornaliero di profili**.
- La schermata "hai finito" e i contatori (tenuti / da togliere / spariti) si riferiscono alla modalità attiva.

### "Togli subito"

- L'interruttore "Togli il follow subito" nelle Impostazioni vale per entrambe le modalità. *(Mia scelta)* Etichetta e spiegazione vanno rese generiche (es. "Togli subito": "scartando un account si apre il suo profilo per togliere il follow o rimuoverlo dai follower").
- **La rimozione si fa solo dall'app di Instagram** (verificato dall'utente: nella WebView di `instagram.com` la voce «Rimuovi follower» non c'è; nell'app sta in profilo → ⋯ → «Rimuovi follower»).
- Quindi, in modalità Follower, uno swipe "tolgo" con "Togli subito" acceso **non** apre la WebView né `UnfollowBar`. Apre il profilo nell'app di Instagram (il link `_u/` in `profileURL`, come fa già la lista "da togliere"), e al ritorno in InstaSwipe compare la domanda "L'hai rimosso?" (`ReturnPromptSheet`, stesso meccanismo di ritorno di `ReportSession`). "Sì" la segna come fatta, e quindi la carta Following perde "ti segue". "Ho cambiato idea" la segna "tengo". Chiudere la domanda la lascia "da fare".
- *(Mia scelta)* Aprire l'app di Instagram non consuma il budget dei profili, perché non è un caricamento fatto da InstaSwipe. Oggi infatti la lista "da togliere" non lo conta.
- Il testo nelle Impostazioni deve dire che, per i follower, si apre l'app di Instagram.
- In modalità Following non cambia nulla: WebView + `UnfollowBar` come oggi.
- **Chiudi senza Fatto** (richiesta aggiunta il 2026-10-30): in modalità Following, se dalla pagina profilo aperta da "Togli subito" si esce con "Chiudi" invece di "Fatto", lo swipe si annulla. L'account torna da decidere e la sua carta ricompare subito davanti, come dopo "Annulla", perché probabilmente il follow non è stato tolto.

### Lista "da togliere" in modalità Follower

- Stessi filtri (Da fare, Dubbi, Fatti, Spariti, Tenuti), ricerca, casella "fatto" e apertura del profilo, sulla lista follower.
- Testi adattati: "L'hai rimosso?" al posto di "Hai tolto il follow?", "Fatto" = rimosso dai follower.
- CSV: esporta la lista della modalità attiva. *(Mia scelta)* Per i follower il file si chiama `InstaSwipe-follower-AAAA-MM-GG.csv`, con colonne `username,link,ti segue dal,decisione,fatto,lo segui`. Il CSV dei following resta identico a oggi.

### Limite giornaliero

- L'avviso oltre `Limits.dailyUnfollowWarning` (150) vale sulla **somma** di unfollow e rimozioni segnati oggi. Il contatore lo dice in modo neutro (es. "Oggi: N azioni segnate") sia nella lista sia nella barra di "Togli subito" dei following.

## Vincoli

- Swift/SwiftUI, logica pura in `InstaSwipeKit` con test, come il resto del progetto. Stato immutabile: le funzioni restituiscono un nuovo `AppState` (pattern di `Review` e `Report`).
- Niente duplicazione della logica di coda, progresso, annulla e report: va riusata per entrambe le liste, non copiata.
- Nessuna richiesta a Instagram oltre al caricamento della pagina della carta visibile e della successiva (vincolo dello spec principale).
- TDD, copertura almeno 80% sulla logica nuova; un UI test per il cambio di modalità (stile `InstantUnfollowFlowTests`).

## Lasciato a chi costruisce

- Come rappresentare i follower nel modello: un tipo nuovo, o un tipo comune ai due elenchi, e come rendere `Review` / `Report` / `MergeEngine` generici sulla lista. Vincoli: niente copia-incolla, stati vecchi sempre decodificabili, follower in un file separato.
- Se "ti segue" / "lo segui" restano campi salvati, ricalcolati a ogni modifica, oppure vengono derivati al volo dall'altra lista. Conta solo il comportamento descritto sopra.
- Testi esatti di etichette e messaggi, purché in italiano e nel tono dell'app.
- Aspetto del selettore e della carta follower, in attesa del passaggio con Claude Design.
