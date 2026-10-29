import Foundation

public enum Limits {
    public static let defaultDailyProfileLoads = 400
    public static let dailyUnfollowWarning = 150
    public static let reimportSuspiciousRatio = 0.2
    public static let profileLoadTimeout: Duration = .seconds(10)
    public static let dailyBackupsKept = 14
    public static let stepBackupsKept = 10
    public static let backupEveryDecisions = 100
    public static let preImportBackupsKept = 5
    public static let cloudMirrorDebounce: Duration = .seconds(5)
}
