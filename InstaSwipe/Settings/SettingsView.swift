import InstaSwipeKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var isLoggingIn = false
    @State private var isShowingTutorial = false
    @AppStorage private var isInstantUnfollowEnabled: Bool

    init(model: AppModel) {
        self.model = model
        // Same suite `SwipeSession` reads, so UI tests stay isolated.
        _isInstantUnfollowEnabled = AppStorage(
            wrappedValue: false, SwipeSession.instantUnfollowDefaultsKey, store: model.environment.defaults
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        "Profili al giorno: \(dailyLimit)",
                        value: dailyLimitBinding,
                        in: Limits.minDailyProfileLoads...Limits.maxDailyProfileLoads,
                        step: Self.dailyLimitStep
                    )
                }
                Section {
                    Toggle("Togli subito", isOn: $isInstantUnfollowEnabled)
                        .accessibilityIdentifier("instantUnfollowToggle")
                } footer: {
                    Text("Quando scarti un account si apre il suo profilo. Per chi segui: togli il follow e tocca Fatto (ogni apertura conta nei profili del giorno). Per i follower si apre l'app di Instagram: tocca ⋯ → «Rimuovi follower» e torna qui.")
                }
                Section {
                    Button("Come esportare da Instagram") { isShowingTutorial = true }
                    Button("Reimporta export") { isImporting = true }
                    Button("Accedi di nuovo a Instagram") { isLoggingIn = true }
                }
                Section {
                    LabeledContent("Copie su iCloud", value: model.isCloudAvailable ? "attive" : "disattivate")
                }
            }
            .navigationTitle("Impostazioni")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() } }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: ExportPicker.contentTypes, allowsMultipleSelection: true) { result in
                ExportPicker.handle(result, model: model)
            }
            .sheet(isPresented: $isLoggingIn) { LoginView() }
            .sheet(isPresented: $isShowingTutorial) { ExportTutorialView(model: model, context: .settings) }
            .onChange(of: model.confirmedImportCount) {
                // An import from the tutorial ends on the cards (step 14); "Reimporta export" stays here.
                guard isShowingTutorial else { return }
                isShowingTutorial = false
                dismiss()
            }
            .errorAlert(model, isActive: model.pendingMerge == nil && !isShowingTutorial)
            .sheet(isPresented: pendingBinding) {
                if let preview = model.pendingMerge {
                    MergeSummaryView(model: model, preview: preview)
                }
            }
        }
    }

    private static let dailyLimitStep = 50

    private var dailyLimit: Int { model.state?.dailyProfileLimit ?? Limits.defaultDailyProfileLoads }

    private var dailyLimitBinding: Binding<Int> {
        Binding(
            get: { dailyLimit },
            set: { newLimit in model.apply { ProfileBudget.setDailyLimit(newLimit, in: $0) } }
        )
    }

    private var pendingBinding: Binding<Bool> {
        // While the tutorial is up, its own import controls present the summary.
        Binding(get: { model.pendingMerge != nil && !isShowingTutorial }, set: { if !$0 { model.cancelImport() } })
    }
}
