import Foundation
import Testing
@testable import InstaSwipe

struct NavigationErrorPolicyTests {
    @Test func cancelledRequestIsIgnorable() {
        #expect(NavigationErrorPolicy.isIgnorable(URLError(.cancelled)))
        #expect(NavigationErrorPolicy.isIgnorable(NSError(domain: NSURLErrorDomain, code: -999)))
    }

    @Test func interruptedFrameLoadIsIgnorable() {
        #expect(NavigationErrorPolicy.isIgnorable(NSError(domain: "WebKitErrorDomain", code: 102)))
    }

    @Test func realFailuresAreFinal() {
        #expect(!NavigationErrorPolicy.isIgnorable(URLError(.notConnectedToInternet)))
        #expect(!NavigationErrorPolicy.isIgnorable(URLError(.timedOut)))
        #expect(!NavigationErrorPolicy.isIgnorable(NSError(domain: "WebKitErrorDomain", code: 101)))
        #expect(!NavigationErrorPolicy.isIgnorable(NSError(domain: "OtherDomain", code: -999)))
        #expect(!NavigationErrorPolicy.isIgnorable(NSError(domain: "OtherDomain", code: 102)))
    }
}
