import Foundation

public enum StateStoreError: Error, Equatable {
    /// State files existed but none could be read; they were renamed, not deleted.
    case corrupted(quarantined: [URL])
}

/// Local atomic persistence with an optional iCloud mirror. Never deletes or
/// overwrites a file it could not read: unreadable files are renamed aside.
public final class FileStateStore: Sendable {
    static let fileName = "state.json"

    private let localDirectory: URL
    private let cloudDirectory: URL?

    public init(localDirectory: URL, cloudDirectory: URL?) {
        self.localDirectory = localDirectory
        self.cloudDirectory = cloudDirectory
    }

    private enum Candidate {
        case absent
        case valid(AppState)
        case quarantined(URL)
    }

    /// `nil` only when no state file exists anywhere.
    public func load() throws -> AppState? {
        let local = try inspect(directory: localDirectory)
        let cloud = try cloudDirectory.map(inspect(directory:)) ?? .absent

        var quarantined: [URL] = []
        for case let .quarantined(url) in [local, cloud] { quarantined.append(url) }

        switch (local, cloud) {
        case let (.valid(localState), .valid(cloudState)):
            guard cloudState.savedAt > localState.savedAt else { return localState }
            try save(cloudState)
            return cloudState
        case let (.valid(localState), _):
            return localState
        case let (_, .valid(cloudState)):
            try save(cloudState)
            return cloudState
        default:
            if quarantined.isEmpty { return nil }
            throw StateStoreError.corrupted(quarantined: quarantined)
        }
    }

    public func save(_ state: AppState) throws {
        let data = try StateCoding.encoder().encode(state)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try data.write(to: localDirectory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    public func mirrorToCloud(_ state: AppState) throws {
        guard let cloudDirectory else { return }
        let data = try StateCoding.encoder().encode(state)
        try FileManager.default.createDirectory(at: cloudDirectory, withIntermediateDirectories: true)
        let target = cloudDirectory.appendingPathComponent(Self.fileName)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: target, options: .forReplacing, error: &coordinationError
        ) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func inspect(directory: URL) throws -> Candidate {
        let file = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .absent }
        if let data = try? Data(contentsOf: file),
           let state = try? StateCoding.decoder().decode(AppState.self, from: data) {
            return .valid(state)
        }
        return .quarantined(try quarantine(file))
    }

    /// Renames `file` to `state.corrupt-<stamp>.json`, adding `-2`, `-3`... if taken.
    private func quarantine(_ file: URL) throws -> URL {
        let directory = file.deletingLastPathComponent()
        let base = "state.corrupt-\(FileNameStamp.timestamp(Date()))"
        var destination = directory.appendingPathComponent("\(base).json")
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base)-\(attempt).json")
            attempt += 1
        }
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }
}
