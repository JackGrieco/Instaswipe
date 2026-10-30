import InstaSwipeKit
import SwiftUI

struct ReturnPromptSheet: View {
    /// Nil only if the account vanished from the state while the sheet was up.
    let account: FollowedAccount?
    let username: String
    let title: String
    let thumbnails: ThumbnailCache
    let onConfirm: () -> Void
    let onNotYet: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let account {
                AvatarView(account: account, thumbnails: thumbnails, size: 64)
            }
            Text(title)
                .font(.outfit(21, .bold))
                .tracking(-0.01, size: 21)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Button("Sì, segna come fatto", action: onConfirm)
                .buttonStyle(GradientButtonStyle(height: 54))
            Button("Non ancora", action: onNotYet)
                .buttonStyle(SheetButtonStyle(foreground: Theme.ink, background: Theme.surface2))
            Button("Ho cambiato idea, lo tengo", action: onKeep)
                .buttonStyle(SheetButtonStyle(foreground: Theme.green, background: .clear))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Theme.bg)
    }
}

private struct SheetButtonStyle: ButtonStyle {
    let foreground: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.outfit(17, .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(background))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
