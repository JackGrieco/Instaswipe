# Modalità Follower – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere una seconda lista, i follower, che si scorre, si decide e si ripulisce con lo stesso flusso dei following. Le due modalità si alternano con un controllo a due segmenti e sono collegate tramite lo username.

**Architecture:** Il record `FollowedAccount` si riusa anche per i follower, con il significato dei campi documentato. `Review` e `Report` diventano generici su un protocollo `ReviewList`, a cui si conformano `AppState`, il nuovo `FollowerState` e il tipo concreto `AccountList` usato dalle sessioni. I follower si salvano in un file separato (`followers.json`), attraverso uno store generico ricavato da `FileStateStore`. I backup contengono entrambe le liste in un unico JSON. Un `Linking` puro ricalcola "ti segue" / "lo segui" in memoria a ogni caricamento e a ogni modifica, così una build vecchia che sovrascrive `state.json` non lo può corrompere.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, Swift Testing, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-30-followers-mode-design.md`

## Global Constraints

- iOS 17.0, solo iPhone, Swift 6 (`project.yml`). Dopo aver aggiunto file: `xcodegen generate`.
- Test del package: `swift test --package-path Packages/InstaSwipeKit`.
- Build app: `xcodebuild -project InstaSwipe.xcodeproj -scheme InstaSwipe -destination 'platform=iOS Simulator,name=iPhone 17' build`. Test unit: stesso comando con `test -only-testing:InstaSwipeTests`; UI test: `-only-testing:InstaSwipeUITests`.
- UI in italiano. Stile: token `Theme`, font `.outfit(...)`, componenti di `DesignSystem/Components.swift`. Nessun redesign: la UI verrà rifinita con Claude Design.
- Funzioni pure in `InstaSwipeKit` che restituiscono una copia nuova, mai mutazioni dell'input (pattern di `Review` / `Report`).
- Nessuna copia-incolla della logica di coda, progresso, annulla, report, merge e persistenza: si generalizza quella esistente.
- `Fixtures/state-v1.json` deve continuare a decodificarsi e i test esistenti devono continuare a passare. Si aggiornano solo quando cambia una firma.
- Nessuna rimozione automatica: "Rimuovi follower" resta un tap dell'utente nell'app di Instagram.
- Avviso giornaliero: `Limits.dailyUnfollowWarning` (150) sulla **somma** di unfollow e rimozioni segnati oggi.
- Commit in stile conventional (`feat:`, `refactor:`, `test:`), chiusi con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Una build vecchia risalva `state.json` dopo una rimozione di follower.** In quel file `followsMe` torna a valere quanto dice l'export. Al caricamento successivo la carta Following deve dire comunque "non ti segue" → test in Task 6 (`loadRelinksFollowsMeOverStaleStateFile`).
2. **Stato senza lista follower** (utente che aggiorna l'app). La modalità Follower mostra l'invito a reimportare, senza crash; filtro, annulla e contatori non fanno nulla → test in Task 7 (`followerModeWithoutListShowsInvite`).
3. **Spunta "fatto" tolta su un follower rimosso.** "Ti segue" torna vero solo se la persona è ancora nell'ultimo export follower → test in Task 4.
4. **Ritorno da Instagram dopo aver cambiato modalità.** La domanda "L'hai rimosso?" agisce sulla lista da cui è partita, non su quella attiva → test in Task 7 (`returnPromptActsOnOriginListAfterModeSwitch`) e in Task 8.
5. **Reimport con un export richiesto prima della rimozione.** Il follower ricompare con "ti segue dal" uguale o precedente alla data di rimozione: deve restare rimosso e fatto → test in Task 3.

---

### Task 1: Liste generiche e `FollowerState`

**Files:**
- Create: `Packages/InstaSwipeKit/Sources/InstaSwipeKit/Model/ReviewList.swift`
- Create: `Packages/InstaSwipeKit/Sources/InstaSwipeKit/Model/FollowerState.swift`
- Modify: `Packages/InstaSwipeKit/Sources/InstaSwipeKit/Review/Review.swift`, `Review/Report.swift`, `Model/FollowedAccount.swift` (solo doc comment)
- Test: `Packages/InstaSwipeKit/Tests/InstaSwipeKitTests/FollowerStateTests.swift`, `Fixtures.swift`

**Interfaces:**
- Produces:
  - `public enum ListMode: String, Sendable, CaseIterable { case following, followers }`
  - `public protocol ReviewList: Sendable { var accounts: [FollowedAccount] { get set }; var totalDecisionsMade: Int { get set } }`
  - `public struct AccountList: ReviewList, Equatable { public var accounts: [FollowedAccount]; public var totalDecisionsMade: Int }`
  - `extension AppState: ReviewList { public var list: AccountList { get set } }`
  - `public struct FollowerState: Codable, Sendable, Equatable, ReviewList { schemaVersion: Int; savedAt: Date; accounts: [FollowedAccount]; totalDecisionsMade: Int; static let currentSchemaVersion = 1; static func empty(now: Date) -> FollowerState; var list: AccountList { get set } }`
  - Tutte le funzioni di `Review` e `Report` diventano `<L: ReviewList>(…, in list: L …) -> L` (o il tipo di ritorno attuale): stessi nomi, stesse etichette `in:`, così i chiamanti esistenti compilano senza modifiche.

- [ ] **Step 1: Write the failing tests** in `FollowerStateTests.swift`
  - `followerStateRoundTripsThroughStateCoding`: `FollowerState` con due account → `StateCoding.encoder()` / `decoder()` → uguale all'originale.
  - `reviewWorksOnFollowerState`: `FollowerState` con `aa`, `bb` pending → `Review.current(in:)` è `aa`; `Review.decide(.remove, username: "aa", …)` → `current` è `bb`, `totalDecisionsMade == 1`; `Review.undo` → torna `aa`.
  - `reportWorksOnFollowerState`: un account `.remove` non fatto → `Report.counts(in:)[.toDo] == 1`; `Report.setUnfollowed(true, …)` → `[.done] == 1`.
  - `appStateListRoundTrip`: `var s = state; s.list = AccountList(accounts: [x], totalDecisionsMade: 7)` → `s.accounts == [x]`, `s.totalDecisionsMade == 7`, gli altri campi invariati.
  - Aggiungi a `Fixtures` `static func followers(_ accounts: [FollowedAccount]) -> FollowerState`.

- [ ] **Step 2: Run** `swift test --package-path Packages/InstaSwipeKit --filter FollowerStateTests` → FAIL (tipi non definiti).

- [ ] **Step 3: Implement.** Crea `ListMode`, `ReviewList` e `AccountList` in `ReviewList.swift`, `FollowerState` in `FollowerState.swift`. Rendi generici `Review` e `Report`. Nel doc comment di `FollowedAccount` scrivi il significato dei campi per un follower: `followedSince` = da quando ti segue, `followsMe` = lo segui tu (ricalcolato da `Linking`), `unfollowedManually` / `unfollowedAt` = rimosso a mano dai follower / quando. In `ReviewScope.notFollowingBack` scrivi che per i follower significa "Solo chi non segui".

- [ ] **Step 4: Run** `swift test --package-path Packages/InstaSwipeKit` → tutti PASS, compresi `ReviewTests`, `ReportTests` e `SchemaFixtureTests`.

- [ ] **Step 5: Commit** `refactor: make review and report generic over account lists`

---

### Task 2: Follower nell'export e "ti segue" preservato

**Files:**
- Modify: `Import/ExportParser.swift`, `Import/ExportLocator.swift`, `Import/MergeEngine.swift`
- Modify: `InstaSwipe/AppModel.swift` (solo `seedTestAccounts`, per compilare)
- Test: `ExportParserTests.swift`, `ExportLocatorTests.swift`, `MergeEngineTests.swift`, `Fixtures.swift`

**Interfaces:**
- Produces:
  - `ExportParser.parseFollowers(_ data: Data) throws -> [ExportedFollow]`: stesso formato e stessa logica di `parseFollowing`, senza duplicarla. `timestamp` = da quando ti segue.
  - `ExportSnapshot.followers: [ExportedFollow]?` (`nil` = nessun file `followers*.json` nell'export) e `public var followerUsernames: Set<String>? { get }`.
  - `ExportLocator.load` deduplica i follower per username con la stessa regola "il più vecchio vince" dei following.

- [ ] **Step 1: Write the failing tests**
  - `ExportParserTests.parseFollowersKeepsTimestamp`: una voce `{"string_list_data":[{"value":"aa","timestamp":1600000000}]}` → `[ExportedFollow(username: "aa", profileURL: …/_u/aa, followedSince: Date(1600000000))]`.
  - `ExportLocatorTests.loadWithoutFollowerFilesGivesNilFollowers`: cartella con solo `following.json` → `snapshot.followers == nil`.
  - `ExportLocatorTests.loadDeduplicatesFollowersKeepingOldest`: `followers_1.json` e `followers_2.json` con `aa` a 200 e a 100 → un solo `aa`, `followedSince` 100.
  - `MergeEngineTests.missingFollowerFilesKeepFollowsMe`: stato con `aa.followsMe == true` + snapshot `followers: nil` → dopo il merge `aa.followsMe == true`.
  - `MergeEngineTests.emptyFollowerFilesClearFollowsMe`: stesso stato + `followers: []` → `false`.

- [ ] **Step 2: Run** `swift test --package-path Packages/InstaSwipeKit` → FAIL.

- [ ] **Step 3: Implement.** In `MergeEngine.preview`, `followsMe` = `snapshot.followerUsernames?.contains(username) ?? account.followsMe` per i record esistenti e `?? false` per quelli nuovi. Aggiorna i test e `AppModel.seedTestAccounts` che costruiscono `ExportSnapshot(followers: Set)`: passano un array di `ExportedFollow`.

- [ ] **Step 4: Run** `swift test --package-path Packages/InstaSwipeKit` → PASS.

- [ ] **Step 5: Commit** `feat: parse follower timestamps and keep follow-back flags when the export has no followers`

---

### Task 3: Merge dei follower

**Files:**
- Modify: `Import/MergeEngine.swift`
- Test: `Packages/InstaSwipeKit/Tests/InstaSwipeKitTests/FollowerMergeTests.swift`

**Interfaces:**
- Consumes: `FollowerState`, `ExportSnapshot.followers` (Task 1–2).
- Produces:
  - `MergeSummary` guadagna `public let refollowed: Int` (parametro di init con default `0`).
  - `public struct FollowerMergePreview: Equatable, Sendable { public let followers: FollowerState; public let summary: MergeSummary }`
  - `MergeEngine.previewFollowers(current: FollowerState?, exported: [ExportedFollow], now: Date) -> FollowerMergePreview`
  - Nel riepilogo dei follower, `summary.noLongerFollowed` vale "non ti seguono più".

- [ ] **Step 1: Write the failing tests** in `FollowerMergeTests.swift` (date: `removedAt = referenceDate`)
  - `firstImportCreatesFollowersInReviewOrder`: `current: nil`, follower `bb`@200 e `aa`@100 → accounts `[aa, bb]`, tutti pending, `newAccounts == 2`.
  - `goneFollowerLeavesThePile`: `aa` nello stato, assente dall'export → `stillInLatestExport == false`, `noLongerFollowed == 1`.
  - `goneFollowerMarkedRemoveIsAutoDone`: `aa` `.remove` non fatto, assente → `unfollowedManually == true`, `unfollowedAt == nil`, `autoMarkedDone == 1`.
  - `refollowAfterRemovalReopens`: `aa` `.remove`, fatto, `unfollowedAt = removedAt`; export con `aa` `followedSince = removedAt + 1 giorno` → `decision == .pending`, `decidedAt == nil`, `unfollowedManually == false`, `unfollowedAt == nil`, `followedSince` = nuova data, `refollowed == 1`.
  - `olderExportKeepsRemovedFollowerDone`: stesso stato, export con `followedSince = removedAt - 1 giorno` → resta `.remove` e fatto, `refollowed == 0`.
  - `refollowWithoutDateKeepsRemovedFollowerDone`: export con `followedSince == nil` → resta fatto.
  - `suspiciousWhenMostFollowersVanish`: 10 follower attivi, export con 5 → `isSuspicious == true`.
  - `followingMergeNeverReopensManualDone`: guardia di regressione. Un following `.remove` fatto a mano, con `unfollowedAt`, ricompare in `MergeEngine.preview` → resta fatto.

- [ ] **Step 2: Run** `swift test --package-path Packages/InstaSwipeKit --filter FollowerMergeTests` → FAIL.

- [ ] **Step 3: Implement** `previewFollowers`. Estrai da `preview` un nucleo privato condiviso che lavora su `[FollowedAccount]` + `[ExportedFollow]` e restituisce account riordinati (`AppState.reviewOrdered`) + conteggi. La riapertura dei rimossi è un parametro del nucleo, attivo solo per i follower: `exported.followedSince > account.unfollowedAt`, entrambi non nil, con `decision == .remove && unfollowedManually`. Il record riaperto si ricostruisce con il nuovo `followedSince`, perché è un `let`.

- [ ] **Step 4: Run** `swift test --package-path Packages/InstaSwipeKit` → PASS (anche `MergeEngineTests`).

- [ ] **Step 5: Commit** `feat: merge follower exports and reopen people who follow you again`

---

### Task 4: `Linking` tra le due liste

**Files:**
- Create: `Packages/InstaSwipeKit/Sources/InstaSwipeKit/Review/Linking.swift`
- Test: `Packages/InstaSwipeKit/Tests/InstaSwipeKitTests/LinkingTests.swift`

**Interfaces:**
- Consumes: `AppState`, `FollowerState`.
- Produces: `public enum Linking { public static func linked(state: AppState, followers: FollowerState?) -> (state: AppState, followers: FollowerState?) }`
  - Con `followers == nil` lo `state` resta invariato, perché nessuna lista follower è mai stata importata.
  - Follower "attivo" = presente in `followers.accounts`, `stillInLatestExport`, e non (`decision == .remove && unfollowedManually`). Ogni following ha `followsMe` = follower attivo.
  - Following "attivo" = stessa regola su `state.accounts`. Ogni follower ha `followsMe` ("lo segui") = following attivo.

- [ ] **Step 1: Write the failing tests**
  - `removedFollowerLosesFollowsMe`: following `aa` (`followsMe: true`) + follower `aa` `.remove` fatto → following `aa.followsMe == false`.
  - `untickedRemovalRestoresFollowsMe`: come sopra ma `unfollowedManually == false` → `true`.
  - `untickedRemovalOfGoneFollowerStaysFalse`: follower `aa` `.remove`, non fatto, `stillInLatestExport == false` → `false`.
  - `followerShowsFollowedByMe`: following `aa` attivo, `bb` unfollow fatto; follower `aa`, `bb`, `cc` → `followsMe` dei follower: `aa` true, `bb` false, `cc` false.
  - `nilFollowersLeavesStateUntouched`: `linked(state: s, followers: nil).state == s`.
  - `linkingIsIdempotent`: applicarlo due volte dà lo stesso risultato.

- [ ] **Step 2: Run** `swift test --package-path Packages/InstaSwipeKit --filter LinkingTests` → FAIL.
- [ ] **Step 3: Implement** `Linking.linked`, con due `Set<String>` di attivi: niente ricerche annidate O(n²), le liste arrivano a migliaia di account.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: link follow-back flags between following and followers`

