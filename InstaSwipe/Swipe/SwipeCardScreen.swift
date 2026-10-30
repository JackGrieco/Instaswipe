import InstaSwipeKit
import SwiftUI

/// The "Aura" swipe screen: header, the card deck with drag feedback, and the round buttons.
struct SwipeCardScreen: View {
    static let decisionThreshold: CGFloat = 110
    private static let exitDistance: CGFloat = 560
    /// "Ho il dubbio" sends the card up and off the screen.
    private static let exitDistanceUp: CGFloat = 900
    private static let exitAnimation = Animation.easeIn(duration: 0.24)
    private static let returnSpring = Animation.spring(response: 0.45, dampingFraction: 0.7)

    let session: SwipeSession
    @Binding var toast: Toast?

    @State private var dragOffset: CGSize = .zero
    @State private var isExiting = false
    /// Set by undo: the restored card slides back in from the side it left.
    @State private var entryDecision: Decision?

    /// 0 at rest, 1 once the front card has moved by the decision threshold (sideways, or up when unsure).
    private var dragProgress: CGFloat {
        let travel = max(abs(dragOffset.width), abs(dragOffset.height * SwipeableCard.verticalDamping))
        return min(travel / Self.decisionThreshold, 1)
    }
    private var keepOpacity: CGFloat { max(0, min(dragOffset.width / Self.decisionThreshold, 1)) }
    private var removeOpacity: CGFloat { max(0, min(-dragOffset.width / Self.decisionThreshold, 1)) }

    var body: some View {
        VStack(spacing: 0) {
            SwipeHeader(session: session, isFilterLocked: isExiting)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            deck
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            buttons
                .padding(.bottom, 21)
        }
        .background { feedbackTints }
        .onChange(of: session.revertedUnfollowCount) { cardReturned() }
    }

    // MARK: Background feedback

