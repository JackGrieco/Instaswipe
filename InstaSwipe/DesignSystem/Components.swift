import InstaSwipeKit
import SwiftUI
import UIKit

/// "Insta" in ink + "swipe" in the pink→orange gradient.
struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            Text("Insta").foregroundStyle(Theme.ink)
            Text("swipe").foregroundStyle(Theme.wordmarkGradient)
        }
        .font(.outfit(size, .bold))
        .tracking(-0.02, size: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("InstaSwipe")
    }
}

/// Shrinks while pressed (scale 0.88 for the round swipe buttons, 0.97 for wide ones).
struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Full-width capsule with the brand gradient: the main call to action of a screen.
struct GradientButtonStyle: ButtonStyle {
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.outfit(17, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(Theme.brandGradient))
            .shadow(color: Theme.pink.opacity(0.33), radius: 14, y: 12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small round button that opens Impostazioni from any screen header.
struct SettingsButton: View {
    @Environment(SettingsPresenter.self) private var settings

    var body: some View {
        Button { settings.isPresented = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surface2))
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.9))
        .accessibilityLabel("Impostazioni")
    }
}

/// Owned by `RootView`, which presents the sheet; any header can raise it through the environment.
@MainActor
@Observable
final class SettingsPresenter {
    var isPresented = false
}

/// Round avatar: the cached profile thumbnail, or the account gradient with its initial.
struct AvatarView: View {
    let account: FollowedAccount
    let thumbnails: ThumbnailCache
    var size: CGFloat = 44
    var isGone = false

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if isGone {
                initial.foregroundStyle(Theme.ink2).background(Theme.surface2)
            } else {
                initial.foregroundStyle(.white).background(Theme.accountGradient(for: account.username))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: account.username) { image = await thumbnails.image(for: account.username) }
    }

    private var initial: some View {
        Text(String((account.displayName ?? account.username).prefix(1)).uppercased())
            .font(.outfit(size * 0.42, .bold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small pill label ("Tenuto", "Sparito", "Ti segue").
struct TagPill: View {
    let text: String
    let foreground: Color
    let background: Color
    var weight: OutfitWeight = .semibold

    var body: some View {
        Text(text)
            .font(.outfit(12, weight))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
    }
}

/// Rises 24 pt and fades in, optionally after a delay: the entrance used by the full-screen states.
struct RiseIn: ViewModifier {
    var delay: Double = 0
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 24)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(delay)) { isVisible = true }
            }
    }
}

extension View {
    func riseIn(delay: Double = 0) -> some View {
        modifier(RiseIn(delay: delay))
    }
}

@MainActor
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
