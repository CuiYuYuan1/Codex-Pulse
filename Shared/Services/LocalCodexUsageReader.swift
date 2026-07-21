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

/// 从本机 Codex session JSONL 中只提取 `token_count` 数值，补齐官方日桶的同步延迟。
actor LocalCodexUsageReader {
    static let shared = LocalCodexUsageReader()

    /// 会话文件通常跟随写入更新，但跨日续用的线程可能仍保留在前一天的
    /// 目录/时间戳中；回看一天可以覆盖这类文件，同时避免扫描多年历史。
    private let sessionLookback: TimeInterval = 24 * 60 * 60

    private struct CacheEntry {
        var size: UInt64
        var modifiedAt: Date
        var dayStart: Date
        var todayTokens: Int64?
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

            enum CodingKeys: String, CodingKey {
                case totalTokenUsage = "total_token_usage"
            }
        }

        struct TokenTotal: Decodable {
            var totalTokens: Int64?

            enum CodingKeys: String, CodingKey {
                case totalTokens = "total_tokens"
            }
        }
    }

    private var cache: [String: CacheEntry] = [:]
    private var historyCache: [String: HistoryCacheEntry] = [:]
    private var aggregateHistoryCache: AggregateHistoryCache?
    private let aggregateHistoryCacheLifetime: TimeInterval = 15 * 60
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

        var sum: Int64 = 0
        var found = false
        for case let file as URL in files where file.pathExtension.lowercased() == "jsonl" {
            guard let total = sessionTodayTokens(at: file, start: start, end: end) else { continue }
            found = true
            let (next, overflow) = sum.addingReportingOverflow(total)
            sum = overflow ? Int64.max : next
        }
        return found ? sum : nil
    }

    /// 本机全部 session 最近 7 个自然日的 Token 增量。每个 session 的
    /// `total_token_usage.total_tokens` 是累计值，因此按日用“当日末值 - 前日末值”
    /// 计算，再跨 session 求和。该慢路径单独缓存，不影响高频 `todayTokens()`。
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

    private func sessionTodayTokens(at url: URL, start: Date, end: Date) -> Int64? {
        guard let metadata = freshLocalFileMetadata(at: url), metadata.isRegularFile else { return nil }

        let size = UInt64(max(0, metadata.size))
        let modifiedAt = metadata.modifiedAt
        guard modifiedAt >= start.addingTimeInterval(-sessionLookback) else { return nil }
        if let cached = cache[url.path],
           cached.size == size,
           cached.modifiedAt == modifiedAt,
           cached.dayStart == start {
            return cached.todayTokens
        }

        let total = parseSessionTodayTokens(at: url, start: start, end: end)
        cache[url.path] = CacheEntry(
            size: size,
            modifiedAt: modifiedAt,
            dayStart: start,
            todayTokens: total
        )
        return total
    }

    private func parseSessionTodayTokens(at url: URL, start: Date, end: Date) -> Int64? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let decoder = JSONDecoder()
        // Codex normally emits compact JSON, but some versions/launchers add
        // whitespace around the colon. Match the event name rather than one
        // exact serialization so API-key sessions are not silently skipped.
        let marker = Data("token_count".utf8)
        var baseline: Int64 = 0
        var latestToday: Int64?

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

            if timestamp < start {
                baseline = max(baseline, tokens)
            } else if timestamp < end {
                latestToday = max(latestToday ?? 0, tokens)
            }
        }
        guard let latestToday else { return nil }
        return max(0, latestToday - baseline)
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
        var events: [(timestamp: Date, tokens: Int64)] = []

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
            events.append((timestamp, tokens))
        }
        guard !events.isEmpty else { return nil }
        events.sort { $0.timestamp < $1.timestamp }

        var result: [String: Int64] = [:]
        var previous: Int64?
        var foundInRange = false
        for event in events {
            if event.timestamp < start {
                // 取窗口前最后一次值，而不是最大值；压缩等场景会重置累计计数器。
                previous = event.tokens
                continue
            }
            foundInRange = true
            let delta: Int64
            if let previous {
                delta = event.tokens >= previous ? event.tokens - previous : event.tokens
            } else {
                delta = event.tokens
            }
            let day = formatter.string(from: event.timestamp)
            let current = result[day] ?? 0
            let (next, overflow) = current.addingReportingOverflow(max(0, delta))
            result[day] = overflow ? Int64.max : next
            previous = event.tokens
        }
        return foundInRange ? result : nil
    }

    private func parseTimestamp(_ raw: String) -> Date? {
        fractionalISO8601.date(from: raw) ?? basicISO8601.date(from: raw)
    }
}

/// `thread/list` 无法感知另一个 Codex 进程的 turn 时，从共享 session JSONL 判断最近线程是否仍在执行。
struct LocalCodexActivity: Sendable {
    var threadID: String
    var cwd: String?
    var modifiedAt: Date
    var startedAt: Date?
    var state: CodexRunState
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
                modifiedAt: candidate.modifiedAt,
                startedAt: cached.analysis.startedAt,
                state: cached.analysis.state
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
            modifiedAt: candidate.modifiedAt,
            startedAt: cached.analysis.startedAt,
            state: cached.analysis.state
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
            return SessionAnalysis(isActive: false, startedAt: nil, state: .idle)
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > tailByteCount ? size - tailByteCount : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return SessionAnalysis(isActive: false, startedAt: nil, state: .idle)
        }

        // 从文件中段开始读取时，第一行可能是不完整 JSON。
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }

        var isActive = false
        var startedAt: Date?
        var recognizedEvent = false
        var state: CodexRunState = .thinking

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let envelopeType = object["type"] as? String else {
                continue
            }
            let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp)

            // 自动续跑或上下文压缩后不一定再次写入 user_message，turn_context 本身
            // 就代表一个新 turn 已开始，避免仍沿用上一轮 task_complete 的空闲状态。
            if envelopeType == "turn_context" || envelopeType == "compacted" {
                recognizedEvent = true
                isActive = true
                startedAt = startedAt ?? timestamp
                state = .thinking
                continue
            }

            guard let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String else {
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
                case "agent_reasoning", "agent_message":
                    recognizedEvent = true
                    isActive = true
                    startedAt = startedAt ?? timestamp
                    state = payloadType == "agent_reasoning" ? .thinking : .generatingCode
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
            state: resolvedActive ? state : .idle
        )
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