    private var feedbackTints: some View {
        ZStack {
            tint(Theme.red, center: UnitPoint(x: 0, y: 0.55)).opacity(removeOpacity)
            tint(Theme.green, center: UnitPoint(x: 1, y: 0.55)).opacity(keepOpacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func tint(_ color: Color, center: UnitPoint) -> some View {
        GeometryReader { proxy in
            EllipticalGradient(
                colors: [color.opacity(0.55), color.opacity(0)],
                center: center,
                endRadiusFraction: 0.7
            )
            // CSS `radial-gradient(120% 70% at …)`: the frame holds the whole ellipse.
            .frame(width: proxy.size.width * 2.4, height: proxy.size.height * 1.4)
            .position(x: center.x * proxy.size.width, y: center.y * proxy.size.height)
        }
    }

    // MARK: Deck

    private var deck: some View {
        ZStack {
            if let next = session.next {
                AccountCardView(
                    account: next, imageURL: session.imageURL(for: next.username),
                    isOffline: session.isOfflineSession, mode: session.mode, isFront: false
                )
                    .scaleEffect(0.92 + 0.08 * dragProgress)
                    .offset(y: 14 - 14 * dragProgress)
                    .opacity(0.5 + 0.5 * dragProgress)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(true)
            }
            if let current = session.current {
                SwipeableCard(
                    account: current,
                    imageURL: session.imageURL(for: current.username),
                    isOffline: session.isOfflineSession,
                    mode: session.mode,
                    dragOffset: $dragOffset,
                    entryDecision: entryDecision ?? session.revertedEntryDecision,
                    onRelease: release,
                    onTap: session.requestProfilePage
                )
                .id(current.username)
                .onAppear {
                    entryDecision = nil
                    session.consumeRevertedEntry()
                }
            }
        }
    }

    // MARK: Buttons

    /// X · ? · ✓ centred, with undo set apart on the left so the three decisions stay symmetric.
    private var buttons: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 18) {
                RoundActionButton(symbol: "xmark", size: 68, iconSize: 29, foreground: Theme.red, background: Theme.surface) {
                    commit(.remove)
                }
                .accessibilityLabel("Da togliere")
                .accessibilityIdentifier("removeButton")
                .keyboardShortcut(.leftArrow, modifiers: [])

                RoundActionButton(
                    symbol: "questionmark", size: 56, iconSize: 24, foreground: .white,
                    background: Theme.orange, shadowColor: Theme.orange.opacity(0.4)
                ) {
                    commit(.unsure)
                }
                .accessibilityLabel("Ho il dubbio")
                .accessibilityIdentifier("unsureButton")
                .keyboardShortcut(.upArrow, modifiers: [])

                RoundActionButton(symbol: "checkmark", size: 68, iconSize: 31, foreground: Theme.green, background: Theme.surface) {
                    commit(.keep)
                }
                .accessibilityLabel("Tieni")
                .accessibilityIdentifier("keepButton")
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .frame(maxWidth: .infinity)

            RoundActionButton(
                symbol: "arrow.uturn.backward", size: 46, iconSize: 20, foreground: Theme.ink2,
                background: Theme.surface2, shadowColor: .clear, action: undo
            )
            .opacity(session.canUndo ? 1 : 0.35)
            .disabled(!session.canUndo)
            .accessibilityLabel("Annulla")
            .accessibilityIdentifier("undoButton")
            .padding(.leading, 16)
        }
    }

    // MARK: Actions

    private func release(_ translation: CGSize) {
        if abs(translation.width) > Self.decisionThreshold {
            commit(translation.width > 0 ? .keep : .remove)
        } else {
            withAnimation(Self.returnSpring) { dragOffset = .zero }
        }
    }

    /// Flies the card out, then records the decision. If it was not applied (e.g. a failed save) the card returns.
    private func commit(_ decision: Decision) {
        guard !isExiting, session.current != nil else { return }
        isExiting = true
        entryDecision = nil
        Haptics.impact(.medium)
        withAnimation(Self.exitAnimation) {
            dragOffset = exitOffset(for: decision)
        } completion: {
            let isApplied = session.decide(decision)
            isExiting = false
            guard isApplied else {
                withAnimation(Self.returnSpring) { dragOffset = .zero }
                return
            }
            dragOffset = .zero
            toast = Toast.after(decision)
        }
    }

    private func exitOffset(for decision: Decision) -> CGSize {
        switch decision {
        case .unsure:
            CGSize(width: dragOffset.width, height: -Self.exitDistanceUp / SwipeableCard.verticalDamping)
        case .keep:
            CGSize(width: Self.exitDistance, height: dragOffset.height * 1.4)
        case .remove, .pending:
            CGSize(width: -Self.exitDistance, height: dragOffset.height * 1.4)
        }
    }

    /// The unfollow page closed without "Fatto": the session already restored the card, entering from the left.
    private func cardReturned() {
        reenterCard(from: .remove)
    }

    private func undo() {
        guard !isExiting else { return }
        let username = session.current?.username
        let decision = session.lastDecision
        session.undo()
        guard session.current?.username != username else { return }
        reenterCard(from: decision)
    }

    /// The restored card slides back in from the side it left, with the "undone" toast.
    private func reenterCard(from decision: Decision?) {
        Haptics.impact(.soft)
        dragOffset = .zero
        entryDecision = decision
        toast = .undone
    }
}

/// Wordmark, today's profile budget, the overall progress bar and the "Solo chi non ti segue" switch.
private struct SwipeHeader: View {
    @Bindable var session: SwipeSession
    /// The flying card's decision lands on `session.current`: the queue must not change under it.
    let isFilterLocked: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Wordmark()
                Spacer()
                Text(session.profilesTodayLabel)
                    .font(.outfit(12, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surface2))
                    .accessibilityIdentifier("profilesTodayLabel")
                SettingsButton()
            }
            HStack(spacing: 10) {
                ProgressBar(fraction: session.progressFraction, fill: AnyShapeStyle(Theme.brandGradient))
                Text(session.progressLabel)
                    .font(.outfit(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("progressLabel")
            }
            ListModePicker(mode: $session.mode, isDisabled: isFilterLocked)
            Toggle(isOn: $session.isNotFollowingBackOnly.animation(.easeOut(duration: 0.2))) {
                Label(session.mode.notFollowingBackFilter, systemImage: "person.fill.xmark")
                    .font(.outfit(14, .medium))
                    .foregroundStyle(Theme.ink2)
            }
            .tint(Theme.pink)
            .disabled(isFilterLocked)
            .accessibilityIdentifier("notFollowingBackToggle")
        }
    }
}

/// Height-6 rounded meter used for review progress and the daily unfollow counter.
struct ProgressBar: View {
    let fraction: Double
    let fill: AnyShapeStyle

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                Capsule()
                    .fill(fill)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct RoundActionButton: View {
    let symbol: String
    let size: CGFloat
    let iconSize: CGFloat
    let foreground: Color
    let background: Color
    var shadowColor = Theme.shadow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .shadow(color: shadowColor, radius: 14, y: 10)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
    }
}
