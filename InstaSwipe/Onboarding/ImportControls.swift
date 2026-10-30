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

/// Phase 4 of the export tutorial: the picker button, the first-import confirmation and the
/// merge summary sheet.
struct ImportControls: View {
    @Bindable var model: AppModel
    @State private var isImporting = false
    @State private var isConfirmingFirstImport = false

    var body: some View {
        Button("Scegli cartella o file JSON") {
            if model.needsFirstImportConfirmation {
                isConfirmingFirstImport = true
            } else {
                isImporting = true
            }
        }
        .buttonStyle(GradientButtonStyle(height: 58))
        .alert("Non ho trovato progressi su iCloud. Importare da zero?", isPresented: $isConfirmingFirstImport) {
            Button("Importa") { isImporting = true }
            Button("Annulla", role: .cancel) {}
        }
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

/// Shown before importing when iCloud is off, so existing progress is not overwritten.
struct CloudOffWarning: View {
    var body: some View {
        Text("iCloud è spento: se avevi già dei progressi salvati su iCloud, riaccendilo prima di importare, altrimenti verranno sovrascritti.")
            .font(.outfit(15, .semibold))
            .foregroundStyle(Theme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
