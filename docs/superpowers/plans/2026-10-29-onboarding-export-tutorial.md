# Tutorial export Instagram – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sostituire l'attuale `ImportView` con un tutorial a 4 fasi (14 passi, screenshot in alto sempre in vista) che porta dall'app Instagram all'import, riprende dal passo 12 dopo l'attesa dell'email e si può riaprire dalle Impostazioni.

**Architecture:** Il contenuto (fasi, passi, testi, nomi delle immagini) e la regola "da quale fase si parte" sono tipi puri in `InstaSwipe/Onboarding/ExportTutorial.swift`. Il punto di ripresa è un flag in `UserDefaults`, posseduto da `AppModel`, che lo azzera a ogni import confermato. Le view (`ExportTutorialView`, `TutorialPhaseView`) leggono questi tipi. La fase 4 riusa i controlli di import che oggi stanno in `ImportView`, estratti in `ImportControls`.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, Swift Testing (unit app), XCUITest, XcodeGen, CoreGraphics (script per oscurare gli screenshot).

**Spec:** `docs/superpowers/specs/2026-10-29-onboarding-export-tutorial-design.md`

## Global Constraints

- iOS 17.0, solo iPhone, Swift 6 (`project.yml`). Dopo aver aggiunto file o asset: `xcodegen generate`.
- UI in italiano. Testi dei passi **esattamente** come nella tabella "Contenuto: i 14 passi" della spec.
- Stile: token `Theme`, font `.outfit(...)`, `GradientButtonStyle`, `riseIn()`.
- Nessun cambiamento a `InstaSwipeKit`, al formato di `AppState` o alla logica di import/merge oltre al reset del punto di ripresa.
- Asset `TutorialStep05` … `TutorialStep12` (spec, "Screenshot ricevuti"); mancano 01–04 e 13 → riquadro neutro `Theme.surface2` con il numero del passo. Passo 14: logo `Logo`.
- Gli originali in `~/Desktop/Screen` non si modificano; `IMG_7743` non si usa.
- Build: `xcodebuild -project InstaSwipe.xcodeproj -scheme InstaSwipe -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- Test unit: stesso comando con `test -only-testing:InstaSwipeTests`; UI: `-only-testing:InstaSwipeUITests`.

## Review Focus

1. **Import annullato o fallito nella fase 4** (cartella sbagliata, "Annulla" nel riepilogo): il punto di ripresa deve restare, così alla riapertura si è ancora alla fase 4 → test in Task 2.
2. **"Indietro" dalla fase 3 o 4 e poi chiusura dell'app:** si riapre comunque sulla fase 4 (la spec dice che "Indietro" non azzera) → test in Task 2.
3. **Due `MergeSummaryView` insieme** quando il tutorial è aperto come foglio sopra le Impostazioni: il foglio delle Impostazioni deve restare spento mentre il tutorial è aperto → controllo manuale in Task 5, step dedicato.
4. **Errore di import dentro il tutorial aperto dalle Impostazioni:** l'alert "Attenzione" deve comparire sopra il tutorial, non sotto → controllo manuale in Task 5.
5. **Schermi piccoli e testo grande** (iPhone 17e, Dynamic Type XL): la fase 1 (6 passi) deve scorrere senza tagliare il pulsante → controllo manuale in Task 4.

---

### Task 1: Contenuto del tutorial e fase di partenza

**Files:**
- Create: `InstaSwipe/Onboarding/ExportTutorial.swift`
- Test: `InstaSwipeTests/ExportTutorialTests.swift`

**Interfaces:**
- Produces:
  - `enum TutorialPhase: Int, CaseIterable, Identifiable { case openExport = 1, chooseData, waitForEmail, importFile }` con `var title: String` ("Apri l'esportazione", "Scegli cosa esportare", "Aspetta l'email", "Importa"), `var steps: [TutorialStep]`, `var next: TutorialPhase?`, `var previous: TutorialPhase?`.
  - `struct TutorialStep: Identifiable, Equatable { let number: Int; let text: String; let imageName: String? }`, `id` = `number`.
  - `enum ExportTutorial { static let steps: [TutorialStep]; static func startPhase(hasStartedExport: Bool) -> TutorialPhase }`.
  - `imageName` = `String(format: "TutorialStep%02d", number)` per i passi 1–13, `nil` per il 14.

- [ ] **Step 1: Scrivi i test che falliscono**

```swift
@Test func fourteenStepsNumberedInOrder() {
    #expect(ExportTutorial.steps.map(\.number) == Array(1...14))
}
@Test func phasesSplitStepsAsInTheSpec() {
    #expect(TutorialPhase.openExport.steps.map(\.number) == Array(1...6))
    #expect(TutorialPhase.chooseData.steps.map(\.number) == Array(7...10))
    #expect(TutorialPhase.waitForEmail.steps.map(\.number) == [11])
    #expect(TutorialPhase.importFile.steps.map(\.number) == [12, 13, 14])
}
@Test func stepTextsMatchTheSpec() {
    #expect(ExportTutorial.steps[6].text == "In «Personalizza informazioni» deseleziona tutto tranne «Follower e persone/Pagine seguite»")
    #expect(ExportTutorial.steps[13].text == "Comincia a swipare!")
}
@Test func imageNamesAreZeroPaddedAndLastStepHasNone() {
    #expect(ExportTutorial.steps[4].imageName == "TutorialStep05")
    #expect(ExportTutorial.steps[13].imageName == nil)
}
@Test func startsFromImportOnlyAfterExportStarted() {
    #expect(ExportTutorial.startPhase(hasStartedExport: false) == .openExport)
    #expect(ExportTutorial.startPhase(hasStartedExport: true) == .importFile)
}
@Test func phaseNavigationStopsAtTheEnds() {
    #expect(TutorialPhase.openExport.previous == nil)
    #expect(TutorialPhase.importFile.next == nil)
    #expect(TutorialPhase.chooseData.next == .waitForEmail)
}
```

- [ ] **Step 2: `xcodegen generate` e test unit → FAIL** (tipi non definiti).
- [ ] **Step 3: Implementa** `ExportTutorial.swift`: i 14 testi copiati dalla tabella della spec; ogni fase filtra `steps` per intervallo di numeri.
- [ ] **Step 4: Test unit → PASS.**
- [ ] **Step 5: Commit** `feat: add the export tutorial content and start phase`

---

### Task 2: Punto di ripresa

**Files:**
- Create: `InstaSwipe/Onboarding/TutorialProgressStore.swift`
- Modify: `InstaSwipe/AppEnvironment.swift` (nuovo campo), `InstaSwipe/AppModel.swift` (proprietà + `confirmImport()`), `InstaSwipeTests/TestSupport.swift`
- Test: `InstaSwipeTests/TutorialProgressTests.swift`

**Interfaces:**
- Consumes: `ExportTutorial.startPhase(hasStartedExport:)`.
- Produces:
  - `struct TutorialProgressStore { init(defaults: UserDefaults); var hasStartedExport: Bool { get }; func markExportStarted(); func reset() }`, chiave `"exportTutorial.hasStartedExport"`.
  - `AppEnvironment.defaultsSuiteName: String?` (`nil` = `.standard`). In UI-test mode vale `"uitest-" + <stateDir>`, così ogni esecuzione ha la sua suite (la stateDir è un UUID nuovo) ma un relaunch con la stessa stateDir la ritrova.
  - In `AppModel`: `private(set) var hasStartedExport: Bool`, `func markExportStarted()`, `func restartTutorial()` (azzera), `private(set) var confirmedImportCount = 0`. `confirmImport()`, quando `persist` riesce, chiama `reset()` e incrementa `confirmedImportCount`.
  - `TestSupport.environment(local:cloud:)` passa `defaultsSuiteName: UUID().uuidString`.

- [ ] **Step 1: Scrivi i test che falliscono** (`@MainActor`, stile `AppModelTests`, export finto come `makeExport` di `AppModelTests`: spostalo in `TestSupport` se serve a entrambi)

```swift
@Test func freshModelHasNotStartedExport()          // hasStartedExport == false
@Test func markExportStartedSurvivesANewModel()    // mark → nuovo AppModel stessa env → true
@Test func confirmedImportResetsTheResumePoint()   // mark → prepareImport + confirmImport → false, confirmedImportCount == 1
@Test func cancelledImportKeepsTheResumePoint()    // mark → prepareImport + cancelImport → true, confirmedImportCount == 0
@Test func failedImportKeepsTheResumePoint()       // mark → prepareImport(cartella vuota) → errorMessage != nil, true
@Test func restartTutorialClearsTheResumePoint()   // mark → restartTutorial → false
```

- [ ] **Step 2: Test unit → FAIL.**
- [ ] **Step 3: Implementa** store, campo in `AppEnvironment.resolve` (UI test: suite dalla stateDir; normale: `nil`), proprietà in `AppModel` letta dallo store in `init`.
- [ ] **Step 4: Test unit (tutti, inclusi quelli esistenti) → PASS.**
- [ ] **Step 5: Commit** `feat: remember when the Instagram export was started`

---

### Task 3: Screenshot oscurati nell'asset catalog

**Files:**
- Create: `InstaSwipe/Assets.xcassets/Tutorial/Contents.json` (cartella con `provides-namespace: false`), `InstaSwipe/Assets.xcassets/Tutorial/TutorialStep05.imageset` … `TutorialStep12.imageset` (PNG + `Contents.json`, scala universale `1x` non usata: un solo PNG con `"idiom": "universal"`)
- Script one-off (non committato): `<scratchpad>/redact.swift`, CoreGraphics + ImageIO, eseguito con `swift redact.swift <src> <dst>`

**Interfaces:**
- Produces: immagini con i nomi di `TutorialStep.imageName`.

Abbinamento (spec): 05←7744, 06←7745, 07←7747, 08←7748, 09←7749, 10←7750, 11←7746, 12←7751.

Coordinate indicative nelle anteprime 414×900 (moltiplica per 1320/414 ≈ 3,188 negli originali). Verificale guardando il risultato.

| File | Taglio verticale (tieni) | Copri con barra `#E6E3EA` arrotondata |
|---|---|---|
| 7744 | y 110–455 (via barra URL e «Download disponibili») | — |
| 7745 | y 110–812 | riga username y 185–205 |
| 7746 | y 110–812 | foto x 33–95 y 335–398; username x 100–235 y 340–362; email x 84–275 y 468–490 |
| 7747 | y 80–900 | — |
| 7748–7750 | y 80–900 | riga username y 152–174 |
| 7751 | y 80–900 | foto x 33–95 y 190–250; username x 100–220 y 192–212 |

