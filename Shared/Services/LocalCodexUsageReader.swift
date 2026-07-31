import Foundation

/// `URL.resourceValues` 可能复用目录枚举时缓存的 size/mtime，不适合高频判断追加写入。
/// 每次通过 FileManager 重新读取文件系统属性，确保看到 Codex 刚写入的数据。
private struct FreshLocalFileMetadata {
    var isRegularFile: Bool
    var isDirectory: Bool
    var size: Int
    var modifiedAt: Date
}

private func freshLocalFileMetadata(at url: URL) -> FreshLocalFileMetadata? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
    let type = attributes[.type] as? FileAttributeType
    return FreshLocalFileMetadata(
        isRegularFile: type == .typeRegular,
        isDirectory: type == .typeDirectory,
        size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
        modifiedAt: (attributes[.modificationDate] as? Date) ?? .distantPast
    )
}

struct LocalCodexUsageHistorySummary: Sendable {
    var totalTokens: Int64
    var estimatedCostUSD: Double?
    var streak: LocalUsageStreakSummary
}

struct LocalCodexUsageTodaySummary: Sendable {
    var totalTokens: Int64
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var estimatedCostUSD: Double?
    var uncachedInputCostUSD: Double?
    var cachedInputCostUSD: Double?
    var outputCostUSD: Double?
}

private struct LocalTokenPrice {
    var input: Double
    var cachedInput: Double
    var output: Double
    var longContextThreshold: Int64?
}

private func estimatedAPICost(
    model: String?,
    inputTokens: Int64,
    cachedInputTokens: Int64,
    outputTokens: Int64
) -> (total: Double, uncachedInput: Double, cachedInput: Double, output: Double)? {
    guard let price = localTokenPrice(for: model) else { return nil }
    let isLongContext = price.longContextThreshold.map { inputTokens > $0 } ?? false
    let inputMultiplier = isLongContext ? 2.0 : 1.0
    let outputMultiplier = isLongContext ? 1.5 : 1.0
    let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
    let uncached = max(0, inputTokens - cached)
    let uncachedCost = Double(uncached) / 1_000_000 * price.input * inputMultiplier
    let cachedCost = Double(cached) / 1_000_000 * price.cachedInput * inputMultiplier
    let generatedCost = Double(max(0, outputTokens)) / 1_000_000
        * price.output * outputMultiplier
    return (
        total: uncachedCost + cachedCost + generatedCost,
        uncachedInput: uncachedCost,
        cachedInput: cachedCost,
        output: generatedCost
    )
}

/// 公开 API 的标准文本 Token 单价（USD / 1M Token）。ChatGPT 套餐本身
/// 不按这些价格扣费，因此界面明确标注为“API 等价估算”。
private func localTokenPrice(for rawModel: String?) -> LocalTokenPrice? {
    guard let rawModel else { return nil }
    let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard model.contains("gpt") else { return nil }

    if model.contains("5.6") {
        if model.contains("luna") {
            return LocalTokenPrice(
                input: 1, cachedInput: 0.1, output: 6, longContextThreshold: 272_000
            )
        }
        if model.contains("terra") {
            return LocalTokenPrice(
                input: 2.5, cachedInput: 0.25, output: 15,
                longContextThreshold: 272_000
            )
        }
        return LocalTokenPrice(
            input: 5, cachedInput: 0.5, output: 30, longContextThreshold: 272_000
        )
    }
    if model.contains("5.5-pro") {
        return LocalTokenPrice(
            input: 30, cachedInput: 30, output: 180, longContextThreshold: nil
        )
    }
    if model.contains("5.5") {
        return LocalTokenPrice(
            input: 5, cachedInput: 0.5, output: 30, longContextThreshold: 272_000
        )
    }
    if model.contains("5.4-pro") {
        return LocalTokenPrice(
            input: 30, cachedInput: 30, output: 180, longContextThreshold: 272_000
        )
    }
    if model.contains("5.4-mini") {
        return LocalTokenPrice(
            input: 0.75, cachedInput: 0.075, output: 4.5, longContextThreshold: nil
        )
    }
    if model.contains("5.4-nano") {
        return LocalTokenPrice(
            input: 0.2, cachedInput: 0.02, output: 1.25, longContextThreshold: nil
        )
    }
    if model.contains("5.4") {
        return LocalTokenPrice(
            input: 2.5, cachedInput: 0.25, output: 15,
            longContextThreshold: 272_000
        )
    }
    if model.contains("gpt-5") {
        return LocalTokenPrice(
            input: 1.25, cachedInput: 0.125, output: 10, longContextThreshold: nil
        )
    }
    return nil
}

private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (value, overflow) = lhs.addingReportingOverflow(max(0, rhs))
    return overflow ? Int64.max : value
}

