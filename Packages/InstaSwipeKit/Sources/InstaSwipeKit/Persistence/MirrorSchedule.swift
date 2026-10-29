import Foundation

/// When to copy the state to iCloud: `Limits.cloudMirrorDebounce` after the last change,
/// but never later than `Limits.cloudMirrorMaxWait` after the first change not yet mirrored.
public enum MirrorSchedule {
    public static func fireInstant(
        lastChange: ContinuousClock.Instant,
        firstUnmirroredChange: ContinuousClock.Instant
    ) -> ContinuousClock.Instant {
        min(
            lastChange.advanced(by: Limits.cloudMirrorDebounce),
            firstUnmirroredChange.advanced(by: Limits.cloudMirrorMaxWait)
        )
    }
}