---

### Task 5: Persistenza su due file e backup combinati

**Files:**
- Modify: `Persistence/FileStateStore.swift` (diventa generico), `Persistence/BackupRotator.swift`
- Create: `Packages/InstaSwipeKit/Sources/InstaSwipeKit/Persistence/StoredDocument.swift`, `Persistence/BackupSnapshot.swift`
- Test: `FileStateStoreTests.swift`, `BackupRotatorTests.swift`, `Packages/InstaSwipeKit/Tests/InstaSwipeKitTests/FollowerPersistenceTests.swift`

**Interfaces:**
- Produces:
  - `public protocol StoredDocument: Codable, Sendable { static var fileName: String { get }; var savedAt: Date { get set } }`. `AppState.fileName = "state.json"`, `FollowerState.fileName = "followers.json"`.
  - `public final class FileDocumentStore<Document: StoredDocument>: Sendable` con le stesse API di oggi (`load() throws -> Document?`, `save(_:)`, `mirrorToCloud(_:)`) e lo stesso comportamento (placeholder iCloud, scelta della copia più recente, quarantena). Il prefisso di quarantena si ricava dal nome del file: `state.corrupt-…`, `followers.corrupt-…`.
  - `public typealias FileStateStore = FileDocumentStore<AppState>` e `public typealias FollowerStore = FileDocumentStore<FollowerState>`.
  - `public struct BackupSnapshot: Codable, Sendable, Equatable { public var state: AppState; public var followers: FollowerState? }`. Si codifica **piatto**: le chiavi di `AppState` più una chiave `followers` opzionale. Così un backup vecchio decodifica con `followers == nil`, e una build vecchia legge un backup nuovo come un `AppState`.
  - `BackupRotator.backupIfNeeded(_ snapshot: BackupSnapshot, now:calendar:)`, `backup(_ snapshot: BackupSnapshot, kind:now:)`, `newestValidBackup() throws -> BackupSnapshot?`. Il conteggio per i backup a passi è `state.totalDecisionsMade + (followers?.totalDecisionsMade ?? 0)`.

