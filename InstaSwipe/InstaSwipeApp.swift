import InstaSwipeKit
import SwiftUI

@main
struct InstaSwipeApp: App {
    @State private var model: AppModel?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else {
                    ProgressView("Avvio…")
                }
            }
            .tint(Theme.pink)
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
    @State private var settings = SettingsPresenter()
    @State private var selectedTab = RootTab.swipe

    var body: some View {
        Group {
            switch model.rootScreen {
            case .loadError(let message):
                LoadErrorView(model: model, message: message)
            case .checkingCloud:
                ProgressView("Controllo i progressi su iCloud…")
            case .waitingForCloud:
                ProgressView("Sto recuperando i progressi da iCloud…")
            case .main:
                mainTabs
            case .importer:
                ExportTutorialView(model: model, context: .onboarding)
            }
        }
        .font(.outfit(16))
        .errorAlert(model, isActive: !settings.isPresented && model.pendingMerge == nil)
        // The summary's button reads "Inizia a swipare": every confirmed import ends on the cards.
        .onChange(of: model.confirmedImportCount) { selectedTab = .swipe }
    }

    private var mainTabs: some View {
        VStack(spacing: 0) {
            banners
            TabView(selection: $selectedTab) {
                SwipeView(model: model) { selectedTab = .toRemove }
                    .tabItem { Label("Swipe", systemImage: "hand.draw") }
                    .tag(RootTab.swipe)
                ReportView(model: model)
                    .tabItem { Label("Da togliere", systemImage: "person.badge.minus") }
                    .badge(toDoCount)
                    .tag(RootTab.toRemove)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .environment(settings)
        .sheet(isPresented: $settings.isPresented) { SettingsView(model: model) }
    }

    /// Badge on "Da togliere": accounts still to unfollow; 0 hides it.
    private var toDoCount: Int {
        model.state.map { Report.counts(in: $0)[.toDo] ?? 0 } ?? 0
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
            Text(text).font(.outfit(13, .medium)).foregroundStyle(Theme.warningText)
            Spacer()
            if let onDismiss {
                Button("Chiudi", action: onDismiss).font(.outfit(13, .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.warningFill.opacity(0.14))
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
