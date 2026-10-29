# InstaSwipe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App iPhone che fa passare in rassegna con uno swipe i circa 5.600 account seguiti su Instagram, partendo dall'export ufficiale, senza mai perdere una decisione, e che tiene un elenco "Da togliere" da smaltire a mano.

**Architecture:** Tutta la logica sta in un Swift package locale `InstaSwipeKit`, puro Foundation, testabile con `swift test` sul Mac: modello, parser dell'export, merge, revisione/annulla, contatori, persistenza con backup, classificazione delle pagine profilo, CSV. Le funzioni sono pure e restituiscono un nuovo `AppState`, senza mutare quello ricevuto. L'app SwiftUI (progetto generato con XcodeGen) contiene solo UI, la WebView e un `AppModel` che applica le trasformazioni e salva dopo ognuna.

**Tech Stack:** Swift 6.3, SwiftUI, iOS 17+, WebKit (`WKWebView`), Swift Testing (package), XCTest/XCUITest (app), XcodeGen, iCloud Documents.

**Spec:** `docs/superpowers/specs/2026-10-29-instaswipe-design.md`

## Global Constraints

- Solo iPhone, deployment target iOS 17.0. Lingua della UI: italiano.
- Bundle id `com.giacomogrieco.InstaSwipe`, container iCloud `iCloud.com.giacomogrieco.InstaSwipe`, nome visibile in File: "InstaSwipe". Team `CBRAP62CDG` (dedotto dal certificato Developer ID nel portachiavi: va verificato nel Task 8).
- Nessun click o unfollow automatico, nessuna API non ufficiale. Verso Instagram si fanno solo caricamenti di pagine profilo: la card visibile più al massimo la successiva.
- Costanti in `Limits.swift`: `defaultDailyProfileLoads = 400`, `dailyUnfollowWarning = 150`, `reimportSuspiciousRatio = 0.2`, `profileLoadTimeout = 10 s`, `dailyBackupsKept = 14`, `stepBackupsKept = 10`, `backupEveryDecisions = 100`, `preImportBackupsKept = 5`, `cloudMirrorDebounce = 5 s`.
- Lo stato si scrive su disco locale **in modo sincrono e atomico** dopo ogni mutazione, prima che la UI mostri la card successiva.
- `connections/` non si committa mai. Le fixture dei test sono sintetiche, con username inventati.
- Immutabilità: le API del package prendono un `AppState` e ne restituiscono uno nuovo.
- Ogni commit termina con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Copertura del package ≥ 80% (comando nel Task 7).

## Review Focus

1. **File di stato illeggibile all'avvio** → l'app non deve mai partire "vuota" e salvare sopra. Mostra un errore, conserva il file (rinominato `state.corrupt-<timestamp>.json`) e prova la copia iCloud. Test: Task 6 (`loadQuarantinesCorruptLocalAndUsesCloud`, `loadThrowsWhenBothCorrupt`) e Task 8 (`AppModel` non salva se `load` ha lanciato).
2. **Lo stesso export importato due volte** → nessun cambiamento, riepilogo tutto a zero, non sospetto. Test: Task 3 (`reimportSameExportIsNoOp`).
3. **Il risultato del profilo arriva dopo che l'utente ha già swipato** (precaricamento lento) → la decisione già presa non cambia. Test: Task 4 (`markAvailabilityKeepsExistingDecision`).
4. **Mezzanotte durante una sessione** → i contatori "oggi" (unfollow e profili caricati) ripartono da zero e il freno d'emergenza di ieri non blocca più. Test: Task 5 (`countersResetOnNewDay`, `emergencyStopExpiresNextDay`).
5. **iCloud spento o non loggato** → l'app funziona solo in locale, salva comunque e mostra l'avviso. Test: Task 6 (`storeWorksWithoutCloudDirectory`) e Task 8 (banner con `cloudDirectory == nil`).

---

## File Structure

```
.gitignore                                  (esiste)
project.yml                                 XcodeGen: target app + UI test
InstaSwipe/                                 target app
  InstaSwipeApp.swift                       @main, TabView, scenePhase
  AppModel.swift                            @Observable: stato, apply+save, backup, mirror iCloud
  AppEnvironment.swift                      risoluzione directory, argomenti UI test
  InstaSwipe.entitlements
  Info.plist                                NSUbiquitousContainers
  Onboarding/ImportView.swift               picker cartella, MergeSummaryView
  Onboarding/MergeSummaryView.swift
  Web/WebView.swift                         UIViewRepresentable WKWebView visibile (login, profilo intero)
  Web/LoginView.swift
  Web/ProfileLoader.swift                   protocollo ProfileLoading + WebProfileLoader + FakeProfileLoader
  Web/ThumbnailCache.swift
  Swipe/SwipeView.swift                     contatori, card, pulsanti, gesture, annulla
  Swipe/SwipeSession.swift                  @Observable: caricamento corrente/successiva, budget
  Swipe/AccountCardView.swift
  Swipe/LimitReachedView.swift              tetto/freno/fine lista
  Report/ReportView.swift                   filtri, ricerca, contatore oggi, share CSV
  Report/ReportRow.swift
  Report/ReturnPromptSheet.swift
  Settings/SettingsView.swift               tetto giornaliero, reimport, login
InstaSwipeUITests/PersistenceFlowTests.swift
Packages/InstaSwipeKit/
  Package.swift
  Sources/InstaSwipeKit/
    Model/FollowedAccount.swift             Decision, Availability, FollowedAccount
    Model/AppState.swift                    AppState, DailyCount
    Model/Limits.swift
    Import/ExportParser.swift               parseFollowing/parseFollowers/fixMojibake
    Import/ExportLocator.swift              ricerca file + ExportLoader (dedup)
    Import/MergeEngine.swift
    Review/Review.swift                     coda, decide, undo, progress, availability
    Review/Report.swift                     filtri, ricerca, spunta, contatore unfollow
    Review/ProfileBudget.swift              tetto profili + freno d'emergenza
    Persistence/StateCoding.swift           encoder/decoder JSON condivisi
    Persistence/FileStateStore.swift
    Persistence/BackupRotator.swift
    Profile/ProfilePageClassifier.swift
    Export/CSVExporter.swift
  Tests/InstaSwipeKitTests/
    Fixtures.swift                          builder di JSON e AppState sintetici
    (un file *Tests.swift per ogni file sorgente sopra)
```