- [ ] **Step 1: Write the failing tests** in `FollowerPersistenceTests.swift`
  - `followerStoreRoundTrip`: `save` + `load` → stesso `FollowerState`; il file su disco si chiama `followers.json`.
  - `followerStoreQuarantinesWithOwnPrefix`: `followers.json` corrotto → `StateStoreError.corrupted`, file `followers.corrupt-*.json`, nessun file `state.corrupt-*`.
  - `followerStoreAbsentGivesNil`: nessun file → `nil`.
  - `oldBuildStateSaveLeavesFollowersIntact`: salva `FollowerState` con 3 decisioni; scrivi `state.json` come farebbe una build vecchia (`AppState` senza follower, `savedAt` più recente); ricarica entrambi → i follower hanno ancora le 3 decisioni.
  - `backupSnapshotDecodesLegacyBackup`: JSON di `Fixtures/state-v1.json` decodificato come `BackupSnapshot` → `followers == nil`, `state` uguale alla decodifica come `AppState`.
  - `backupSnapshotIsReadableAsAppState`: `BackupSnapshot` con follower codificato → decodificato come `AppState` riesce (compatibilità con le build vecchie).
  - `stepBackupCountsBothLists`: `state.totalDecisionsMade = 60`, `followers.totalDecisionsMade = 40` → viene scritto `step-100.json`.
  - Adatta `BackupRotatorTests` alla nuova firma (avvolgi lo stato in `BackupSnapshot(state:followers: nil)`).

