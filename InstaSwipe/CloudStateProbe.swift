import Foundation
import os

/// Answers "is this saved file (state.json, followers.json) in iCloud?" even when its metadata
/// has not reached this device's folder yet (e.g. right after a reinstall).
@MainActor
protocol CloudStateProbe {
    func cloudFile(named fileName: String) async -> CloudProbeAnswer
}

enum CloudProbeAnswer: Sendable, Equatable {
    case found
    /// iCloud answered, and the file is not there.
    case absent
    /// No answer (timeout, query did not start): the file may still be there.
    case unknown
}

/// Asks iCloud through an `NSMetadataQuery` for the file in the Documents scope and waits for
/// the first gathering, at most `timeout`. A timeout or a failed start answers `.unknown`.
@MainActor
final class MetadataCloudStateProbe: CloudStateProbe {
    private static let timeout: Duration = .seconds(15)

    func cloudFile(named fileName: String) async -> CloudProbeAnswer {
        await MetadataQueryRun().run(fileName: fileName, timeout: Self.timeout)
    }
}

/// One query run; resumes its continuation exactly once.
@MainActor
private final class MetadataQueryRun {
    private static let logger = Logger(subsystem: "com.giacomogrieco.InstaSwipe", category: "CloudStateProbe")

    private let query = NSMetadataQuery()
    private var fileName = ""
    private var observer: (any NSObjectProtocol)?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<CloudProbeAnswer, Never>?

    func run(fileName: String, timeout: Duration) async -> CloudProbeAnswer {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.fileName = fileName
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.gathered() }
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                Self.logger.info("iCloud query for \(self.fileName, privacy: .public) timed out")
                self.finish(.unknown)
            }
            if !query.start() {
                Self.logger.error("iCloud query for \(fileName, privacy: .public) did not start")
                finish(.unknown)
            }
        }
    }

    private func gathered() {
        query.disableUpdates()
        let urls = query.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL }
        Self.logger.info("iCloud query for \(self.fileName, privacy: .public) found \(urls.count, privacy: .public) item(s)")
        urls.forEach(startDownloading)
        finish(urls.isEmpty ? .absent : .found)
    }

    /// Best effort: the regular load retry also starts the download once the placeholder shows up.
    private func startDownloading(_ url: URL) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            Self.logger.error("iCloud download request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finish(_ answer: CloudProbeAnswer) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation.resume(returning: answer)
    }
}
