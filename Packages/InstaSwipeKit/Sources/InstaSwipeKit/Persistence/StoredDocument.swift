import Foundation

/// A document persisted by `FileDocumentStore` under its own file name.
public protocol StoredDocument: Codable, Sendable {
    static var fileName: String { get }
    /// Picks the newer of the local and iCloud copies.
    var savedAt: Date { get set }
}

extension AppState: StoredDocument {
    public static let fileName = "state.json"
}

/// A separate file because older builds decode `state.json`, drop the keys they do not know
/// and save it back: followers kept there would be lost.
extension FollowerState: StoredDocument {
    public static let fileName = "followers.json"
}
