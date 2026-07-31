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
    /// 本机所有 Codex session JSONL 的当日累计值。session 日志不含账号 ID，
    /// 因此“今日 Token”始终采用设备口径，包含今天在本机使用过的所有账号。
    var localTodayTokens: Int64? = nil
    /// 本机全部 session 最近 7 个自然日的增量桶。
    var localDailyBuckets: [DailyTokenBucket]? = nil
    /// 本机全部 session 的历史累计 Token，跨账号且不随登录账号切换清空。
    var localTotalTokens: Int64? = nil
    /// 本机全部 session 按自然日计算的当前/历史最长连续活跃天数。
    /// 与账号额度解耦，切换账号时仍保持设备级统计。
    var localCurrentStreakDays: Int? = nil
    var localLongestStreakDays: Int? = nil
    /// 经过平滑的本机 Token 消耗速度。
    var tokenVelocityPerMinute: Int64? = nil
    /// 今日设备级 Token 构成。`input` 已包含 `cachedInput`，与 Codex
    /// session JSONL 的 `last_token_usage` 字段保持一致。
    var localTodayInputTokens: Int64? = nil
    var localTodayCachedInputTokens: Int64? = nil
    var localTodayOutputTokens: Int64? = nil
    /// 按 session 记录的模型和公开 API 单价换算，仅用于成本感知，不代表
    /// ChatGPT 套餐账单。
    var localTodayEstimatedCostUSD: Double? = nil
    var localTodayUncachedInputCostUSD: Double? = nil
    var localTodayCachedInputCostUSD: Double? = nil
    var localTodayOutputCostUSD: Double? = nil
    /// 本机全部 session 按事件模型与公开 API 单价换算的历史累计成本。
    /// 仅用于成本感知，不代表 ChatGPT 套餐账单。
    var localTotalEstimatedCostUSD: Double? = nil

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
            || localTodayTokens != nil
            || localTotalTokens != nil
            || localDailyBuckets?.contains(where: { $0.tokens > 0 }) == true
    }

    var localTodayCacheHitRate: Double? {
        guard let input = localTodayInputTokens, input > 0,
              let cached = localTodayCachedInputTokens else {
            return nil
        }
        return min(1, max(0, Double(cached) / Double(input)))
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
        localTodayInputTokens = 0
        localTodayCachedInputTokens = 0
        localTodayOutputTokens = 0
        localTodayEstimatedCostUSD = 0
        localTodayUncachedInputCostUSD = 0
        localTodayCachedInputCostUSD = 0
        localTodayOutputCostUSD = 0
        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)
        if localDailyBuckets != nil {
            localDailyBuckets = dailyBuckets
        }
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

    /// 记录本机日志累计。提升后设备值是界面“今日 Token”的唯一口径，
    /// 不与当前账号的远端摘要取较大值。
    mutating func mergeLocalTodayTokens(
        _ localTokens: Int64,
        promoteToDisplayedUsage: Bool = false,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard localTokens >= 0 else { return }
        // 完整 session 重扫是设备口径的权威值，必须允许纠正旧版本曾经高估的
        // 持久化快照；实时事件在 Store 中单独增量合并，不依赖这里取 max。
        let resolvedLocalTokens = localTokens
        localTodayTokens = resolvedLocalTokens
        guard promoteToDisplayedUsage else { return }

        let formatter = Self.dayFormatter(calendar: calendar)
        let todayKey = formatter.string(from: reference)
        todayTokens = resolvedLocalTokens

        if let index = dailyBuckets.firstIndex(where: {
            Self.normalizeDay($0.dateString) == todayKey
        }) {
            dailyBuckets[index].dateString = todayKey
            dailyBuckets[index].tokens = resolvedLocalTokens
        } else {
            dailyBuckets.append(DailyTokenBucket(dateString: todayKey, tokens: resolvedLocalTokens))
        }

        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)
        if localDailyBuckets != nil {
            localDailyBuckets = dailyBuckets
        }
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: reference)
            .map { formatter.string(from: $0) }
        if let yesterdayKey {
            yesterdayTokens = dailyBuckets.first(where: { $0.dateString == yesterdayKey })?.tokens
        }
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        peakDailyTokens = dailyBuckets.map(\.tokens).max()
        updatedAt = reference
        sourceNote = "Token 来自本机全部 Codex session，包含本机使用过的所有账号"
    }

    mutating func mergeLocalTodayBreakdown(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        estimatedCostUSD: Double?,
        uncachedInputCostUSD: Double?,
        cachedInputCostUSD: Double?,
        outputCostUSD: Double?
    ) {
        localTodayInputTokens = max(0, inputTokens)
        localTodayCachedInputTokens = min(
            max(0, cachedInputTokens),
            max(0, inputTokens)
        )
        localTodayOutputTokens = max(0, outputTokens)
        localTodayEstimatedCostUSD = estimatedCostUSD.map { max(0, $0) }
        localTodayUncachedInputCostUSD = uncachedInputCostUSD.map { max(0, $0) }
        localTodayCachedInputCostUSD = cachedInputCostUSD.map { max(0, $0) }
        localTodayOutputCostUSD = outputCostUSD.map { max(0, $0) }
    }

    mutating func mergeLocalDailyBuckets(
        _ localBuckets: [DailyTokenBucket],
        promoteToDisplayedUsage: Bool = false,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        var byDay: [String: Int64] = [:]
        for bucket in localBuckets {
            let day = Self.normalizeDay(bucket.dateString)
            let value = max(0, bucket.tokens)
            let current = byDay[day] ?? 0
            let (next, overflow) = current.addingReportingOverflow(value)
            byDay[day] = overflow ? Int64.max : next
        }
        let previousDisplayedBuckets = dailyBuckets
        dailyBuckets = byDay.map { DailyTokenBucket(dateString: $0.key, tokens: $0.value) }
        let filledLocal = filledLast7Days(reference: reference, calendar: calendar)
        localDailyBuckets = filledLocal
        guard promoteToDisplayedUsage else {
            dailyBuckets = previousDisplayedBuckets
            return
        }
        dailyBuckets = filledLocal

        let formatter = Self.dayFormatter(calendar: calendar)
        let todayKey = formatter.string(from: reference)
        if let localToday = dailyBuckets.first(where: { $0.dateString == todayKey })?.tokens {
            todayTokens = localToday
        }
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: reference)
            .map { formatter.string(from: $0) }
        if let yesterdayKey {
            yesterdayTokens = dailyBuckets.first(where: { $0.dateString == yesterdayKey })?.tokens
        }
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        peakDailyTokens = dailyBuckets.map(\.tokens).max()
        updatedAt = reference
        sourceNote = "Token 来自本机全部 Codex session，包含本机使用过的所有账号"
    }

    mutating func mergeLocalTotalTokens(
        _ localTokens: Int64,
        estimatedCostUSD: Double? = nil,
        promoteToDisplayedUsage: Bool = false,
        reference: Date = Date()
    ) {
        guard localTokens >= 0 else { return }
        // 历史文件被清理或聚合算法修正后累计值也可能合法下降。
        let resolvedLocalTokens = localTokens
        localTotalTokens = resolvedLocalTokens
        if let estimatedCostUSD {
            localTotalEstimatedCostUSD = max(0, estimatedCostUSD)
        }
        guard promoteToDisplayedUsage else { return }
        totalTokens = resolvedLocalTokens
        updatedAt = reference
        sourceNote = "Token 来自本机全部 Codex session，包含本机使用过的所有账号"
    }

    mutating func mergeLocalStreak(
        currentDays: Int,
        longestDays: Int,
        promoteToDisplayedUsage: Bool = false,
        reference: Date = Date()
    ) {
        let current = max(0, currentDays)
        let longest = max(current, longestDays)
        localCurrentStreakDays = current
        localLongestStreakDays = longest
        guard promoteToDisplayedUsage else { return }
        currentStreakDays = current
        longestStreakDays = longest
        updatedAt = reference
        sourceNote = "连续天数来自本机全部 Codex session，包含本机使用过的所有账号"
    }

    /// 本次只拿到本机今日数据或官方接口返回不完整时，保留同一账号上一份完整汇总。
    /// 今日值仍以最新结果为准；日桶按日期取较大值，避免接口抖动把历史刷成 0。
    mutating func preserveMissingSummary(
        from cached: UsageStats,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        totalTokens = totalTokens ?? cached.totalTokens
        localTotalTokens = localTotalTokens ?? cached.localTotalTokens
        localTodayTokens = localTodayTokens ?? cached.localTodayTokens
        localDailyBuckets = localDailyBuckets ?? cached.localDailyBuckets
        localCurrentStreakDays = localCurrentStreakDays ?? cached.localCurrentStreakDays
        localLongestStreakDays = localLongestStreakDays ?? cached.localLongestStreakDays
        localTodayInputTokens = localTodayInputTokens ?? cached.localTodayInputTokens
        localTodayCachedInputTokens =
            localTodayCachedInputTokens ?? cached.localTodayCachedInputTokens
        localTodayOutputTokens = localTodayOutputTokens ?? cached.localTodayOutputTokens
        localTodayEstimatedCostUSD =
            localTodayEstimatedCostUSD ?? cached.localTodayEstimatedCostUSD
        localTodayUncachedInputCostUSD =
            localTodayUncachedInputCostUSD ?? cached.localTodayUncachedInputCostUSD
        localTodayCachedInputCostUSD =
            localTodayCachedInputCostUSD ?? cached.localTodayCachedInputCostUSD
        localTodayOutputCostUSD =
            localTodayOutputCostUSD ?? cached.localTodayOutputCostUSD
        localTotalEstimatedCostUSD =
            localTotalEstimatedCostUSD ?? cached.localTotalEstimatedCostUSD
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

        // 远端账号摘要仅用于补齐非 Token 元数据；一旦存在本机值，重新提升本机
        // 口径，避免账号切换或慢响应把设备汇总覆盖回单账号数据。
        if let localBuckets = localDailyBuckets {
            mergeLocalDailyBuckets(
                localBuckets,
                promoteToDisplayedUsage: true,
                reference: reference,
                calendar: calendar
            )
        }
        if let localTodayTokens {
            mergeLocalTodayTokens(
                localTodayTokens,
                promoteToDisplayedUsage: true,
                reference: reference,
                calendar: calendar
            )
        }
        if let localTotalTokens {
            mergeLocalTotalTokens(
                localTotalTokens,
                promoteToDisplayedUsage: true,
                reference: reference
            )
        }
        if let localCurrentStreakDays {
            mergeLocalStreak(
                currentDays: localCurrentStreakDays,
                longestDays: localLongestStreakDays ?? localCurrentStreakDays,
                promoteToDisplayedUsage: true,
                reference: reference
            )
        }
    }

    /// 清理旧版本留下的混合口径缓存。本机今日与本机累计都存在时，两者天然属于
    /// 同一设备口径；只有完全没有本机来源时才沿用旧的账号摘要校验。
    mutating func discardImpossibleTodayUsage(
        reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        if let localTotalTokens {
            totalTokens = localTotalTokens
        }
        if let localTodayTokens {
            todayTokens = localTodayTokens
        }
        if localTotalTokens != nil { return }
        if localTodayTokens != nil {
            if let todayTokens, let totalTokens, todayTokens > totalTokens {
                self.totalTokens = nil
            }
            return
        }
        guard let todayTokens, let totalTokens, todayTokens > totalTokens else { return }
        let todayKey = Self.dayFormatter(calendar: calendar).string(from: reference)
        self.todayTokens = nil
        dailyBuckets.removeAll { Self.normalizeDay($0.dateString) == todayKey }
        dailyBuckets = filledLast7Days(reference: reference, calendar: calendar)
        last7DaysTokens = dailyBuckets.reduce(0) { $0 + $1.tokens }
        tokenVelocityPerMinute = nil
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

struct LocalUsageStreakSummary: Equatable, Sendable {
    var currentDays: Int
    var longestDays: Int

    static func calculate(
        activeDayKeys: Set<String>,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> LocalUsageStreakSummary {
        let formatter = UsageStats.dayFormatter(calendar: calendar)
        let normalizedDays = Set(activeDayKeys.map(UsageStats.normalizeDay))
        let activeDates = normalizedDays.compactMap(formatter.date(from:)).sorted()
        guard !activeDates.isEmpty else {
            return LocalUsageStreakSummary(currentDays: 0, longestDays: 0)
        }

        var longest = 1
        var run = 1
        for index in activeDates.indices.dropFirst() {
            let previous = activeDates[activeDates.index(before: index)]
            let current = activeDates[index]
            if calendar.dateComponents([.day], from: previous, to: current).day == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        let today = calendar.startOfDay(for: reference)
        let todayKey = formatter.string(from: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let anchor: Date?
        if normalizedDays.contains(todayKey) {
            anchor = today
        } else if let yesterday,
                  normalizedDays.contains(formatter.string(from: yesterday)) {
            // 零点后尚未开始工作时保留截至昨天的连续记录。
            anchor = yesterday
        } else {
            anchor = nil
        }

        var currentDays = 0
        var cursor = anchor
        while let day = cursor,
              normalizedDays.contains(formatter.string(from: day)) {
            currentDays += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        return LocalUsageStreakSummary(currentDays: currentDays, longestDays: longest)
    }
}

struct DailyTokenBucket: Codable, Identifiable, Equatable, Sendable {
    var id: String { dateString }
    var dateString: String // yyyy-MM-dd
    var tokens: Int64
}
