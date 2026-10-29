import Foundation
import InstaSwipeKit

/// Pure mapping from the JS extraction result to a `ProfilePageSnapshot`.
enum ProfileSnapshotMapper {
    /// Size assumed for a CDN copy without an `sNNNxNNN` token: Instagram omits it on full-size copies.
    private static let unsizedImageSide = Int.max

    static func snapshot(from jsResult: Any?, requestedURL: URL) -> ProfilePageSnapshot? {
        guard let dictionary = jsResult as? [String: Any] else { return nil }
        let ogImage = dictionary["ogImage"] as? String
        let rendered = dictionary["images"] as? [String] ?? []
        return ProfilePageSnapshot(
            finalURL: (dictionary["url"] as? String).flatMap(URL.init(string:)) ?? requestedURL,
            title: dictionary["title"] as? String ?? "",
            ogTitle: dictionary["ogTitle"] as? String,
            ogImage: largestImage(among: [ogImage].compactMap { $0 } + rendered),
            bodyText: dictionary["body"] as? String ?? ""
        )
    }

    /// og:image is a 100 px copy; the rendered page may hold larger copies of the same photo.
    private static func largestImage(among candidates: [String]) -> URL? {
        let urls = candidates.compactMap(URL.init(string:))
        return urls.max { side(of: $0) < side(of: $1) }
    }

    private static func side(of url: URL) -> Int {
        let text = url.absoluteString
        guard let match = text.firstMatch(of: #/[_=]s(\d+)x\d+/#), let side = Int(match.1) else {
            return unsizedImageSide
        }
        return side
    }
}
