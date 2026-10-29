import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Button("Reimporta export") { isImporting = true }
            }
            .navigationTitle("Impostazioni")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() } }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: ExportPicker.contentTypes) { result in
                ExportPicker.handle(result, model: model)
            }
            .sheet(isPresented: pendingBinding) {
                if let preview = model.pendingMerge {
                    MergeSummaryView(model: model, preview: preview)
                }
            }
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { model.pendingMerge != nil }, set: { if !$0 { model.cancelImport() } })
    }
}
