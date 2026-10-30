import Foundation
import InstaSwipeKit

/// Import of an Instagram export into both lists.
extension AppModel {
    /// `picked` is either one folder or the JSON files chosen in the Files picker.
    func prepareImport(picked: [URL]) async {
        guard !isBlocked else { return }
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
            let date = now()
            pendingSnapshot = snapshot
            pendingMerge = MergeEngine.preview(current: state, snapshot: snapshot, now: date)
            pendingFollowerMerge = snapshot.followers.map { MergeEngine.previewFollowers(current: followers, exported: $0, now: date) }
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

    /// Re-merges the picked snapshot into the CURRENT lists, so decisions made after the
    /// preview was computed are never overwritten. Without followers files the follower list stays as is.
    func confirmImport() {
        guard let snapshot = pendingSnapshot, !isBlocked else { return }
        if state != nil || followers != nil {
            let current = BackupSnapshot(state: state ?? AppState.empty(now: now()), followers: followers)
            do {
                try backups.backup(current, kind: .preImport, now: now())
            } catch {
                Self.logger.error("Pre-import backup failed: \(error.localizedDescription)")
                errorMessage = "Import annullato: non sono riuscito a fare la copia di sicurezza (\(error.localizedDescription))."
                return
            }
        }
        let merged = merging(snapshot)
        // On failure the preview stays up so the error alert shows inside the sheet.
        if persist(state: merged.state, followers: merged.followers) {
            clearPendingImport()
            restartTutorial()
            confirmedImportCount += 1
        }
    }

    /// `followers` is nil when the snapshot has no followers files: that file is then left alone.
    func merging(_ snapshot: ExportSnapshot) -> (state: AppState, followers: FollowerState?) {
        let date = now()
        let mergedState = MergeEngine.preview(current: state, snapshot: snapshot, now: date).state
        let mergedFollowers = snapshot.followers.map {
            MergeEngine.previewFollowers(current: followers, exported: $0, now: date).followers
        }
        return (mergedState, mergedFollowers)
    }

    func clearPendingImport() {
        pendingMerge = nil
        pendingFollowerMerge = nil
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
}
