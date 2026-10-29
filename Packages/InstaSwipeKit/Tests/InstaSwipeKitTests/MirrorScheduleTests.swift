import Foundation
import Testing
@testable import InstaSwipeKit

struct MirrorScheduleTests {
    private let start = ContinuousClock.now

    @Test func singleChangeFiresAfterDebounce() {
        let fire = MirrorSchedule.fireInstant(lastChange: start, firstUnmirroredChange: start)
        #expect(fire == start.advanced(by: Limits.cloudMirrorDebounce))
    }

    @Test func laterChangePushesFireTimeBack() {
        let last = start.advanced(by: .seconds(3))
        let fire = MirrorSchedule.fireInstant(lastChange: last, firstUnmirroredChange: start)
        #expect(fire == last.advanced(by: Limits.cloudMirrorDebounce))
    }

    @Test func continuousChangesNeverWaitPastMaxWait() {
        let last = start.advanced(by: .seconds(29))
        let fire = MirrorSchedule.fireInstant(lastChange: last, firstUnmirroredChange: start)
        #expect(fire == start.advanced(by: Limits.cloudMirrorMaxWait))
    }

    @Test func maxWaitIsThirtySeconds() {
        #expect(Limits.cloudMirrorMaxWait == .seconds(30))
    }
}
