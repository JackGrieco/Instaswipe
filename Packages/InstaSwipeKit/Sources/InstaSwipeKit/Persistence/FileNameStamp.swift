import Foundation

/// Locale-independent date stamps used in file names.
enum FileNameStamp {
    /// `yyyyMMdd-HHmmss` in the current time zone.
    static func timestamp(_ date: Date) -> String {
        format(date, pattern: "yyyyMMdd-HHmmss", timeZone: .current)
    }

    /// `yyyy-MM-dd` in the calendar's time zone.
    static func day(_ date: Date, calendar: Calendar) -> String {
        format(date, pattern: "yyyy-MM-dd", timeZone: calendar.timeZone)
    }

    private static func format(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
