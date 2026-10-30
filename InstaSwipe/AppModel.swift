import Foundation
import InstaSwipeKit
import Observation
import os

enum RootScreen: Equatable {
    case loadError(String)
    case checkingCloud
    case waitingForCloud
    case importer
    case main
}

@MainActor
@Observable
final class AppModel {
    static let logger = Logger(subsystem: "com.giacomogrieco.InstaSwipe", category: "AppModel")
    private static let cloudRetryInterval: Duration = .seconds(2)
    private static let listModeKey = "listMode"

    /// Always `Linking.linked` with `followers`, so "ti segue" never trusts a stale state.json.
    private(set) var state: AppState?
    /// The accounts that follow you; nil until an import brings a followers file.
    private(set) var followers: FollowerState?
    /// Which list swipe and "Da togliere" show; a view preference kept in `environment.defaults`.
    var listMode: ListMode {
        didSet { environment.defaults.set(listMode.rawValue, forKey: Self.listModeKey) }
    }
    /// Set when `load()` failed for good: nothing is ever saved while it is non-nil.
    private(set) var loadError: String?
    private(set) var quarantinedFileNames: [String] = []
    private(set) var isWaitingForCloud = false
    /// True while the probe asks iCloud whether a state exists (fresh install with iCloud on).
    private(set) var isCheckingCloud = false
    /// Non-blocking warning (backup or mirror problems).
    private(set) var bannerMessage: String?
    /// Blocking-but-dismissable message (save or import failure).
    var errorMessage: String?
    // Import state: settable only so `AppModel+Import.swift` can manage it; views only read it.
    var pendingMerge: MergePreview?
    /// Set with `pendingMerge` when the picked export has followers files.
    var pendingFollowerMerge: FollowerMergePreview?
    var pendingSnapshot: ExportSnapshot?
    /// What `confirmRestore()` will put in place, waiting for the user's confirmation: the newest
    /// readable backup's state, and the followers chosen by `restoreFollowers(for:)`.
    private(set) var pendingRestore: BackupSnapshot?
    /// False when `pendingRestore.followers` is the readable followers.json, left untouched.
    private var restoreSavesFollowers = true
    /// The user reached the "wait for the email" phase and has not imported since.
    private(set) var hasStartedExport: Bool
    /// Bumped by every confirmed import, so a view can react to one finishing.
    var confirmedImportCount = 0

    let isCloudAvailable: Bool
    let environment: AppEnvironment

    private let store: FileStateStore
    private let followerStore: FollowerStore
    private let tutorialProgress: TutorialProgressStore
    let backups: BackupRotator
    let now: @Sendable () -> Date
    /// Pending debounced mirror; replaced on every change.
    private var mirrorTask: Task<Void, Never>?
    /// Last started iCloud write: each write waits for it, so writes never overlap or reorder.
    private var mirrorWriteTask: Task<Result<Void, any Error>, Never>?
    private var firstUnmirroredChange: ContinuousClock.Instant?
    private var cloudRetryTask: Task<Void, Never>?
    private let cloudProbe: (any CloudStateProbe)?
    private(set) var cloudCheckTask: Task<Void, Never>?
    private var hasCheckedCloud = false
    /// The probe saw a state in iCloud: keep waiting for it, never offer an import.
    private var isCloudStateExpected = false

    /// `cloudProbe` defaults to an `NSMetadataQuery` probe, except in UI-test mode or without iCloud.
    init(
        environment: AppEnvironment,
        cloudProbe: (any CloudStateProbe)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.environment = environment
        self.now = now
        self.cloudProbe = cloudProbe
            ?? (environment.isUITesting || environment.cloudDirectory == nil ? nil : MetadataCloudStateProbe())
        isCloudAvailable = environment.cloudDirectory != nil
        tutorialProgress = TutorialProgressStore(defaults: environment.defaults)
        hasStartedExport = tutorialProgress.hasStartedExport
        listMode = environment.defaults.string(forKey: Self.listModeKey).flatMap(ListMode.init(rawValue:)) ?? .following
        store = FileStateStore(localDirectory: environment.localDirectory, cloudDirectory: environment.cloudDirectory)
        followerStore = FollowerStore(localDirectory: environment.localDirectory, cloudDirectory: environment.cloudDirectory)
        let backupsRoot = environment.cloudDirectory ?? environment.localDirectory
        backups = BackupRotator(directory: backupsRoot.appendingPathComponent("Backups", isDirectory: true))
        attemptLoad()
    }

