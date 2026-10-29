import InstaSwipeKit
import SwiftUI

struct SwipeView: View {
    @State private var session: SwipeSession
    @State private var toast: Toast?
    let onShowToRemove: () -> Void

    init(model: AppModel, onShowToRemove: @escaping () -> Void) {
        let loader: any ProfileLoading = model.environment.useFakeProfiles ? FakeProfileLoader() : WebProfileLoader()
        _session = State(initialValue: SwipeSession(model: model, loader: loader))
        self.onShowToRemove = onShowToRemove
    }

    var body: some View {
        @Bindable var session = session
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .toast($toast)
            .task { session.start() }
            .sheet(isPresented: $session.isLoginPresented, onDismiss: session.loginDismissed) { LoginView() }
            .fullScreenCover(isPresented: profilePageBinding) { profilePage }
            .alert("Per oggi hai raggiunto il limite di profili.", isPresented: $session.isLimitAlertPresented) {
                Button("OK", role: .cancel) {}
            }
    }

    @ViewBuilder private var content: some View {
        switch session.screen {
        case .finished:
            let counts = session.reviewCounts
            SwipeEndView(kept: counts.kept, toRemove: counts.toRemove, gone: counts.gone, onShowToRemove: onShowToRemove)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) { SettingsButton().padding(.trailing, 20).padding(.top, 4) }
        case .limit(let status):
            LimitReachedView(
                isEmergencyStop: status == .emergencyStopped,
                profilesTodayLabel: session.profilesTodayLabel,
                progressLabel: session.progressLabel
            ) { session.isOfflineSession = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { SettingsButton().padding(.trailing, 20).padding(.top, 4) }
        case .card:
            SwipeCardScreen(session: session, toast: $toast)
        }
    }

    private var profilePageBinding: Binding<Bool> {
        Binding(get: { session.profilePageURL != nil }, set: { if !$0 { session.closeProfilePage() } })
    }

    @ViewBuilder private var profilePage: some View {
        if let url = session.profilePageURL {
            NavigationStack {
                WebView(url: url)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Chiudi") { session.closeProfilePage() } }
                    }
            }
        }
    }
}
