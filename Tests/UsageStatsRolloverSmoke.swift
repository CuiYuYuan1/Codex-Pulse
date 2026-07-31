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
        usage.totalTokens = 8_765_432
        usage.localTotalTokens = 8_765_432
        usage.localTotalEstimatedCostUSD = 286.42
        usage.tokenVelocityPerMinute = 42_000
        usage.updatedAt = previousDay
        usage.dailyBuckets = [
            DailyTokenBucket(dateString: formatter.string(from: previousDay), tokens: 987_654)
        ]

        usage.resetForNewDay(reference: newDay, calendar: calendar)

        precondition(usage.todayTokens == 0, "today must reset immediately at local midnight")
        precondition(usage.localTodayTokens == 0, "local today must reset with the headline")
        precondition(usage.localTotalTokens == 8_765_432, "device lifetime total must survive midnight")
        precondition(usage.totalTokens == 8_765_432, "displayed lifetime total must survive midnight")
        precondition(
            usage.localTotalEstimatedCostUSD == 286.42,
            "lifetime estimated cost must survive midnight"
        )
        precondition(usage.yesterdayTokens == 987_654, "the previous day must move to yesterday")
        precondition(usage.tokenVelocityPerMinute == nil, "cross-day velocity must reset")
        precondition(usage.dailyBuckets.last?.dateString == "2026-07-21")
        precondition(usage.dailyBuckets.last?.tokens == 0)

        var corrupted = UsageStats.empty
        corrupted.todayTokens = 1_160_000_000
        corrupted.totalTokens = 413_000_000
        corrupted.localTodayTokens = 1_160_000_000
        corrupted.localTotalTokens = 2_413_000_000
        corrupted.dailyBuckets = [
            DailyTokenBucket(dateString: formatter.string(from: newDay), tokens: 1_160_000_000)
        ]
        corrupted.discardImpossibleTodayUsage(reference: newDay, calendar: calendar)
        precondition(corrupted.todayTokens == 1_160_000_000, "device today must remain authoritative")
        precondition(corrupted.totalTokens == 2_413_000_000, "device lifetime total must replace account summary")
        precondition(corrupted.localTodayTokens == 1_160_000_000)
        precondition(corrupted.localTotalTokens == 2_413_000_000)

        var inflatedSnapshot = UsageStats.empty
        inflatedSnapshot.todayTokens = 2_400_000_000
        inflatedSnapshot.localTodayTokens = 2_400_000_000
        inflatedSnapshot.totalTokens = 24_000_000_000
        inflatedSnapshot.localTotalTokens = 24_000_000_000
        inflatedSnapshot.mergeLocalTodayTokens(
            210_000_000,
            promoteToDisplayedUsage: true,
            reference: newDay,
            calendar: calendar
        )
        inflatedSnapshot.mergeLocalTotalTokens(
            7_500_000_000,
            estimatedCostUSD: 731.25,
            promoteToDisplayedUsage: true,
            reference: newDay
        )
        precondition(
            inflatedSnapshot.todayTokens == 210_000_000,
            "authoritative local rescan must correct an inflated persisted today value"
        )
        precondition(
            inflatedSnapshot.totalTokens == 7_500_000_000,
            "authoritative local rescan must correct an inflated persisted lifetime value"
        )
        precondition(inflatedSnapshot.localTotalEstimatedCostUSD == 731.25)

        let streak = LocalUsageStreakSummary.calculate(
            activeDayKeys: Set([
                "2026-07-10",
                "2026-07-11",
                "2026-07-12",
                "2026-07-13",
                "2026-07-14",
                "2026-07-15",
                "2026-07-16",
                "2026-07-19",
                "2026-07-20"
            ]),
            reference: calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 21, hour: 0, minute: 1)
            )!,
            calendar: calendar
        )
        precondition(streak.currentDays == 2, "midnight grace must retain the streak through yesterday")
        precondition(streak.longestDays == 7, "longest streak must use all local session days")

        var localStreakUsage = UsageStats.empty
        localStreakUsage.mergeLocalStreak(
            currentDays: streak.currentDays,
            longestDays: streak.longestDays,
            promoteToDisplayedUsage: true,
            reference: newDay
        )
        precondition(localStreakUsage.currentStreakDays == 2)
        precondition(localStreakUsage.longestStreakDays == 7)
        precondition(localStreakUsage.localCurrentStreakDays == 2)
        print("UsageStats rollover smoke: PASS")
    }
}