- [ ] **Step 1: Scrivi ed esegui lo script** per gli 8 file; output ridimensionato a larghezza 750 px.
- [ ] **Step 2: Verifica visiva:** apri ogni PNG generato e controlla che non resti leggibile niente tra `giacomogrieco_`, foto profilo, l'email, il numero di telefono. Atteso: nessun dato personale visibile, testi dei menu leggibili.
- [ ] **Step 3: Crea gli imageset**, `xcodegen generate`, build → `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Commit** `feat: add redacted Instagram export screenshots`

---

### Task 4: Schermata del tutorial al posto di `ImportView`

**Files:**
- Create: `InstaSwipe/Onboarding/TutorialPhaseView.swift`, `InstaSwipe/Onboarding/ExportTutorialView.swift`
- Modify: `InstaSwipe/Onboarding/ImportView.swift` (resta `ExportPicker`, `ErrorAlert`; `ImportView` diventa `ImportControls`), `InstaSwipe/InstaSwipeApp.swift` (`RootView`: `.importer` → `ExportTutorialView(model: model, context: .onboarding)`)
- Test: `InstaSwipeUITests/ExportTutorialFlowTests.swift`

**Interfaces:**
- Consumes: Task 1 (`TutorialPhase`, `ExportTutorial`), Task 2 (`model.hasStartedExport`, `markExportStarted()`, `restartTutorial()`).
- Produces:
  - `struct ExportTutorialView: View { init(model: AppModel, context: TutorialContext) }`, `enum TutorialContext { case onboarding, settings }`. Fase iniziale = `ExportTutorial.startPhase(hasStartedExport: model.hasStartedExport)`. Arrivando su `.waitForEmail` chiama `model.markExportStarted()`. In `.onboarding` la fase 1 mostra logo + `Wordmark` sopra la barra.
  - `struct TutorialPhaseView: View { init(phase: TutorialPhase) }`: kicker `"FASE \(n) DI 4"`, barra di avanzamento (`n/4`, gradiente), titolo, carosello (`TabView` `.page`, altezza fissa ~ 46% dell'altezza disponibile, `scaledToFit`, angoli 18) legato a `@State selectedStep: Int`, lista con evidenza (`Theme.pink.opacity(0.08)`, numero `Theme.pink`); tocco su un passo → `selectedStep`. `imageName == nil` (passo 14) → immagine `Logo` centrata su `Theme.surface`. Immagine mancante (`UIImage(named:) == nil`) → riquadro `Theme.surface2` con `String(format: "%02d", number)`. `accessibilityLabel` dell'immagine = testo del passo.
  - Fase 3: sotto la lista, testo "L'email può arrivare anche dopo qualche ora. Puoi chiudere l'app: quando torni, ripartiamo dal passo 12." Pulsante principale: "È arrivata l'email".
  - Fase 4: sotto la lista `ImportControls(model:)` (il pulsante "Scegli cartella o file JSON", avviso iCloud, alert di primo import, `fileImporter`, foglio `MergeSummaryView`: tutto come oggi) e il link "Rivedi il tutorial dall'inizio" → `model.restartTutorial()` e fase 1.
  - Pulsanti: "Avanti" (fasi 1–2), "È arrivata l'email" (fase 3), "Indietro" testuale dalla fase 2 in poi.
  - Accessibility identifier: `tutorialPhaseKicker` sul kicker, `tutorialNextButton` sul pulsante principale, `tutorialBackButton`, `tutorialRestartButton`.

- [ ] **Step 1: Scrivi il test UI che fallisce** (`makeApp` senza `-uiTestSeed`, stateDir riusata nel relaunch come in `PersistenceFlowTests`)

```swift
func testResumesFromImportAfterReachingTheWaitPhase() {
    // launch → kicker "FASE 1 DI 4"; tap Avanti ×2 → "FASE 3 DI 4"
    // relaunch → kicker "FASE 4 DI 4"; il pulsante "Scegli cartella o file JSON" esiste
    // tap tutorialRestartButton → "FASE 1 DI 4"; relaunch → "FASE 1 DI 4"
}
func testBackFromWaitPhaseStillResumesAtImport() {
    // Avanti ×2 → fase 3; Indietro ×2 → fase 1; relaunch → "FASE 4 DI 4"
}
```

- [ ] **Step 2: UI test → FAIL.**
- [ ] **Step 3: Implementa** `ImportControls` (estratto senza cambiare comportamento), `TutorialPhaseView`, `ExportTutorialView`, aggancio in `RootView`.
- [ ] **Step 4: UI test (tutti) → PASS**; test unit → PASS.
- [ ] **Step 5: Controllo manuale sul simulatore** (iPhone 17e, poi Dynamic Type XL): la fase 1 scorre, il pulsante resta visibile, gli screenshot 05–12 compaiono nei passi giusti, i riquadri 01–04 e 13 mostrano il numero, toccare un passo sposta il carosello e viceversa. Fai uno screenshot di ogni fase per Giacomo.
- [ ] **Step 6: Commit** `feat: replace the import screen with the export tutorial`

---

### Task 5: Tutorial dalle Impostazioni

**Files:**
- Modify: `InstaSwipe/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `ExportTutorialView(model:context: .settings)`, `model.confirmedImportCount`.

