import Foundation

enum PulseSyncService: String, CaseIterable, Identifiable, Hashable, Sendable {
    case account
    case rateLimits
    case usage
    case threads

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .account: return "账号"
        case .rateLimits: return "额度"
        case .usage: return "Token"
        case .threads: return "任务"
        }
    }
}

enum PulseSyncHealthLevel: Int, Comparable, Sendable {
    case unknown = 0
    case healthy = 1
    case delayed = 2
    case unavailable = 3

    static func < (lhs: PulseSyncHealthLevel, rhs: PulseSyncHealthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PulseEndpointSyncHealth: Equatable, Sendable {
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var consecutiveFailures: Int
    var lastError: String?

    static let empty = PulseEndpointSyncHealth(
        lastSuccessAt: nil,
        lastFailureAt: nil,
        consecutiveFailures: 0,
        lastError: nil
    )

    var level: PulseSyncHealthLevel {
        if consecutiveFailures >= 3 { return .unavailable }
        if consecutiveFailures > 0 { return .delayed }
        return lastSuccessAt == nil ? .unknown : .healthy
    }

    mutating func recordSuccess(at date: Date = Date()) {
        lastSuccessAt = date
        consecutiveFailures = 0
        lastError = nil
    }

    mutating func recordFailure(_ message: String, at date: Date = Date()) {
        lastFailureAt = date
        consecutiveFailures = min(999, consecutiveFailures + 1)
        lastError = message
    }
}
