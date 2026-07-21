import Foundation

/// Token 使用统计，对应 `account/usage/read`
struct UsageStats: Codable, Equatable, Sendable {
    var totalTokens: Int64?
    var todayTokens: Int64?
    var yesterdayTokens: Int64?
    var last7DaysTokens: Int64?
    var last30DaysTokens: Int64?
    var peakDailyTokens: Int64?
    var currentStreakDays: Int?
    var longestStreakDays: Int?
    var longestTaskDurationSeconds: TimeInterval?
    var dailyBuckets: [DailyTokenBucket]
    var updatedAt: Date
    /// 接口说明：为何为空 / 是否仅 ChatGPT 认证可用
    var sourceNote: String?
    /// 本机所有 Codex session JSONL 的当日累计值，用于实时速度、切换账号后的
    /// 即时补偿，以及 API Key 模式下官方汇总不可用时的今日用量估算。
    /// 本机日志不含账号 ID；因此今日标题始终明确采用设备汇总口径，账号切换后
    /// 也会立即重新读取，不把它描述成单一账号的官方账单。
    var localTodayTokens: Int64? = nil
    /// 本机全部 session 最近 7 个自然日的增量桶。日志没有账号 ID，
    /// 因此只有 API Key 模式会把它提升为界面历史；ChatGPT 仅保留官方日桶。
    var localDailyBuckets: [DailyTokenBucket]? = nil
    /// 经过平滑的本机 Token 消耗速度。
    var tokenVelocityPerMinute: Int64? = nil

    static let empty = UsageStats(
        totalTokens: nil,
        todayTokens: nil,
        yesterdayTokens: nil,
        last7DaysTokens: nil,
        last30DaysTokens: nil,
        peakDailyTokens: nil,
        currentStreakDays: nil,
        longestStreakDays: nil,
        longestTaskDurationSeconds: nil,
        dailyBuckets: [],
        updatedAt: .distantPast,
        sourceNote: nil
    )

    var hasAnyTokenMetric: Bool {
        totalTokens != nil
            || todayTokens != nil
            || yesterdayTokens != nil
            || last7DaysTokens != nil
            || last30DaysTokens != nil
            || dailyBuckets.contains(where: { $0.tokens > 0 })
    }

