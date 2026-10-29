import Foundation

/// Read-only snapshot of a loaded Instagram profile page.
public struct ProfilePageSnapshot: Equatable, Sendable {
    public let finalURL: URL
    public let title: String
    public let ogTitle: String?
    public let ogImage: URL?
    public let bodyText: String

    public init(finalURL: URL, title: String, ogTitle: String?, ogImage: URL?, bodyText: String) {
        self.finalURL = finalURL
        self.title = title
        self.ogTitle = ogTitle
        self.ogImage = ogImage
        self.bodyText = bodyText
    }
}

public enum ProfilePageResult: Equatable, Sendable {
    case profile(displayName: String?, imageURL: URL?)
    case unavailable
    case rateLimited
    case loginRequired
    case unrecognized
}

public enum ProfilePageClassifier {
    /// Phrases signalling a rate limit. To be refined with real ones on device (Task 9).
    static let rateLimitPhrases = [
        "Please wait a few minutes before you try again",
        "Attendi qualche minuto prima di riprovare",
        "Try Again Later",
        "Riprova più tardi"
    ]

    /// Phrases signalling a missing page. To be refined with real ones on device (Task 9).
    static let unavailablePhrases = [
        "Sorry, this page isn't available",
        "Questa pagina non è disponibile"
    ]

    static let loginPath = "/accounts/login"
    static let rateLimitPaths = ["/challenge", "/accounts/suspended"]
    private static let nameSeparators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "•·|-–—"))

    public static func classify(_ snapshot: ProfilePageSnapshot, username: String) -> ProfilePageResult {
        let path = snapshot.finalURL.path
        if path.contains(loginPath) { return .loginRequired }

        if rateLimitPaths.contains(where: path.contains) || contains(snapshot.bodyText, anyOf: rateLimitPhrases) {
            return .rateLimited
        }

        if let ogTitle = snapshot.ogTitle {
            guard ogTitle.localizedCaseInsensitiveContains("(@\(username))") else { return .unrecognized }
            return .profile(displayName: displayName(from: ogTitle, username: username), imageURL: snapshot.ogImage)
        }

        return contains(snapshot.bodyText, anyOf: unavailablePhrases) ? .unavailable : .unrecognized
    }

    private static func contains(_ text: String, anyOf phrases: [String]) -> Bool {
        phrases.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func displayName(from ogTitle: String, username: String) -> String? {
        guard let marker = ogTitle.range(of: "(@") else { return nil }
        let name = String(ogTitle[..<marker.lowerBound]).trimmingCharacters(in: nameSeparators)
        if name.isEmpty || name.caseInsensitiveCompare(username) == .orderedSame { return nil }
        return name
    }
}
