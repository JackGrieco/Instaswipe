# Onboarding: tutorial per l'export di Instagram – Design

Data: 2026-10-29 · Estende `2026-10-29-instaswipe-design.md` (sezione Import).

## Perché

Oggi `ImportView` riassume l'export di Instagram in tre righe ("Centro gestione account → Esporta", "«Follower e persone seguite» · JSON", "Estrai lo ZIP e scegli la cartella"). Sono troppo poche: chi non ha mai fatto un export di Meta non sa dove toccare, sceglie il formato sbagliato (HTML), l'intervallo sbagliato, o esporta tutto e aspetta un archivio enorme.

L'obiettivo di Giacomo: un tutorial **preciso**, passo per passo, con i nomi esatti dei menu di Instagram, "così nessuno ha dubbi". Si parte da Instagram aperto e si arriva alla prima card da swipare.

## Obiettivi

- Guidare un utente nuovo dall'app Instagram fino all'import riuscito in InstaSwipe, senza ambiguità su quale voce toccare.
- Mostrare per ogni passo uno screenshot reale di Instagram, sempre in vista mentre si leggono i passi.
- Gestire l'attesa dell'email di Meta: chi chiude l'app dopo aver avviato l'export, alla riapertura **riparte dal passo 12**.
- Poter riaprire il tutorial completo anche dopo il primo import, per fare un export nuovo.

## Non-obiettivi

- Nessuna automazione dell'export, nessuna WebView sul Centro gestione account: l'utente fa tutto nell'app Instagram.
- Nessun video o animazione: screenshot statici.
- Solo italiano, come il resto dell'app.
- Nessuna rilevazione automatica di "email arrivata" o "ZIP scaricato".

## Anti-obiettivi

- Un tutorial vago o generico ("vai nelle impostazioni ed esporta i dati"): è proprio quello che c'è oggi e che si vuole superare.
- Perdere il punto di ripresa: chi torna con lo ZIP pronto e si ritrova al passo 1 deve riscorrere tutto per niente.
- Rompere l'import attuale: conferma del primo import con iCloud, avviso iCloud spento, riepilogo del merge e reimport dalle Impostazioni devono continuare a funzionare come oggi.

## Contenuto: i 14 passi

Il testo è quello di Giacomo. Ho solo sistemato i refusi e messo i nomi dei menu tra «». *(La rifinitura del testo è una mia scelta, i contenuti no.)*

| # | Testo del passo |
|---|---|
| 1 | Apri Instagram, vai sul tuo profilo e tocca le tre righe ☰ in alto a destra |
| 2 | Tocca «Account Meta» |
| 3 | Tocca «Le tue informazioni e autorizzazioni» |
| 4 | Tocca «Esporta le tue informazioni» |
| 5 | Tocca «Crea esportazione» e scegli il tuo profilo Instagram |
| 6 | Scegli «Esporta sul dispositivo» |
| 7 | In «Personalizza informazioni» deseleziona tutto tranne «Follower e persone/Pagine seguite» |
| 8 | In «Intervallo di date» scegli «Sempre» |
| 9 | In «Formato» scegli «JSON» |
| 10 | In «Qualità dei contenuti multimediali» scegli «Qualità inferiore» |
| 11 | Tocca «Avvia esportazione» e aspetta l'email di conferma di Meta |
| 12 | Quando arriva l'email, scarica il file ZIP e aprilo (estrailo) dall'app File |
| 13 | Torna in InstaSwipe, scegli la cartella estratta e tocca «Apri» |
| 14 | Comincia a swipare! |

## Struttura: 4 fasi

Una schermata per fase (opzione "B1" scelta sui mockup):

| Fase | Titolo | Passi |
|---|---|---|
| 1 | Apri l'esportazione | 1–6 |
| 2 | Scegli cosa esportare | 7–10 |
| 3 | Aspetta l'email | 11 |
| 4 | Importa | 12–14 |

### Layout di una fase

Dall'alto verso il basso:

1. "Fase X di 4" (monospaziato, stile delle etichette `01`/`02` attuali) e barra di avanzamento con il gradiente del brand.
2. Titolo della fase.
3. **Screenshot del passo corrente**, grande, sempre visibile. Si scorre orizzontalmente tra gli screenshot della fase, con gli indicatori a pallini sotto.
4. Lista dei passi della fase. Il passo corrente è evidenziato (sfondo rosa tenue, numero rosa). Scorrere lo screenshot cambia il passo evidenziato. Toccare un passo porta lo screenshot su quel passo.
5. In basso: pulsante principale con il gradiente (`GradientButtonStyle`) per andare alla fase successiva, e "Indietro" per tornare alla precedente (dalla fase 2 in poi).

