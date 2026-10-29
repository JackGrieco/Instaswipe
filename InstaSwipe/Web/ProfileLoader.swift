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

    private static let logger = Logger(subsystem: "com.giacomogrieco.InstaSwipe", category: "ProfileLoader")

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
        webView.evaluateJavaScript(WebProfileLoader.extractionScript) { [weak self] value, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let snapshot = ProfileSnapshotMapper.snapshot(from: value, requestedURL: self.url) else {
                    self.finish(.unrecognized)
                    return
                }
                self.finish(ProfilePageClassifier.classify(snapshot, username: self.username))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.unrecognized)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.unrecognized)
    }
}