- [ ] **Step 2: Run** `swift test --package-path Packages/InstaSwipeKit` → FAIL.
- [ ] **Step 3: Implement.** Generalizza `FileStateStore` senza cambiare il comportamento per `state.json`. Per la codifica piatta di `BackupSnapshot`, `encode(to:)` chiama `state.encode(to: encoder)` e poi aggiunge `followers` con un container con chiave sullo stesso encoder; `init(from:)` è speculare.
- [ ] **Step 4: Run** `swift test --package-path Packages/InstaSwipeKit` → PASS, compresi `FileStateStoreTests` e `SchemaFixtureTests`.
- [ ] **Step 5: Commit** `feat: store followers in their own file and back up both lists together`

---

### Task 6: `AppModel` con due liste

**Files:**
- Modify: `InstaSwipe/AppModel.swift`, `InstaSwipe/InstaSwipeApp.swift` (`LoadErrorView`: `pendingRestore.state.savedAt`, decisioni contate su entrambe le liste)
- Test: `InstaSwipeTests/AppModelFollowersTests.swift`, e adatta `AppModelRestoreTests.swift` / `CloudMirrorTests.swift` se cambiano firme.

**Interfaces:**
- Consumes: Task 1–5.
- Produces (su `AppModel`):
  - `private(set) var followers: FollowerState?`. Dopo ogni load e ogni persist, `state` e `followers` in memoria sono **sempre** `Linking.linked(...)` dei valori salvati.
  - `var listMode: ListMode`, salvato in `environment.defaults` con chiave `"listMode"`, default `.following`. È condiviso da swipe e lista.
  - `func list(_ mode: ListMode) -> AccountList?`: per `.followers` è `nil` se `followers == nil`.
  - `func apply(_ mode: ListMode, _ transform: (AccountList) -> AccountList)`: salva solo il file di quella lista. Il vecchio `apply(_: (AppState) -> AppState)` resta.
  - `func applyToBothLists(_ transform: (AccountList) -> AccountList)`, per disponibilità e nome visualizzato.
  - `func actionsToday(now: Date, calendar: Calendar) -> Int`: somma di `Report.unfollowsToday` sulle due liste.
  - `private(set) var pendingFollowerMerge: FollowerMergePreview?`, impostato da `prepareImport` quando `snapshot.followers != nil`.
  - `pendingRestore: BackupSnapshot?`.
