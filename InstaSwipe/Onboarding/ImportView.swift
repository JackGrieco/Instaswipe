import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ExportPicker {
    static let contentTypes: [UTType] = [.folder, .json]

    /// The user picks one folder, or the JSON files themselves.
    static func handle(_ result: Result<[URL], Error>, model: AppModel) {
        switch result {
        case .success(let urls):
            Task { await model.prepareImport(picked: urls) }
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
            if !model.isCloudAvailable {
                Text("iCloud è spento: se avevi già dei progressi salvati su iCloud, riaccendilo prima di importare, altrimenti verranno sovrascritti.")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Scegli cartella o file JSON") { isImporting = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .fileImporter(isPresented: $isImporting, allowedContentTypes: ExportPicker.contentTypes, allowsMultipleSelection: true) { result in
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

/// Shows `model.errorMessage` as an alert. Each presented sheet needs its own, because an
/// alert attached underneath a sheet is not visible.
struct ErrorAlert: ViewModifier {
    let model: AppModel
    var isActive = true

    func body(content: Content) -> some View {
        content.alert("Attenzione", isPresented: Binding(
            get: { isActive && model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

extension View {
    func errorAlert(_ model: AppModel, isActive: Bool = true) -> some View {
        modifier(ErrorAlert(model: model, isActive: isActive))
    }
}
