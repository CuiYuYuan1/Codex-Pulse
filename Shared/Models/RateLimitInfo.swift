import Foundation

/// 单个额度窗口，对应 `account/rateLimits/read` 中的桶
struct RateLimitBucket: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// 官方 usedPercent：已使用 0…100
    var usedPercent: Double
    var windowDurationSeconds: TimeInterval?
    var resetsAt: Date?
    var isLimitReached: Bool
    var remainingCredits: Double?

    /// 剩余百分比（界面主展示）
    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    var resetCountdown: TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSinceNow)
    }

    /// 按剩余额度划分健康度（剩余多 = 健康）
    var statusLevel: UsageLevel {
        UsageLevel.fromRemaining(remainingPercent)
    }
}

/// 重置卡信息
struct RateLimitResetCard: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var acquiredAt: Date?
    var expiresAt: Date?
    var applicableLimitTypes: [String]
    var isAvailable: Bool
}

enum RateLimitForecastConfidence: String, Codable, Sendable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "初步"
        case .medium: return "中等"
        case .high: return "较高"
        }
    }
}

/// 基于同一重置周期的本地额度样本计算，不依赖远程分析服务。
struct RateLimitForecast: Codable, Equatable, Sendable {
    var bucketID: String
    var sampleCount: Int
    var observedDuration: TimeInterval
    var burnRatePercentPerHour: Double
    var estimatedExhaustionAt: Date?
    var projectedRemainingAtReset: Double?
    var willExhaustBeforeReset: Bool
    var confidence: RateLimitForecastConfidence
    var updatedAt: Date
}

/// 额度汇总
struct RateLimitSnapshot: Codable, Equatable, Sendable {
    var buckets: [RateLimitBucket]
    var resetCards: [RateLimitResetCard]
    var updatedAt: Date

    var primaryBucket: RateLimitBucket? {
        buckets.first
    }

    var secondaryBucket: RateLimitBucket? {
        buckets.count > 1 ? buckets[1] : nil
    }

    var availableResetCardCount: Int {
        resetCards.filter(\.isAvailable).count
    }

    var nextResetCardExpiration: Date? {
        resetCards
            .filter { $0.isAvailable && ($0.expiresAt ?? .distantPast) > Date() }
            .compactMap(\.expiresAt)
            .min()
    }

    static let empty = RateLimitSnapshot(buckets: [], resetCards: [], updatedAt: .distantPast)
}

/// Codex session JSONL 中 `token_count.rate_limits` 的本地实时解析器。
///
/// App Server RPC 使用 camelCase，而 session rollout 使用 snake_case。活跃任务的
/// rollout 通常比独立 App Server 的 `/wham/usage` 轮询更早落盘，因此这里直接把
/// 本地窗口映射成领域模型，避免为了一个百分比再次等待远端请求。
enum LocalRateLimitParser {
    static func parse(_ raw: [String: Any], observedAt: Date) -> RateLimitSnapshot? {
        let limitID = string(raw["limit_id"] ?? raw["limitId"]) ?? "codex"
        let limitName = string(raw["limit_name"] ?? raw["limitName"])
        let reached = raw["rate_limit_reached_type"] ?? raw["rateLimitReachedType"]
        let credits = raw["credits"] as? [String: Any]
        let remainingCredits = number(credits?["balance"])

        var buckets: [RateLimitBucket] = []
        if let primary = raw["primary"] as? [String: Any],
           let bucket = bucket(
               from: primary,
               limitID: limitID,
               role: "primary",
               fallbackName: limitName ?? "主额度窗口",
               limitReached: reached != nil,
               remainingCredits: remainingCredits
           ) {
            buckets.append(bucket)
        }
        if let secondary = raw["secondary"] as? [String: Any],
           let bucket = bucket(
               from: secondary,
               limitID: limitID,
               role: "secondary",
               fallbackName: limitName ?? "次级额度",
               limitReached: false,
               remainingCredits: remainingCredits
           ) {
            buckets.append(bucket)
        }

        guard !buckets.isEmpty else { return nil }
        var byID: [String: RateLimitBucket] = [:]
        for bucket in buckets {
            byID[bucket.id] = bucket
        }
        return RateLimitSnapshot(
            buckets: byID.values.sorted {
                let lhs = $0.windowDurationSeconds ?? .greatestFiniteMagnitude
                let rhs = $1.windowDurationSeconds ?? .greatestFiniteMagnitude
                if lhs != rhs { return lhs < rhs }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            },
            resetCards: [],
            updatedAt: observedAt
        )
    }

    private static func bucket(
        from raw: [String: Any],
        limitID: String,
        role: String,
        fallbackName: String,
        limitReached: Bool,
        remainingCredits: Double?
    ) -> RateLimitBucket? {
        guard let rawUsed = number(raw["used_percent"] ?? raw["usedPercent"]) else {
            return nil
        }
        let used = min(100, max(0, rawUsed))
        let durationMinutes = number(raw["window_minutes"] ?? raw["windowDurationMins"])
        let resetsAt = serverDate(raw["resets_at"] ?? raw["resetsAt"])
        let id = durationMinutes.map {
            "\(limitID)-\(Int($0.rounded()))m"
        } ?? "\(limitID)-\(role)"
        return RateLimitBucket(
            id: id,
            name: displayName(durationMinutes: durationMinutes, fallback: fallbackName),
            usedPercent: used,
            windowDurationSeconds: durationMinutes.map { $0 * 60 },
            resetsAt: resetsAt,
            isLimitReached: limitReached || used >= 100,
            remainingCredits: remainingCredits
        )
    }

