import InstaSwipeKit
import SwiftUI

/// Design "C": big photo, name, @username, follow date and a green "Ti segue" tag.
struct AccountCardView: View {
    let account: FollowedAccount
    let imageURL: URL?

    private static let cornerRadius: CGFloat = 24
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            photo
            VStack(alignment: .leading, spacing: 6) {
                Text(account.displayName ?? account.username)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text("@\(account.username)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cardUsername")
                if let since = account.followedSince {
                    Text("Lo segui dal \(Self.dateFormatter.string(from: since))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if account.followsMe { followsYouTag }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private var photo: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 0, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(account.username.prefix(1)).uppercased())
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var followsYouTag: some View {
        Text("Ti segue")
            .font(.caption.bold())
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.green.opacity(0.15)))
    }
}
