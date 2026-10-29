import Foundation
import InstaSwipeKit
import OSLog
import UIKit
import WebKit

@MainActor
protocol ProfileLoading {
    func load(username: String) async -> ProfilePageResult
}

@MainActor
final class FakeProfileLoader: ProfileLoading {
    private static let delay: Duration = .milliseconds(50)

    func load(username: String) async -> ProfilePageResult {
        try? await Task.sleep(for: Self.delay)
        return .profile(displayName: "Test \(username)", imageURL: nil)
    }
}

/// Loads one profile page per call in a hidden WKWebView and classifies a read-only snapshot.
/// No clicks, no scripts beyond reading the DOM. Callers limit concurrency to 2.
@MainActor
final class WebProfileLoader: ProfileLoading {
    static let extractionScript = """
    (() => ({ url: location.href, title: document.title,
      ogTitle: document.querySelector('meta[property="og:title"]')?.content ?? null,
      ogImage: document.querySelector('meta[property="og:image"]')?.content ?? null,
      body: (document.body?.innerText ?? '').slice(0, 3000) }))()
    """

    static let logger = Logger(subsystem: "com.giacomogrieco.InstaSwipe", category: "ProfileLoader")

    func load(username: String) async -> ProfilePageResult {
        guard let url = URL(string: "https://www.instagram.com/\(username)/") else { return .unrecognized }
        let session = LoadSession(url: url, username: username)
        return await session.run()
    }
}

/// One hidden web view, one page load; resumes its continuation exactly once.
@MainActor
private final class LoadSession: NSObject, WKNavigationDelegate {
    private let url: URL
    private let username: String
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ProfilePageResult, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(url: URL, username: String) {
        self.url = url
        self.username = username
    }

    func run() async -> ProfilePageResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
            webView.alpha = 0
            webView.navigationDelegate = self
            self.webView = webView
            attachToWindow(webView)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Limits.profileLoadTimeout)
                guard !Task.isCancelled else { return }
                WebProfileLoader.logger.error("Profile load timed out")
                self?.finish(.unrecognized)
            }
            webView.load(URLRequest(url: url))
        }
    }

    private func attachToWindow(_ webView: WKWebView) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        window?.addSubview(webView)
    }

    private func finish(_ result: ProfilePageResult) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        continuation.resume(returning: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(WebProfileLoader.extractionScript) { [weak self] value, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    let nsError = error as NSError
                    WebProfileLoader.logger.error(
                        "Extraction script failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)"
                    )
                }
                guard let snapshot = ProfileSnapshotMapper.snapshot(from: value, requestedURL: self.url) else {
                    WebProfileLoader.logger.error("Unreadable page snapshot")
                    self.finish(.unrecognized)
                    return
                }
                let result = ProfilePageClassifier.classify(snapshot, username: self.username)
                WebProfileLoader.logger.notice(
                    "Classified \(result.logLabel, privacy: .public) at \(snapshot.finalURL.absoluteString, privacy: .public)"
                )
                self.finish(result)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    /// Cancelled or interrupted navigations are not final: `didFinish` or the timeout decides.
    private func navigationFailed(_ error: any Error) {
        let nsError = error as NSError
        let isIgnorable = NavigationErrorPolicy.isIgnorable(error)
        WebProfileLoader.logger.error(
            "Navigation failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public), ignored: \(isIgnorable, privacy: .public)"
        )
        guard !isIgnorable else { return }
        finish(.unrecognized)
    }
}

private extension ProfilePageResult {
    /// Case name only, without display name or image URL.
    var logLabel: String {
        switch self {
        case .profile: "profile"
        case .unavailable: "unavailable"
        case .rateLimited: "rateLimited"
        case .loginRequired: "loginRequired"
        case .unrecognized: "unrecognized"
        }
    }
}