/// 从本机 Codex session JSONL 提取 `token_count`，统一生成设备级今日、日桶与累计值。
actor LocalCodexUsageReader {
    static let shared = LocalCodexUsageReader()

    /// 会话文件通常跟随写入更新，但跨日续用的线程可能仍保留在前一天的
    /// 目录/时间戳中；回看一天可以覆盖这类文件，同时避免扫描多年历史。
    private let sessionLookback: TimeInterval = 24 * 60 * 60

    private struct CacheEntry {
        var size: UInt64
        var modifiedAt: Date
        var dayStart: Date
        var todayUsage: LocalCodexUsageTodaySummary?
    }

    private struct HistoryCacheEntry {
        var size: UInt64
        var modifiedAt: Date
        var rangeStart: Date
        var timeZoneIdentifier: String
        var dailyTokens: [String: Int64]?
    }

    private struct AggregateHistoryCache {
        var sessionsPath: String
        var rangeStart: Date
        var timeZoneIdentifier: String
        var fetchedAt: Date
        var buckets: [DailyTokenBucket]?
    }

    private struct TotalCacheEntry {
        var size: UInt64
        var modifiedAt: Date
        var timeZoneIdentifier: String
        var usage: SessionAllTimeUsage?
    }

    private struct AggregateTotalCache {
        var sessionsPath: String
        var timeZoneIdentifier: String
        var fetchedAt: Date
        var summary: LocalCodexUsageHistorySummary?
    }

    private struct SessionAllTimeUsage {
        var totalTokens: Int64
        var estimatedCostUSD: Double?
        var activeDayKeys: Set<String>
    }

    private struct SessionEvent: Decodable {
        var timestamp: String?
        var type: String
        var payload: Payload?

        struct Payload: Decodable {
            var type: String?
            var info: UsageInfo?
        }

        struct UsageInfo: Decodable {
            var totalTokenUsage: TokenTotal?
            var lastTokenUsage: TokenTotal?

            enum CodingKeys: String, CodingKey {
                case totalTokenUsage = "total_token_usage"
                case lastTokenUsage = "last_token_usage"
            }
        }

        struct TokenTotal: Decodable {
            var totalTokens: Int64?
            var inputTokens: Int64?
            var cachedInputTokens: Int64?
            var outputTokens: Int64?

            enum CodingKeys: String, CodingKey {
                case totalTokens = "total_tokens"
                case inputTokens = "input_tokens"
                case cachedInputTokens = "cached_input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }

    private struct SessionContextEvent: Decodable {
        var type: String
        var payload: Payload?

        struct Payload: Decodable {
            var model: String?
            var modelSlug: String?

            enum CodingKeys: String, CodingKey {
                case model
                case modelSlug = "model_slug"
            }
        }
    }

    private struct SessionMetadataEvent: Decodable {
        var timestamp: String?
        var type: String
        var payload: Payload?

        struct Payload: Decodable {
            var source: Source?
        }

        struct Source: Decodable {
            var subagent: Subagent?
        }

        /// 这里只需要判断字段是否存在；具体的 parent/depth 信息不参与统计。
        struct Subagent: Decodable {}
    }

    private struct TokenUsageEvent {
        var timestamp: Date?
        var tokens: Int64
        var lastTokens: Int64?
        var inputTokens: Int64? = nil
        var cachedInputTokens: Int64? = nil
        var outputTokens: Int64? = nil
        var model: String? = nil
    }

    private var cache: [String: CacheEntry] = [:]
    private var historyCache: [String: HistoryCacheEntry] = [:]
    private var aggregateHistoryCache: AggregateHistoryCache?
    private var totalCache: [String: TotalCacheEntry] = [:]
    private var aggregateTotalCache: AggregateTotalCache?
    private let aggregateHistoryCacheLifetime: TimeInterval = 15 * 60
    /// 活跃任务通过实时事件逐次补增量；完整 session 重扫只需承担最终校正。
    private let aggregateTotalCacheLifetime: TimeInterval = 0.75
    /// fork 出来的子代理会在建档时把父任务历史压缩回放到新 JSONL。回放事件集中在
    /// session 创建后的极短时间内；达到这个密度才排除，避免误伤正常的首轮响应。
    private let subagentReplayWindow: TimeInterval = 2
    private let minimumSubagentReplayEvents = 8
    private let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let basicISO8601 = ISO8601DateFormatter()

    func todayTokens(
        codexHome: String?,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Int64? {
        todayUsageSummary(
            codexHome: codexHome,
            reference: reference,
            calendar: calendar
        )?.totalTokens
    }

    func todayUsageSummary(
        codexHome: String?,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> LocalCodexUsageTodaySummary? {
        let homeURL: URL
        if let codexHome, !codexHome.isEmpty {
            homeURL = URL(fileURLWithPath: codexHome, isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }

        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        let start = calendar.startOfDay(for: reference)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let files = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var totalTokens: Int64 = 0
        var inputTokens: Int64 = 0
        var cachedInputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var estimatedCostUSD: Double = 0
        var uncachedInputCostUSD: Double = 0
        var cachedInputCostUSD: Double = 0
        var outputCostUSD: Double = 0
        var hasPricedUsage = false
        var found = false
        for case let file as URL in files where file.pathExtension.lowercased() == "jsonl" {
            guard let usage = sessionTodayUsage(at: file, start: start, end: end) else { continue }
            found = true
            totalTokens = saturatingAdd(totalTokens, usage.totalTokens)
            inputTokens = saturatingAdd(inputTokens, usage.inputTokens)
            cachedInputTokens = saturatingAdd(cachedInputTokens, usage.cachedInputTokens)
            outputTokens = saturatingAdd(outputTokens, usage.outputTokens)
            if let value = usage.estimatedCostUSD {
                estimatedCostUSD += value
                hasPricedUsage = true
            }
            if let value = usage.uncachedInputCostUSD { uncachedInputCostUSD += value }
            if let value = usage.cachedInputCostUSD { cachedInputCostUSD += value }
            if let value = usage.outputCostUSD { outputCostUSD += value }
        }
        guard found else { return nil }
        return LocalCodexUsageTodaySummary(
            totalTokens: totalTokens,
            inputTokens: inputTokens,
            cachedInputTokens: min(cachedInputTokens, inputTokens),
            outputTokens: outputTokens,
            estimatedCostUSD: hasPricedUsage ? estimatedCostUSD : nil,
            uncachedInputCostUSD: hasPricedUsage ? uncachedInputCostUSD : nil,
            cachedInputCostUSD: hasPricedUsage ? cachedInputCostUSD : nil,
            outputCostUSD: hasPricedUsage ? outputCostUSD : nil
        )
    }

    /// 本机全部 session 最近 7 个自然日的 Token 增量。优先使用每次事件自带的
    /// `last_token_usage`；旧日志缺少该字段时才回退到累计值之差。该慢路径单独缓存，
    /// 不影响高频 `todayTokens()`。
    func last7DaysBuckets(
        codexHome: String?,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyTokenBucket]? {
        let homeURL: URL
        if let codexHome, !codexHome.isEmpty {
            homeURL = URL(fileURLWithPath: codexHome, isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }

        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        let todayStart = calendar.startOfDay(for: reference)
        guard let rangeStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return nil
        }
        let timeZoneIdentifier = calendar.timeZone.identifier
        if let cached = aggregateHistoryCache,
           cached.sessionsPath == sessionsURL.path,
           cached.rangeStart == rangeStart,
           cached.timeZoneIdentifier == timeZoneIdentifier,
           Date().timeIntervalSince(cached.fetchedAt) < aggregateHistoryCacheLifetime {
            return cached.buckets
        }

        guard let files = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var totalsByDay: [String: Int64] = [:]
        var found = false
        for case let file as URL in files where file.pathExtension.lowercased() == "jsonl" {
            guard let daily = sessionDailyTokens(
                at: file,
                start: rangeStart,
                end: rangeEnd,
                calendar: calendar
            ) else { continue }
            found = true
            for (day, tokens) in daily {
                let current = totalsByDay[day] ?? 0
                let (next, overflow) = current.addingReportingOverflow(tokens)
                totalsByDay[day] = overflow ? Int64.max : next
            }
        }

        let formatter = UsageStats.dayFormatter(calendar: calendar)
        let buckets: [DailyTokenBucket]? = found ? (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: rangeStart) else { return nil }
            let key = formatter.string(from: day)
            return DailyTokenBucket(dateString: key, tokens: totalsByDay[key] ?? 0)
        } : nil
        aggregateHistoryCache = AggregateHistoryCache(
            sessionsPath: sessionsURL.path,
            rangeStart: rangeStart,
            timeZoneIdentifier: timeZoneIdentifier,
            fetchedAt: Date(),
            buckets: buckets
        )
        return buckets
    }

    /// 本机 `sessions` 目录内所有历史会话的累计 Token。Codex 新版日志会在同一
    /// JSONL 中交错写入不同累计流，因此优先累计每条事件的 `last_token_usage`；
    /// 旧日志缺少该字段时才按累计计数器差值兼容。
    /// 这里不读取账号信息，因此天然覆盖本机使用过的所有 Codex 账号。
    func allTimeSummary(
        codexHome: String?,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> LocalCodexUsageHistorySummary? {
        let homeURL: URL
        if let codexHome, !codexHome.isEmpty {
            homeURL = URL(fileURLWithPath: codexHome, isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }

        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        let timeZoneIdentifier = calendar.timeZone.identifier
        if let cached = aggregateTotalCache,
           cached.sessionsPath == sessionsURL.path,
           cached.timeZoneIdentifier == timeZoneIdentifier,
           Date().timeIntervalSince(cached.fetchedAt) < aggregateTotalCacheLifetime {
            return cached.summary
        }

        guard let files = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var sum: Int64 = 0
        var estimatedCostUSD: Double = 0
        var hasPricedUsage = false
        var found = false
        var activeDayKeys: Set<String> = []
        var currentPaths: Set<String> = []
        for case let file as URL in files where file.pathExtension.lowercased() == "jsonl" {
            currentPaths.insert(file.path)
            guard let usage = sessionAllTimeUsage(at: file, calendar: calendar) else { continue }
            found = true
            let (next, overflow) = sum.addingReportingOverflow(max(0, usage.totalTokens))
            sum = overflow ? Int64.max : next
            if let value = usage.estimatedCostUSD {
                estimatedCostUSD += value
                hasPricedUsage = true
            }
            activeDayKeys.formUnion(usage.activeDayKeys)
        }
        totalCache = totalCache.filter { currentPaths.contains($0.key) }

        let summary: LocalCodexUsageHistorySummary? = found
            ? LocalCodexUsageHistorySummary(
                totalTokens: sum,
                estimatedCostUSD: hasPricedUsage ? estimatedCostUSD : nil,
                streak: LocalUsageStreakSummary.calculate(
                    activeDayKeys: activeDayKeys,
                    reference: reference,
                    calendar: calendar
                )
            )
            : nil
        aggregateTotalCache = AggregateTotalCache(
            sessionsPath: sessionsURL.path,
            timeZoneIdentifier: timeZoneIdentifier,
            fetchedAt: Date(),
            summary: summary
        )
        return summary
    }

    func allTimeTokens(codexHome: String?) -> Int64? {
        allTimeSummary(codexHome: codexHome)?.totalTokens
    }

    private func sessionTodayUsage(
        at url: URL,
        start: Date,
        end: Date
    ) -> LocalCodexUsageTodaySummary? {
        guard let metadata = freshLocalFileMetadata(at: url), metadata.isRegularFile else { return nil }

        let size = UInt64(max(0, metadata.size))
        let modifiedAt = metadata.modifiedAt
        guard modifiedAt >= start.addingTimeInterval(-sessionLookback) else { return nil }
        if let cached = cache[url.path],
           cached.size == size,
           cached.modifiedAt == modifiedAt,
           cached.dayStart == start {
            return cached.todayUsage
        }

        let usage = parseSessionTodayUsage(at: url, start: start, end: end)
        cache[url.path] = CacheEntry(
            size: size,
            modifiedAt: modifiedAt,
            dayStart: start,
            todayUsage: usage
        )
        return usage
    }

    private func parseSessionTodayUsage(
        at url: URL,
        start: Date,
        end: Date
    ) -> LocalCodexUsageTodaySummary? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let decoder = JSONDecoder()
        // Codex normally emits compact JSON, but some versions/launchers add
        // whitespace around the colon. Match the event name rather than one
        // exact serialization so API-key sessions are not silently skipped.
        let marker = Data("token_count".utf8)
        let contextMarker = Data("turn_context".utf8)
        var events: [TokenUsageEvent] = []
        let subagentStartedAt = subagentSessionStart(in: data, decoder: decoder)
        var currentModel: String?

        for line in data.split(separator: 0x0A) {
            let lineData = Data(line)
            if lineData.range(of: contextMarker) != nil,
               let context = try? decoder.decode(SessionContextEvent.self, from: lineData),
               context.type == "turn_context" {
                currentModel = context.payload?.model ?? context.payload?.modelSlug ?? currentModel
            }
            guard lineData.range(of: marker) != nil,
                  let event = try? decoder.decode(SessionEvent.self, from: lineData),
                  event.type == "event_msg",
                  event.payload?.type == "token_count",
                  let tokens = event.payload?.info?.totalTokenUsage?.totalTokens,
                  let rawTimestamp = event.timestamp,
                  let timestamp = parseTimestamp(rawTimestamp) else {
                continue
            }

            guard timestamp < end else { continue }
            let lastUsage = event.payload?.info?.lastTokenUsage
            events.append(TokenUsageEvent(
                timestamp: timestamp,
                tokens: max(0, tokens),
                lastTokens: lastUsage?.totalTokens.map { max(0, $0) },
                inputTokens: lastUsage?.inputTokens.map { max(0, $0) },
                cachedInputTokens: lastUsage?.cachedInputTokens.map { max(0, $0) },
                outputTokens: lastUsage?.outputTokens.map { max(0, $0) },
                model: currentModel
            ))
        }
        guard !events.isEmpty else { return nil }
        events.sort { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        let importedPrefixCount = importedSubagentPrefixCount(
            events: events,
            subagentStartedAt: subagentStartedAt
        )

        var previous: Int64?
        var total: Int64 = 0
        var input: Int64 = 0
        var cachedInput: Int64 = 0
        var output: Int64 = 0
        var estimatedCostUSD: Double = 0
        var uncachedInputCostUSD: Double = 0
        var cachedInputCostUSD: Double = 0
        var outputCostUSD: Double = 0
        var hasPricedUsage = false
        var foundToday = false
        for (index, event) in events.enumerated() {
            if index < importedPrefixCount {
                previous = event.tokens
                continue
            }
            guard let timestamp = event.timestamp else { continue }
            if timestamp < start {
                previous = event.tokens
                continue
            }
            foundToday = true
            let delta = tokenIncrement(
                totalTokens: event.tokens,
                lastUsageTokens: event.lastTokens,
                previousTotalTokens: previous
            )
            let (next, overflow) = total.addingReportingOverflow(max(0, delta))
            total = overflow ? Int64.max : next
            if delta > 0,
               let eventInput = event.inputTokens,
               let eventCached = event.cachedInputTokens,
               let eventOutput = event.outputTokens {
                let normalizedInput = max(0, eventInput)
                let normalizedCached = min(max(0, eventCached), normalizedInput)
                let normalizedOutput = max(0, eventOutput)
                input = saturatingAdd(input, normalizedInput)
                cachedInput = saturatingAdd(cachedInput, normalizedCached)
                output = saturatingAdd(output, normalizedOutput)
                if let costs = estimatedAPICost(
                    model: event.model,
                    inputTokens: normalizedInput,
                    cachedInputTokens: normalizedCached,
                    outputTokens: normalizedOutput
                ) {
                    estimatedCostUSD += costs.total
                    uncachedInputCostUSD += costs.uncachedInput
                    cachedInputCostUSD += costs.cachedInput
                    outputCostUSD += costs.output
                    hasPricedUsage = true
                }
            }
            previous = event.tokens
        }
        guard foundToday else { return nil }
        return LocalCodexUsageTodaySummary(
            totalTokens: total,
            inputTokens: input,
            cachedInputTokens: cachedInput,
            outputTokens: output,
            estimatedCostUSD: hasPricedUsage ? estimatedCostUSD : nil,
            uncachedInputCostUSD: hasPricedUsage ? uncachedInputCostUSD : nil,
            cachedInputCostUSD: hasPricedUsage ? cachedInputCostUSD : nil,
            outputCostUSD: hasPricedUsage ? outputCostUSD : nil
        )
    }

    private func sessionDailyTokens(
        at url: URL,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [String: Int64]? {
        guard let metadata = freshLocalFileMetadata(at: url), metadata.isRegularFile else { return nil }
        guard metadata.modifiedAt >= start.addingTimeInterval(-sessionLookback) else { return nil }

        let size = UInt64(max(0, metadata.size))
        let timeZoneIdentifier = calendar.timeZone.identifier
        if let cached = historyCache[url.path],
           cached.size == size,
           cached.modifiedAt == metadata.modifiedAt,
           cached.rangeStart == start,
           cached.timeZoneIdentifier == timeZoneIdentifier {
            return cached.dailyTokens
        }

        let daily = parseSessionDailyTokens(at: url, start: start, end: end, calendar: calendar)
        historyCache[url.path] = HistoryCacheEntry(
            size: size,
            modifiedAt: metadata.modifiedAt,
            rangeStart: start,
            timeZoneIdentifier: timeZoneIdentifier,
            dailyTokens: daily
        )
        return daily
    }

    private func parseSessionDailyTokens(
        at url: URL,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [String: Int64]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let decoder = JSONDecoder()
        let marker = Data("token_count".utf8)
        let formatter = UsageStats.dayFormatter(calendar: calendar)
        var events: [TokenUsageEvent] = []
        let subagentStartedAt = subagentSessionStart(in: data, decoder: decoder)

        for line in data.split(separator: 0x0A) {
            let lineData = Data(line)
            guard lineData.range(of: marker) != nil,
                  let event = try? decoder.decode(SessionEvent.self, from: lineData),
                  event.type == "event_msg",
                  event.payload?.type == "token_count",
                  let tokens = event.payload?.info?.totalTokenUsage?.totalTokens,
                  let rawTimestamp = event.timestamp,
                  let timestamp = parseTimestamp(rawTimestamp) else {
                continue
            }

            guard timestamp < end else { continue }
            let lastTokens = event.payload?.info?.lastTokenUsage?.totalTokens
            events.append(TokenUsageEvent(
                timestamp: timestamp,
                tokens: max(0, tokens),
                lastTokens: lastTokens.map { max(0, $0) }
            ))
        }
        guard !events.isEmpty else { return nil }
        events.sort { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        let importedPrefixCount = importedSubagentPrefixCount(
            events: events,
            subagentStartedAt: subagentStartedAt
        )

        var result: [String: Int64] = [:]
        var previous: Int64?
        var foundInRange = false
        for (index, event) in events.enumerated() {
            if index < importedPrefixCount {
                previous = event.tokens
                continue
            }
            guard let timestamp = event.timestamp else { continue }
            if timestamp < start {
                // 取窗口前最后一次值，而不是最大值；压缩等场景会重置累计计数器。
                previous = event.tokens
                continue
            }
            foundInRange = true
            let delta = tokenIncrement(
                totalTokens: event.tokens,
                lastUsageTokens: event.lastTokens,
                previousTotalTokens: previous
            )
            let day = formatter.string(from: timestamp)
            let current = result[day] ?? 0
            let (next, overflow) = current.addingReportingOverflow(max(0, delta))
            result[day] = overflow ? Int64.max : next
            previous = event.tokens
        }
        return foundInRange ? result : nil
    }

    private func sessionAllTimeUsage(
        at url: URL,
        calendar: Calendar
    ) -> SessionAllTimeUsage? {
        guard let metadata = freshLocalFileMetadata(at: url), metadata.isRegularFile else { return nil }
        let size = UInt64(max(0, metadata.size))
        let timeZoneIdentifier = calendar.timeZone.identifier
        if let cached = totalCache[url.path],
           cached.size == size,
           cached.modifiedAt == metadata.modifiedAt,
           cached.timeZoneIdentifier == timeZoneIdentifier {
            return cached.usage
        }

        let usage = parseSessionAllTimeUsage(at: url, calendar: calendar)
        totalCache[url.path] = TotalCacheEntry(
            size: size,
            modifiedAt: metadata.modifiedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            usage: usage
        )
        return usage
    }

    private func parseSessionAllTimeUsage(
        at url: URL,
        calendar: Calendar
    ) -> SessionAllTimeUsage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let decoder = JSONDecoder()
        let marker = Data("token_count".utf8)
        let contextMarker = Data("turn_context".utf8)
        let formatter = UsageStats.dayFormatter(calendar: calendar)
        var events: [TokenUsageEvent] = []
        let subagentStartedAt = subagentSessionStart(in: data, decoder: decoder)
        var currentModel: String?

        for line in data.split(separator: 0x0A) {
            let lineData = Data(line)
            if lineData.range(of: contextMarker) != nil,
               let context = try? decoder.decode(SessionContextEvent.self, from: lineData),
               context.type == "turn_context" {
                currentModel = context.payload?.model ?? context.payload?.modelSlug ?? currentModel
            }
            guard lineData.range(of: marker) != nil,
                  let event = try? decoder.decode(SessionEvent.self, from: lineData),
                  event.type == "event_msg",
                  event.payload?.type == "token_count",
                  let rawTokens = event.payload?.info?.totalTokenUsage?.totalTokens else {
                continue
            }
            events.append(TokenUsageEvent(
                timestamp: event.timestamp.flatMap(parseTimestamp),
                tokens: max(0, rawTokens),
                lastTokens: (event.payload?.info?.lastTokenUsage?.totalTokens).map { max(0, $0) },
                inputTokens: event.payload?.info?.lastTokenUsage?.inputTokens.map { max(0, $0) },
                cachedInputTokens: event.payload?.info?.lastTokenUsage?.cachedInputTokens.map { max(0, $0) },
                outputTokens: event.payload?.info?.lastTokenUsage?.outputTokens.map { max(0, $0) },
                model: currentModel
            ))
        }
        guard !events.isEmpty else { return nil }
        let importedPrefixCount = importedSubagentPrefixCount(
            events: events,
            subagentStartedAt: subagentStartedAt
        )
        var previous: Int64?
        var total: Int64 = 0
        var estimatedCostUSD: Double = 0
        var hasPricedUsage = false
        var found = false
        var activeDayKeys: Set<String> = []

        // JSONL 本身按写入顺序记录累计计数，不依赖时间戳即可覆盖旧版或时钟异常日志。
        for (index, event) in events.enumerated() {
            if index < importedPrefixCount {
                previous = event.tokens
                continue
            }

            let delta = tokenIncrement(
                totalTokens: event.tokens,
                lastUsageTokens: event.lastTokens,
                previousTotalTokens: previous
            )
            let (next, overflow) = total.addingReportingOverflow(max(0, delta))
            total = overflow ? Int64.max : next
            if delta > 0,
               let input = event.inputTokens,
               let cachedInput = event.cachedInputTokens,
               let output = event.outputTokens,
               let cost = estimatedAPICost(
                model: event.model,
                inputTokens: input,
                cachedInputTokens: cachedInput,
                outputTokens: output
               ) {
                estimatedCostUSD += cost.total
                hasPricedUsage = true
            }
            if delta > 0, let timestamp = event.timestamp {
                activeDayKeys.insert(formatter.string(from: timestamp))
            }
            previous = event.tokens
            found = true
        }
        return found
            ? SessionAllTimeUsage(
                totalTokens: total,
                estimatedCostUSD: hasPricedUsage ? estimatedCostUSD : nil,
                activeDayKeys: activeDayKeys
            )
            : nil
    }

    private func parseTimestamp(_ raw: String) -> Date? {
        fractionalISO8601.date(from: raw) ?? basicISO8601.date(from: raw)
    }

    private func subagentSessionStart(in data: Data, decoder: JSONDecoder) -> Date? {
        let firstLineEnd = data.firstIndex(of: 0x0A) ?? data.endIndex
        let firstLine = Data(data[..<firstLineEnd])
        guard let metadata = try? decoder.decode(SessionMetadataEvent.self, from: firstLine),
              metadata.type == "session_meta",
              metadata.payload?.source?.subagent != nil,
              let rawTimestamp = metadata.timestamp else {
            return nil
        }
        return parseTimestamp(rawTimestamp)
    }

    /// Codex 的 fork session 会把父任务事件拷贝到子文件开头，并把时间戳压缩到
    /// 子 session 创建后的毫秒级窗口。只有密集度足够高时才视为回放前缀。
    private func importedSubagentPrefixCount(
        events: [TokenUsageEvent],
        subagentStartedAt: Date?
    ) -> Int {
        guard let subagentStartedAt else { return 0 }
        let replayEnd = subagentStartedAt.addingTimeInterval(subagentReplayWindow)
        var count = 0
        for event in events {
            guard let timestamp = event.timestamp,
                  timestamp >= subagentStartedAt,
                  timestamp <= replayEnd else {
                break
            }
            count += 1
        }
        return count >= minimumSubagentReplayEvents ? count : 0
    }

    /// `total_token_usage` 在新版 Codex 中可能由多条计数流交错写入，单纯比较
    /// 相邻累计值会把流切换误判成新增或重置。累计值没变化时是重复事件；变化时
    /// 优先采用该事件明确给出的 last usage。旧日志再使用原来的差值规则。
    private func tokenIncrement(
        totalTokens: Int64,
        lastUsageTokens: Int64?,
        previousTotalTokens: Int64?
    ) -> Int64 {
        if let previousTotalTokens, totalTokens == previousTotalTokens {
            return 0
        }
        if let lastUsageTokens {
            return max(0, lastUsageTokens)
        }
        guard let previousTotalTokens else {
            return max(0, totalTokens)
        }
        return totalTokens >= previousTotalTokens
            ? totalTokens - previousTotalTokens
            : max(0, totalTokens)
    }
}

/// `thread/list` 无法感知另一个 Codex 进程的 turn 时，从共享 session JSONL 判断最近线程是否仍在执行。
struct LocalCodexActivity: Sendable {
    var threadID: String
    var cwd: String?
    var model: String?
    var reasoningEffort: String?
    var modifiedAt: Date
    var startedAt: Date?
    var state: CodexRunState
    /// session 尾部最近一次 token_count 的线程累计值。
    var totalTokens: Int64?
    /// 与最近一次累计值对应的单次增量，用于处理多计数流交错写入。
    var lastUsageTokens: Int64?
    /// session 尾部最近一次带时间戳的 token_count.rate_limits。
    var rateLimits: RateLimitSnapshot?
    /// 当前 turn 中用户可见的用户/助手消息。
    var conversation: [TaskConversationMessage]
}

actor LocalCodexActivityReader {
    static let shared = LocalCodexActivityReader()

    /// 为长命令保留足够窗口；final/task_complete 仍会立即结束活动状态。
    private let staleInterval: TimeInterval = 3 * 60 * 60
    private let tailByteCount: UInt64 = 512 * 1024
    private let fullDiscoveryInterval: TimeInterval = 60
    private let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let basicISO8601 = ISO8601DateFormatter()
    private struct CachedSessionAnalysis {
        var size: Int
        var modifiedAt: Date
        var analysis: SessionAnalysis
        var metadata: (id: String?, cwd: String?)
    }
    private struct SessionCandidate {
        var url: URL
        var modifiedAt: Date
        var size: Int
    }
    private var sessionCache: [String: CachedSessionAnalysis] = [:]
    private var candidateIndex: [String: SessionCandidate] = [:]
    /// 会话文件按创建日期分目录，但旧任务恢复后仍会继续写入原文件。
    /// 保存线程 ID 到原文件的索引，避免高频轮询只看今天目录而漏掉恢复的旧任务。
    private var sessionURLByThreadID: [String: URL] = [:]
    private var recentSessionDirectories: [URL] = []
    private var lastFullDiscoveryAt = Date.distantPast

    func activeThreads(
        codexHome: String?,
        reference: Date = Date(),
        limit: Int = 10,
        hintedThreadIDs: [String] = []
    ) -> [LocalCodexActivity] {
        let homeURL: URL
        if let codexHome, !codexHome.isEmpty {
            homeURL = URL(fileURLWithPath: codexHome, isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }

        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        refreshCandidateIndex(sessionsURL: sessionsURL, reference: reference)
        refreshHintedCandidates(hintedThreadIDs, reference: reference)
        var candidates = Array(candidateIndex.values)

        candidates.sort { $0.modifiedAt > $1.modifiedAt }
        var result: [LocalCodexActivity] = []
        var seenThreadIDs: Set<String> = []
        for candidate in candidates {
            guard result.count < max(1, limit) else { break }
            let cached = cachedAnalysis(
                at: candidate.url,
                size: candidate.size,
                modifiedAt: candidate.modifiedAt
            )
            guard cached.analysis.isActive else { continue }
            let metadata = cached.metadata
            let fallbackID = threadIDFromFilename(candidate.url)
            let threadID = metadata.id ?? fallbackID
            guard seenThreadIDs.insert(threadID).inserted else { continue }
            result.append(LocalCodexActivity(
                threadID: threadID,
                cwd: metadata.cwd,
                model: cached.analysis.model,
                reasoningEffort: cached.analysis.reasoningEffort,
                modifiedAt: candidate.modifiedAt,
                startedAt: cached.analysis.startedAt,
                state: cached.analysis.state,
                totalTokens: cached.analysis.totalTokens,
                lastUsageTokens: cached.analysis.lastUsageTokens,
                rateLimits: cached.analysis.rateLimits,
                conversation: cached.analysis.conversation
            ))
        }
        // 防止长期运行后缓存无限增长；只保留仍处于活动检测窗口内的文件。
        sessionCache = sessionCache.filter {
            reference.timeIntervalSince($0.value.modifiedAt) <= staleInterval
        }
        return result
    }

    /// 返回需要进行文件系统事件监听的会话文件。优先覆盖 thread/list 已知线程，
    /// 再补最近写入的候选；监听方无需高频遍历整个 sessions 目录。
    func realtimeSessionURLs(
        hintedThreadIDs: [String],
        limit: Int = 128
    ) -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        // 目录 vnode 事件用于捕获刚创建的新会话文件；已有会话仍由文件事件直接驱动。
        for directory in recentSessionDirectories where seen.insert(directory.path).inserted {
            urls.append(directory)
        }

        for threadID in hintedThreadIDs {
            guard let url = sessionURLByThreadID[threadID], seen.insert(url.path).inserted else { continue }
            urls.append(url)
            if urls.count >= limit { return urls }
        }

        for candidate in candidateIndex.values.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
            guard seen.insert(candidate.url.path).inserted else { continue }
            urls.append(candidate.url)
            if urls.count >= limit { break }
        }
        return urls
    }

    /// 文件系统事件已给出精确文件时，直接解析该线程的最后状态。
    /// 与 activeThreads 不同，即使任务已完成也会返回 `.idle`，供 UI 立即结束计时。
    func activitySnapshot(at url: URL, reference: Date = Date()) -> LocalCodexActivity? {
        guard let candidate = sessionCandidate(at: url, reference: reference) else { return nil }
        let cached = cachedAnalysis(
            at: candidate.url,
            size: candidate.size,
            modifiedAt: candidate.modifiedAt
        )
        let metadata = cached.metadata
        return LocalCodexActivity(
            threadID: metadata.id ?? threadIDFromFilename(url),
            cwd: metadata.cwd,
            model: cached.analysis.model,
            reasoningEffort: cached.analysis.reasoningEffort,
            modifiedAt: candidate.modifiedAt,
            startedAt: cached.analysis.startedAt,
            state: cached.analysis.state,
            totalTokens: cached.analysis.totalTokens,
            lastUsageTokens: cached.analysis.lastUsageTokens,
            rateLimits: cached.analysis.rateLimits,
            conversation: cached.analysis.conversation
        )
    }

    /// 高频状态轮询只扫描当天/前一天目录与少量已知候选；完整目录树最多每分钟一次。
    private func refreshCandidateIndex(sessionsURL: URL, reference: Date) {
        if candidateIndex.isEmpty
            || reference.timeIntervalSince(lastFullDiscoveryAt) >= fullDiscoveryInterval {
            fullDiscoverSessions(at: sessionsURL, reference: reference)
            discoverRecentDaySessions(at: sessionsURL, reference: reference)
        } else {
            discoverRecentDaySessions(at: sessionsURL, reference: reference)
            refreshKnownCandidates(reference: reference)
        }
        candidateIndex = candidateIndex.filter {
            reference.timeIntervalSince($0.value.modifiedAt) <= staleInterval
        }
    }

    private func fullDiscoverSessions(at sessionsURL: URL, reference: Date) {
        lastFullDiscoveryAt = reference
        guard let files = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return }

        var refreshed: [String: SessionCandidate] = [:]
        for case let file as URL in files where file.pathExtension.lowercased() == "jsonl" {
            sessionURLByThreadID[threadIDFromFilename(file)] = file
            if let candidate = sessionCandidate(at: file, reference: reference) {
                refreshed[file.path] = candidate
            }
        }
        candidateIndex = refreshed
    }

    private func discoverRecentDaySessions(at sessionsURL: URL, reference: Date) {
        let calendar = Calendar.current
        var directories: [URL] = []
        for dayOffset in [0, -1] {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: reference) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let directory = sessionsURL
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            directories.append(directory)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension.lowercased() == "jsonl" {
                sessionURLByThreadID[threadIDFromFilename(file)] = file
                if let candidate = sessionCandidate(at: file, reference: reference) {
                    candidateIndex[file.path] = candidate
                }
            }
        }
        recentSessionDirectories = directories
    }

    /// 直接检查完整扫描时建立的旧会话路径。这里只访问调用方提示的少量线程，
    /// 因此恢复历史任务也能 1 秒发现，同时避免每秒遍历整个 sessions 目录树。
    private func refreshHintedCandidates(_ threadIDs: [String], reference: Date) {
        for threadID in threadIDs.prefix(100) {
            guard let url = sessionURLByThreadID[threadID],
                  let candidate = sessionCandidate(at: url, reference: reference) else { continue }
            candidateIndex[url.path] = candidate
        }
    }

    private func refreshKnownCandidates(reference: Date) {
        for path in Array(candidateIndex.keys) {
            guard let candidate = candidateIndex[path] else { continue }
            if let refreshed = sessionCandidate(at: candidate.url, reference: reference) {
                candidateIndex[path] = refreshed
            } else {
                candidateIndex.removeValue(forKey: path)
            }
        }
    }

    private func sessionCandidate(at url: URL, reference: Date) -> SessionCandidate? {
        guard let metadata = freshLocalFileMetadata(at: url),
              metadata.isRegularFile,
              metadata.modifiedAt != .distantPast,
              reference.timeIntervalSince(metadata.modifiedAt) <= staleInterval else { return nil }
        let modifiedAt = metadata.modifiedAt
        return SessionCandidate(url: url, modifiedAt: modifiedAt, size: metadata.size)
    }

    private func threadIDFromFilename(_ url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        return filename.count >= 36 ? String(filename.suffix(36)) : filename
    }

    private struct SessionAnalysis {
        var isActive: Bool
        var startedAt: Date?
        var state: CodexRunState
        var model: String?
        var reasoningEffort: String?
        var totalTokens: Int64?
        var lastUsageTokens: Int64?
        var rateLimits: RateLimitSnapshot?
        var conversation: [TaskConversationMessage]
    }

    private func cachedAnalysis(
        at url: URL,
        size: Int,
        modifiedAt: Date
    ) -> CachedSessionAnalysis {
        if let cached = sessionCache[url.path],
           cached.size == size,
           cached.modifiedAt == modifiedAt {
            return cached
        }
        let value = CachedSessionAnalysis(
            size: size,
            modifiedAt: modifiedAt,
            analysis: analyzeSession(at: url),
            metadata: sessionMetadata(at: url)
        )
        sessionCache[url.path] = value
        return value
    }

    /// 顺序分析尾部事件，既判断是否完成，也尽量恢复当前 turn 的开始时间。
    private func analyzeSession(at url: URL) -> SessionAnalysis {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return SessionAnalysis(
                isActive: false,
                startedAt: nil,
                state: .idle,
                model: nil,
                reasoningEffort: nil,
                totalTokens: nil,
                lastUsageTokens: nil,
                rateLimits: nil,
                conversation: []
            )
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > tailByteCount ? size - tailByteCount : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return SessionAnalysis(
                isActive: false,
                startedAt: nil,
                state: .idle,
                model: nil,
                reasoningEffort: nil,
                totalTokens: nil,
                lastUsageTokens: nil,
                rateLimits: nil,
                conversation: []
            )
        }

        // 从文件中段开始读取时，第一行可能是不完整 JSON。
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }

        var isActive = false
        var startedAt: Date?
        var recognizedEvent = false
        var state: CodexRunState = .thinking
        var model: String?
        var reasoningEffort: String?
        var totalTokens: Int64?
        var lastUsageTokens: Int64?
        var rateLimits: RateLimitSnapshot?
        var conversation: [TaskConversationMessage] = []
        var messageSequence = 0

        func appendConversationMessage(
            role: TaskConversationMessage.Role,
            text rawText: String,
            timestamp: Date?,
            fallbackID: String
        ) {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if let lastIndex = conversation.indices.last,
               conversation[lastIndex].role == role,
               conversation[lastIndex].text == text {
                conversation[lastIndex].isStreaming = false
                return
            }
            messageSequence += 1
            conversation.append(TaskConversationMessage(
                id: "\(fallbackID)-\(messageSequence)",
                role: role,
                text: String(text.prefix(16_000)),
                timestamp: timestamp,
                isStreaming: false
            ))
            if conversation.count > 32 {
                conversation.removeFirst(conversation.count - 32)
            }
        }

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let envelopeType = object["type"] as? String else {
                continue
            }
            let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp)

            let payload = object["payload"] as? [String: Any]

            if envelopeType == "session_meta"
                || envelopeType == "turn_context"
                || envelopeType == "compacted" {
                model = (payload?["model"] as? String)
                    ?? (payload?["model_slug"] as? String)
                    ?? (payload?["modelSlug"] as? String)
                    ?? model
                reasoningEffort = (payload?["reasoning_effort"] as? String)
                    ?? (payload?["reasoningEffort"] as? String)
                    ?? (payload?["effort"] as? String)
                    ?? reasoningEffort
            }

            // 自动续跑或上下文压缩后不一定再次写入 user_message，turn_context 本身
            // 就代表一个新 turn 已开始，避免仍沿用上一轮 task_complete 的空闲状态。
            if envelopeType == "turn_context" || envelopeType == "compacted" {
                recognizedEvent = true
                isActive = true
                startedAt = startedAt ?? timestamp
                state = .thinking
                continue
            }

            guard let payload,
                  let payloadType = payload["type"] as? String else {
                continue
            }

            if envelopeType == "event_msg", payloadType == "token_count" {
                if let nextTotal = sessionTokenTotal(from: payload) {
                    totalTokens = nextTotal
                    lastUsageTokens = sessionLastUsageTotal(from: payload)
                }
                if let observedAt = timestamp,
                   let rawRateLimits = (payload["rate_limits"] as? [String: Any])
                    ?? (payload["rateLimits"] as? [String: Any]),
                   let parsed = LocalRateLimitParser.parse(
                       rawRateLimits,
                       observedAt: observedAt
                   ),
                   parsed.updatedAt >= (rateLimits?.updatedAt ?? .distantPast) {
                    rateLimits = parsed
                }
                continue
            }

            if envelopeType == "event_msg" {
                switch payloadType {
                case "task_complete", "turn_complete", "turn_completed", "turn_aborted":
                    recognizedEvent = true
                    isActive = false
                    startedAt = nil
                    state = .idle
                case "user_message", "turn_started", "task_started":
                    recognizedEvent = true
                    isActive = true
                    startedAt = timestamp ?? startedAt
                    state = .thinking
                    if payloadType == "turn_started" || payloadType == "task_started" {
                        conversation.removeAll(keepingCapacity: true)
                    }
                    if payloadType == "user_message" {
                        let text = (payload["message"] as? String)
                            ?? (payload["text"] as? String)
                            ?? (payload["content"] as? String)
                            ?? ""
                        appendConversationMessage(
                            role: .user,
                            text: text,
                            timestamp: timestamp,
                            fallbackID: "user"
                        )
                    }
                case "agent_reasoning", "agent_message", "agent_message_content_delta":
                    recognizedEvent = true
                    isActive = true
                    startedAt = startedAt ?? timestamp
                    state = payloadType == "agent_reasoning" ? .thinking : .generatingCode
                    if payloadType == "agent_message" {
                        let text = (payload["message"] as? String)
                            ?? (payload["text"] as? String)
                            ?? (payload["content"] as? String)
                            ?? ""
                        appendConversationMessage(
                            role: .assistant,
                            text: text,
                            timestamp: timestamp,
                            fallbackID: "assistant"
                        )
                    } else if payloadType == "agent_message_content_delta",
                              let delta = payload["delta"] as? String,
                              !delta.isEmpty {
                        let itemID = (payload["item_id"] as? String)
                            ?? (payload["itemId"] as? String)
                            ?? "streaming-assistant"
                        if let index = conversation.lastIndex(where: { $0.id == itemID }) {
                            conversation[index].text += delta
                            conversation[index].isStreaming = true
                        } else {
                            conversation.append(TaskConversationMessage(
                                id: itemID,
                                role: .assistant,
                                text: delta,
                                timestamp: timestamp,
                                isStreaming: true
                            ))
                        }
                    }
                default:
                    continue
                }
            }

            if envelopeType == "response_item" {
                if payloadType == "message" {
                    recognizedEvent = true
                    let phase = (payload["phase"] as? String)?.lowercased()
                    if phase == "final" || phase == "final_answer" {
                        isActive = false
                        startedAt = nil
                        state = .idle
                    } else {
                        isActive = true
                        startedAt = startedAt ?? timestamp
                        state = .generatingCode
                    }
                    if (payload["role"] as? String)?.lowercased() == "assistant" {
                        let content = payload["content"] as? [[String: Any]] ?? []
                        let text = content.compactMap { item in
                            (item["text"] as? String)
                                ?? (item["output_text"] as? String)
                        }.joined(separator: "\n")
                        appendConversationMessage(
                            role: .assistant,
                            text: text,
                            timestamp: timestamp,
                            fallbackID: "response"
                        )
                    }
                    continue
                }
                switch payloadType {
                case "reasoning":
                    recognizedEvent = true
                    isActive = true
                    startedAt = startedAt ?? timestamp
                    state = .thinking
                case "function_call", "function_call_output",
                     "custom_tool_call", "custom_tool_call_output",
                     "web_search_call", "computer_tool_call", "computer_tool_call_output":
                    recognizedEvent = true
                    isActive = true
                    startedAt = startedAt ?? timestamp
                    state = inferredToolState(payloadType: payloadType, payload: payload)
                default:
                    continue
                }
            }
        }

        // 新版事件类型暂未识别时，近期发生写入仍视为活动，避免误报空闲。
        let resolvedActive = recognizedEvent ? isActive : true
        return SessionAnalysis(
            isActive: resolvedActive,
            startedAt: startedAt,
            state: resolvedActive ? state : .idle,
            model: model,
            reasoningEffort: reasoningEffort,
            totalTokens: totalTokens,
            lastUsageTokens: lastUsageTokens,
            rateLimits: rateLimits,
            conversation: conversation
        )
    }

    private func sessionTokenTotal(from payload: [String: Any]) -> Int64? {
        guard let info = payload["info"] as? [String: Any],
              let total = (info["total_token_usage"] as? [String: Any])
                ?? (info["totalTokenUsage"] as? [String: Any]) else {
            return nil
        }
        let value = total["total_tokens"] ?? total["totalTokens"]
        switch value {
        case let number as NSNumber: return number.int64Value
        case let number as Int64: return number
        case let number as Int: return Int64(number)
        case let text as String: return Int64(text)
        default: return nil
        }
    }

    private func sessionLastUsageTotal(from payload: [String: Any]) -> Int64? {
        guard let info = payload["info"] as? [String: Any],
              let last = (info["last_token_usage"] as? [String: Any])
                ?? (info["lastTokenUsage"] as? [String: Any]) else {
            return nil
        }
        let value = last["total_tokens"] ?? last["totalTokens"]
        switch value {
        case let number as NSNumber: return number.int64Value
        case let number as Int64: return number
        case let number as Int: return Int64(number)
        case let text as String: return Int64(text)
        default: return nil
        }
    }

    private func inferredToolState(payloadType: String, payload: [String: Any]) -> CodexRunState {
        if payloadType.contains("output") { return .thinking }
        let name = ((payload["name"] as? String) ?? (payload["tool_name"] as? String) ?? "").lowercased()
        if name.contains("request_user_input") {
            return .awaitingInput
        }
        // Codex 会根据工具协议使用 arguments 或 input；桌面版 custom_tool_call
        // 当前主要写入 input，其中包含 sandbox_permissions/require_escalated。
        let arguments = (payload["arguments"] as? String)
            ?? (payload["input"] as? String)
            ?? ""
        let lowerArguments = arguments.lowercased()
        if lowerArguments.contains("require_escalated") {
            return .awaitingAuthorization
        }
        if name.contains("exec") || name.contains("command") || name.contains("terminal") {
            return .executingCommand
        }
        if name.contains("apply_patch") || name.contains("file") || name.contains("write") {
            return .modifyingFiles
        }
        return .callingTool
    }

    private func parseTimestamp(_ raw: String) -> Date? {
        fractionalISO8601.date(from: raw) ?? basicISO8601.date(from: raw)
    }

    private func sessionMetadata(at url: URL) -> (id: String?, cwd: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 64 * 1024),
              let firstLine = prefix.split(separator: 0x0A).first,
              let object = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            return (nil, nil)
        }
        return (payload["id"] as? String, payload["cwd"] as? String)
    }
}
