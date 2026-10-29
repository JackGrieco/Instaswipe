import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ExportPicker {
    static let contentTypes: [UTType] = [.folder, .json]

    /// A selected JSON file stands for its containing folder.
    static func handle(_ result: Result<URL, Error>, model: AppModel) {
        switch result {
        case .success(let url):
            let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
            Task { await model.prepareImport(folder: folder) }
        case .failure(let error):
            model.errorMessage = "Non riesco ad aprire la selezione: \(error.localizedDescription)"
        }
    }
}

struct ImportView: View {
    @Bindable var model: AppModel
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Importa il tuo export di Instagram")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Scarica da Instagram i tuoi dati in formato JSON (intervallo «Sempre»), poi scegli qui la cartella dell'export.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Scegli la cartella dell'export") { isImporting = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .fileImporter(isPresented: $isImporting, allowedContentTypes: ExportPicker.contentTypes) { result in
            ExportPicker.handle(result, model: model)
        }
        .sheet(isPresented: sheetBinding) {
            if let preview = model.pendingMerge {
                MergeSummaryView(model: model, preview: preview)
            }
        }
    }

    private var sheetBinding: Binding<Bool> {
        Binding(get: { model.pendingMerge != nil }, set: { if !$0 { model.cancelImport() } })
    }
}
