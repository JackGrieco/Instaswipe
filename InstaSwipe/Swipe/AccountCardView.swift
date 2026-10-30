import InstaSwipeKit
import SwiftUI

/// "Aura" card: full-bleed photo, dark scrim, name, @username, follow date and the green "Ti segue" tag.
struct AccountCardView: View {
    static let cornerRadius: CGFloat = 30

    let account: FollowedAccount
    let imageURL: URL?
    /// Offline session: no photo or name, just a grey card titled with the @username.
    var isOffline = false
    var mode = ListMode.following
    /// False for the card waiting behind: it must not expose the front card's test identifiers.
    var isFront = true

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            photo
            scrim
            info
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    /// The placeholder sets the size; the photo sits in an overlay so a `scaledToFill` image wider or
    /// taller than the card can never push the layout beyond it.
    private var photo: some View {
        placeholder
            .overlay {
                if let imageURL, !isOffline {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(isOffline ? Theme.offlineCardGradient : Theme.accountGradient(for: account.username))
            Text(String(title.drop { $0 == "@" }.prefix(1)).uppercased())
                .font(.outfit(150, .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 90)
                .accessibilityHidden(true)
        }
    }

    /// Bottom 62%: transparent → rgba(12,6,20,.35) at 35% → rgba(12,6,20,.82).
    private var scrim: some View {
        GeometryReader { proxy in
            let night = Color(red: 12 / 255, green: 6 / 255, blue: 20 / 255)
            LinearGradient(
                stops: [
                    .init(color: night.opacity(0), location: 0),
                    .init(color: night.opacity(0.35), location: 0.35),
                    .init(color: night.opacity(0.82), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: proxy.size.height * 0.62)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    private var title: String {
        isOffline ? "@\(account.username)" : account.displayName ?? account.username
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.outfit(30, .bold))
                .tracking(-0.02, size: 30)
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityIdentifier(isFront && isOffline ? "cardUsername" : "")
            if !isOffline {
                Text("@\(account.username)")
                    .font(.outfit(17, .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .accessibilityIdentifier(isFront ? "cardUsername" : "")
            }
            HStack(spacing: 8) {
                if let since = account.followedSince {
                    Text("\(mode == .followers ? "Ti segue dal" : "Lo segui dal") \(Self.dateFormatter.string(from: since))")
                        .font(.outfit(14))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if account.followsMe {
                    TagPill(text: mode == .followers ? "Lo segui" : "Ti segue", foreground: .white, background: Theme.green.opacity(0.92), weight: .bold)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