    // MARK: Loading

    /// Reads both files every time, so both downloads start and both quarantines are listed.
    /// A failure of either blocks the app as a whole: nothing is saved until both load.
    private func attemptLoad() {
        let loadedState = Result { try store.load() }
        let loadedFollowers = Result { try followerStore.load() }
        guard case .success(let state) = loadedState, case .success(let followers) = loadedFollowers else {
            loadFailed([loadedState.failure, loadedFollowers.failure].compactMap { $0 })
            return
        }
        finishLoading(state: state, followers: followers)
    }

    /// Waiting for iCloud wins over corruption: the download may bring a readable copy.
    private func loadFailed(_ errors: [any Error]) {
        let storeErrors = errors.compactMap { $0 as? StateStoreError }
        if storeErrors.contains(.cloudNotDownloaded) {
            isWaitingForCloud = true
            scheduleCloudRetry()
            return
        }
        isWaitingForCloud = false
        let quarantined = storeErrors.flatMap { error -> [URL] in
            if case .corrupted(let urls) = error { return urls }
            return []
        }
        if storeErrors.isEmpty, let error = errors.first {
            loadError = error.localizedDescription
            Self.logger.error("State load failed: \(error.localizedDescription)")
            return
        }
        quarantinedFileNames = quarantined.map(\.lastPathComponent)
        loadError = corruptedMessage
        Self.logger.error("State corrupted, quarantined \(quarantined.count) file(s)")
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

    var rootScreen: RootScreen {
        if let loadError { return .loadError(loadError) }
        if isCheckingCloud { return .checkingCloud }
        if isWaitingForCloud { return .waitingForCloud }
        return state == nil ? .importer : .main
    }

    /// Nothing saves while loading failed, iCloud is still being checked or downloaded.
    var isBlocked: Bool {
        loadError != nil || isWaitingForCloud || isCheckingCloud
    }

    /// A first import with iCloud on asks for confirmation (the cloud copy may be late).
    var needsFirstImportConfirmation: Bool {
        state == nil && isCloudAvailable
    }

    private func finishLoading(state loaded: AppState?, followers loadedFollowers: FollowerState?) {
        loadError = nil
        if loaded == nil, deferToCloudState() { return }
        isWaitingForCloud = false
        setLinked(state: loaded, followers: loadedFollowers)
        if loaded != nil {
            scheduleCloudMirror()
        } else if environment.shouldSeedTestAccounts {
            seedTestAccounts()
        }
    }

    /// With iCloud on and no state found, the iCloud copy may simply not be visible yet: ask the
    /// probe once, and wait (retrying every `cloudRetryInterval`) when it says a copy exists.
    /// Returns true when the import screen must not be shown yet.
    private func deferToCloudState() -> Bool {
        if isCloudStateExpected {
            isWaitingForCloud = true
            scheduleCloudRetry()
            return true
        }
        guard isCloudAvailable, !hasCheckedCloud, let cloudProbe else { return false }
        hasCheckedCloud = true
        isCheckingCloud = true
        cloudCheckTask = Task { [weak self] in
            let exists = await cloudProbe.cloudStateExists()
            self?.cloudCheckFinished(exists: exists)
        }
        return true
    }

    private func cloudCheckFinished(exists: Bool) {
        Self.logger.info("iCloud state probe: \(exists ? "found" : "not found", privacy: .public)")
        isCheckingCloud = false
        isCloudStateExpected = exists
        attemptLoad()
    }

    // MARK: Restore

    /// Picks the newest readable backup and asks for confirmation (see `pendingRestore`).
    func prepareRestore() {
        do {
            guard let backup = try backups.newestValidBackup() else {
                errorMessage = "Non ho trovato copie di sicurezza leggibili."
                return
            }
            let followers = try restoreFollowers(for: backup)
            pendingRestore = BackupSnapshot(state: backup.state, followers: followers.value)
            restoreSavesFollowers = followers.isFromBackup
        } catch StateStoreError.cloudNotDownloaded {
            errorMessage = "I follower stanno ancora arrivando da iCloud. Riprova tra poco."
        } catch {
            Self.logger.error("Backup listing failed: \(error.localizedDescription)")
            errorMessage = "Non riesco a leggere le copie di sicurezza: \(error.localizedDescription)"
        }
    }

    /// The backup's own followers when it has them. A backup from an older build has none: then a
    /// readable followers.json stays as it is, and a missing or quarantined one comes from the newest
    /// backup that holds followers (older builds may own the newest daily names). Nil when none does.
    private func restoreFollowers(for backup: BackupSnapshot) throws -> (value: FollowerState?, isFromBackup: Bool) {
        if let followers = backup.followers { return (followers, true) }
        do {
            if let current = try followerStore.load() { return (current, false) }
        } catch StateStoreError.corrupted {
            // Quarantined: fall back to the backups below.
        }
        return (try backups.newestValidFollowers(), true)
    }

    func cancelRestore() {
        pendingRestore = nil
    }

    /// Saves the chosen backup as the current state, leaving the quarantined files in place.
    func confirmRestore() {
        guard let backup = pendingRestore, let previousError = loadError else { return }
        pendingRestore = nil
        loadError = nil
        let followersToSave = restoreSavesFollowers ? backup.followers : nil
        // Not saved here means already on disk (or none at all): link the state to them.
        if followersToSave == nil { followers = backup.followers }
        if persist(state: backup.state, followers: followersToSave) {
            quarantinedFileNames = []
        } else {
            loadError = previousError
        }
    }

    // MARK: Mutations

    /// Applies `transform` and persists the result synchronously. No-op without a loaded state
    /// or after a load error; `state` only changes if the save succeeded.
    func apply(_ transform: (AppState) -> AppState) {
        guard !isBlocked, let current = state else { return }
        persist(state: transform(current))
    }

    /// `nil` for `.followers` until an import brought followers.
    func list(_ mode: ListMode) -> AccountList? {
        switch mode {
        case .following: state?.list
        case .followers: followers?.list
        }
    }

    /// Applies `transform` to one list and saves only that list's file.
    func apply(_ mode: ListMode, _ transform: (AccountList) -> AccountList) {
        guard !isBlocked else { return }
        switch mode {
        case .following:
            persist(state: state.map { Self.replacingList(of: $0, with: transform) })
        case .followers:
            persist(followers: followers.map { Self.replacingList(of: $0, with: transform) })
        }
    }

    /// For what belongs to the profile rather than the list (availability, display name).
    func applyToBothLists(_ transform: (AccountList) -> AccountList) {
        guard !isBlocked else { return }
        persist(
            state: state.map { Self.replacingList(of: $0, with: transform) },
            followers: followers.map { Self.replacingList(of: $0, with: transform) }
        )
    }

    /// Unfollows and follower removals marked done today, for the shared daily warning.
    func actionsToday(now: Date, calendar: Calendar) -> Int {
        ListMode.allCases.compactMap(list).map { Report.unfollowsToday(in: $0, now: now, calendar: calendar) }.reduce(0, +)
    }

    private static func replacingList<Document: ReviewList>(
        of document: Document, with transform: (AccountList) -> AccountList
    ) -> Document {
        let changed = transform(AccountList(accounts: document.accounts, totalDecisionsMade: document.totalDecisionsMade))
        var next = document
        next.accounts = changed.accounts
        next.totalDecisionsMade = changed.totalDecisionsMade
        return next
    }

    /// The only way to save (internal for `AppModel+Import.swift`; views use `apply`). Saves the
    /// given documents, nil leaving that file alone, followers first: a failed follower save returns
    /// before the state is touched. Only what was saved changes in memory, re-linked.
    @discardableResult
    func persist(state newState: AppState? = nil, followers newFollowers: FollowerState? = nil) -> Bool {
        guard !isBlocked, newState != nil || newFollowers != nil else { return false }
        let stamp = now()
        var savedFollowers = followers
        if let newFollowers {
            guard let saved = save(newFollowers, in: followerStore, at: stamp) else { return false }
            savedFollowers = saved
        }
        var savedState = state
        var isComplete = true
        if let newState {
            if let saved = save(newState, in: store, at: stamp) { savedState = saved } else { isComplete = false }
        }
        if isComplete || newFollowers != nil {
            didSave(state: savedState, followers: savedFollowers, at: stamp)
        }
        return isComplete
    }

    private func save<Document: StoredDocument>(_ candidate: Document, in store: FileDocumentStore<Document>, at stamp: Date) -> Document? {
        var next = candidate
        next.savedAt = stamp
        do {
            try store.save(next)
            return next
        } catch {
            Self.logger.error("Save of \(Document.fileName, privacy: .public) failed: \(error.localizedDescription)")
            errorMessage = "Non sono riuscito a salvare: \(error.localizedDescription)"
            return nil
        }
    }

    private func didSave(state saved: AppState?, followers savedFollowers: FollowerState?, at stamp: Date) {
        setLinked(state: saved, followers: savedFollowers)
        if let state { runBackupIfNeeded(BackupSnapshot(state: state, followers: followers), at: stamp) }
        scheduleCloudMirror()
    }

    private func setLinked(state newState: AppState?, followers newFollowers: FollowerState?) {
        guard let newState else {
            state = nil
            followers = newFollowers
            return
        }
        let linked = Linking.linked(state: newState, followers: newFollowers)
        state = linked.state
        followers = linked.followers
    }

    private func runBackupIfNeeded(_ snapshot: BackupSnapshot, at stamp: Date) {
        do {
            _ = try backups.backupIfNeeded(snapshot, now: stamp, calendar: .current)
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
    /// Followers are mirrored only once they exist: an empty list never replaces the iCloud copy.
    private func mirrorLatestState() async {
        guard !isBlocked, let snapshot = state else { return }
        let followerSnapshot = followers
        firstUnmirroredChange = nil
        let previous = mirrorWriteTask
        let store = store
        let followerStore = followerStore
        let write = Task.detached(priority: .utility) {
            _ = await previous?.value
            return Self.mirror(snapshot, followerSnapshot, store: store, followerStore: followerStore)
        }
        mirrorWriteTask = write
        if case .failure(let error) = await write.value {
            Self.logger.error("Cloud mirror failed: \(error.localizedDescription)")
            bannerMessage = "Copia su iCloud non riuscita: \(error.localizedDescription)"
        }
    }

    /// Tries both files even when one fails; returns the first failure.
    private nonisolated static func mirror(
        _ state: AppState, _ followers: FollowerState?, store: FileStateStore, followerStore: FollowerStore
    ) -> Result<Void, any Error> {
        let followerResult = Result { try followers.map(followerStore.mirrorToCloud) }
        let stateResult = Result { try store.mirrorToCloud(state) }
        if case .failure(let error) = followerResult { return .failure(error) }
        return stateResult
    }

    func dismissBanner() {
        bannerMessage = nil
    }

    // MARK: Export tutorial

    func markExportStarted() {
        tutorialProgress.markExportStarted()
        hasStartedExport = true
    }

    /// Forgets the resume point: the tutorial opens on its first phase again.
    func restartTutorial() {
        tutorialProgress.reset()
        hasStartedExport = false
    }

    // MARK: UI-test seed

    /// Following `test_01`...`test_05`; followers `fan_01`, `fan_02` (not followed back) and
    /// `test_02`, in that date order so the first follower card is `fan_01`.
    private func seedTestAccounts() {
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        let follows = (1...5).map { Self.seedFollow(String(format: "test_%02d", $0), base: base, day: $0) }
        let followers = ["fan_01", "fan_02", "test_02"].enumerated().map { Self.seedFollow($1, base: base, day: $0) }
        let merged = merging(ExportSnapshot(follows: follows, followers: followers))
        persist(state: merged.state, followers: merged.followers)
    }

    private static func seedFollow(_ name: String, base: Date, day: Int) -> ExportedFollow {
        ExportedFollow(
            username: name,
            profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
            followedSince: base.addingTimeInterval(Double(day) * 86_400)
        )
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
