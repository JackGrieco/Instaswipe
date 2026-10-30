import InstaSwipeKit
import SwiftUI

/// The front card: follows the finger, tilts, shows the TENGO / TOLGO stamps and reports where it was released.
struct SwipeableCard: View {
    private static let maxRotation: Double = 12
    private static let rotationDivisor: Double = 20
    static let verticalDamping: CGFloat = 0.25
    private static let entryDistance: CGFloat = 560
    private static let entrySpring = Animation.spring(response: 0.45, dampingFraction: 0.7)

    let account: FollowedAccount
    let imageURL: URL?
    let isOffline: Bool
    let mode: ListMode
    @Binding var dragOffset: CGSize
    let onRelease: (CGSize) -> Void
    let onTap: () -> Void

    @State private var entryOffset: CGSize
    @State private var isPastThreshold = false

    init(
        account: FollowedAccount,
        imageURL: URL?,
        isOffline: Bool,
        mode: ListMode = .following,
        dragOffset: Binding<CGSize>,
        entryDecision: Decision?,
        onRelease: @escaping (CGSize) -> Void,
        onTap: @escaping () -> Void
    ) {
        self.account = account
        self.imageURL = imageURL
        self.isOffline = isOffline
        self.mode = mode
        _dragOffset = dragOffset
        self.onRelease = onRelease
        self.onTap = onTap
        let entry: CGSize = switch entryDecision {
        case .keep: CGSize(width: Self.entryDistance, height: 0)
        case .remove: CGSize(width: -Self.entryDistance, height: 0)
        case .unsure: CGSize(width: 0, height: -Self.entryDistance)
        case .pending, nil: .zero
        }
        _entryOffset = State(initialValue: entry)
    }

    private var offsetX: CGFloat { dragOffset.width + entryOffset.width }
    private var offsetY: CGFloat { dragOffset.height * Self.verticalDamping + entryOffset.height }
    private var stampProgress: CGFloat { min(abs(offsetX) / SwipeCardScreen.decisionThreshold, 1) }

    var body: some View {
        AccountCardView(account: account, imageURL: imageURL, isOffline: isOffline, mode: mode)
            .overlay(alignment: .topLeading) {
                if offsetX > 0 {
                    Stamp(text: "TENGO", color: Theme.green, angle: -14, progress: stampProgress)
                        .padding(.leading, 22)
                        .padding(.top, 30)
                }
            }
            .overlay(alignment: .topTrailing) {
                if offsetX < 0 {
                    Stamp(text: "TOLGO", color: Theme.red, angle: 14, progress: stampProgress)
                        .padding(.trailing, 22)
                        .padding(.top, 30)
                }
            }
            .shadow(color: Theme.pink.opacity(0.45), radius: 22, y: 20)
            .shadow(color: Color(red: 30 / 255, green: 10 / 255, blue: 50 / 255).opacity(0.18), radius: 10, y: 8)
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(min(Self.maxRotation, max(-Self.maxRotation, Double(offsetX) / Self.rotationDivisor))))
            .gesture(drag)
            .onTapGesture(perform: onTap)
            .onAppear {
                guard entryOffset != .zero else { return }
                withAnimation(Self.entrySpring) { entryOffset = .zero }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Apri profilo", onTap)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                let isPast = abs(value.translation.width) > SwipeCardScreen.decisionThreshold
                if isPast != isPastThreshold {
                    isPastThreshold = isPast
                    Haptics.impact(.light)
                }
            }
            .onEnded { value in
                isPastThreshold = false
                onRelease(value.translation)
            }
    }
}

/// Rubber-stamp label that fades and grows in with the drag.
private struct Stamp: View {
    let text: String
    let color: Color
    let angle: Double
    let progress: CGFloat

    var body: some View {
        Text(text)
            .font(.outfit(30, .extraBold))
            .tracking(0.06, size: 30)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 4))
            .scaleEffect(0.8 + 0.2 * progress)
            .rotationEffect(.degrees(angle))
            .opacity(progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