---

### Task 1: Package e modello dati

**Files:**
- Create: `Packages/InstaSwipeKit/Package.swift`, `Sources/InstaSwipeKit/Model/{FollowedAccount,AppState,Limits}.swift`, `Sources/InstaSwipeKit/Persistence/StateCoding.swift`
- Test: `Tests/InstaSwipeKitTests/ModelTests.swift`, `Tests/InstaSwipeKitTests/Fixtures.swift`

**Interfaces:**
- Produces:
  - `public enum Decision: String, Codable, Sendable { case pending, keep, remove }`
  - `public enum Availability: String, Codable, Sendable { case unknown, available, unavailable }`
  - `public struct FollowedAccount: Codable, Sendable, Equatable, Identifiable` con i campi della spec: `username`, `profileURL`, `followedSince: Date?`, `followsMe`, `displayName: String?`, `availability`, `decision`, `decidedAt: Date?`, `unfollowedManually`, `unfollowedAt: Date?`, `stillInLatestExport`; `id == username`.
  - `public struct DailyCount: Codable, Sendable, Equatable { public var day: Date; public var count: Int }` (`day` = inizio del giorno locale)
  - `public struct AppState: Codable, Sendable, Equatable { schemaVersion: Int; savedAt: Date; accounts: [FollowedAccount]; totalDecisionsMade: Int; profileLoads: DailyCount; dailyProfileLimit: Int; emergencyStopDay: Date? }` con `static let currentSchemaVersion = 1` e `static func empty(now: Date) -> AppState`. `accounts` è sempre in ordine di revisione: `followedSince` crescente, `nil` in fondo, a parità username crescente.
  - `public enum Limits` con le costanti dei Global Constraints.
  - `public enum StateCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }`: date `.iso8601`, `.prettyPrinted` + `.sortedKeys`.
  - `Fixtures` (solo test): `static func account(_ username: String, since: Date?, decision: Decision = .pending, ...) -> FollowedAccount`, `static func state(_ accounts: [FollowedAccount]) -> AppState`, `static func followingJSON(_ entries: [(String, Int?)]) -> Data`, `static func followersJSON(_ usernames: [String]) -> Data`.

- [ ] **Step 1: Crea `Package.swift`**: `swift-tools-version:6.0`, prodotto/target `InstaSwipeKit`, test target `InstaSwipeKitTests`, `platforms: [.iOS(.v17), .macOS(.v14)]` (macOS serve solo per `swift test` sul Mac).
- [ ] **Step 2: Scrivi i test che falliscono** in `ModelTests.swift`:

```swift
@Test func appStateRoundTripsThroughJSON() throws {
    let state = Fixtures.state([Fixtures.account("anna", since: .init(timeIntervalSince1970: 1_580_000_000), decision: .remove)])
    let data = try StateCoding.encoder().encode(state)
    #expect(try StateCoding.decoder().decode(AppState.self, from: data) == state)
}
@Test func emptyStateHasDefaults() {
    let s = AppState.empty(now: .init(timeIntervalSince1970: 0))
    #expect(s.schemaVersion == 1 && s.accounts.isEmpty && s.dailyProfileLimit == 400 && s.emergencyStopDay == nil)
}
```
- [ ] **Step 3: Esegui** `cd Packages/InstaSwipeKit && swift test`. Atteso: errore di compilazione (tipi mancanti).
- [ ] **Step 4: Implementa i tipi** elencati negli Interfaces.
- [ ] **Step 5: Esegui** `swift test`. Atteso: PASS.
- [ ] **Step 6: Commit** `feat: add InstaSwipeKit package and data model`

---

### Task 2: Parser e lettura dell'export

**Files:**
- Create: `Sources/InstaSwipeKit/Import/ExportParser.swift`, `Sources/InstaSwipeKit/Import/ExportLocator.swift`
- Test: `Tests/InstaSwipeKitTests/ExportParserTests.swift`, `ExportLocatorTests.swift`

**Interfaces:**
- Produces:
  - `public struct ExportedFollow: Equatable, Sendable { username: String; profileURL: URL; followedSince: Date? }`
  - `public enum ExportParserError: Error, Equatable { case unrecognizedFormat, followingNotFound }`
  - `public enum ExportParser { static func parseFollowing(_ data: Data) throws -> [ExportedFollow]; static func parseFollowers(_ data: Data) throws -> Set<String>; static func fixMojibake(_ s: String) -> String }`
  - `public struct ExportFiles: Equatable { following: [URL]; followers: [URL] }`
  - `public struct ExportSnapshot: Equatable, Sendable { follows: [ExportedFollow]; followers: Set<String> }`
  - `public enum ExportLocator { static func locate(in folder: URL) throws -> ExportFiles; static func load(_ files: ExportFiles) throws -> ExportSnapshot }`

