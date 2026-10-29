import Foundation

/// Navigation errors that do not end a profile load: a cancelled request (replaced by a redirect
/// or a new navigation) or an interrupted frame load. `didFinish` or the timeout decides instead.
enum NavigationErrorPolicy {
    private static let webKitErrorDomain = "WebKitErrorDomain"
    private static let frameLoadInterruptedCode = 102

    static func isIgnorable(_ error: any Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain: return nsError.code == NSURLErrorCancelled
        case webKitErrorDomain: return nsError.code == frameLoadInterruptedCode
        default: return false
        }
    }
}
