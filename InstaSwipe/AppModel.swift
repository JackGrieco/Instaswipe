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
    /// Set while iCloud may still hold a followers.json this device has not seen: survives a
    /// relaunch during the wait and a probe timeout, cleared by a definite answer or after
    /// `maxUnknownFollowerProbes` unanswered probes in a row.
    private static let followerProbePendingKey = "followerCloudProbePending"
    private static let followerProbeUnknownCountKey = "followerCloudProbeUnknownCount"
    /// A user whose iCloud never answers stops waiting on every launch after this many.
    private static let maxUnknownFollowerProbes = 3

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
    /// True while the probe asks iCloud whether state.json or followers.json exists there.
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
    /// What `confirmRestore()` will change, waiting for the user's confirmation.
    private(set) var pendingRestore: RestorePlan?
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
    /// Files saved since their last iCloud write. Only those are mirrored: a list this device did
    /// not touch never overwrites a newer copy another device mirrored.
    private var unmirroredFiles: Set<String> = []
    private var cloudRetryTask: Task<Void, Never>?
    private let cloudProbe: (any CloudStateProbe)?
    private(set) var cloudCheckTask: Task<Void, Never>?
    /// This device had its own state.json before this launch's first load. Then a missing
    /// followers.json means "never imported followers", not "not yet listed by iCloud".
    private let hadLocalStateAtLaunch: Bool
    /// File names already asked of the probe: once per launch each.
    private var checkedCloudFiles: Set<String> = []
    /// File names the probe saw in iCloud: keep waiting for them, never treat them as absent.
    private var expectedCloudFiles: Set<String> = []

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
        hadLocalStateAtLaunch = store.hasLocalCopy
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
        errors.forEach { Self.logger.error("Load failed: \(String(describing: $0))") }
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
            return
        }
        quarantinedFileNames = quarantined.map(\.lastPathComponent)
        loadError = corruptedMessage
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
        if let missing = cloudFileToLookFor(state: loaded, followers: loadedFollowers),
           deferToCloud(fileName: missing) { return }
        isWaitingForCloud = false
        quarantinedFileNames = []
        if loadedFollowers != nil { setFollowerProbePending(false) }
        setLinked(state: loaded, followers: loadedFollowers)
        if loaded != nil {
            scheduleCloudMirror(of: [AppState.fileName, FollowerState.fileName])
        } else if environment.shouldSeedTestAccounts {
            seedTestAccounts()
        }
    }

    /// The file to look for in iCloud: state.json when missing; followers.json only when the state
    /// itself was just recovered from iCloud (fresh install, reinstall, new device) or an earlier
    /// launch did not get a definite answer about it. Nil otherwise.
    private func cloudFileToLookFor(state: AppState?, followers: FollowerState?) -> String? {
        if state == nil { return AppState.fileName }
        guard followers == nil, !hadLocalStateAtLaunch || isFollowerProbePending else { return nil }
        return FollowerState.fileName
    }

    private var isFollowerProbePending: Bool {
        environment.defaults.bool(forKey: Self.followerProbePendingKey)
    }

    /// Any change of the flag starts the count of unanswered probes again.
    private func setFollowerProbePending(_ isPending: Bool) {
        environment.defaults.set(isPending, forKey: Self.followerProbePendingKey)
        environment.defaults.set(0, forKey: Self.followerProbeUnknownCountKey)
    }

    /// Updates the flag from a probe answer about followers.json.
    private func recordFollowerProbeAnswer(_ answer: CloudProbeAnswer) {
        switch answer {
        case .found:
            environment.defaults.set(0, forKey: Self.followerProbeUnknownCountKey)
        case .absent:
            setFollowerProbePending(false)
        case .unknown:
            let unknownCount = environment.defaults.integer(forKey: Self.followerProbeUnknownCountKey) + 1
            if unknownCount >= Self.maxUnknownFollowerProbes {
                setFollowerProbePending(false)
            } else {
                environment.defaults.set(unknownCount, forKey: Self.followerProbeUnknownCountKey)
            }
        }
    }

    /// With iCloud on and a file not found, the iCloud copy may simply not be visible yet: ask the
    /// probe once per file, and wait (retrying every `cloudRetryInterval`) when it says a copy exists.
    /// Returns true when loading must not finish yet (nothing is saved meanwhile: `isBlocked`).
    private func deferToCloud(fileName: String) -> Bool {
        if expectedCloudFiles.contains(fileName) {
            isWaitingForCloud = true
            scheduleCloudRetry()
            return true
        }
        guard isCloudAvailable, !checkedCloudFiles.contains(fileName), let cloudProbe else { return false }
        checkedCloudFiles = checkedCloudFiles.union([fileName])
        if fileName == FollowerState.fileName, !isFollowerProbePending { setFollowerProbePending(true) }
        isCheckingCloud = true
        cloudCheckTask = Task { [weak self] in
            let answer = await cloudProbe.cloudFile(named: fileName)
            self?.cloudCheckFinished(fileName: fileName, answer: answer)
        }
        return true
    }

    /// `.unknown` loads like `.absent` for now, but leaves the follower flag set for the next
    /// launch (see `recordFollowerProbeAnswer`).
    private func cloudCheckFinished(fileName: String, answer: CloudProbeAnswer) {
        Self.logger.info("iCloud probe for \(fileName, privacy: .public): \(String(describing: answer), privacy: .public)")
        isCheckingCloud = false
        if answer == .found { expectedCloudFiles = expectedCloudFiles.union([fileName]) }
        if fileName == FollowerState.fileName { recordFollowerProbeAnswer(answer) }
        attemptLoad()
    }

    /// Before an import builds a follower list from nothing: this device does not reload while
    /// running, so another device may have mirrored one to iCloud since launch. A readable one is
    /// adopted (linked) so the import merges into it instead of overwriting it. Returns false when
    /// the import must stop: the copy is still downloading, or unreadable (then the app blocks
    /// exactly as after a failed load).
    func adoptCloudFollowersBeforeImport() -> Bool {
        guard followers == nil, isCloudAvailable, !isBlocked else { return true }
        do {
            if let loaded = try followerStore.load() {
                setFollowerProbePending(false)
                setLinked(state: state, followers: loaded)
            }
            return true
        } catch StateStoreError.cloudNotDownloaded {
            errorMessage = "I follower stanno arrivando da iCloud, riprova tra poco."
            return false
        } catch {
            loadFailed([error])
            return false
        }
    }

    // MARK: Restore

    private enum FileCondition { case readable, missing, quarantined }

    /// Plans the restore of the quarantined lists only and asks for confirmation (see `pendingRestore`).
    func prepareRestore() {
        do {
            guard let plan = try makeRestorePlan() else {
                errorMessage = "Non ho trovato copie di sicurezza leggibili."
                return
            }
            // Both files read fine now: nothing to restore, just load them.
            guard !plan.isEmpty else {
                attemptLoad()
                return
            }
            pendingRestore = plan
        } catch StateStoreError.cloudNotDownloaded {
            errorMessage = "I progressi stanno ancora arrivando da iCloud. Riprova tra poco."
        } catch {
            Self.logger.error("Restore planning failed: \(error.localizedDescription)")
            errorMessage = "Non riesco a leggere le copie di sicurezza: \(error.localizedDescription)"
        }
    }

    /// Only a quarantined file is replaced: a readable one never, and a missing one neither, since
    /// iCloud may simply not have listed it yet (a backup stamped now would beat the real copy).
    /// A quarantined state comes from the newest readable backup with accounts; quarantined
    /// followers from the newest backup holding followers (older builds share the folder and may
    /// own the newest daily names), or are set aside when none does.
    /// Nil when state.json was quarantined and no backup can replace it.
    private func makeRestorePlan() throws -> RestorePlan? {
        let stateCondition = try Self.condition(of: store.load)
        let followerCondition = try Self.condition(of: followerStore.load)
        let stateSource = try stateCondition == .quarantined ? backups.newestStateBackup() : nil
        if stateCondition == .quarantined, stateSource == nil { return nil }
        let followerSource = try followerCondition == .quarantined ? backups.newestFollowersBackup() : nil
        let isFromTwoBackups = stateSource != nil && followerSource != nil && stateSource?.name != followerSource?.name
        return RestorePlan(
            state: stateSource?.content,
            followers: followerSource?.content,
            discardsFollowers: followerCondition == .quarantined && followerSource == nil,
            isFromTwoBackups: isFromTwoBackups
        )
    }

    /// `cloudNotDownloaded` and other errors propagate: nothing is planned over a pending copy.
    private static func condition<Document>(of load: () throws -> Document?) throws -> FileCondition {
        do {
            return try load() == nil ? .missing : .readable
        } catch StateStoreError.corrupted {
            return .quarantined
        }
    }

    func cancelRestore() {
        pendingRestore = nil
    }

    /// The files or backups may have changed while the dialog was up (iCloud, another device):
    /// never write a plan the user did not see.
    private func isStillCurrent(_ plan: RestorePlan) -> Bool {
        do {
            guard try makeRestorePlan() == plan else {
                errorMessage = "I file sono cambiati nel frattempo: riprova il ripristino."
                return false
            }
            return true
        } catch {
            Self.logger.error("Restore re-check failed: \(error.localizedDescription)")
            errorMessage = "Non riesco a ricontrollare i file: \(error.localizedDescription)"
            return false
        }
    }

    /// Writes only what the plan restores, then loads both files again, so the lists in memory are
    /// exactly what is on disk, linked. Quarantined files stay in place, except unrecoverable
    /// follower copies, which are renamed aside. Any failure keeps the app blocked.
    func confirmRestore() {
        guard let plan = pendingRestore, loadError != nil, !isWaitingForCloud, !isCheckingCloud else { return }
        pendingRestore = nil
        guard isStillCurrent(plan) else { return }
        if plan.discardsFollowers {
            do {
                _ = try followerStore.discardQuarantined()
            } catch {
                Self.logger.error("Setting aside followers failed: \(error.localizedDescription)")
                errorMessage = "Non sono riuscito a mettere da parte i follower illeggibili: \(error.localizedDescription)"
                return
            }
        }
        let stamp = now()
        if let followers = plan.followers, save(followers, in: followerStore, at: stamp) == nil { return }
        if let state = plan.state, save(state, in: store, at: stamp) == nil { return }
        attemptLoad()
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

    /// For what belongs to the profile rather than the list (availability, display name). Saves only
    /// the lists `transform` changes: an untouched file keeps its bytes and `savedAt`, so it never
    /// wins over a newer copy another device mirrored to iCloud.
    func applyToBothLists(_ transform: (AccountList) -> AccountList) {
        guard !isBlocked else { return }
        persist(
            state: state.flatMap { Self.changedList(of: $0, by: transform) },
            followers: followers.flatMap { Self.changedList(of: $0, by: transform) }
        )
    }

    /// Follower mode before any follower list exists: swipe and "Da togliere" invite a reimport.
    var isAwaitingFollowerImport: Bool {
        listMode == .followers && followers == nil
    }

    /// Unfollows and follower removals marked done today, for the shared daily warning.
    func actionsToday(now: Date, calendar: Calendar) -> Int {
        ListMode.allCases.compactMap(list).map { Report.unfollowsToday(in: $0, now: now, calendar: calendar) }.reduce(0, +)
    }

    private static func replacingList<Document: ReviewList>(
        of document: Document, with transform: (AccountList) -> AccountList
    ) -> Document {
        var next = document
        next.list = transform(document.list)
        return next
    }

    /// Nil when `transform` leaves the list as it is.
    private static func changedList<Document: ReviewList>(
        of document: Document, by transform: (AccountList) -> AccountList
    ) -> Document? {
        let changed = transform(document.list)
        guard changed != document.list else { return nil }
        var next = document
        next.list = changed
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
            let savedFiles = [
                newFollowers.map { _ in FollowerState.fileName },
                isComplete ? newState.map { _ in AppState.fileName } : nil,
            ].compactMap { $0 }
            didSave(state: savedState, followers: savedFollowers, changed: Set(savedFiles), at: stamp)
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

    private func didSave(
        state saved: AppState?, followers savedFollowers: FollowerState?, changed files: Set<String>, at stamp: Date
    ) {
        setLinked(state: saved, followers: savedFollowers)
        if let state { runBackupIfNeeded(BackupSnapshot(state: state, followers: followers), at: stamp) }
        scheduleCloudMirror(of: files)
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
    private func scheduleCloudMirror(of files: Set<String>) {
        guard isCloudAvailable else { return }
        unmirroredFiles = unmirroredFiles.union(files)
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
    /// Only the files saved since the last write go (see `unmirroredFiles`); a failed write puts
    /// them back for the next one. Followers are mirrored only once they exist: an empty list never
    /// replaces the iCloud copy.
    private func mirrorLatestState() async {
        guard !isBlocked, let current = state, !unmirroredFiles.isEmpty else { return }
        let files = unmirroredFiles
        let stateSnapshot = files.contains(AppState.fileName) ? current : nil
        let followerSnapshot = files.contains(FollowerState.fileName) ? followers : nil
        unmirroredFiles = []
        firstUnmirroredChange = nil
        let previous = mirrorWriteTask
        let store = store
        let followerStore = followerStore
        let write = Task.detached(priority: .utility) {
            _ = await previous?.value
            return Self.mirror(stateSnapshot, followerSnapshot, store: store, followerStore: followerStore)
        }
        mirrorWriteTask = write
        if case .failure(let error) = await write.value {
            unmirroredFiles = unmirroredFiles.union(files)
            Self.logger.error("Cloud mirror failed: \(error.localizedDescription)")
            bannerMessage = "Copia su iCloud non riuscita: \(error.localizedDescription)"
        }
    }

    /// Tries both files even when one fails; returns the first failure.
    private nonisolated static func mirror(
        _ state: AppState?, _ followers: FollowerState?, store: FileStateStore, followerStore: FollowerStore
    ) -> Result<Void, any Error> {
        let followerResult = Result { _ = try followers.map(followerStore.mirrorToCloud) }
        let stateResult = Result { _ = try state.map(store.mirrorToCloud) }
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