- Comportamento:
  - Il load legge entrambi gli store. `cloudNotDownloaded` di uno qualsiasi fa attendere; le quarantene dei due file confluiscono in `quarantinedFileNames`.
  - Il mirror iCloud copia entrambi i file e il backup prende un `BackupSnapshot` di entrambi.
  - `confirmImport` fa il backup pre-import del `BackupSnapshot`, poi salva prima i follower e poi lo stato. Se il salvataggio dei follower fallisce, l'import si annulla senza toccare lo stato.
  - `confirmRestore` salva lo stato e, se il backup li contiene, i follower. Altrimenti lascia `followers.json` com'è.
  - `seedTestAccounts` crea anche i follower `fan_01`, `fan_02` (che non segui) e `test_02` (che segui), con date crescenti in quest'ordine, così la prima carta follower è `fan_01`.

- [ ] **Step 1: Write the failing tests** in `AppModelFollowersTests.swift`, con il setup dei test esistenti (directory temporanea, `AppEnvironment` di test)
  - `importCreatesFollowersFile`: `prepareImport` + `confirmImport` su una cartella con `following.json` e `followers_1.json` → `model.followers?.accounts.count` corretto, `followers.json` su disco.
  - `removingFollowerUpdatesFollowingCard`: `apply(.followers) { Review.decide(.remove, …) }`, poi `apply(.followers) { Report.setUnfollowed(true, …) }` → `model.state` following `aa.followsMe == false`.
  - `loadRelinksFollowsMeOverStaleStateFile` (Review Focus 1): dopo il caso sopra, riscrivi `state.json` con `aa.followsMe = true` e `savedAt` più recente, poi crea un nuovo `AppModel` → `aa.followsMe == false`.
  - `listModePersists`: `listMode = .followers` → nuovo `AppModel` sugli stessi defaults → `.followers`.
  - `restoreBringsBackFollowers`: backup con follower → `confirmRestore` → `model.followers` uguale a quello del backup.
  - `actionsTodaySumsBothLists`: un unfollow e una rimozione segnati oggi → `2`.
  - `importWithoutFollowerFilesKeepsFollowers`: follower esistenti + import con solo `following.json` → `pendingFollowerMerge == nil`, `model.followers` invariato.

