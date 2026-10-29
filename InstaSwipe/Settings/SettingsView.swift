import InstaSwipeKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var isLoggingIn = false

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
            .errorAlert(model, isActive: model.pendingMerge == nil)
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
        Binding(get: { model.pendingMerge != nil }, set: { if !$0 { model.cancelImport() } })
    }
}
