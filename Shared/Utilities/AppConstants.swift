import Foundation

enum AppConstants {
    static let appName = "Codex-Pulse"
    static let bundleID = "com.codexpulse.app"
    static let appGroupID = "group.com.codexpulse.shared"
    static let snapshotFileName = "pulse_snapshot.json"
    static let settingsFileName = "pulse_settings.json"
    static let historyDBName = "pulse_history.sqlite"

    /// 临时隐藏额外额度重置预测展示；设为 true 即可恢复。
    static let showsResetPredictionPanels = false

    /// 默认轮询间隔（秒）
    static let defaultRefreshInterval: TimeInterval = 10

    /// 可选刷新间隔（秒）
    static let refreshIntervalOptions: [TimeInterval] = [5, 10, 15]

    /// 本地保留天数
    static let historyRetentionDays = 30
    static let historyRetentionOptions: [Int] = [0, 7, 30, 90, 365]

    /// 额度预警默认阈值（已使用百分比）
    static let defaultAlertThresholds: [Double] = [70, 85, 95]

    /// 设置页可选的额度预警阈值。
    static let alertThresholdOptions: [Double] = [50, 70, 85, 95]

    /// 0 表示关闭长任务提醒。
    static let longTaskAlertMinuteOptions: [Int] = [0, 15, 30, 60, 120]

    /// 每分钟 Token，0 表示关闭异常消耗提醒。
    static let tokenSpikeThresholdOptions: [Int64] = [0, 100_000, 500_000, 1_000_000, 2_000_000]

    /// 0 表示关闭重置卡到期提醒。
    static let resetCardExpiryAlertDayOptions: [Int] = [0, 1, 3, 7, 14]
}

enum NotificationIDs {
    static let rateLimitWarning = "rate-limit-warning"
    static let rateLimitExhausted = "rate-limit-exhausted"
    static let taskCompleted = "task-completed"
    static let taskFailed = "task-failed"
    static let awaitingAuth = "awaiting-auth"
    static let awaitingInput = "awaiting-input"
    static let rateLimitReset = "rate-limit-reset"
    static let longTask = "long-task"
    static let tokenSpike = "token-spike"
    static let resetCardExpiry = "reset-card-expiry"
}
