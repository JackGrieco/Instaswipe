import Foundation

/// Remembers, on this device only, that the user started the Instagram export and is
/// waiting for Meta's email: the tutorial then reopens on the import phase.
struct TutorialProgressStore {
    private static let hasStartedExportKey = "exportTutorial.hasStartedExport"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var hasStartedExport: Bool {
        defaults.bool(forKey: Self.hasStartedExportKey)
    }

    func markExportStarted() {
        defaults.set(true, forKey: Self.hasStartedExportKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.hasStartedExportKey)
    }
}
