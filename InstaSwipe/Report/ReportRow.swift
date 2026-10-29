import InstaSwipeKit
import SwiftUI

struct ReportRow: View {
    let account: FollowedAccount
    let thumbnails: ThumbnailCache
    let onToggleDone: () -> Void

    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName ?? account.username).font(.body)
                Text("@\(account.username)").font(.footnote).foregroundStyle(.secondary)
                if account.followsMe {
                    Text("ti segue").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onToggleDone) {
                Image(systemName: account.unfollowedManually ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(account.unfollowedManually ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(account.unfollowedManually ? "Togli spunta" : "Segna come fatto")
            .accessibilityIdentifier("doneToggle-\(account.username)")
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("reportRow-\(account.username)")
        .task(id: account.username) { image = await thumbnails.image(for: account.username) }
    }

    @ViewBuilder private var avatar: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(account.username.prefix(1)).uppercased())
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.gray.opacity(0.25))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}
