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
                if phase == .background { model?.flushCloudMirror() }
            }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if let loadError = model.loadError {
                LoadErrorView(message: loadError, fileNames: model.quarantinedFileNames)
            } else if model.isWaitingForCloud {
                ProgressView("Sto recuperando i progressi da iCloud…")
            } else if model.state != nil {
                mainTabs
            } else {
                ImportView(model: model)
            }
        }
        .alert("Attenzione", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var mainTabs: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banners
                TabView {
                    Text("Swipe").tabItem { Label("Swipe", systemImage: "hand.draw") }
                    Text("Da togliere").tabItem { Label("Da togliere", systemImage: "person.badge.minus") }
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
    let message: String
    let fileNames: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Progressi non leggibili", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                Text(message)
                ForEach(fileNames, id: \.self) { name in
                    Text(name).font(.footnote.monospaced())
                }
            }
            .padding()
        }
    }
}
