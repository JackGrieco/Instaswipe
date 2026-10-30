import InstaSwipeKit
import SwiftUI

struct SwipeView: View {
    @State private var session: SwipeSession
    @State private var toast: Toast?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let thumbnails = ThumbnailCache()
    let model: AppModel
    let onShowToRemove: () -> Void

    init(model: AppModel, onShowToRemove: @escaping () -> Void) {
        let loader: any ProfileLoading = model.environment.useFakeProfiles ? FakeProfileLoader() : WebProfileLoader()
        _session = State(initialValue: SwipeSession(model: model, loader: loader, defaults: model.environment.defaults))
        self.model = model
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
            .sheet(isPresented: returnPromptBinding) { returnPromptSheet }
            .onChange(of: session.appHandoffURL) { _, url in
                guard let url else { return }
                openURL(url)
                session.appHandoffOpened()
            }
            .onChange(of: scenePhase) { _, phase in session.returnPrompt.scenePhaseChanged(phase) }
            .alert("Per oggi hai raggiunto il limite di profili.", isPresented: $session.isLimitAlertPresented) {
                Button("OK", role: .cancel) {}
            }
    }

    @ViewBuilder private var content: some View {
        switch session.screen {
        case .finished:
            let counts = session.reviewCounts
            withModePicker {
                SwipeEndView(
                    mode: session.mode,
                    kept: counts.kept, toRemove: counts.toRemove, gone: counts.gone, onShowToRemove: onShowToRemove,
                    onShowEveryone: session.hasOthersToReview ? { session.isNotFollowingBackOnly = false } : nil
                )
            }
        case .limit(let status):
            withModePicker {
                LimitReachedView(
                    isEmergencyStop: status == .emergencyStopped,
                    profilesTodayLabel: session.profilesTodayLabel,
                    progressLabel: session.progressLabel
                ) { session.isOfflineSession = true }
            }
        case .card:
            SwipeCardScreen(session: session, toast: $toast)
        case .noFollowers:
            withModePicker { NoFollowersView() }
        }
    }

    /// Picker on top and settings in the corner, shared by every screen except the cards (which have their own header).
    private func withModePicker<Body: View>(@ViewBuilder _ body: () -> Body) -> some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ListModePicker(mode: $session.mode)
                SettingsButton()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            body().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var returnPromptBinding: Binding<Bool> {
        Binding(get: { session.returnPrompt.prompt != nil }, set: { if !$0 { session.returnPrompt.dismiss() } })
    }

    @ViewBuilder private var returnPromptSheet: some View {
        if let prompt = session.returnPrompt.prompt {
            let username = prompt.username
            ReturnPromptSheet(
                account: model.list(prompt.mode)?.accounts.first { $0.username == username },
                username: username,
                title: prompt.mode.returnPromptTitle(for: username),
                thumbnails: thumbnails,
                onConfirm: {
                    session.confirmReturnPrompt()
                    toast = .markedDone
                },
                onNotYet: session.returnPrompt.dismiss,
                onKeep: {
                    session.keepFromReturnPrompt()
                    toast = .keptAfterAll
                }
            )
        }
    }

    private var profilePageBinding: Binding<Bool> {
        Binding(get: { session.profilePageURL != nil }, set: { if !$0 { session.closeProfilePage() } })
    }

    @ViewBuilder private var profilePage: some View {
        if let url = session.profilePageURL {
            NavigationStack {
                WebView(url: url)
                    .navigationTitle(session.unfollowUsername.map { "@\($0)" } ?? "")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Chiudi") { session.closeProfilePage() } }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if session.unfollowUsername != nil {
                            UnfollowBar(
                                unfollowsToday: session.unfollowsToday,
                                isOverDailyWarning: session.isOverDailyUnfollowWarning,
                                onDone: session.confirmUnfollowed
                            )
                        }
                    }
            }
        }
    }
}