    private static func displayName(durationMinutes: Double?, fallback: String) -> String {
        guard let minutes = durationMinutes, minutes > 0 else { return fallback }
        if abs(minutes - 300) <= 5 { return "5 小时用量" }
        if abs(minutes - 10_080) <= 5 { return "每周用量" }
        if minutes < 1_440 {
            return "\(max(1, Int((minutes / 60).rounded()))) 小时用量"
        }
        return "\(max(1, Int((minutes / 1_440).rounded()))) 日用量"
    }

    private static func serverDate(_ value: Any?) -> Date? {
        guard let raw = number(value) else { return nil }
        let seconds = raw > 10_000_000_000 ? raw / 1_000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}

struct LocalRateLimitMergeResult: Sendable {
    var merged: RateLimitSnapshot
    /// 仅包含本次确实被接受的本地桶，供慢速远端响应完成时做精确覆盖。
    var acceptedObservation: RateLimitSnapshot
}

/// 本地 session 额度与远端完整快照的纯函数合并规则。
///
/// - 本地事件只能更新远端已经确认过的同一桶，不能为刚切换的账号自行建桶；
/// - 同一重置周期内 usedPercent 只增不减；
/// - 更晚的 resetsAt 代表新周期，可以接受更低的 usedPercent；
/// - 更早的 resetsAt 视为历史/并发旧会话事件，不覆盖当前周期；
/// - resetCards 与远端补充字段始终保留。
enum RateLimitFreshness {
    private static let resetTolerance: TimeInterval = 2

    static func mergeLocal(
        current: RateLimitSnapshot,
        observation: RateLimitSnapshot
    ) -> LocalRateLimitMergeResult? {
        guard !current.buckets.isEmpty, !observation.buckets.isEmpty else { return nil }

        var mergedBuckets = current.buckets
        var acceptedBuckets: [RateLimitBucket] = []
        for incoming in observation.buckets {
            guard let index = matchingIndex(for: incoming, in: mergedBuckets) else {
                continue
            }
            let existing = mergedBuckets[index]
            guard shouldAcceptLocal(incoming, over: existing) else { continue }
            mergedBuckets[index] = mergedBucket(existing: existing, incoming: incoming)
            acceptedBuckets.append(incoming)
        }

        guard !acceptedBuckets.isEmpty else { return nil }
        let merged = RateLimitSnapshot(
            buckets: mergedBuckets,
            resetCards: current.resetCards,
            updatedAt: max(current.updatedAt, observation.updatedAt)
        )
        let accepted = RateLimitSnapshot(
            buckets: acceptedBuckets,
            resetCards: [],
            updatedAt: observation.updatedAt
        )
        return LocalRateLimitMergeResult(merged: merged, acceptedObservation: accepted)
    }

    private static func matchingIndex(
        for incoming: RateLimitBucket,
        in existing: [RateLimitBucket]
    ) -> Int? {
        if let index = existing.firstIndex(where: { $0.id == incoming.id }) {
            return index
        }
        if let incomingDuration = incoming.windowDurationSeconds,
           let index = existing.firstIndex(where: {
               guard let duration = $0.windowDurationSeconds else { return false }
               return abs(duration - incomingDuration) < 60
           }) {
            return index
        }
        return existing.firstIndex(where: { $0.name == incoming.name })
    }

    private static func shouldAcceptLocal(
        _ incoming: RateLimitBucket,
        over existing: RateLimitBucket
    ) -> Bool {
        if let incomingReset = incoming.resetsAt, let existingReset = existing.resetsAt {
            let delta = incomingReset.timeIntervalSince(existingReset)
            if delta < -resetTolerance { return false }
            if delta > resetTolerance { return true }
        }
        return incoming.usedPercent + 0.001 >= existing.usedPercent
    }

    private static func mergedBucket(
        existing: RateLimitBucket,
        incoming: RateLimitBucket
    ) -> RateLimitBucket {
        RateLimitBucket(
            id: existing.id,
            name: existing.name,
            usedPercent: incoming.usedPercent,
            windowDurationSeconds: incoming.windowDurationSeconds
                ?? existing.windowDurationSeconds,
            resetsAt: incoming.resetsAt ?? existing.resetsAt,
            isLimitReached: incoming.isLimitReached || incoming.usedPercent >= 100,
            // 本地 token_count 的 credits 属于整个快照，不能安全映射到某个桶。
            // 桶级补充字段继续以远端完整快照为准。
            remainingCredits: existing.remainingCredits
        )
    }
}

/// 额度健康度（基于剩余百分比）
enum UsageLevel: String, Sendable {
    case healthy   // 剩余充足
    case caution   // 开始偏低
    case warning   // 紧张
    case critical  // 极少
    case exhausted // 耗尽

    /// remainingPercent: 0…100（剩余）
    /// 产品规则：80–100 绿 · 20–80 橙 · 1–20 红 · 0 耗尽
    static func fromRemaining(_ remaining: Double) -> UsageLevel {
        switch remaining {
        case 80...: return .healthy       // 剩 ≥80% 绿
        case 20..<80: return .warning     // 剩 20–80% 橙
        case 1..<20: return .critical     // 剩 1–20% 红
        case 0.001..<1: return .critical  // 剩 <1% 红
        default: return .exhausted        // 0 红
        }
    }

    /// 兼容旧调用：传入已使用百分比
    static func from(percent used: Double) -> UsageLevel {
        fromRemaining(max(0, min(100, 100 - used)))
    }
}
