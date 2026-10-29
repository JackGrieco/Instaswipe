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
    private static let steps = [
        "Centro gestione account → Esporta",
        "«Follower e persone seguite» · JSON",
        "Estrai lo ZIP e scegli la cartella"
    ]

    @Bindable var model: AppModel
    @State private var isImporting = false
    @State private var isConfirmingFirstImport = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                brand
                Text("Importa il tuo export di Instagram")
                    .font(.outfit(26, .bold))
                    .tracking(-0.01, size: 26)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 48)
                Text("Scarica da Instagram i tuoi dati in formato JSON (intervallo «Sempre»), poi scegli qui la cartella dell'export.")
                    .font(.outfit(16))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                stepsList.padding(.top, 28)
                if !model.isCloudAvailable { cloudWarning.padding(.top, 16) }
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 24)
            .riseIn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Scegli cartella o file JSON") {
                if model.needsFirstImportConfirmation {
                    isConfirmingFirstImport = true
                } else {
                    isImporting = true
                }
            }
            .buttonStyle(GradientButtonStyle(height: 58))
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .background { background }
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

    private var brand: some View {
        VStack(spacing: 22) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Theme.pink.opacity(0.35), radius: 20, y: 18)
                .accessibilityHidden(true)
            Wordmark(size: 34)
        }
    }

    private var stepsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink2)
                    Text(step)
                        .font(.outfit(14))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .overlay(alignment: .top) {
                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var cloudWarning: some View {
        Text("iCloud è spento: se avevi già dei progressi salvati su iCloud, riaccendilo prima di importare, altrimenti verranno sovrascritti.")
            .font(.outfit(15, .semibold))
            .foregroundStyle(Theme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Pink/purple glow behind the logo.
    private var background: some View {
        ZStack(alignment: .top) {
            Theme.bg
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Theme.pink.opacity(0.28), location: 0),
                        .init(color: Theme.purple.opacity(0.12), location: 0.45),
                        .init(color: .clear, location: 0.7)
                    ],
                    center: .center, startRadius: 0, endRadius: 260
                ))
                .frame(width: 520, height: 520)
                .offset(y: -120)
        }
        .ignoresSafeArea()
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