- [ ] **Step 2: Run** `xcodegen generate`, poi i test unit → FAIL.
- [ ] **Step 3: Implement.** `AppModel.swift` resta sotto le 800 righe. Se supera ~550, sposta import e restore in `InstaSwipe/AppModel+Import.swift` (extension).
- [ ] **Step 4: Run** i test unit dell'app → PASS (tutti, compresi `AppModelTests`, `AppModelRestoreTests` e `CloudMirrorTests`).
- [ ] **Step 5: Commit** `feat: load, save, mirror and restore the follower list`

---

### Task 7: `SwipeSession` in modalità Follower

**Files:**
- Create: `InstaSwipe/Report/ReturnPromptTracker.swift`
- Modify: `InstaSwipe/Swipe/SwipeSession.swift`, `InstaSwipe/Report/ReportSession.swift` (usa il tracker; il comportamento non cambia)
- Test: `InstaSwipeTests/SwipeSessionFollowersTests.swift`, `InstaSwipeTests/ReportSessionTests.swift` (devono continuare a passare)

**Interfaces:**
- Consumes: `AppModel.listMode`, `list(_:)`, `apply(_:_:)`, `applyToBothLists`, `actionsToday` (Task 6).
- Produces:
  - `@MainActor @Observable final class ReturnPromptTracker`: `struct Pending: Equatable { let username: String; let mode: ListMode }`; `func willOpen(_ pending: Pending?)`; `func scenePhaseChanged(_ phase: ScenePhase)`; `private(set) var prompt: Pending?`; `func dismiss()`. È la logica "l'`.active` subito dopo il tap si ignora" spostata da `ReportSession`.
  - `SwipeSession`:
    - `var mode: ListMode` (legge e scrive `model.listMode`).
    - `enum Screen` guadagna `case noFollowers`: modalità Follower con `model.followers == nil`.
    - Filtro per modalità: `isNotFollowingBackOnly` legge e scrive la chiave `"swipeScope"` in Following e `"followerSwipeScope"` in Follower.
    - `current`, `next`, `progress`, `undo`, `lastDecision`, `reviewCounts` e `hasOthersToReview` lavorano su `model.list(mode)`.
    - `decide` usa `model.apply(mode)`.
    - Disponibilità e nome visualizzato da `finishLoad` passano per `applyToBothLists`.
    - `unfollowsToday` = `model.actionsToday`.
    - Uno swipe `.remove` con "Togli subito" acceso: in Following come oggi (WebView + `UnfollowBar`). In Follower imposta `private(set) var appHandoffURL: URL?` = `account.profileURL` e `returnPrompt.willOpen(.init(username:mode: .followers))`, **senza** `recordLoad()`.
    - `func appHandoffOpened()` azzera `appHandoffURL`.
    - `let returnPrompt: ReturnPromptTracker`.
    - `func confirmReturnPrompt()` segna fatto sulla lista di `prompt.mode`. `func keepFromReturnPrompt()` decide `.keep` su quella lista.