*(Mia scelta)* "Avanti" porta alla fase successiva, non al passo successivo: dentro una fase ci si muove scorrendo gli screenshot o toccando i passi. Se la lista di una fase non sta tutta nello schermo, la schermata scorre in verticale.

Stile: token "Aura" di `Theme` e font Outfit, come `ImportView`. Il bagliore rosa/viola di sfondo si può riusare.

### Fase 3: l'attesa

Contiene solo il passo 11. *(Mia scelta)* Sotto il passo c'è una riga che spiega che l'email può arrivare anche dopo ore e che si può chiudere l'app: alla riapertura si riparte dal passo 12. Il pulsante principale dice qualcosa come "È arrivata l'email" e porta alla fase 4.

### Fase 4: l'import

La fase 4 **sostituisce l'attuale `ImportView`**. Sotto la lista dei passi 12–14 restano, invariati:

- il pulsante "Scegli cartella o file JSON" (con la conferma "Non ho trovato progressi su iCloud. Importare da zero?" quando serve);
- l'avviso rosso "iCloud è spento…" quando iCloud non è disponibile;
- il foglio `MergeSummaryView` e gli errori di import.

Il passo 14 non ha un'azione propria: è il risultato dell'import riuscito, che porta alle card come oggi.

*(Mia scelta)* Nella fase 4 c'è anche un link discreto "Rivedi il tutorial dall'inizio", che porta alla fase 1. Serve a chi riapre l'app al passo 12 ma non aveva finito davvero l'export.

## Punto di ripresa

- Appena l'utente arriva alla fase 3, l'app memorizza che l'export è stato avviato. *(Mia scelta)* Aprire la fase 3 conta già come export avviato, perché ci si arriva solo dopo aver configurato l'export nella fase 2. È più semplice e più robusto che aspettare un tocco esplicito, che si perderebbe se l'utente chiude l'app nell'attesa.
- Alla riapertura, se l'export risulta avviato, il tutorial si apre direttamente sulla **fase 4**, con il passo 12 evidenziato.
- *(Mia scelta)* Il punto di ripresa vale **sia per il primo export sia per un nuovo export avviato dalle Impostazioni**: anche lì si aspetta l'email per ore. Chi ha già uno stato importato all'avvio va comunque alle card come oggi. Il punto di ripresa conta solo quando il tutorial viene aperto, dal primo avvio o dalle Impostazioni.
- *(Mia scelta)* Il punto di ripresa si **azzera dopo ogni import confermato** (conferma nel `MergeSummaryView`) e quando si sceglie "Rivedi il tutorial dall'inizio". Tornare indietro dalla fase 3 o 4 con "Indietro" non lo azzera.
- *(Mia scelta)* Il punto di ripresa è una preferenza **locale del dispositivo** (`UserDefaults` / `@AppStorage`), non fa parte di `AppState`. `AppState` esiste solo dopo il primo import ed è copiato su iCloud, mentre questo è un dettaglio di interfaccia. Se si reinstalla l'app si riparte dalla fase 1, e va bene così.

## Quando si vede il tutorial

- **Primo avvio senza stato** (`RootScreen.importer`): il tutorial al posto dell'attuale `ImportView`, sulla fase 1 oppure sulla 4 se l'export era già stato avviato.
- **Dalle Impostazioni:** *(mia scelta)* nella sezione dove c'è "Reimporta export" si aggiunge "Come esportare da Instagram", che apre il tutorial come foglio dalla fase 1, oppure dalla fase 4 se c'è un export avviato (vedi Punto di ripresa). La fase 4 aperta da qui usa lo stesso picker e lo stesso flusso di `MergeSummaryView` del reimport attuale. Il "Reimporta export" diretto resta per chi ha già lo ZIP pronto.
- *(Mia scelta)* **Dopo un import riuscito dal tutorial aperto dalle Impostazioni** si chiudono il tutorial e le Impostazioni e si torna alle card: è il passo 14, "Comincia a swipare!". Il "Reimporta export" diretto continua invece a lasciare aperte le Impostazioni, come oggi. Il costruttore decide chi gestisce il picker e il foglio del merge e in che ordine si chiudono i fogli, ma ci deve essere un solo `MergeSummaryView` presentato alla volta.
- Nella prima schermata (fase 1) restano logo e wordmark sopra la barra di avanzamento, per chi apre l'app per la prima volta. *(Mia scelta)*

## Screenshot

