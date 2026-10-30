# InstaSwipe – Specifica iniziale

App personale per ridurre i circa 5.000 account seguiti su Instagram.

## Obiettivo

Passare in rassegna tutti gli account seguiti con uno swipe stile Tinder (destra = tengo, sinistra = tolgo), salvando i progressi in locale per poter interrompere e riprendere in qualsiasi momento. Alla fine l'app genera un report con gli account da smettere di seguire, che verranno rimossi **a mano**.

Nessuno scraping, nessuna API non ufficiale, nessun unfollow automatico.

## Piattaforma e stack

- Swift + SwiftUI, target macOS (eventualmente anche iOS)
- `WKWebView` per mostrare il profilo Instagram reale
- Persistenza locale: SwiftData (oppure un file JSON in Application Support)

## Fonte dati

Export ufficiale di Instagram: Centro gestione account → Le tue informazioni e autorizzazioni → Esporta le tue informazioni → "Follower e persone seguite", formato JSON, intervallo "Sempre".

Dopo aver estratto lo ZIP, il file si trova in:

```
connections/followers_and_following/following.json
```

Il nome può variare (es. `following_1.json`), quindi l'import deve cercare qualsiasi file `following*.json` nella cartella.

Struttura tipica di una voce (può variare tra export):

```json
{
  "relationships_following": [
    {
      "title": "nomeutente",
      "string_list_data": [
        {
          "href": "https://www.instagram.com/nomeutente",
          "value": "nomeutente",
          "timestamp": 1580000000
        }
      ]
    }
  ]
}
```

Il parser deve essere tollerante:
- la radice può essere un oggetto con chiave `relationships_following` oppure direttamente un array
- lo username può stare in `title` o in `string_list_data[0].value`
- se manca `href`, costruirlo come `https://www.instagram.com/<username>`
- `timestamp` è in secondi Unix e può mancare
- le stringhe possono avere caratteri speciali codificati male (mojibake latin1/utf8): gestire la ricodifica

**Prima di scrivere il parser, leggere il file reale fornito dall'utente e adattarsi alla sua struttura.**

## Modello dati

```swift
enum Decision: String, Codable { case pending, keep, remove }

struct FollowedAccount: Codable, Identifiable {
    var id: String { username }
    let username: String
    let profileURL: URL
    let followedSince: Date?
    var decision: Decision = .pending
    var unfollowedManually: Bool = false
    var decidedAt: Date?
}
```

## Funzionalità

### 1. Import

- Selezione del file `following.json` o della cartella dell'export tramite file picker
- Parsing e deduplica per username
- Se esiste già uno stato salvato, unire senza perdere le decisioni prese

### 2. Schermata di swipe

- Una card per account, con una `WKWebView` che carica `profileURL`
- Login a Instagram fatto una sola volta nella WebView (cookie persistenti con `WKWebsiteDataStore.default()`)
- Swipe a destra = keep, swipe a sinistra = remove; su macOS anche frecce destra/sinistra
- Pulsante "Annulla" per tornare all'ultimo account
- Ordine: dal follow più vecchio al più recente
- Barra di avanzamento (es. "1.240 / 5.000")
- Salvataggio automatico dopo ogni decisione
- Opzione "Togli il follow subito" (Impostazioni, spenta di default): scartando un account si apre il suo profilo nella WebView; l'unfollow resta un tap dell'utente su Instagram, poi "Fatto" lo segna come fatto. Ogni apertura conta nel budget dei profili

### 3. Report unfollow

- Elenco degli account con decisione `remove`
- Per ciascuno: username, link cliccabile che apre il profilo, casella "fatto" (`unfollowedManually`)
- Filtro "mostra solo da fare"
- Contatore giornaliero degli unfollow segnati, con avviso oltre ~150 al giorno per evitare blocchi di Instagram
- Esportazione CSV (username, link, data follow, decisione, fatto)

## Vincoli

- Nessuna automazione di click o unfollow nella WebView
- Nessuna richiesta ai server di Instagram oltre al normale caricamento della pagina della card visibile
- Precaricare al massimo la card successiva

## Primi passi

1. Creare il progetto SwiftUI e il modello `FollowedAccount`
2. Leggere il `following.json` reale e scrivere il parser con un test
3. Implementare persistenza locale e ripresa dello stato
4. Costruire la schermata di swipe con la `WKWebView`
5. Costruire il report e l'export CSV