- [ ] **Step 1: Write the failing tests** in `SwipeSessionFollowersTests.swift`
  - `followerModeShowsFollowers`: `mode = .followers` → `current?.username` è il primo follower.
  - `followerModeWithoutListShowsInvite` (Review Focus 2): `followers == nil`, `mode = .followers` → `screen == .noFollowers`; `undo()` e `decide(.keep)` non cambiano nulla e non vanno in crash.
  - `undoIsPerMode`: decidi `aa` in Following, poi `fan_01` in Follower, poi `undo()` in Following → torna `aa`; `fan_01` resta deciso.
  - `scopeIsPerMode`: `isNotFollowingBackOnly = true` in Follower → in Following resta `false`.
  - `instantRemoveInFollowerModeHandsOffToInstagram`: instant acceso, `decide(.remove)` in Follower → `appHandoffURL == profileURL` (`_u/`), `profilePageURL == nil`, il conteggio dei profili di oggi non aumenta.
  - `returnPromptActsOnOriginListAfterModeSwitch` (Review Focus 4): handoff in Follower, poi `mode = .following`, `.background` → `.active`, `confirmReturnPrompt()` → follower segnato fatto, following non toccato.
  - `availabilityAppliesToBothLists`: `finishLoad` di `test_02` con `.unavailable` → `availability == .unavailable` in entrambe le liste.

- [ ] **Step 2: Run** i test unit → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** i test unit → PASS (anche `SwipeSessionTests` e `ReportSessionTests`).
- [ ] **Step 5: Commit** `feat: swipe through followers and hand removals off to Instagram`

---

### Task 8: `ReportSession` e CSV per modalità

**Files:**
- Modify: `InstaSwipe/Report/ReportSession.swift`, `Packages/InstaSwipeKit/Sources/InstaSwipeKit/Export/CSVExporter.swift`
- Test: `CSVExporterTests.swift`, `InstaSwipeTests/ReportSessionTests.swift`

**Interfaces:**
- Consumes: Task 6–7.
- Produces:
  - `CSVExporter.csv(for accounts: [FollowedAccount], mode: ListMode = .following) -> String`. Intestazione per `.followers`: `username,link,ti segue dal,decisione,fatto,lo segui`. Righe identiche a oggi.
  - `CSVExport` guadagna `mode: ListMode`. `fileName` = `InstaSwipe-AAAA-MM-GG.csv` per i following e `InstaSwipe-follower-AAAA-MM-GG.csv` per i follower.
  - `ReportSession`:
    - `rows`, `count(for:)`, `setUnfollowed`, `decide`, `retryAvailability` e `csvExport` lavorano su `model.list(model.listMode)`.
    - `open(_:)` passa la modalità al tracker.
    - `counterText` = `"Oggi: \(n) azioni segnate"` con `n = model.actionsToday`; `isOverDailyWarning` sulla stessa somma.
    - `promptTitle(for username: String) -> String` = `"Hai tolto il follow a @\(username)?"` per i following e `"Hai rimosso @\(username) dai follower?"` per i follower, secondo la modalità del prompt.

- [ ] **Step 1: Write the failing tests**
  - `CSVExporterTests.followersHeader`: `csv(for: [], mode: .followers)` == `"username,link,ti segue dal,decisione,fatto,lo segui"`.
  - `ReportSessionTests.followerModeListsFollowers`: `listMode = .followers` → `rows` contiene solo follower `.remove` da fare.
  - `ReportSessionTests.followerCSVFileName`: data fissa 2026-10-30 → `"InstaSwipe-follower-2026-10-30.csv"`.
  - `ReportSessionTests.counterSumsBothLists`: un unfollow e una rimozione oggi → `counterText == "Oggi: 2 azioni segnate"`.
  - `ReportSessionTests.promptKeepsOriginMode`: `open` in Follower, cambio a Following, ritorno → `confirmUnfollowed()` segna il follower.
  - Aggiorna l'atteso del contatore nei test esistenti, se lo controllano (oggi `"Oggi: N unfollow segnati"`).

