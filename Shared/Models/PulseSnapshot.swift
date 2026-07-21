import Foundation

/// 应用全局状态快照，主 App 与 Widget 共享
struct PulseSnapshot: Codable, Equatable, Sendable {
    var account: AccountInfo
    var rateLimits: RateLimitSnapshot
    /// 主额度桶的本地消耗预测。可选字段保证旧版共享快照可继续解码。
    var primaryRateLimitForecast: RateLimitForecast? = nil
    var usage: UsageStats
    var currentTask: CurrentTaskInfo
    var recentTasks: [TaskRecord]
    var connectionState: ConnectionState
    var updatedAt: Date

    enum ConnectionState: String, Codable, Sendable {
        case disconnected
        case connecting
        case connected
        case degraded
        case error

        var displayName: String {
            switch self {
            case .disconnected: return "未连接"
            case .connecting: return "连接中"
            case .connected: return "已连接"
            case .degraded: return "部分异常"
            case .error: return "连接错误"
            }
        }
    }

    var statusColor: PulseStatusColor {
        if connectionState == .disconnected || connectionState == .connecting
            || connectionState == .error || !account.isLoggedIn {
            return .gray
        }
        if currentTask.state == .failed || currentTask.state == .networkError {
            return .red
        }
        if let primary = rateLimits.primaryBucket, primary.isLimitReached || primary.remainingPercent <= 0 {
            return .red
        }
        if currentTask.state.needsAttention {
            return .yellow
        }
        if connectionState == .degraded {
            return .yellow
        }
        // 紧急额度优先于运行状态；普通额度提醒不能盖掉“正在运行”的蓝色。
        if let primary = rateLimits.primaryBucket, primary.remainingPercent < 20 {
            return .red
        }
        if currentTask.state.isActive {
            return .blue
        }
        if let primary = rateLimits.primaryBucket, primary.remainingPercent < 80 {
            return .yellow
        }
        return .green
    }

    var activeTaskCount: Int {
        var ids = Set(recentTasks.compactMap { task -> String? in
            guard task.runState?.isActive == true
                    || task.runState == .awaitingAuthorization
                    || task.runState == .awaitingInput else {
                return nil
            }
            return task.id
        })
        if currentTask.state.isActive
            || currentTask.state == .awaitingAuthorization
            || currentTask.state == .awaitingInput {
            ids.insert(currentTask.id)
        }
        return ids.count
    }

    var taskStatusLabel: String {
        activeTaskCount > 1 ? "\(activeTaskCount) 个任务处理中" : currentTask.state.rawValue
    }

    func isStale(reference: Date = Date(), threshold: TimeInterval = 30 * 60) -> Bool {
        guard updatedAt != .distantPast else { return true }
        return reference.timeIntervalSince(updatedAt) > threshold
    }

    /// 忽略所有 `updatedAt` 时间戳的内容比较。轮询每次都会刷新顶层及
    /// 各子模型（额度、用量、预测）的时间戳，但实质内容常常没变。用它
    /// 判断“内容是否真的变化”，从而跳过无谓的写盘与 Widget 重载。
    func hasSameContent(as other: PulseSnapshot) -> Bool {
        Self.normalizedForComparison(self) == Self.normalizedForComparison(other)
    }

    private static func normalizedForComparison(_ snapshot: PulseSnapshot) -> PulseSnapshot {
        var copy = snapshot
        copy.updatedAt = .distantPast
        copy.rateLimits.updatedAt = .distantPast
        copy.usage.updatedAt = .distantPast
        copy.primaryRateLimitForecast?.updatedAt = .distantPast
        return copy
    }

    static let empty = PulseSnapshot(
        account: .empty,
        rateLimits: .empty,
        usage: .empty,
        currentTask: .empty,
        recentTasks: [],
        connectionState: .disconnected,
        updatedAt: .distantPast
    )
}
