import Foundation
import InstaSwipeKit
import Observation
import os

@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "com.giacomogrieco.InstaSwipe", category: "AppModel")
    private static let cloudRetryInterval: Duration = .seconds(2)

    private(set) var state: AppState?
    /// Set when `load()` failed for good: nothing is ever saved while it is non-nil.
    private(set) var loadError: String?
    private(set) var quarantinedFileNames: [String] = []
    private(set) var isWaitingForCloud = false
    /// Non-blocking warning (backup or mirror problems).
    private(set) var bannerMessage: String?
    /// Blocking-but-dismissable message (save or import failure).
    var errorMessage: String?
    private(set) var pendingMerge: MergePreview?
    private var pendingSnapshot: ExportSnapshot?
    /// Backup chosen by `prepareRestore()`, waiting for the user's confirmation.
    private(set) var pendingRestore: AppState?

    let isCloudAvailable: Bool
    let environment: AppEnvironment

    private let store: FileStateStore
    private let backups: BackupRotator
    private let now: @Sendable () -> Date
    /// Pending debounced mirror; replaced on every change.
    private var mirrorTask: Task<Void, Never>?
    /// Last started iCloud write: each write waits for it, so writes never overlap or reorder.
    private var mirrorWriteTask: Task<Result<Void, any Error>, Never>?
    private var firstUnmirroredChange: ContinuousClock.Instant?
    private var cloudRetryTask: Task<Void, Never>?

    init(environment: AppEnvironment, now: @escaping @Sendable () -> Date = { Date() }) {
        self.environment = environment
        self.now = now
        isCloudAvailable = environment.cloudDirectory != nil
        store = FileStateStore(localDirectory: environment.localDirectory, cloudDirectory: environment.cloudDirectory)
        let backupsRoot = environment.cloudDirectory ?? environment.localDirectory
        backups = BackupRotator(directory: backupsRoot.appendingPathComponent("Backups", isDirectory: true))
        attemptLoad()
    }

    // MARK: Loading

    private func attemptLoad() {
        do {
            let loaded = try store.load()
            finishLoading(with: loaded)
        } catch StateStoreError.cloudNotDownloaded {
            isWaitingForCloud = true
            scheduleCloudRetry()
        } catch StateStoreError.corrupted(let quarantined) {
            isWaitingForCloud = false
            quarantinedFileNames = quarantined.map(\.lastPathComponent)
            loadError = corruptedMessage
            Self.logger.error("State corrupted, quarantined \(quarantined.count) file(s)")
        } catch {
            isWaitingForCloud = false
            loadError = error.localizedDescription
            Self.logger.error("State load failed: \(error.localizedDescription)")
        }
    }

    private var corruptedMessage: String {
        let intro = "Non riesco a leggere i progressi salvati. Non ho cancellato niente: i file sono stati messi da parte."
        return isCloudAvailable
            ? "\(intro) Le copie di sicurezza sono anche in File → iCloud Drive → InstaSwipe → Backups."
            : "\(intro) Le copie di sicurezza sono dentro l'app: usa «Ripristina l'ultima copia di sicurezza»."
    }

    /// "Riprova" on the load error screen.
    func retryLoad() {
        attemptLoad()
    }

    private func scheduleCloudRetry() {
        cloudRetryTask?.cancel()
        cloudRetryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.cloudRetryInterval)
            guard !Task.isCancelled else { return }
            self?.attemptLoad()
        }
    }

    private func finishLoading(with loaded: AppState?) {
        loadError = nil
        isWaitingForCloud = false
        state = loaded
        if loaded != nil {
            scheduleCloudMirror()
        } else if environment.shouldSeedTestAccounts {
            seedTestAccounts()
        }
    }

    // MARK: Restore

    /// Picks the newest readable backup and asks for confirmation (see `pendingRestore`).
    func prepareRestore() {
        do {
            guard let backup = try backups.newestValidBackup() else {
                errorMessage = "Non ho trovato copie di sicurezza leggibili."
                return
            }
            pendingRestore = backup
        } catch {
            Self.logger.error("Backup listing failed: \(error.localizedDescription)")
            errorMessage = "Non riesco a leggere le copie di sicurezza: \(error.localizedDescription)"
        }
    }

    func cancelRestore() {
        pendingRestore = nil
    }

    /// Saves the chosen backup as the current state, leaving the quarantined files in place.
    func confirmRestore() {
        guard let backup = pendingRestore, let previousError = loadError else { return }
        pendingRestore = nil
        loadError = nil
        if persist(backup) {
            quarantinedFileNames = []
        } else {
            loadError = previousError
        }
    }

    // MARK: Mutations

    /// Applies `transform` and persists the result synchronously. No-op without a loaded state
    /// or after a load error; `state` only changes if the save succeeded.
    func apply(_ transform: (AppState) -> AppState) {
        guard loadError == nil, !isWaitingForCloud, let current = state else { return }
        persist(transform(current))
    }

    @discardableResult
    private func persist(_ candidate: AppState) -> Bool {
        guard loadError == nil, !isWaitingForCloud else { return false }
        var next = candidate
        next.savedAt = now()
        do {
            try store.save(next)
        } catch {
            Self.logger.error("Save failed: \(error.localizedDescription)")
            errorMessage = "Non sono riuscito a salvare: \(error.localizedDescription)"
            return false
        }
        state = next
        runBackupIfNeeded(next)
        scheduleCloudMirror()
        return true
    }

    private func runBackupIfNeeded(_ saved: AppState) {
        do {
            _ = try backups.backupIfNeeded(saved, now: saved.savedAt, calendar: .current)
        } catch {
            Self.logger.error("Backup failed: \(error.localizedDescription)")
            bannerMessage = "Copia di sicurezza non riuscita: \(error.localizedDescription)"
        }
    }

    // MARK: Cloud mirror

    /// Debounced, but never later than `Limits.cloudMirrorMaxWait` after the first unmirrored change.
    private func scheduleCloudMirror() {
        guard isCloudAvailable else { return }
        let changedAt = ContinuousClock.now
        let firstChange = firstUnmirroredChange ?? changedAt
        firstUnmirroredChange = firstChange
        let fireAt = MirrorSchedule.fireInstant(lastChange: changedAt, firstUnmirroredChange: firstChange)
        mirrorTask?.cancel()
        mirrorTask = Task { [weak self] in
            try? await Task.sleep(until: fireAt, clock: .continuous)
            guard !Task.isCancelled else { return }
            await self?.mirrorLatestState()
        }
    }

    /// Cancels the debounce and mirrors right away (call when the app goes to background).
    /// Runs inside a background task so the write can finish after the app is suspended.
    func flushCloudMirror() async {
        guard isCloudAvailable else { return }
        mirrorTask?.cancel()
        let activity = BackgroundActivity(name: "iCloudMirror")
        await mirrorLatestState()
        activity.end()
    }

    /// Writes are chained: each waits for the previous one, so the latest state is written last.
    private func mirrorLatestState() async {
        guard loadError == nil, let snapshot = state else { return }
        firstUnmirroredChange = nil
        let previous = mirrorWriteTask
        let store = store
        let write = Task.detached(priority: .utility) {
            _ = await previous?.value
            return Result { try store.mirrorToCloud(snapshot) }
        }
        mirrorWriteTask = write
        if case .failure(let error) = await write.value {
            Self.logger.error("Cloud mirror failed: \(error.localizedDescription)")
            bannerMessage = "Copia su iCloud non riuscita: \(error.localizedDescription)"
        }
    }

    func dismissBanner() {
        bannerMessage = nil
    }

    // MARK: Import

    /// `picked` is either one folder or the JSON files chosen in the Files picker.
    func prepareImport(picked: [URL]) async {
        guard loadError == nil, !isWaitingForCloud else { return }
        let scoped = picked.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        let result = await Task.detached(priority: .userInitiated) {
            Result { try Self.loadSnapshot(from: picked) }
        }.value
        switch result {
        case .success(let snapshot) where snapshot.follows.isEmpty:
            clearPendingImport()
            errorMessage = "L'export non contiene account seguiti."
        case .success(let snapshot):
            pendingSnapshot = snapshot
            pendingMerge = MergeEngine.preview(current: state, snapshot: snapshot, now: now())
        case .failure(let error):
            errorMessage = Self.importMessage(for: error)
        }
    }

    private nonisolated static func loadSnapshot(from picked: [URL]) throws -> ExportSnapshot {
        let files: ExportFiles
        if picked.count == 1, picked[0].hasDirectoryPath {
            files = try ExportLocator.locate(in: picked[0])
        } else {
            files = try ExportLocator.classify(picked)
        }
        return try ExportLocator.load(files)
    }

    /// Re-merges the picked snapshot into the CURRENT state, so decisions made after the
    /// preview was computed are never overwritten.
    func confirmImport() {
        guard let snapshot = pendingSnapshot, loadError == nil, !isWaitingForCloud else { return }
        if let current = state {
            do {
                try backups.backup(current, kind: .preImport, now: now())
            } catch {
                Self.logger.error("Pre-import backup failed: \(error.localizedDescription)")
                errorMessage = "Import annullato: non sono riuscito a fare la copia di sicurezza (\(error.localizedDescription))."
                return
            }
        }
        let merged = MergeEngine.preview(current: state, snapshot: snapshot, now: now())
        // On failure the preview stays up so the error alert shows inside the sheet.
        if persist(merged.state) { clearPendingImport() }
    }

    private func clearPendingImport() {
        pendingMerge = nil
        pendingSnapshot = nil
    }

    func cancelImport() {
        clearPendingImport()
    }

    private static func importMessage(for error: Error) -> String {
        switch error as? ExportParserError {
        case .followingNotFound:
            return "Non trovo i file «following» nella cartella scelta. Scegli la cartella dell'export di Instagram."
        case .unrecognizedFormat:
            return "Il formato dei file non è riconosciuto. Esporta di nuovo da Instagram in formato JSON."
        case nil:
            return "Import non riuscito: \(error.localizedDescription)"
        }
    }

    // MARK: UI-test seed

    private func seedTestAccounts() {
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        let follows = (1...5).map { index -> ExportedFollow in
            let name = String(format: "test_%02d", index)
            return ExportedFollow(
                username: name,
                profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
                followedSince: base.addingTimeInterval(Double(index) * 86_400)
            )
        }
        let snapshot = ExportSnapshot(follows: follows, followers: ["test_02"])
        persist(MergeEngine.preview(current: nil, snapshot: snapshot, now: now()).state)
    }
}