- **Li fa Giacomo** dal suo iPhone, con Instagram in italiano. *(Mia scelta)* **Esattamente uno per passo**, quindi il carosello ha tante pagine quanti passi:
  - 1–10: la schermata di Instagram con la voce da toccare;
  - 11: la schermata di Instagram con «Avvia esportazione» (non l'email);
  - 12: l'app File con lo ZIP estratto;
  - 13: il selettore di InstaSwipe con la cartella e «Apri»;
  - 14: niente screenshot di Instagram, si mostra il logo o una card di InstaSwipe (scelta del costruttore).
- Vanno nell'asset catalog con i nomi `TutorialStep01` … `TutorialStep13`, così si sostituiscono senza toccare il codice quando Instagram cambia i menu.

### Screenshot ricevuti (2026-10-29)

Giacomo ha fornito 9 screenshot (`~/Desktop/Screen`, 1320×2868, Centro gestione account aperto nel browser interno di Instagram). Abbinamento:

| Passo | File | Schermata |
|---|---|---|
| 5 | `IMG_7744` | «Esporta le tue informazioni» con il pulsante «Crea esportazione» |
| 6 | `IMG_7745` | «Scegli dove effettuare l'esportazione» |
| 7 | `IMG_7747` | «Personalizza informazioni», solo «Follower e persone/Pagine seguite» spuntato |
| 8 | `IMG_7748` | «Intervallo di date» su «Sempre» |
| 9 | `IMG_7749` | «Formato» su «JSON» |
| 10 | `IMG_7750` | «Qualità dei contenuti multimediali» su «Qualità inferiore» |
| 11 | `IMG_7746` | «Conferma la tua esportazione» (il pulsante «Avvia esportazione» è più in basso, fuori dallo screenshot) |
| 12 | `IMG_7751` | «Scarica i tuoi file» con «Download» |

- *(Mia scelta)* Il passo 12 mostra la pagina di download di Meta invece dell'app File: è lo screenshot disponibile e corrisponde alla prima metà del passo.
- *(Mia scelta)* `IMG_7743` («Scegli un profilo») **non si usa**: contiene nome e cognome, numero di telefono e altri account. Il passo 5 ha già `IMG_7744`.
- **Mancano ancora** i passi 1–4 (profilo e ☰, «Account Meta», «Le tue informazioni e autorizzazioni», «Esporta le tue informazioni») e 13 (selettore di InstaSwipe). Al loro posto c'è il riquadro neutro finché non arrivano.
- **Oscuramento:** le copie messe nell'app coprono la foto profilo e lo username `giacomogrieco_` (7744, 7745, 7746, 7748, 7749, 7750, 7751), l'indirizzo email di terzi in 7746 e il riquadro «Download disponibili» con l'export già fatto in 7744. Si taglia anche la barra di stato. Gli originali in `~/Desktop/Screen` non si toccano.
- **Finché uno screenshot manca**, al suo posto si mostra un riquadro neutro (superficie `Theme.surface2`, numero del passo al centro), così il tutorial si può costruire e provare subito, prima che arrivino le immagini.
- **Privacy:** gli screenshot finiscono nell'app distribuita via TestFlight. Prima di aggiungerli, Giacomo deve coprire o ritagliare username, foto profilo, email e nomi di terzi.
- Ogni screenshot ha un'etichetta di accessibilità uguale al testo del passo.

## Vincoli

- Swift 6, SwiftUI, iOS 17+, solo iPhone (`project.yml`).
- Nessun cambiamento al formato di `AppState` né alla logica di import, merge e persistenza di `InstaSwipeKit`.
- Le stringhe dell'interfaccia sono in italiano, come nel resto dell'app.
- Il progetto Xcode si genera con XcodeGen (`project.yml`). I file nuovi sotto `InstaSwipe/` vengono inclusi da soli.

## Test

- La logica "da quale fase si parte" (export avviato o no) e il punto di ripresa (si attiva arrivando alla fase 3, si azzera dopo un import confermato o con "Rivedi dall'inizio") vanno tenuti fuori dalla view e coperti da unit test, nello stile di `AppModelTests`. Nei test e negli UI test il `UserDefaults` va isolato tra un'esecuzione e l'altra.
- La sincronizzazione screenshot ↔ passo evidenziato e la navigazione tra fasi sono semplici abbastanza da coprirle con un UI test del percorso principale, come `PersistenceFlowTests`: fase 1 → 4, chiudi e riapri, si riparte dalla fase 4.

## Lasciato al costruttore

- Nomi di file e tipi, e dove mettere la definizione dei passi (un elenco statico in Swift va benissimo).
- Animazioni di passaggio tra fasi, purché coerenti con `riseIn()` e lo stile attuale.
- Le parole esatte dei pulsanti principali di ogni fase, purché brevi e in italiano ("Avanti", "È arrivata l'email").
- Come fare il carosello degli screenshot (per esempio `TabView` in stile pagina oppure `ScrollView` con paging).
