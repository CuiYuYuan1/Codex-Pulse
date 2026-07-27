import Foundation

/// Token-driven pet growth shared by every macOS companion.
///
/// Growth is additive in 10 percentage-point steps:
/// - One step for each complete 10M tokens used today.
/// - 900M tokens reaches the 10x cap.
/// - A new day reports zero today-tokens, which deterministically restores 1x.
enum PetGrowth {
    static let baseInterval: Int64 = 10_000_000
    static let maximumScale = 10.0

    static func scale(forTodayTokens rawTokens: Int64?) -> Double {
        let tokens = max(0, rawTokens ?? 0)
        let growthSteps = tokens / baseInterval
        return min(maximumScale, 1.0 + Double(growthSteps) * 0.1)
    }
}