Regole (dalla spec e dall'export reale):
- La radice è un oggetto con chiave `relationships_following` (o qualunque chiave `relationships_*` il cui valore sia un array), oppure direttamente un array.
- Username: `title` se non vuoto, altrimenti `string_list_data[0].value`, altrimenti l'ultimo componente di `href`. Viene normalizzato in minuscolo e passato per `fixMojibake`. Le voci senza username si scartano.
- `profileURL` = `https://www.instagram.com/_u/<username>`, sempre in questa forma anche se `href` è diverso, perché apre l'app Instagram.
- `timestamp` in secondi Unix, opzionale.
- `fixMojibake`: se tutti gli scalari sono ≤ 0xFF e i loro byte decodificati come UTF-8 danno una stringa valida e diversa, restituisce quella; altrimenti la stringa originale.
- `locate`: ricerca ricorsiva di file `following*.json` e `followers*.json`, ordinati per nome. `following_hashtags.json` è escluso. Se non trova nessun following lancia `followingNotFound`.
- `load`: unisce tutti i file; dedup per username tenendo il `followedSince` più vecchio.

- [ ] **Step 1: Scrivi i test che falliscono**:

```swift
@Test func parsesRealFollowingShape() throws {   // oggetto + title + href _u + timestamp, nessun value
    let f = try ExportParser.parseFollowing(Fixtures.followingJSON([("flipper_zero", 1_793_097_949)]))
    #expect(f == [ExportedFollow(username: "flipper_zero", profileURL: URL(string: "https://www.instagram.com/_u/flipper_zero")!, followedSince: Date(timeIntervalSince1970: 1_793_097_949))])
}
@Test func parsesFollowersArrayWithEmptyTitle() throws { /* array, title "", value "zoe" */ #expect(try ExportParser.parseFollowers(Fixtures.followersJSON(["zoe"])) == ["zoe"]) }
@Test func usernameFallsBackToValueThenHref()
@Test func missingTimestampGivesNilDate()
@Test func rejectsUnknownRoot()  // {"foo": 1} -> throws .unrecognizedFormat
@Test func fixesMojibake() { #expect(ExportParser.fixMojibake("caff\u{00C3}\u{00A8}") == "caffè"); #expect(ExportParser.fixMojibake("caffè") == "caffè") }
@Test func locateFindsSplitFilesAndIgnoresHashtags()  // temp dir con following.json, following_2.json, following_hashtags.json, followers_1.json
@Test func loadDedupesCaseInsensitiveKeepingOldest()  // "Anna"@200 in un file, "anna"@100 nell'altro -> un solo "anna" @100
```
- [ ] **Step 2: Esegui** `swift test --filter ExportParserTests` e `--filter ExportLocatorTests`. Atteso: FAIL.
- [ ] **Step 3: Implementa** `ExportParser` e `ExportLocator` con `JSONSerialization`. La struttura varia tra un export e l'altro, quindi niente `Codable` rigido.
- [ ] **Step 4: Esegui** gli stessi comandi. Atteso: PASS.
- [ ] **Step 5: Verifica sul file reale (solo in locale, niente commit)**: aggiungi un test temporaneo che chiama `ExportLocator.load(ExportLocator.locate(in: <repo>/connections))` e controlla `follows.count == 6079` e `followers.count == 726`. Eseguilo, poi elimina il test.
- [ ] **Step 6: Commit** `feat: parse Instagram export (following/followers)`

---

### Task 3: Merge dell'import

**Files:**
- Create: `Sources/InstaSwipeKit/Import/MergeEngine.swift`
- Test: `Tests/InstaSwipeKitTests/MergeEngineTests.swift`

**Interfaces:**
- Consumes: `AppState`, `ExportSnapshot` (Task 1, 2)
- Produces:
  - `public struct MergeSummary: Equatable, Sendable { newAccounts: Int; noLongerFollowed: Int; autoMarkedDone: Int; isSuspicious: Bool }`
  - `public struct MergePreview: Equatable, Sendable { state: AppState; summary: MergeSummary }`
  - `public enum MergeEngine { static func preview(current: AppState?, snapshot: ExportSnapshot, now: Date) -> MergePreview }`

Regole (spec, sezione "Reimport"):
- `current == nil` → stato nuovo con tutti gli account `pending`, `availability .unknown`, `stillInLatestExport = true`; `newAccounts` = totale.
- Account già presenti: decisione, spunta e date invariate; `followsMe` aggiornato; `stillInLatestExport = true`; `unavailable` → `unknown`.
- Account nuovi: aggiunti `pending`, poi l'array viene riordinato in ordine di revisione.
- Account assenti dal nuovo export: `stillInLatestExport = false`. Se `decision == .remove && !unfollowedManually` → anche `unfollowedManually = true`, `unfollowedAt = nil` (così non conta nel contatore di oggi; scostamento voluto dalla spec, che diceva "data dell'import"), e conta in `autoMarkedDone`.
- `noLongerFollowed` = account che passano da `stillInLatestExport` true a false (compresi gli auto-fatti).
- `isSuspicious` = `noLongerFollowed > reimportSuspiciousRatio × (account attivi prima del merge)`.

- [ ] **Step 1: Scrivi i test che falliscono**:

```swift
@Test func firstImportCreatesPendingAccountsInOldestFirstOrder()   // export in ordine dal più recente -> accounts[0] è il più vecchio
@Test func reimportKeepsDecisionsAndUpdatesFollowsMe()
@Test func reimportAddsNewAccountsInChronologicalPosition()
@Test func removedAndMissingIsAutoMarkedDoneWithoutDate()  // unfollowedManually == true, unfollowedAt == nil, summary.autoMarkedDone == 1
@Test func keptAndMissingIsHiddenNotDeleted()               // stillInLatestExport == false, decision == .keep, accounts.count invariato
@Test func unavailableAccountIsRecheckedOnReimport()        // .unavailable -> .unknown
@Test func reimportSameExportIsNoOp()                       // summary == MergeSummary(0,0,0,false) e accounts identici
@Test func losingMoreThan20PercentIsSuspicious()            // 10 attivi, 3 spariscono -> true; 2 spariscono -> false
```
- [ ] **Step 2: Esegui** `swift test --filter MergeEngineTests`. Atteso: FAIL.
- [ ] **Step 3: Implementa** `MergeEngine.preview`.
- [ ] **Step 4: Esegui** lo stesso comando. Atteso: PASS.
- [ ] **Step 5: Commit** `feat: merge export into saved state without losing decisions`

---

### Task 4: Revisione (coda, decisione, annulla, avanzamento)

**Files:**
- Create: `Sources/InstaSwipeKit/Review/Review.swift`
- Test: `Tests/InstaSwipeKitTests/ReviewTests.swift`

**Interfaces:**
- Produces:
  - `public struct Progress: Equatable, Sendable { decided: Int; total: Int }`
  - `public enum Review`:
    - `static func current(in: AppState) -> FollowedAccount?`: primo account in ordine con `decision == .pending`, `stillInLatestExport`, `availability != .unavailable`.
    - `static func next(after username: String, in: AppState) -> FollowedAccount?`: il successivo che rispetta lo stesso criterio (serve per il precaricamento).
    - `static func decide(_: Decision, username: String, in: AppState, now: Date) -> AppState`: imposta `decision` e `decidedAt` (`nil` se `.pending`); `totalDecisionsMade += 1` solo per keep/remove. Usata sia dallo swipe sia dall'elenco.
    - `static func undo(in: AppState) -> AppState`: l'account non `pending` con `decidedAt` più recente torna `pending`, con `decidedAt`, `unfollowedManually` e `unfollowedAt` azzerati. Se non c'è nulla da annullare, lo stato resta invariato.
    - `static func markAvailability(_: Availability, displayName: String?, username: String, in: AppState) -> AppState`: non tocca mai `decision`; `displayName` viene aggiornato solo se non è `nil`.
    - `static func progress(in: AppState) -> Progress`: `total` = account con `stillInLatestExport && availability != .unavailable`; `decided` = quelli tra questi non `pending`.

- [ ] **Step 1: Scrivi i test che falliscono**:

```swift
@Test func currentIsOldestPendingSkippingUnavailableAndHidden()
@Test func nextSkipsTheSameWay()
@Test func decideSetsDecisionDateAndCounter()        // totalDecisionsMade 0 -> 1; decidedAt == now
@Test func decidePendingClearsDate()                  // e non incrementa il contatore
@Test func undoRevertsMostRecentDecision()            // decidi A (t1), B (t2) -> undo -> B pending, A remove
@Test func undoClearsDoneFlag()
@Test func undoWithNothingDecidedIsNoOp()
@Test func markAvailabilityKeepsExistingDecision()   // A .remove, poi markAvailability(.unavailable) -> decision ancora .remove
@Test func progressExcludesUnavailableAndHidden()    // 5 account: 1 unavailable, 1 nascosto, 1 deciso -> Progress(decided: 1, total: 3)
@Test func decideDoesNotMutateInput()                // il vecchio stato resta uguale
```
- [ ] **Step 2: Esegui** `swift test --filter ReviewTests`. Atteso: FAIL.
- [ ] **Step 3: Implementa** `Review`.
- [ ] **Step 4: Esegui** lo stesso comando. Atteso: PASS.
- [ ] **Step 5: Commit** `feat: review queue with decide, undo and progress`

---

### Task 5: Elenco "Da togliere", contatori giornalieri, tetto profili, CSV

**Files:**
- Create: `Sources/InstaSwipeKit/Review/Report.swift`, `Review/ProfileBudget.swift`, `Export/CSVExporter.swift`
- Test: `ReportTests.swift`, `ProfileBudgetTests.swift`, `CSVExporterTests.swift`

**Interfaces:**
- Produces:
  - `public enum ReportFilter: String, CaseIterable, Sendable { case toDo, done, gone, kept }`
  - `public enum Report`:
    - `static func accounts(_: ReportFilter, search: String, in: AppState) -> [FollowedAccount]`. Con `search` vuoto applica il filtro: `toDo` = remove ∧ ¬fatto ∧ ¬unavailable; `done` = remove ∧ fatto; `gone` = unavailable ∧ stillInLatestExport; `kept` = keep. Con `search` non vuoto **ignora il filtro** e cerca tra tutti gli account non `pending` (username o displayName, senza distinzione di maiuscole e accenti).
    - `static func counts(in: AppState) -> [ReportFilter: Int]`
    - `static func setUnfollowed(_ done: Bool, username: String, in: AppState, now: Date) -> AppState`: `unfollowedAt = done ? now : nil`.
    - `static func unfollowsToday(in: AppState, now: Date, calendar: Calendar) -> Int`
  - `public enum BudgetStatus: Equatable, Sendable { case available(remaining: Int), limitReached, emergencyStopped }`
  - `public enum ProfileBudget { static func status(in: AppState, now: Date, calendar: Calendar) -> BudgetStatus; static func recordLoad(in: AppState, now: Date, calendar: Calendar) -> AppState; static func recordEmergencyStop(in: AppState, now: Date, calendar: Calendar) -> AppState; static func setDailyLimit(_: Int, in: AppState) -> AppState }`. Se `profileLoads.day` non è oggi il contatore vale 0. `setDailyLimit` accetta valori tra 50 e 2000 (clamp).
  - `public enum CSVExporter { static func csv(for: [FollowedAccount]) -> String }`: header esatto `username,link,data follow,decisione,fatto,ti segue`. Data `yyyy-MM-dd` (vuota se nil); decisione `da decidere|tengo|tolgo`; fatto e ti segue `sì|no`. Campi tra virgolette quando contengono `,` `"` o newline, con `"` raddoppiate; righe separate da `\n`.

- [ ] **Step 1: Scrivi i test che falliscono**:

```swift
@Test func toDoListsRemovedNotDoneAndNotGone()
@Test func searchIgnoresFilterAndMatchesDisplayNameWithoutAccents()   // "lucà" trova displayName "Luca"
@Test func setUnfollowedStampsAndClearsDate()
@Test func unfollowsTodayCountsOnlyToday()
@Test func countersResetOnNewDay()          // 23:59 -> 400 caricati -> .limitReached; 00:01 del giorno dopo -> .available(remaining: 400)
@Test func budgetReachesLimitAtDailyLimit() // 399 -> .available(remaining: 1); dopo recordLoad -> .limitReached
@Test func emergencyStopBlocksTodayOnly()
@Test func emergencyStopExpiresNextDay()
@Test func dailyLimitIsClamped()            // 10 -> 50, 99999 -> 2000
@Test func csvHasExactHeaderAndEscapes()    // prima riga == header esatto; un campo con `a,"b"` diventa `"a,""b"""`
@Test func csvFormatsDecisionAndFlagsInItalian()
```
Usa `Calendar(identifier: .gregorian)` con `timeZone = Europe/Rome` nei test.
- [ ] **Step 2: Esegui** `swift test --filter "ReportTests|ProfileBudgetTests|CSVExporterTests"`. Atteso: FAIL.
- [ ] **Step 3: Implementa** `Report`, `ProfileBudget` e `CSVExporter`.
- [ ] **Step 4: Esegui** lo stesso comando. Atteso: PASS.
- [ ] **Step 5: Commit** `feat: report filters, daily counters, profile budget and CSV`

---

### Task 6: Persistenza (locale atomica, mirror iCloud, backup)

**Files:**
- Create: `Sources/InstaSwipeKit/Persistence/FileStateStore.swift`, `Persistence/BackupRotator.swift`
- Test: `FileStateStoreTests.swift`, `BackupRotatorTests.swift` (directory temporanee, iCloud simulato come semplice cartella)

**Interfaces:**
- Produces:
  - `public enum StateStoreError: Error, Equatable { case corrupted(quarantined: [URL]) }`
  - `public final class FileStateStore: Sendable`:
    - `init(localDirectory: URL, cloudDirectory: URL?)`
    - `func load() throws -> AppState?`: legge `state.json` da locale e da cloud. Un file illeggibile viene rinominato `state.corrupt-<yyyyMMdd-HHmmss>.json` e ignorato. Con due copie valide vince quella con `savedAt` più recente; se vince il cloud, la copia viene riscritta anche in locale. `nil` solo se non esiste nessun file. Se esistevano file ma sono tutti corrotti lancia `.corrupted`.
    - `func save(_: AppState) throws`: scrittura locale `Data.write(to:options: .atomic)`; crea la directory se manca.
    - `func mirrorToCloud(_: AppState) throws`: scrittura atomica in `cloudDirectory/state.json` dentro `NSFileCoordinator.coordinate(writingItemAt:options: .forReplacing)`. No-op se `cloudDirectory == nil`.
  - `public enum BackupKind: Sendable { case daily, step(Int), preImport }`
  - `public struct BackupRotator: Sendable`:
    - `init(directory: URL)` (`<cloud o locale>/Backups`)
    - `func backupIfNeeded(_: AppState, now: Date, calendar: Calendar) throws -> [BackupKind]`: scrive `daily-yyyy-MM-dd.json` se manca quello di oggi, e `step-<n>.json` quando `totalDecisionsMade` è un multiplo positivo di 100 e il file non esiste. Restituisce ciò che ha scritto.
    - `func backup(_: AppState, kind: BackupKind, now: Date) throws`: `preImport` → `preimport-yyyyMMdd-HHmmss.json`.
    - Dopo ogni scrittura applica la potatura: tiene i 14 daily, i 10 step e i 5 preImport più recenti (per nome).

- [ ] **Step 1: Scrivi i test che falliscono**:

```swift
@Test func saveThenLoadReturnsSameState()
@Test func saveIsAtomicLeavesNoTempFiles()
@Test func loadPrefersNewestOfLocalAndCloud()           // e riscrive locale se vince cloud
@Test func loadRestoresFromCloudWhenLocalMissing()      // simula app cancellata e reinstallata
@Test func loadQuarantinesCorruptLocalAndUsesCloud()
@Test func loadThrowsWhenBothCorrupt()                  // .corrupted con 2 URL, file originali non più presenti col vecchio nome, nessun state.json nuovo creato
@Test func loadReturnsNilWhenNothingSaved()
@Test func storeWorksWithoutCloudDirectory()
@Test func dailyBackupOncePerDay()
@Test func stepBackupEveryHundredDecisions()            // 99 -> nessuno step, 100 -> step-100, 100 di nuovo -> nessun duplicato
@Test func pruningKeepsNewest()                         // 16 daily -> restano 14, i più recenti
```
- [ ] **Step 2: Esegui** `swift test --filter "FileStateStoreTests|BackupRotatorTests"`. Atteso: FAIL.
- [ ] **Step 3: Implementa** `FileStateStore` e `BackupRotator` con `StateCoding`.
- [ ] **Step 4: Esegui** lo stesso comando. Atteso: PASS.
- [ ] **Step 5: Commit** `feat: atomic local persistence, iCloud mirror and rotating backups`

---

### Task 7: Classificazione della pagina profilo

**Files:**
- Create: `Sources/InstaSwipeKit/Profile/ProfilePageClassifier.swift`
- Test: `ProfilePageClassifierTests.swift`

**Interfaces:**
- Produces:
  - `public struct ProfilePageSnapshot: Equatable, Sendable { finalURL: URL; title: String; ogTitle: String?; ogImage: URL?; bodyText: String }`
  - `public enum ProfilePageResult: Equatable, Sendable { case profile(displayName: String?, imageURL: URL?), unavailable, rateLimited, loginRequired, unrecognized }`
  - `public enum ProfilePageClassifier { static func classify(_: ProfilePageSnapshot, username: String) -> ProfilePageResult }`

Regole, in ordine di priorità. Le frasi sono costanti in un array, da aggiornare con quelle reali al Task 9:
1. Il path di `finalURL` contiene `/accounts/login` → `.loginRequired`.
2. Il path contiene `/challenge` o `/accounts/suspended`, oppure `bodyText` contiene una frase di limite ("Please wait a few minutes before you try again", "Attendi qualche minuto prima di riprovare", "Try Again Later", "Riprova più tardi") → `.rateLimited`.
3. `ogTitle` contiene `(@<username>)` senza distinzione di maiuscole → `.profile`, con nome = testo prima di ` (@` ripulito (`nil` se vuoto o uguale allo username) e immagine = `ogImage`.
4. `ogTitle == nil` e `bodyText` contiene una frase di pagina mancante ("Sorry, this page isn't available", "Questa pagina non è disponibile") → `.unavailable`.
5. Altrimenti `.unrecognized`. Per la regola "marca spariti solo su segnale positivo e specifico", nel dubbio non si marca mai `.unavailable`.

- [ ] **Step 1: Scrivi i test che falliscono**: un test per ogni regola, più:

```swift
@Test func parsesNameFromItalianOgTitle()   // "Luca Diddi (@luca_diddi) • Foto e video di Instagram" -> .profile("Luca Diddi", img)
@Test func nameEqualToUsernameBecomesNil()
@Test func unavailableNeedsMissingOgTitle() // frase presente ma ogTitle valido -> .profile
@Test func emptyPageIsUnrecognizedNotUnavailable()
```
- [ ] **Step 2: Esegui** `swift test --filter ProfilePageClassifierTests`. Atteso: FAIL.
- [ ] **Step 3: Implementa** `ProfilePageClassifier`.
- [ ] **Step 4: Esegui** `swift test --enable-code-coverage` e poi `xcrun llvm-cov report .build/debug/InstaSwipeKitPackageTests.xctest/Contents/MacOS/InstaSwipeKitPackageTests -instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex='Tests|\.build'`. Atteso: tutti i test PASS, TOTAL lines ≥ 80%.
- [ ] **Step 5: Commit** `feat: classify Instagram profile page snapshots`

---

### Task 8: Progetto app, AppModel, import e merge in UI

**Files:**
- Create: `project.yml`, `InstaSwipe/{InstaSwipeApp,AppModel,AppEnvironment}.swift`, `InstaSwipe/InstaSwipe.entitlements`, `InstaSwipe/Info.plist`, `InstaSwipe/Onboarding/{ImportView,MergeSummaryView}.swift`, `InstaSwipe/Settings/SettingsView.swift` (per ora solo "Reimporta export"), `InstaSwipeUITests/` (vuota, target pronto)
- Modify: `.gitignore` (aggiungere `InstaSwipe.xcodeproj/`: il progetto si rigenera)

**Interfaces:**
- Consumes: tutto il package.
- Produces:
  - `@MainActor @Observable final class AppModel`:
    - `private(set) var state: AppState?`, `private(set) var loadError: String?`, `let isCloudAvailable: Bool`, `var pendingMerge: MergePreview?`
    - `init(environment: AppEnvironment)`: chiama `store.load()`. Se lancia, imposta `loadError` e **blocca ogni salvataggio** finché l'app è aperta.
    - `func apply(_ transform: (AppState) -> AppState)`: calcola il nuovo stato con `savedAt = now`, `store.save` sincrono, poi `backups.backupIfNeeded`, poi programma `mirrorToCloud` con debounce di 5 s. Se `save` fallisce, mostra l'errore e non aggiorna `state`.
    - `func flushCloudMirror()`: chiamata su `scenePhase == .background`.
    - `func prepareImport(folder: URL) async` (accesso security-scoped, `ExportLocator`, `MergeEngine.preview`, imposta `pendingMerge`) e `func confirmImport()` (backup `preImport` se esiste uno stato, poi `apply`).
  - `struct AppEnvironment { localDirectory: URL; cloudDirectory: URL?; isUITesting: Bool; useFakeProfiles: Bool; static func resolve() -> AppEnvironment }`: locale = Application Support/InstaSwipe; cloud = `url(forUbiquityContainerIdentifier:)` + `Documents`, risolta fuori dal main thread all'avvio. Argomento di lancio `-uiTestStateDir <path>`: usa quella directory, cloud `nil`, profili finti. Argomento `-uiTestSeed`: se lo stato non esiste, importa 5 account sintetici `test_01…test_05`, con `followedSince` crescente nello stesso ordine e `test_02` che ti segue.
  - `InstaSwipeApp`: senza stato mostra `ImportView`; con stato mostra una `TabView` con "Swipe" (segnaposto fino al Task 10) e "Da togliere" (segnaposto fino al Task 11), più l'ingranaggio delle impostazioni. Con `!isCloudAvailable` mostra il banner "Le copie su iCloud sono disattivate"; con `loadError` mostra una schermata di errore che non permette di continuare.

- [ ] **Step 1: Verifica il Team ID**: `security find-identity -v -p codesigning` mostra "Developer ID Application: Giacomo Grieco (CBRAP62CDG)". Conferma con Giacomo che `CBRAP62CDG` è il team del suo account a pagamento.
- [ ] **Step 2: Installa XcodeGen** con `brew install xcodegen`, poi scrivi `project.yml`: target `InstaSwipe` (application, iOS 17.0, solo iPhone `TARGETED_DEVICE_FAMILY: 1`, bundle id e team dai Global Constraints, dipendenza dal package locale `Packages/InstaSwipeKit`, entitlements iCloud Documents con il container) e target `InstaSwipeUITests` (bundle.ui-testing). L'`Info.plist` contiene `NSUbiquitousContainers` → `iCloud.com.giacomogrieco.InstaSwipe` → `NSUbiquitousContainerIsDocumentScopePublic: true`, `NSUbiquitousContainerName: InstaSwipe`, `NSUbiquitousContainerSupportedFolderLevels: Any`.
- [ ] **Step 3: Implementa** `AppEnvironment`, `AppModel`, `ImportView` (`.fileImporter(allowedContentTypes: [.folder, .json])`; con un JSON selezionato usa la sua cartella), `MergeSummaryView` (mostra i 4 numeri; con `isSuspicious` mostra l'avviso rosso "Sembra un export incompleto: controlla di aver scelto l'intervallo «Sempre»"; pulsanti "Applica" e "Annulla") e `InstaSwipeApp`.
- [ ] **Step 4: Compila**: `xcodegen generate && xcodebuild -project InstaSwipe.xcodeproj -scheme InstaSwipe -destination 'platform=iOS Simulator,name=iPhone 17' build`. Atteso: `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Prova manuale sul simulatore**: copia una cartella con fixture sintetiche nel simulatore (trascinandola in File), importala, verifica il riepilogo, chiudi e riapri l'app e controlla che lo stato sia ancora lì.
- [ ] **Step 6: Commit** `feat: app shell with persistence-backed AppModel and export import`

---

### Task 9: WebView, login, caricamento profili, miniature

**Files:**
- Create: `InstaSwipe/Web/{WebView,LoginView,ProfileLoader,ThumbnailCache}.swift`
- Modify: `Sources/InstaSwipeKit/Profile/ProfilePageClassifier.swift` (frasi reali), `ProfilePageClassifierTests.swift`

**Interfaces:**
- Consumes: `ProfilePageSnapshot`, `ProfilePageClassifier` (Task 7).
- Produces:
  - `@MainActor protocol ProfileLoading { func load(username: String) async -> ProfilePageResult }`
  - `@MainActor final class WebProfileLoader: ProfileLoading`: una `WKWebView` nascosta con `WKWebsiteDataStore.default()` per ogni richiesta in corso (al massimo 2: corrente e successiva). Carica `https://www.instagram.com/<username>/`. Dopo `didFinish` estrae lo snapshot con lo script qui sotto. Timeout `Limits.profileLoadTimeout` → `.unrecognized`. Se la WebView non carica fuori dalla gerarchia, va aggiunta alla finestra con frame 1×1 e `alpha = 0`.
  - `@MainActor final class FakeProfileLoader: ProfileLoading`: restituisce `.profile(displayName: "Test \(username)", imageURL: nil)` dopo 50 ms.
  - `struct WebView: UIViewRepresentable` (URL, stesso data store) e `LoginView` (WebView su `https://www.instagram.com/accounts/login/` più il pulsante "Fatto").
  - `actor ThumbnailCache { func image(for username: String) -> UIImage?; func store(from url: URL, username: String) async }`: scarica con `URLSession`, ridimensiona a 200 px, salva JPEG in `Caches/thumbnails/<username>.jpg`.

Script di estrazione (sola lettura):

```js
(() => ({ url: location.href, title: document.title,
  ogTitle: document.querySelector('meta[property="og:title"]')?.content ?? null,
  ogImage: document.querySelector('meta[property="og:image"]')?.content ?? null,
  body: (document.body?.innerText ?? '').slice(0, 3000) }))()
```

- [ ] **Step 1: Implementa** i quattro file.
- [ ] **Step 2: Compila** con il comando del Task 8. Atteso: `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Verifica sull'iPhone reale** (da fare con Giacomo, una manciata di caricamenti in tutto): login; un profilo esistente (deve dare `.profile` con nome e foto); un account dell'export che non esiste più (`.unavailable`); un profilo privato. Registra gli snapshot reali in `print` solo durante la verifica.
- [ ] **Step 4: Aggiorna classificatore e test** con le frasi e i formati di `og:title` visti davvero. Aggiungi un test per ciascuno snapshot reale, anonimizzato (username finti). Esegui `swift test`. Atteso: PASS.
- [ ] **Step 5: Commit** `feat: hidden WebView profile loader, login and thumbnail cache`

---

### Task 10: Schermata Swipe

**Files:**
- Create: `InstaSwipe/Swipe/{SwipeView,SwipeSession,AccountCardView,LimitReachedView}.swift`
- Modify: `InstaSwipe/InstaSwipeApp.swift` (tab "Swipe")

**Interfaces:**
- Consumes: `AppModel.apply`, `Review.*`, `ProfileBudget.*`, `ProfileLoading`, `ThumbnailCache`.
- Produces:
  - `@MainActor @Observable final class SwipeSession`: `current: FollowedAccount?`, `currentResult: ProfilePageResult?`, `isOfflineSession: Bool` (non persistito), `func start()`, `func decide(_: Decision)`, `func undo()`.
    - Prima di ogni caricamento (corrente e successiva) controlla `ProfileBudget.status`. Con `.available` chiama `apply(recordLoad)` e poi il loader. Altrimenti non carica.
    - Risultati: `.profile` → `markAvailability(.available, displayName)` e salvataggio della miniatura; `.unavailable` → `markAvailability(.unavailable)` e, se era la card corrente, passaggio automatico alla successiva; `.rateLimited` → `recordEmergencyStop`; `.loginRequired` → presenta `LoginView`; `.unrecognized` → card di fallback.
    - `decide` chiama `apply(Review.decide…)`, che salva in modo sincrono, e solo dopo mostra la successiva, riusando il risultato già precaricato se c'è.
  - Accessibility identifier: `progressLabel` ("1.240 / 5.622", formattato con il separatore italiano), `profilesTodayLabel` ("Profili oggi: 312 / 400"), `cardUsername`, `removeButton`, `undoButton`, `keepButton`.

Comportamento (spec, design C):
- La card mostra foto grande (segnaposto se manca), nome, `@username`, "Lo segui dal <d MMM yyyy>" ed etichetta verde "Ti segue". Con un tocco si apre `WebView` a schermo intero sul profilo, che conta come caricamento nel budget.
- Gesture: trascinamento orizzontale, oltre 120 pt → decisione; sotto la soglia la card torna al centro. Rotazione e haptics a discrezione.
- `LimitReachedView`: per `.limitReached` mostra "Per oggi basta, riprendi domani"; per `.emergencyStopped` mostra "Instagram ha chiesto di rallentare: ci fermiamo fino a domani". Pulsante secondario "Continua senza profili", con conferma, che imposta `isOfflineSession`. Quando `Review.current == nil` mostra la schermata di fine con il riepilogo tenuti/da togliere/spariti e un pulsante che porta a "Da togliere".

- [ ] **Step 1: Implementa** i quattro file.
- [ ] **Step 2: Compila** con il comando del Task 8. Atteso: `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Prova sul simulatore con `-uiTestStateDir /tmp/is -uiTestSeed`**: swipe a sinistra e a destra, annulla due volte, chiusura forzata e riapertura sulla stessa card.
- [ ] **Step 4: Commit** `feat: swipe screen with card, undo, budget and limit states`

---

### Task 11: Elenco "Da togliere", ritorno da Instagram, CSV, impostazioni

**Files:**
- Create: `InstaSwipe/Report/{ReportView,ReportRow,ReturnPromptSheet}.swift`
- Modify: `InstaSwipe/Settings/SettingsView.swift`, `InstaSwipe/InstaSwipeApp.swift` (tab "Da togliere")

**Interfaces:**
- Consumes: `Report.*`, `Review.decide`, `CSVExporter.csv`, `ProfileBudget.setDailyLimit`, `ThumbnailCache`.
- Produces: accessibility identifier `todayCounter` ("Oggi: 37 unfollow segnati"), `reportRow-<username>`, `doneToggle-<username>`.

Comportamento:
- In alto il contatore di oggi; da `Limits.dailyUnfollowWarning` (150) in su diventa un avviso arancione ben visibile, senza bloccare niente. Sotto, un `Picker` segmentato Da fare / Fatti / Spariti / Tenuti con i conteggi, e `.searchable`.
- Riga: miniatura (da `ThumbnailCache`, altrimenti iniziale), nome, `@username`, "ti segue", cerchio di spunta che chiama `Report.setUnfollowed`. Con lo swipe sulla riga: "Tengo" / "Tolgo" / "Da decidere" (`Review.decide`). Sulle righe "Spariti" c'è anche "Riprova" → `markAvailability(.unknown)`.
- Tocco sulla riga: `openURL(profileURL)` e memorizza `returnPromptUsername`. Quando `scenePhase` torna `.active` e c'è un username in attesa, mostra `ReturnPromptSheet`: "Hai tolto il follow a @…?" con "Sì, segna come fatto", "Non ancora" e "Ho cambiato idea, lo tengo".
- Il pulsante di condivisione nella toolbar usa `ShareLink` su un file temporaneo `InstaSwipe-<yyyy-MM-dd>.csv` con tutti gli account.
- Impostazioni: stepper per il tetto giornaliero (50–2000, passo 50), "Reimporta export", "Accedi di nuovo a Instagram", stato di iCloud.

- [ ] **Step 1: Implementa** i file.
- [ ] **Step 2: Compila** con il comando del Task 8. Atteso: `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Prova sul simulatore con i dati seed**: spunta, togli la spunta, contatore, ricerca, cambio di decisione dall'elenco seguito da annulla nello swipe, export CSV aperto in File.
- [ ] **Step 4: Commit** `feat: unfollow list with return prompt, search, CSV and settings`

---

### Task 12: E2E di persistenza e verifica sul dispositivo

**Files:**
- Create: `InstaSwipeUITests/PersistenceFlowTests.swift`

- [ ] **Step 1: Scrivi il test UI** (XCTest), che usa una directory di stato unica per ogni esecuzione:

```swift
func testDecisionsSurviveRelaunch() {
    let dir = NSTemporaryDirectory() + UUID().uuidString
    let app = XCUIApplication(); app.launchArguments = ["-uiTestStateDir", dir, "-uiTestSeed"]; app.launch()
    XCTAssertEqual(app.staticTexts["progressLabel"].label, "0 / 5")
    app.buttons["removeButton"].tap(); app.buttons["keepButton"].tap()
    XCTAssertEqual(app.staticTexts["progressLabel"].label, "2 / 5")
    app.terminate(); app.launch()
    XCTAssertEqual(app.staticTexts["progressLabel"].label, "2 / 5")
    XCTAssertEqual(app.staticTexts["cardUsername"].label, "@test_03")
    app.tabBars.buttons["Da togliere"].tap()
    app.buttons["doneToggle-test_01"].tap()
    XCTAssertTrue(app.staticTexts["todayCounter"].label.hasPrefix("Oggi: 1"))
    app.terminate(); app.launch(); app.tabBars.buttons["Da togliere"].tap()
    XCTAssertTrue(app.staticTexts["todayCounter"].label.hasPrefix("Oggi: 1"))
}
func testUndoRestoresPreviousCard()   // remove test_01 -> undo -> cardUsername "@test_01", progress "0 / 5"
```
- [ ] **Step 2: Esegui** `xcodebuild test -project InstaSwipe.xcodeproj -scheme InstaSwipe -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InstaSwipeUITests`. Atteso: `** TEST SUCCEEDED **`. Se fallisce, correggi l'app, non il test.
- [ ] **Step 3: Esegui di nuovo tutto il package**: `cd Packages/InstaSwipeKit && swift test`. Atteso: PASS.
- [ ] **Step 4: Verifica sul dispositivo con Giacomo**: installazione sull'iPhone, import dell'export reale da File (6.079 account; il totale atteso scende man mano che vengono trovati gli spariti), una ventina di swipe, chiusura forzata e riapertura, controllo che in File → iCloud Drive → InstaSwipe ci siano `state.json` e `Backups/daily-…json`.
- [ ] **Step 5: Commit** `test: end-to-end persistence flow`

---

## Copertura della spec (self-review)

| Requisito della spec | Task |
|---|---|
| Parser tollerante, più file, mojibake | 2 |
| Ordine dal più vecchio, ripresa dal punto esatto | 1, 4, 12 |
| Reimport in due passi, riepilogo, avviso >20%, backup pre-import | 3, 6, 8 |
| Card C con foto/nome dalla pagina, fallback, tocco → profilo intero | 7, 9, 10 |
| Spariti: segnale rigoroso, non definitivo, riprova | 3, 4, 7, 11 |
| Tetto 400/giorno modificabile, freno d'emergenza, continua senza profili | 5, 10, 11 |
| Salvataggio atomico dopo ogni mutazione, iCloud, ripristino, backup a rotazione | 6, 8, 12 |
| Elenco Da togliere: filtri, ricerca, Tenuti, spunta, contatore 150, ritorno da Instagram | 5, 11 |
| CSV via share sheet | 5, 11 |
| Login una volta, sessione scaduta | 9, 10 |
| Avviso iCloud disattivato, errore di caricamento | 8 |
