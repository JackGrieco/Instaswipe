import InstaSwipeKit
import SwiftUI

struct MergeSummaryView: View {
    let model: AppModel
    let preview: MergePreview

    private var summary: MergeSummary { preview.summary }

    var body: some View {
        NavigationStack {
            Form {
                if summary.isSuspicious {
                    Text("Sembra un export incompleto: controlla di aver scelto l'intervallo «Sempre»")
                        .foregroundStyle(.red)
                        .bold()
                }
                LabeledContent("Nuovi account", value: "\(summary.newAccounts)")
                LabeledContent("Non più seguiti", value: "\(summary.noLongerFollowed)")
                LabeledContent("Segnati come già tolti", value: "\(summary.autoMarkedDone)")
                LabeledContent("Account totali dopo l'import", value: "\(preview.state.accounts.count)")
            }
            .navigationTitle("Riepilogo import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { model.cancelImport() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica") { model.confirmImport() }
                }
            }
        }
    }
}
