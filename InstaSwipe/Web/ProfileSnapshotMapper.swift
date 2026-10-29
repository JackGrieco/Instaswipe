import Foundation
import InstaSwipeKit

/// Pure mapping from the JS extraction result to a `ProfilePageSnapshot`.
enum ProfileSnapshotMapper {
    static func snapshot(from jsResult: Any?, requestedURL: URL) -> ProfilePageSnapshot? {
        guard let dictionary = jsResult as? [String: Any] else { return nil }
        return ProfilePageSnapshot(
            finalURL: (dictionary["url"] as? String).flatMap(URL.init(string:)) ?? requestedURL,
            title: dictionary["title"] as? String ?? "",
            ogTitle: dictionary["ogTitle"] as? String,
            ogImage: (dictionary["ogImage"] as? String).flatMap(URL.init(string:)),
            bodyText: dictionary["body"] as? String ?? ""
        )
    }
}