- [ ] **Step 1: Implementa:** nella sezione di "Reimporta export" aggiungi il pulsante "Come esportare da Instagram" (prima di "Reimporta export") che apre `ExportTutorialView(model:, context: .settings)` come `.sheet` (`@State isShowingTutorial`). Il foglio `MergeSummaryView` delle Impostazioni e il suo `errorAlert` diventano attivi solo con `!isShowingTutorial`. `.onChange(of: model.confirmedImportCount)`: se `isShowingTutorial`, chiudi il tutorial e poi le Impostazioni (`dismiss()`). In contesto `.settings` il tutorial ha un pulsante "Chiudi" in alto e niente logo.
- [ ] **Step 2: Build + tutti i test → PASS.**
- [ ] **Step 3: Controllo manuale sul simulatore con `-uiTestSeed`:** Impostazioni → "Come esportare da Instagram" → fase 1; Avanti fino alla fase 3; chiudi e riapri il tutorial → fase 4. Scegli una cartella senza `following*.json` → l'alert compare sopra il tutorial. Con un export finto valido (cartella con `following.json` copiata nel simulatore): un solo riepilogo, "Inizia a swipare" → si chiudono tutorial e Impostazioni, si vedono le card; riaprendo il tutorial si riparte dalla fase 1. "Reimporta export" diretto lascia ancora aperte le Impostazioni.
- [ ] **Step 4: Commit** `feat: open the export tutorial from Settings`
