import InstaSwipeKit
import SwiftUI

struct ReportRow: View {
    let account: FollowedAccount
    let thumbnails: ThumbnailCache
    let showsSeparator: Bool
    let onToggleDone: () -> Void

    /// Same rule as the "Spariti" filter: the profile no longer exists on Instagram.
    private var isGone: Bool { account.availability == .unavailable }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(account: account, thumbnails: thumbnails, size: 44, isGone: isGone)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName ?? account.username)
                    .font(.outfit(16, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("@\(account.username)")
                    .font(.outfit(13))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                if account.followsMe {
                    Text("ti segue").font(.outfit(12, .medium)).foregroundStyle(Theme.green)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if showsSeparator { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reportRow-\(account.username)")
    }

    @ViewBuilder private var trailing: some View {
        if isGone {
            TagPill(text: "Sparito", foreground: Theme.ink2, background: Theme.surface2)
        } else if account.decision == .remove {
            doneButton
        } else if account.decision == .unsure {
            TagPill(text: "Dubbio", foreground: Theme.warningText, background: Theme.orange.opacity(0.14))
        } else if account.decision == .keep {
            TagPill(text: "Tenuto", foreground: Theme.green, background: Theme.green.opacity(0.12))
        }
    }

    private var doneButton: some View {
        let isDone = account.unfollowedManually
        return Button(action: onToggleDone) {
            ZStack {
                Circle().strokeBorder(Theme.line, lineWidth: 2).opacity(isDone ? 0 : 1)
                Circle().fill(Theme.green).opacity(isDone ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(isDone ? 1 : 0.94)
            .animation(.easeOut(duration: 0.2), value: isDone)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isDone ? "Togli spunta" : "Segna come fatto")
        .accessibilityIdentifier("doneToggle-\(account.username)")
    }
}