- [ ] **Step 2: Run** `swift test --package-path Packages/InstaSwipeKit` e i test unit → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: follower list and CSV in "Da togliere"`

---

### Task 9: UI – selettore, testi e riepilogo import

**Files:**
- Create: `InstaSwipe/DesignSystem/ListModePicker.swift`, `InstaSwipe/Swipe/NoFollowersView.swift`, `InstaSwipeUITests/FollowersModeFlowTests.swift`
- Modify:
  - `Swipe/SwipeView.swift`, `Swipe/SwipeCardScreen.swift` (`SwipeHeader`), `Swipe/LimitReachedView.swift` (`SwipeEndView`)
  - `Swipe/AccountCardView.swift`, `Report/ReportView.swift`, `Report/ReportRow.swift`, `Report/ReturnPromptSheet.swift`
  - `Report/ReportControls.swift`, `Swipe/UnfollowBar.swift`, `Settings/SettingsView.swift`
  - `Onboarding/MergeSummaryView.swift`, `InstaSwipeApp.swift` (badge)

**Interfaces:**
- Consumes: Task 6–8.
- Produces: `struct ListModePicker: View { @Binding var mode: ListMode; var isDisabled = false }`. È un `Picker(.segmented)` con le voci "Following" e "Follower" e `accessibilityIdentifier("listModePicker")`.

Testi e comportamento (copia esatta dove indicata):
- **Selettore.** In cima alla lista "da togliere" e su **ogni** schermata dello swipe: carte, fine, limite, `noFollowers`. Sulle carte è disabilitato mentre una carta vola (stessa condizione `isFilterLocked` del filtro).
- **Filtro.** In Following "Solo chi non ti segue", in Follower "Solo chi non segui". Pulsante della schermata di fine: "Mostra anche chi ti segue" / "Mostra anche chi segui".
- **Carta.** In Follower: "Ti segue dal {data}" al posto di "Lo segui dal {data}", e tag "Lo segui" al posto di "Ti segue". Stesso schema per `ReportRow`: "lo segui" al posto di "ti segue".
- **`NoFollowersView`.** Titolo "Nessun follower importato". Testo "Per ripulire chi ti segue, importa di nuovo l'export di Instagram: questa volta leggo anche i follower." Pulsante "Reimporta export", che apre le Impostazioni (`SettingsPresenter`).
- **`SwipeView`.** `.onChange(of: session.appHandoffURL)` → `openURL(url)` e poi `session.appHandoffOpened()`. `.onChange(of: scenePhase)` → `session.returnPrompt.scenePhaseChanged`. Il foglio `ReturnPromptSheet` si mostra quando `returnPrompt.prompt != nil`, con il titolo per i follower, "Ho cambiato idea, lo tengo" → `keepFromReturnPrompt()` e "Sì, segna come fatto" → `confirmReturnPrompt()`.
- **`ReturnPromptSheet`.** Riceve `title: String` al posto del testo fisso.
- **Contatori.** In `ReportControls` "Oggi: N azioni segnate". In `UnfollowBar` il contatore resta "Oggi: N", con `N` = somma.
- **Impostazioni.** Toggle "Togli subito" (identificatore invariato `instantUnfollowToggle`). Footer: "Quando scarti un account si apre il suo profilo. Per chi segui: togli il follow e tocca Fatto (ogni apertura conta nei profili del giorno). Per i follower si apre l'app di Instagram: tocca ⋯ → «Rimuovi follower» e torna qui."
- **`MergeSummaryView`.** Se `model.pendingFollowerMerge != nil`, aggiungi una seconda card intitolata "Follower" con le righe "Nuovi follower", "Non ti seguono più", "Segnati come già rimossi" e, solo se > 0, "Tornati a seguirti". L'avviso di import incompleto compare se uno dei due riepiloghi è sospetto.
- **Badge** di "Da togliere": somma dei "Da fare" delle due liste.

- [ ] **Step 1: Write the failing UI test** `FollowersModeFlowTests.testSwitchToFollowersAndKeep`. Lancio con `-uiTestStateDir` + `-uiTestSeed`; tap su "Follower" in `listModePicker`; `cardUsername` contiene `fan_01`; tap su "tengo"; `cardUsername` contiene `fan_02`; tap sul segmento "Following" → `cardUsername` contiene `test_01`.
- [ ] **Step 2: Run** `xcodegen generate` + UI test → FAIL.
- [ ] **Step 3: Implement** le modifiche elencate.
- [ ] **Step 4: Run** i UI test (tutti, compresi `InstantUnfollowFlowTests` e `ReportIdentifiersTests`) e i test unit → PASS. Build pulita, senza warning nuovi.
- [ ] **Step 5: Controllo manuale sul simulatore.**
  - Il selettore non si può usare mentre una carta vola.
  - La schermata `noFollowers` compare con uno stato senza `followers.json`.
  - Il foglio "Hai rimosso @… dai follower?" compare dopo un ritorno simulato (Home → app).
- [ ] **Step 6: Commit** `feat: followers mode UI with a following/followers switch`

---

### Task 10: Prova sul dispositivo

- [ ] **Step 1:** Build e installazione sull'iPhone dell'utente via CLI (`xcodebuild` + `devicectl`, come da memoria del progetto). Reimport di un export reale con i follower.
- [ ] **Step 2:** Verifica con l'utente:
  - Il riepilogo import mostra la card Follower.
  - Uno swipe "tolgo" in Follower con "Togli subito" acceso apre l'app di Instagram sul profilo giusto.
  - Al ritorno compare la domanda.
  - "Sì" toglie "Ti segue" dalla carta Following della stessa persona.
- [ ] **Step 3:** Annota nel PR eventuali correzioni ai testi.
