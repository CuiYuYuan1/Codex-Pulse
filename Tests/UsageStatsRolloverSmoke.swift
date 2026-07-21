import Foundation

@main
enum UsageStatsRolloverSmoke {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let formatter = UsageStats.dayFormatter(calendar: calendar)
        let previousDay = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 23, minute: 59)
        )!
        let newDay = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 21, hour: 0, minute: 0, second: 1)
        )!

        var usage = UsageStats.empty
        usage.todayTokens = 987_654
        usage.localTodayTokens = 987_654
        usage.tokenVelocityPerMinute = 42_000
        usage.updatedAt = previousDay
        usage.dailyBuckets = [
            DailyTokenBucket(dateString: formatter.string(from: previousDay), tokens: 987_654)
        ]

        usage.resetForNewDay(reference: newDay, calendar: calendar)

        precondition(usage.todayTokens == 0, "today must reset immediately at local midnight")
        precondition(usage.localTodayTokens == 0, "local today must reset with the headline")
        precondition(usage.yesterdayTokens == 987_654, "the previous day must move to yesterday")
        precondition(usage.tokenVelocityPerMinute == nil, "cross-day velocity must reset")
        precondition(usage.dailyBuckets.last?.dateString == "2026-07-21")
        precondition(usage.dailyBuckets.last?.tokens == 0)
        print("UsageStats rollover smoke: PASS")
    }
}