    /// 切换到新的本地自然日。历史桶顺移，但“今日”必须立即从 0 开始，
    /// 不能等待网络轮询，也不能保留上一日的本机累计值。
    mutating func resetForNewDay(
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        yesterdayTokens = todayTokens ?? yesterdayTokens
        todayTokens = 0
        localTodayTokens = 0
        tokenVelocityPerMinute = nil
        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)
        updatedAt = reference
    }

    /// 近 7 天每日一条，缺失补 0，按日期升序（图表用）
    func filledLast7Days(reference: Date = Date(), calendar: Calendar = .current) -> [DailyTokenBucket] {
        let formatter = Self.dayFormatter(calendar: calendar)
        var map: [String: Int64] = [:]
        for b in dailyBuckets {
            let key = Self.normalizeDay(b.dateString)
            map[key, default: 0] += b.tokens
        }
        var result: [DailyTokenBucket] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: reference) else { continue }
            let key = formatter.string(from: day)
            result.append(DailyTokenBucket(dateString: key, tokens: map[key] ?? 0))
        }
        return result
    }

    /// 从日桶补全今日/昨日/近7天等字段
    mutating func recomputeAggregatesIfNeeded(calendar: Calendar = .current) {
        let filled = filledLast7Days(calendar: calendar)
        if !dailyBuckets.isEmpty {
            dailyBuckets = filled
        }

        let formatter = Self.dayFormatter(calendar: calendar)
        let todayKey = formatter.string(from: Date())
        let yKey = calendar.date(byAdding: .day, value: -1, to: Date()).map { formatter.string(from: $0) }

        if todayTokens == nil, let t = filled.first(where: { $0.dateString == todayKey })?.tokens {
            todayTokens = t
        }
        if yesterdayTokens == nil, let y = yKey, let t = filled.first(where: { $0.dateString == y })?.tokens {
            yesterdayTokens = t
        }
        if last7DaysTokens == nil, !dailyBuckets.isEmpty || filled.contains(where: { $0.tokens > 0 }) {
            last7DaysTokens = filled.reduce(0) { $0 + $1.tokens }
        }
        if peakDailyTokens == nil, !dailyBuckets.isEmpty {
            peakDailyTokens = filled.map(\.tokens).max()
        }
    }

    /// 将实时事件提供的“今日累计量”合入汇总。
    /// 事件值按线程去重后由 Store 累加，因此这里仍取较大值，避免乱序事件回退。
    mutating func mergeEventTodayTokens(
        _ eventTodayTokens: Int64,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard eventTodayTokens > 0 else { return }
        let resolvedToday = max(todayTokens ?? 0, eventTodayTokens)
        todayTokens = resolvedToday

        let todayKey = Self.dayFormatter(calendar: calendar).string(from: reference)
        if let index = dailyBuckets.firstIndex(where: {
            Self.normalizeDay($0.dateString) == todayKey
        }) {
            dailyBuckets[index].dateString = todayKey
            dailyBuckets[index].tokens = max(dailyBuckets[index].tokens, resolvedToday)
        } else {
            dailyBuckets.append(DailyTokenBucket(dateString: todayKey, tokens: resolvedToday))
        }
        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        peakDailyTokens = max(peakDailyTokens ?? 0, dailyBuckets.map(\.tokens).max() ?? 0)
        updatedAt = reference
        sourceNote = "今日数据包含 App Server 实时 Token 事件"
    }

    /// 记录本机日志累计；ChatGPT 账号切换时由调用方禁止提升，API Key 模式
    /// 则将当日全部本地 session 用量作为今日估算。
    mutating func mergeLocalTodayTokens(
        _ localTokens: Int64,
        promoteToAccountTotals: Bool = false,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard localTokens > 0 else { return }
        localTodayTokens = localTokens
        guard promoteToAccountTotals else { return }

        let formatter = Self.dayFormatter(calendar: calendar)
        let todayKey = formatter.string(from: reference)
        let resolvedToday = max(todayTokens ?? 0, localTokens)
        todayTokens = resolvedToday

        if let index = dailyBuckets.firstIndex(where: {
            Self.normalizeDay($0.dateString) == todayKey
        }) {
            dailyBuckets[index].dateString = todayKey
            dailyBuckets[index].tokens = max(dailyBuckets[index].tokens, resolvedToday)
        } else {
            dailyBuckets.append(DailyTokenBucket(dateString: todayKey, tokens: resolvedToday))
        }

        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        peakDailyTokens = max(peakDailyTokens ?? 0, dailyBuckets.map(\.tokens).max() ?? 0)
        updatedAt = reference
    }

    mutating func mergeLocalDailyBuckets(
        _ localBuckets: [DailyTokenBucket],
        promoteToAccountTotals: Bool = false,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        localDailyBuckets = localBuckets
        guard promoteToAccountTotals else { return }

        var byDay: [String: Int64] = [:]
        for bucket in dailyBuckets + localBuckets {
            let day = Self.normalizeDay(bucket.dateString)
            byDay[day] = max(byDay[day] ?? 0, max(0, bucket.tokens))
        }
        dailyBuckets = byDay.map { DailyTokenBucket(dateString: $0.key, tokens: $0.value) }
        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)

        let todayKey = Self.dayFormatter(calendar: calendar).string(from: reference)
        if let localToday = dailyBuckets.first(where: { $0.dateString == todayKey })?.tokens {
            todayTokens = max(todayTokens ?? 0, localToday)
        }
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        peakDailyTokens = max(peakDailyTokens ?? 0, dailyBuckets.map(\.tokens).max() ?? 0)
        updatedAt = reference
        sourceNote = "API Key 用量来自本机全部 session 汇总；不代表 OpenAI 账单"
    }

    /// 本次只拿到本机今日数据或官方接口返回不完整时，保留同一账号上一份完整汇总。
    /// 今日值仍以最新结果为准；日桶按日期取较大值，避免接口抖动把历史刷成 0。
    mutating func preserveMissingSummary(
        from cached: UsageStats,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        totalTokens = totalTokens ?? cached.totalTokens
        yesterdayTokens = yesterdayTokens ?? cached.yesterdayTokens
        last30DaysTokens = last30DaysTokens ?? cached.last30DaysTokens
        currentStreakDays = currentStreakDays ?? cached.currentStreakDays
        longestStreakDays = longestStreakDays ?? cached.longestStreakDays
        longestTaskDurationSeconds = longestTaskDurationSeconds ?? cached.longestTaskDurationSeconds

        var byDay: [String: Int64] = [:]
        for bucket in cached.dailyBuckets + dailyBuckets {
            let day = Self.normalizeDay(bucket.dateString)
            byDay[day] = max(byDay[day] ?? 0, bucket.tokens)
        }
        dailyBuckets = byDay.map { DailyTokenBucket(dateString: $0.key, tokens: $0.value) }
        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)

        let formatter = Self.dayFormatter(calendar: calendar)
        let todayKey = formatter.string(from: reference)
        if let bucketToday = dailyBuckets.first(where: { $0.dateString == todayKey })?.tokens {
            todayTokens = max(todayTokens ?? 0, bucketToday)
        }
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        peakDailyTokens = max(
            max(peakDailyTokens ?? 0, cached.peakDailyTokens ?? 0),
            dailyBuckets.map(\.tokens).max() ?? 0
        )
    }

    static func dayFormatter(calendar: Calendar = .current) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// `2026-07-15` / `2026-07-15T00:00:00Z` → `yyyy-MM-dd`
    static func normalizeDay(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 10 {
            let prefix = String(s.prefix(10))
            if prefix.contains("-") { return prefix }
        }
        return s
    }
}

struct DailyTokenBucket: Codable, Identifiable, Equatable, Sendable {
    var id: String { dateString }
    var dateString: String // yyyy-MM-dd
    var tokens: Int64
}
