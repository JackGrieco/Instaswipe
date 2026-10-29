import InstaSwipeKit
import SwiftUI

@main
struct InstaSwipeApp: App {
    @State private var model: AppModel?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else {
                    ProgressView("Avvio…")
                }
            }
            .task {
                guard model == nil else { return }
                model = AppModel(environment: await AppEnvironment.resolve())
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background, let model else { return }
                Task { await model.flushCloudMirror() }
            }
        }
    }
}

enum RootTab: Hashable { case swipe, toRemove }

struct RootView: View {
    @Bindable var model: AppModel
    @State private var isShowingSettings = false
    @State private var selectedTab = RootTab.swipe

    var body: some View {
        Group {
            if let loadError = model.loadError {
                LoadErrorView(model: model, message: loadError)
            } else if model.isWaitingForCloud {
                ProgressView("Sto recuperando i progressi da iCloud…")
            } else if model.state != nil {
                mainTabs
            } else {
                ImportView(model: model)
            }
        }
        .errorAlert(model, isActive: !isShowingSettings && model.pendingMerge == nil)
    }

    private var mainTabs: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banners
                TabView(selection: $selectedTab) {
                    SwipeView(model: model) { selectedTab = .toRemove }
                        .tabItem { Label("Swipe", systemImage: "hand.draw") }
                        .tag(RootTab.swipe)
                    ReportView(model: model)
                        .tabItem { Label("Da togliere", systemImage: "person.badge.minus") }
                        .tag(RootTab.toRemove)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Impostazioni")
                }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView(model: model) }
        }
    }

    @ViewBuilder private var banners: some View {
        if !model.isCloudAvailable {
            BannerView(text: "Le copie su iCloud sono disattivate", onDismiss: nil)
        }
        if let message = model.bannerMessage {
            BannerView(text: message, onDismiss: model.dismissBanner)
        }
    }
}

struct BannerView: View {
    let text: String
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack {
            Text(text).font(.footnote)
            Spacer()
            if let onDismiss {
                Button("Chiudi", action: onDismiss).font(.footnote)
            }
        }
        .padding(8)
        .background(.yellow.opacity(0.25))
    }
}

struct LoadErrorView: View {
    let model: AppModel
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Progressi non leggibili", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                Text(message)
                ForEach(model.quarantinedFileNames, id: \.self) { name in
                    Text(name).font(.footnote.monospaced())
                }
                Button("Ripristina l'ultima copia di sicurezza", action: model.prepareRestore)
                    .buttonStyle(.borderedProminent)
                Button("Riprova", action: model.retryLoad)
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .alert(restoreTitle, isPresented: restoreBinding) {
            Button("Ripristina", action: model.confirmRestore)
            Button("Annulla", role: .cancel, action: model.cancelRestore)
        } message: {
            Text(restoreMessage)
        }
    }

    /// Both buttons clear `pendingRestore` themselves; the setter must not, or it could run
    /// before "Ripristina" and cancel it.
    private var restoreBinding: Binding<Bool> {
        Binding(get: { model.pendingRestore != nil }, set: { _ in })
    }

    private var restoreTitle: String {
        guard let backup = model.pendingRestore else { return "" }
        return "Ripristinare la copia del \(backup.savedAt.formatted(date: .abbreviated, time: .shortened))?"
    }

    private var restoreMessage: String {
        let decided = model.pendingRestore?.accounts.filter { $0.decision != .pending }.count ?? 0
        return "Contiene \(decided) decisioni. Diventerà il tuo stato attuale; i file illeggibili restano da parte."
    }
}
