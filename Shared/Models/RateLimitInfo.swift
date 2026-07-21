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
