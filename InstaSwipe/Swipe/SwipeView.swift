import InstaSwipeKit
import SwiftUI

struct SwipeView: View {
    @State private var session: SwipeSession
    let onShowToRemove: () -> Void

    init(model: AppModel, onShowToRemove: @escaping () -> Void) {
        let loader: any ProfileLoading = model.environment.useFakeProfiles ? FakeProfileLoader() : WebProfileLoader()
        _session = State(initialValue: SwipeSession(model: model, loader: loader))
        self.onShowToRemove = onShowToRemove
    }

    var body: some View {
        @Bindable var session = session
        content
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
        case .limit(let status):
            LimitReachedView(isEmergencyStop: status == .emergencyStopped) { session.isOfflineSession = true }
        case .card:
            cardScreen
        }
    }

    private var cardScreen: some View {
        VStack(spacing: 12) {
            header
            if let account = session.current {
                SwipeCardContainer(
                    account: account,
                    imageURL: imageURL,
                    onDecision: session.decide,
                    onTap: session.requestProfilePage
                )
                .id(account.username)
            }
            buttons
        }
        .padding()
    }

    private var imageURL: URL? {
        if case .profile(_, let url) = session.currentResult { return url }
        return nil
    }

    private var header: some View {
        HStack {
            Text(session.progressLabel).accessibilityIdentifier("progressLabel")
            Spacer()
            Text(session.profilesTodayLabel).accessibilityIdentifier("profilesTodayLabel")
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var buttons: some View {
        HStack(spacing: 32) {
            circleButton("xmark", color: .red, label: "Da togliere", id: "removeButton") { session.decide(.remove) }
            circleButton("arrow.uturn.backward", color: .gray, label: "Annulla", id: "undoButton", isSmall: true) {
                session.undo()
            }
            .disabled(!session.canUndo)
            circleButton("heart.fill", color: .green, label: "Tieni", id: "keepButton") { session.decide(.keep) }
        }
    }

    private func circleButton(
        _ symbol: String, color: Color, label: String, id: String, isSmall: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(isSmall ? .title3 : .title)
                .frame(width: isSmall ? 48 : 64, height: isSmall ? 48 : 64)
                .foregroundStyle(color)
                .background(Circle().fill(color.opacity(0.15)))
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
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

/// Draggable card: past `swipeDecisionThreshold` the drag becomes a decision; the card always springs back.
private struct SwipeCardContainer: View {
    static let swipeDecisionThreshold: CGFloat = 120
    private static let maxRotation: Double = 12
    private static let rotationDivisor: Double = 20

    let account: FollowedAccount
    let imageURL: URL?
    let onDecision: (Decision) -> Void
    let onTap: () -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        AccountCardView(account: account, imageURL: imageURL)
            .offset(x: dragOffset)
            .rotationEffect(.degrees(min(Self.maxRotation, max(-Self.maxRotation, Double(dragOffset) / Self.rotationDivisor))))
            .gesture(drag)
            .onTapGesture(perform: onTap)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation.width }
            .onEnded { value in
                let width = value.translation.width
                if abs(width) > Self.swipeDecisionThreshold {
                    onDecision(width > 0 ? .keep : .remove)
                }
                // Also after a decision: if it was not applied (e.g. a failed save) the card stays.
                withAnimation(.spring) { dragOffset = 0 }
            }
    }
}
