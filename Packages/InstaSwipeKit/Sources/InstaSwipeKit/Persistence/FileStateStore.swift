import Foundation

public enum StateStoreError: Error, Equatable {
    /// State files existed but none could be read; they were renamed, not deleted.
    case corrupted(quarantined: [URL])
    /// The iCloud copy exists but is not downloaded yet and no usable local copy exists.
    case cloudNotDownloaded
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

    /// `nil` only when no state file, placeholder or quarantined file exists anywhere.
    public func load() throws -> AppState? {
        let local = try inspect(directory: localDirectory, isCloud: false)
        if try isCloudPending() {
            if case let .valid(localState) = local { return localState }
            throw StateStoreError.cloudNotDownloaded
        }
        let cloud = try cloudDirectory.map { try inspect(directory: $0, isCloud: true) } ?? .absent

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
            let quarantined = existingQuarantined()
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

    private var cloudStateURL: URL? {
        cloudDirectory?.appendingPathComponent(Self.fileName)
    }

    /// True when the iCloud copy is a placeholder or not fully downloaded; starts the download.
    private func isCloudPending() throws -> Bool {
        guard let cloudDirectory, let stateURL = cloudStateURL else { return false }
        let manager = FileManager.default
        let placeholder = cloudDirectory.appendingPathComponent(".\(Self.fileName).icloud")
        var isPending = manager.fileExists(atPath: placeholder.path)
        if manager.fileExists(atPath: stateURL.path) {
            let status = try stateURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if let status, status != .current { isPending = true }
        }
        guard isPending else { return false }
        do {
            try manager.startDownloadingUbiquitousItem(at: stateURL)
        } catch let error as NSError where Self.isNotUbiquitous(error) {
            // Plain directory (no file provider): there is nothing to download.
        }
        return true
    }

    /// Error produced by `startDownloadingUbiquitousItem` for a URL outside iCloud.
    private static func isNotUbiquitous(_ error: NSError) -> Bool {
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return error.domain == NSCocoaErrorDomain
            && underlying?.domain == "NSFileProviderInternalErrorDomain"
    }

    private func inspect(directory: URL, isCloud: Bool) throws -> Candidate {
        let file = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return .absent }
        let data = isCloud ? try coordinatedRead(file) : try? Data(contentsOf: file)
        if let data, let state = try? StateCoding.decoder().decode(AppState.self, from: data) {
            return .valid(state)
        }
        return .quarantined(try quarantine(file, isCloud: isCloud))
    }

    /// A read failure inside the coordinator is treated as unreadable (returns nil);
    /// coordinator errors are rethrown.
    private func coordinatedRead(_ file: URL) throws -> Data? {
        var coordinationError: NSError?
        var data: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: file, options: [], error: &coordinationError
        ) { url in
            data = try? Data(contentsOf: url)
        }
        if let coordinationError { throw coordinationError }
        return data
    }

    /// Renames `file` to `state.corrupt-<stamp>.json`, adding `-2`, `-3`... if taken.
    private func quarantine(_ file: URL, isCloud: Bool) throws -> URL {
        let directory = file.deletingLastPathComponent()
        let base = "state.corrupt-\(FileNameStamp.timestamp(Date()))"
        var destination = directory.appendingPathComponent("\(base).json")
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base)-\(attempt).json")
            attempt += 1
        }
        guard isCloud else {
            try FileManager.default.moveItem(at: file, to: destination)
            return destination
        }
        var coordinationError: NSError?
        var moveError: Error?
        let target = destination
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: file, options: .forMoving, error: &coordinationError
        ) { url in
            do { try FileManager.default.moveItem(at: url, to: target) } catch { moveError = error }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
        return destination
    }

    /// All `state.corrupt-*.json` files in both directories, sorted by path.
    private func existingQuarantined() -> [URL] {
        let directories = [localDirectory] + (cloudDirectory.map { [$0] } ?? [])
        return directories.flatMap { directory -> [URL] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names
                .filter { $0.hasPrefix("state.corrupt-") && $0.hasSuffix(".json") }
                .map { directory.appendingPathComponent($0) }
        }.sorted { $0.path < $1.path }
    }
}
