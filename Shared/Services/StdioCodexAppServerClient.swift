import Foundation

#if os(macOS)
import AppKit
import Darwin
#endif

#if os(macOS)
/// 直接监听 Codex session JSONL 的追加写入。相比定时 stat，状态变化可在文件落盘后立即送达。
private final class CodexSessionFileWatcher: @unchecked Sendable {
    private struct FileSignature: Equatable {
        var size: Int
        var modifiedAt: Date
    }

    private let queue = DispatchQueue(label: "com.codexpulse.session-watcher", qos: .userInitiated)
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var monitoredURLs: [String: URL] = [:]
    private var signatures: [String: FileSignature] = [:]
    private var pendingDeliveries: [String: DispatchWorkItem] = [:]
    private var fallbackTimer: DispatchSourceTimer?
    private let onChange: @Sendable (URL) -> Void

    init(onChange: @escaping @Sendable (URL) -> Void) {
        self.onChange = onChange
    }

    func replaceFiles(_ urls: [URL]) {
        queue.async { [weak self] in
            guard let self else { return }
            let wanted = Set(urls.map(\.path))
            for path in Array(self.sources.keys) where !wanted.contains(path) {
                self.sources.removeValue(forKey: path)?.cancel()
                self.monitoredURLs.removeValue(forKey: path)
                self.signatures.removeValue(forKey: path)
            }
            for url in urls where self.sources[url.path] == nil {
                self.addFile(url)
            }
            self.updateFallbackTimer()
        }
    }

    func stop() {
        queue.sync {
            pendingDeliveries.values.forEach { $0.cancel() }
            pendingDeliveries.removeAll()
            fallbackTimer?.cancel()
            fallbackTimer = nil
            let current = Array(sources.values)
            sources.removeAll()
            monitoredURLs.removeAll()
            signatures.removeAll()
            current.forEach { $0.cancel() }
        }
    }

    private func addFile(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleDelivery(for: url)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        sources[url.path] = source
        monitoredURLs[url.path] = url
        signatures[url.path] = signature(of: url)
        source.resume()
    }

    /// vnode 是主通道；独立 100ms 文件签名检查是可靠性兜底。
    /// 它运行在客户端 I/O 队列，不依赖 SwiftUI/MainActor 或远端 RPC。
    private func updateFallbackTimer() {
        if sources.isEmpty {
            fallbackTimer?.cancel()
            fallbackTimer = nil
            return
        }
        guard fallbackTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(100),
            repeating: .milliseconds(100),
            leeway: .milliseconds(15)
        )
        timer.setEventHandler { [weak self] in
            self?.pollFileSignatures()
        }
        fallbackTimer = timer
        timer.resume()
        PulseLog.write("realtime session monitor armed: \(sources.count) path(s), 100ms fallback")
    }

    private func pollFileSignatures() {
        for (path, url) in monitoredURLs {
            guard let current = signature(of: url) else { continue }
            let previous = signatures[path]
            signatures[path] = current
            if let previous, previous != current {
                scheduleDelivery(for: url)
            }
        }
    }

    private func signature(of url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let type = attributes[.type] as? FileAttributeType
        guard type == .typeRegular || type == .typeDirectory else { return nil }
        return FileSignature(
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            modifiedAt: (attributes[.modificationDate] as? Date) ?? .distantPast
        )
    }

    /// 一次 JSONL 事件可能分成数个 vnode 通知；合并 20ms，既避免重复解析又保持即时。
    private func scheduleDelivery(for url: URL) {
        if let current = signature(of: url) {
            signatures[url.path] = current
        }
        pendingDeliveries[url.path]?.cancel()
        let work = DispatchWorkItem { [weak self, onChange] in
            self?.pendingDeliveries.removeValue(forKey: url.path)
            onChange(url)
        }
        pendingDeliveries[url.path] = work
        queue.asyncAfter(deadline: .now() + .milliseconds(20), execute: work)
    }
}
#else
private final class CodexSessionFileWatcher: @unchecked Sendable {
    init(onChange: @escaping @Sendable (URL) -> Void) {}
    func replaceFiles(_ urls: [URL]) {}
    func stop() {}
}
#endif

#if os(macOS)
/// Codex 在 ChatGPT / API Key 之间切换时会改写 auth.json，但已运行的
/// app-server 不一定重新载入凭据。独立监听文件签名并通知 Store 重建连接。
private final class CodexAuthenticationFileWatcher: @unchecked Sendable {
    private struct Signature: Equatable {
        let size: UInt64
        let modifiedAt: TimeInterval
        let fileNumber: UInt64
        /// auth.json 可能被同长度内容原位覆盖，单看文件元数据会漏检。
        /// 这里只保留不可逆向使用的内存指纹，不记录或输出任何认证内容。
        let contentFingerprint: UInt64
    }

    private struct FileState: Equatable {
        let signature: Signature?
    }

    private let queue = DispatchQueue(label: "com.codexpulse.auth-watcher", qos: .utility)
    private let onChange: @Sendable () -> Void
    private var timer: DispatchSourceTimer?
    private var authURL: URL?
    private var lastState: FileState?
    private var pendingState: FileState?

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start(codexHome: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            let configuredHome = codexHome?.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = (configuredHome?.isEmpty == false ? configuredHome : nil)
                ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true).path
            let expandedRoot = NSString(string: root).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedRoot, isDirectory: true)
                .appendingPathComponent("auth.json", isDirectory: false)
            self.authURL = url
            self.lastState = FileState(signature: self.signature(of: url))
            self.pendingState = nil

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + .milliseconds(250),
                repeating: .milliseconds(500),
                leeway: .milliseconds(80)
            )
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
            PulseLog.write("authentication watcher armed")
        }
    }

    func stop() {
        queue.sync { stopLocked() }
    }

    private func stopLocked() {
        timer?.cancel()
        timer = nil
        authURL = nil
        lastState = nil
        pendingState = nil
    }

    private func poll() {
        guard let authURL else { return }
        let next = FileState(signature: signature(of: authURL))
        guard let lastState else {
            self.lastState = next
            return
        }
        guard next != lastState else {
            pendingState = nil
            return
        }

        // 登录流程可能先截断再重写 auth.json。要求连续两次采样完全一致，
        // 既避免用半写入文件重启，也能在约 0.5–1 秒内稳定识别切号。
        guard pendingState == next else {
            pendingState = next
            return
        }

        self.lastState = next
        pendingState = nil
        PulseLog.write("authentication file changed; requesting app-server restart")
        onChange()
    }

    private func signature(of url: URL) -> Signature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return Signature(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modifiedAt: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            contentFingerprint: Self.fingerprint(data)
        )
    }

    /// FNV-1a 仅用于变更比较；认证内容不会离开当前进程。
    private static func fingerprint(_ data: Data) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }
}
#else
private final class CodexAuthenticationFileWatcher: @unchecked Sendable {
    init(onChange: @escaping @Sendable () -> Void) {}
    func start(codexHome: String?) {}
    func stop() {}
}
#endif

private struct CodexLocalCredentials: Sendable {
    let accessToken: String
    let accountID: String?
}

private struct ResetCreditDetailsResponse: Sendable {
    let availableCount: Int?
    /// nil 表示官方响应未带卡片数组；空数组表示明确没有卡片。
    let cards: [RateLimitResetCard]?
}

/// 生产环境：spawn `codex app-server`，JSONL JSON-RPC over stdin/stdout
/// 协议：https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
final class StdioCodexAppServerClient: CodexAppServerClient, @unchecked Sendable {
    private(set) var isConnected = false

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private let queue = DispatchQueue(label: "com.codexpulse.appserver.io")
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var pendingTimeouts: [Int: DispatchWorkItem] = [:]
    private var pendingMethods: [Int: String] = [:]
    private var silentPendingIDs: Set<Int> = []
    private var eventContinuation: AsyncStream<CodexServerEvent>.Continuation?
    private var readBuffer = Data()
    private var stdoutSource: DispatchSourceRead?
    private var serverCodexHome: String?
    private var cliVersionHint: String?
    private let cacheQueue = DispatchQueue(label: "com.codexpulse.appserver.cache")
    private var rateLimitsCache: (value: RateLimitSnapshot, fetchedAt: Date)?
    private var usageCache: (value: UsageStats, fetchedAt: Date, dayKey: String)?
    private var resetCreditDetailsCache: (value: ResetCreditDetailsResponse, fetchedAt: Date)?
    /// 最近一次 thread/list 返回的线程顺序，供不走 RPC 的实时本地状态通道定位旧会话文件。
    private var recentThreadIDs: [String] = []
    private var rateLimitsRetryAfter: Date?
    private var rateLimitsFailureCount = 0
    /// 高频今日指标与全历史汇总使用独立 actor，避免首次历史扫描占住串行队列，
    /// 导致缓存命中率和今日成本虽然已收到文件事件却迟迟不能显示。
    private let realtimeLocalUsageReader = LocalCodexUsageReader()
    private lazy var sessionFileWatcher = CodexSessionFileWatcher { [weak self] url in
        guard let self else { return }
        self.handleSessionFileChange(url)
    }
    private lazy var authenticationFileWatcher = CodexAuthenticationFileWatcher { [weak self] in
        self?.eventContinuation?.yield(.authenticationChanged)
    }

    /// 线程、账号等轻量 RPC 保持快速失败；远端 profile 类接口允许更长响应时间。
    private let defaultRPCTimeout: TimeInterval = 12
    private let profileRPCTimeout: TimeInterval = 25
    // 活跃轮询为 5 秒：额度缓存保持在 4 秒以内；远端 usage 最多缓存
    // 10 秒，本机今日 Token 仍在每次读取时即时合并。
    private let rateLimitsCacheTTL: TimeInterval = 4
    private let usageCacheTTL: TimeInterval = 10
    private let resetCreditDetailsCacheTTL: TimeInterval = 60
    private let rateLimitsFailureBackoff: TimeInterval = 30
    private let rateLimitsMaxBackoff: TimeInterval = 300
    private static let cliDiscoveryQueue = DispatchQueue(label: "com.codexpulse.cli-discovery")
    private static var cachedCLIPath: String?

    private static let resetCreditDetailsSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    // MARK: - Connect / disconnect

    func connect() async throws {
        if isConnected { return }

        let cli = try Self.findCodexCLI()
        cliVersionHint = Self.probeCLIVersion(at: cli)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = ["app-server"]
        // Finder/Xcode 启动时继承的 cwd 可能位于桌面、文稿或下载目录，子进程
        // 第一次访问会触发 macOS 文件授权。app-server 不需要项目 cwd，固定到
        // Codex 自己的隐藏数据目录，避免每次启动重复请求受保护文件夹权限。
        proc.currentDirectoryURL = Self.safeCodexWorkingDirectory()
        // Prefer explicit stdio listen if supported; bare `app-server` defaults to stdio.

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] p in
            self?.queue.async {
                self?.handleProcessExit(code: p.terminationStatus)
            }
        }

        do {
            try proc.run()
        } catch {
            throw CodexServerError.processFailed(error.localizedDescription)
        }

        process = proc
        stdinHandle = inPipe.fileHandleForWriting
        stdoutHandle = outPipe.fileHandleForReading
        stderrHandle = errPipe.fileHandleForReading

        startStdoutReader()
        startStderrLogger()

        // Handshake: initialize → initialized
        do {
            let initResult = try await rpcRaw(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "codex_pulse",
                        "title": "Codex-Pulse",
                        "version": "0.1.0"
                    ],
                    "capabilities": [
                        "experimentalApi": false,
                        "optOutNotificationMethods": [
                            "item/agentMessage/delta",
                            "item/reasoning/summaryTextDelta",
                            "item/reasoning/summaryPartAdded",
                            "item/reasoning/textDelta",
                            "item/commandExecution/outputDelta",
                            "item/fileChange/outputDelta"
                        ]
                    ]
                ]
            )
            if let obj = try? JSONSerialization.jsonObject(with: initResult) as? [String: Any] {
                serverCodexHome = obj["codexHome"] as? String
            }

            try writeNotification(method: "initialized", params: [:])
            isConnected = true
            authenticationFileWatcher.start(codexHome: serverCodexHome)
            eventContinuation?.yield(.connectionRestored)
        } catch {
            await disconnect()
            throw error
        }
    }

    func disconnect() async {
        sessionFileWatcher.stop()
        authenticationFileWatcher.stop()
        queue.sync {
            for (_, cont) in pending {
                cont.resume(throwing: CodexServerError.notConnected)
            }
            pending.removeAll()
            pendingMethods.removeAll()
            silentPendingIDs.removeAll()
            pendingTimeouts.values.forEach { $0.cancel() }
            pendingTimeouts.removeAll()
        }
        stdoutSource?.cancel()
        stdoutSource = nil
        try? stdinHandle?.close()
        process?.terminate()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        isConnected = false
        readBuffer = Data()
    }

    // MARK: - API

    func readAccount() async throws -> AccountInfo {
        let data = try await rpcRaw(method: "account/read", params: ["refreshToken": false])
        let wire = try decode(WireGetAccountResponse.self, from: data)
        return ProtocolMapper.account(from: wire, cliVersion: cliVersionHint)
    }

    func readRateLimits(forceRefresh: Bool) async throws -> RateLimitSnapshot {
        if !forceRefresh {
            if let cached = cachedRateLimits(maxAge: rateLimitsCacheTTL) {
                PulseLog.write("rateLimits cache hit")
                return cached
            }
            if isRateLimitsBackoffActive() {
                throw CodexServerError.requestDeferred
            }
        }

        do {
            let limits = try await fetchRateLimitsWithRetry()
            storeRateLimitsCache(limits)
            return limits
        } catch {
            let delay = deferRateLimitsRetry()
            PulseLog.write("rateLimits remote retry deferred for \(Int(delay))s")
            throw error
        }
    }

    private func fetchRateLimitsWithRetry() async throws -> RateLimitSnapshot {
        do {
            return try await readRateLimitsOnce()
        } catch {
            guard case CodexServerError.rpcError(-32603, let message) = error else { throw error }
            let lower = message.lowercased()
            let connectionFailureMarkers = [
                "error sending request",
                "dns",
                "certificate",
                "connection refused",
                "connection reset"
            ]
            guard !connectionFailureMarkers.contains(where: { lower.contains($0) }) else {
                PulseLog.write("rateLimits connection failure; skip immediate retry")
                throw error
            }
            PulseLog.write("rateLimits -32603, retry once after 1.5s…")
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await readRateLimitsOnce()
        }
    }

    private func readRateLimitsOnce() async throws -> RateLimitSnapshot {
        // App Server 的额度响应目前只包含重置卡数量；官方桌面端另用该接口读取卡片明细。
        // 两个请求并发进行，明细失败不会拖垮或覆盖主额度数据。
        async let resetCreditDetails = readResetCreditDetailsSafely()
        let data = try await rpcRaw(
            method: "account/rateLimits/read",
            params: [:],
            timeout: profileRPCTimeout
        )
        let wire = try RateLimitsWireParser.parse(data)
        var snapshot = ProtocolMapper.rateLimits(from: wire)
        if let details = await resetCreditDetails,
           let cards = details.cards,
           !cards.isEmpty || details.availableCount == 0 {
            snapshot.resetCards = cards
        }
        return snapshot
    }

    func readUsage(forceRefresh: Bool) async throws -> UsageStats {
        if !forceRefresh, let cached = cachedUsage(maxAge: usageCacheTTL) {
            PulseLog.write("usage cache hit; refreshing device-local session totals")
            return await mergingLocalUsage(into: cached)
        }

        do {
            let data = try await rpcRaw(
                method: "account/usage/read",
                params: [:],
                timeout: profileRPCTimeout
            )
            if let preview = String(data: data, encoding: .utf8) {
                let clip = preview.count > 900 ? String(preview.prefix(900)) + "…" : preview
                PulseLog.write("account/usage/read raw: \(PulseLog.redact(clip))")
            }
            let wire: WireGetAccountTokenUsageResponse
            do {
                wire = try decode(WireGetAccountTokenUsageResponse.self, from: data)
            } catch {
                PulseLog.write("usage decode fail: \(error)")
                // 宽松：去掉 result 包装再解
                if let obj = try? JSONSerialization.jsonObject(with: data),
                   let re = try? JSONSerialization.data(withJSONObject: obj),
                   let alt = try? JSONDecoder().decode(WireGetAccountTokenUsageResponse.self, from: re) {
                    let mapped = ProtocolMapper.usage(from: alt)
                    storeUsageCache(mapped)
                    return await mergingLocalUsage(into: mapped)
                }
                let fallback = ProtocolMapper.emptyUsage(note: "Token 数据解析失败")
                // 解析/网络瞬时失败不能占用 60 秒成功缓存，否则后续轮询一直命中空数据。
                return await mergingLocalUsage(into: fallback)
            }
            let mapped = ProtocolMapper.usage(from: wire)
            storeUsageCache(mapped)
            let stats = await mergingLocalUsage(into: mapped)
            PulseLog.write(
                "usage mapped total=\(stats.totalTokens.map(String.init) ?? "nil") today=\(stats.todayTokens.map(String.init) ?? "nil") buckets=\(stats.dailyBuckets.count)"
            )
            return stats
        } catch {
            if var cached = cachedUsage(maxAge: .greatestFiniteMagnitude) {
                cached.sourceNote = "Token 远端统计刷新失败，已保留最近数据：\(error.localizedDescription)"
                PulseLog.write("usage remote fail; using cached summary: \(error.localizedDescription)")
                return await mergingLocalUsage(into: cached)
            }
            // API-key / 无权限：软失败并带说明，避免整页 Token 全是 —
            if case CodexServerError.rpcError(_, let msg) = error {
                let lower = msg.lowercased()
                if lower.contains("not") || lower.contains("unauth") || lower.contains("unsupported")
                    || lower.contains("permission") || lower.contains("forbidden") {
                    let fallback = ProtocolMapper.emptyUsage(
                        note: "当前账号未返回 Token 活跃统计（\(msg)）"
                    )
                    // 明确不支持/无权限属于稳定结果，可以短期缓存避免重复打接口。
                    storeUsageCache(fallback)
                    return await mergingLocalUsage(into: fallback)
                }
                let fallback = ProtocolMapper.emptyUsage(note: "Token 统计 RPC 失败：\(msg)")
                return await mergingLocalUsage(into: fallback)
            }
            if case CodexServerError.timeout = error {
                let fallback = ProtocolMapper.emptyUsage(note: "Token 统计请求超时")
                return await mergingLocalUsage(into: fallback)
            }
            let fallback = ProtocolMapper.emptyUsage(
                note: "Token 统计暂不可用：\(error.localizedDescription)"
            )
            return await mergingLocalUsage(into: fallback)
        }
    }

    func readLocalUsage(merging cached: UsageStats) async -> UsageStats {
        await mergingLocalUsage(into: cached)
    }

    func readRealtimeLocalUsage(merging cached: UsageStats) async -> UsageStats {
        var merged = cached
        if let localToday = await realtimeLocalUsageReader.todayUsageSummary(
            codexHome: serverCodexHome
        ) {
            merged.mergeLocalTodayTokens(localToday.totalTokens)
            merged.mergeLocalTodayBreakdown(
                inputTokens: localToday.inputTokens,
                cachedInputTokens: localToday.cachedInputTokens,
                outputTokens: localToday.outputTokens,
                estimatedCostUSD: localToday.estimatedCostUSD,
                uncachedInputCostUSD: localToday.uncachedInputCostUSD,
                cachedInputCostUSD: localToday.cachedInputCostUSD,
                outputCostUSD: localToday.outputCostUSD
            )
        }
        return merged
    }

    func invalidateAccountScopedState() {
        cacheQueue.sync {
            rateLimitsCache = nil
            usageCache = nil
            resetCreditDetailsCache = nil
            rateLimitsRetryAfter = nil
            rateLimitsFailureCount = 0
        }
        cancelPendingAccountRequests()
        PulseLog.write("account-scoped caches and rate-limit backoff cleared")
    }

    private func cancelPendingAccountRequests() {
        let accountMethods: Set<String> = [
            "account/read",
            "account/rateLimits/read",
            "account/usage/read"
        ]
        queue.async {
            let ids = self.pendingMethods.compactMap { id, method in
                accountMethods.contains(method) ? id : nil
            }
            for id in ids {
                self.pendingTimeouts.removeValue(forKey: id)?.cancel()
                self.pendingMethods.removeValue(forKey: id)
                self.silentPendingIDs.remove(id)
                if let continuation = self.pending.removeValue(forKey: id) {
                    continuation.resume(throwing: CodexServerError.requestDeferred)
                }
            }
            if !ids.isEmpty {
                PulseLog.write("cancelled \(ids.count) stale account-scoped RPC request(s)")
            }
        }
    }

    private func mergingLocalUsage(into usage: UsageStats) async -> UsageStats {
        var merged = usage
        async let localTodayTask = LocalCodexUsageReader.shared.todayUsageSummary(
            codexHome: serverCodexHome
        )
        async let localDailyTask = LocalCodexUsageReader.shared.last7DaysBuckets(codexHome: serverCodexHome)
        async let localHistoryTask = LocalCodexUsageReader.shared.allTimeSummary(codexHome: serverCodexHome)
        if let localToday = await localTodayTask {
            merged.mergeLocalTodayTokens(localToday.totalTokens)
            merged.mergeLocalTodayBreakdown(
                inputTokens: localToday.inputTokens,
                cachedInputTokens: localToday.cachedInputTokens,
                outputTokens: localToday.outputTokens,
                estimatedCostUSD: localToday.estimatedCostUSD,
                uncachedInputCostUSD: localToday.uncachedInputCostUSD,
                cachedInputCostUSD: localToday.cachedInputCostUSD,
                outputCostUSD: localToday.outputCostUSD
            )
        }
        if let localDaily = await localDailyTask {
            merged.mergeLocalDailyBuckets(localDaily)
        }
        if let localHistory = await localHistoryTask {
            merged.mergeLocalTotalTokens(
                localHistory.totalTokens,
                estimatedCostUSD: localHistory.estimatedCostUSD
            )
            merged.mergeLocalStreak(
                currentDays: localHistory.streak.currentDays,
                longestDays: localHistory.streak.longestDays
            )
        }
        return merged
    }

    // MARK: - Reset credit details

    /// 官方 App Server 汇总仅返回 availableCount。此处复用 Codex 本地登录凭据访问
    /// ChatGPT 官方桌面端使用的明细接口，不读取浏览器 Cookie，也不记录任何令牌。
    private func readResetCreditDetailsSafely() async -> ResetCreditDetailsResponse? {
        if let cached = cachedResetCreditDetails(maxAge: resetCreditDetailsCacheTTL) {
            return cached
        }

        do {
            let details = try await fetchResetCreditDetails()
            storeResetCreditDetails(details)
            return details
        } catch {
            PulseLog.write("reset credit details unavailable: \(error.localizedDescription)")
            return cachedResetCreditDetails(maxAge: .greatestFiniteMagnitude)
        }
    }

    private func fetchResetCreditDetails() async throws -> ResetCreditDetailsResponse {
        let credentials = try readCodexCredentials()
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits") else {
            throw CodexServerError.invalidResponse("invalid reset credit details URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await Self.resetCreditDetailsSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexServerError.invalidResponse("reset credit details response is not HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CodexServerError.unauthorized
            }
            throw CodexServerError.invalidResponse("reset credit details HTTP \(http.statusCode)")
        }
        return try Self.parseResetCreditDetails(data)
    }

    private func readCodexCredentials() throws -> CodexLocalCredentials {
        let codexHome: URL
        if let serverCodexHome, !serverCodexHome.isEmpty {
            codexHome = URL(fileURLWithPath: serverCodexHome)
        } else {
            codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        }
        let authURL = codexHome.appendingPathComponent("auth.json")
        let data = try Data(contentsOf: authURL, options: .mappedIfSafe)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            throw CodexServerError.unauthorized
        }
        return CodexLocalCredentials(
            accessToken: accessToken,
            accountID: tokens["account_id"] as? String
        )
    }

    private static func parseResetCreditDetails(_ data: Data) throws -> ResetCreditDetailsResponse {
        guard let rawRoot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexServerError.invalidResponse("reset credit details root not object")
        }
        let root = (rawRoot["data"] as? [String: Any]) ?? rawRoot
        let availableCount = flexibleInt(root["available_count"] ?? root["availableCount"])
        let rawCredits = root["credits"] as? [[String: Any]]
        let cards = rawCredits?.enumerated().map { index, credit in
            let id = string(credit["id"]) ?? "reset-credit-detail-\(index)"
            let status = string(credit["status"])?.lowercased() ?? "available"
            let types = stringArray(
                credit["applicable_limit_types"]
                    ?? credit["applicableLimitTypes"]
                    ?? credit["eligible_limit_types"]
            )
            let resetType = string(credit["reset_type"] ?? credit["resetType"])
            return RateLimitResetCard(
                id: id,
                acquiredAt: serverDate(
                    credit["granted_at"]
                        ?? credit["grantedAt"]
                        ?? credit["acquired_at"]
                        ?? credit["acquiredAt"]
                ),
                expiresAt: serverDate(credit["expires_at"] ?? credit["expiresAt"]),
                applicableLimitTypes: types.isEmpty ? resetType.map { [$0] } ?? [] : types,
                isAvailable: status == "available"
            )
        }
        let resolvedAvailableCount = availableCount ?? cards.map { $0.filter(\.isAvailable).count }
        return ResetCreditDetailsResponse(availableCount: resolvedAvailableCount, cards: cards)
    }

    private static func flexibleInt(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as Int64: return Int(value)
        case let value as Double: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.compactMap(string) }
        if let value = string(value), !value.isEmpty { return [value] }
        return []
    }

    private static func serverDate(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            let normalized = seconds > 10_000_000_000 ? seconds / 1_000 : seconds
            return Date(timeIntervalSince1970: normalized)
        }
        guard let text = string(value), !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
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

    private func cachedResetCreditDetails(maxAge: TimeInterval) -> ResetCreditDetailsResponse? {
        cacheQueue.sync {
            guard let cache = resetCreditDetailsCache,
                  Date().timeIntervalSince(cache.fetchedAt) <= maxAge else { return nil }
            return cache.value
        }
    }

    private func storeResetCreditDetails(_ details: ResetCreditDetailsResponse) {
        cacheQueue.sync {
            resetCreditDetailsCache = (details, Date())
        }
    }

    func listRecentThreads(limit: Int) async throws -> [TaskRecord] {
        try await listThreads(limit: limit, logTraffic: true)
    }

    func listLiveThreads(limit: Int) async throws -> [TaskRecord] {
        guard isConnected else { throw CodexServerError.notConnected }
        let hints = cacheQueue.sync { recentThreadIDs }
        let localActivities = await LocalCodexActivityReader.shared.activeThreads(
            codexHome: serverCodexHome,
            limit: limit,
            hintedThreadIDs: hints
        )
        let watchURLs = await LocalCodexActivityReader.shared.realtimeSessionURLs(
            hintedThreadIDs: hints
        )
        sessionFileWatcher.replaceFiles(watchURLs)
        return localActivities.map(localTaskRecord)
    }

    private func listThreads(limit: Int, logTraffic: Bool) async throws -> [TaskRecord] {
        let data = try await rpcRaw(
            method: "thread/list",
            params: [
                "limit": limit,
                "archived": false
            ],
            timeout: logTraffic ? nil : 3,
            logTraffic: logTraffic
        )
        let wire = try decode(WireThreadListResponse.self, from: data)
        var tasks = ProtocolMapper.tasks(from: wire)
        cacheQueue.sync {
            recentThreadIDs = Array(tasks.map(\.id).prefix(100))
        }

        // 独立启动的 app-server 会把 Codex 桌面正在运行的线程标为 notLoaded；
        // 用共享 session JSONL 的未完成 turn 补成实时状态，支持多个并行 Codex 任务。
        let localActivities = await LocalCodexActivityReader.shared.activeThreads(
            codexHome: serverCodexHome,
            limit: limit,
            hintedThreadIDs: tasks.map(\.id)
        )
        let watchURLs = await LocalCodexActivityReader.shared.realtimeSessionURLs(
            hintedThreadIDs: tasks.map(\.id)
        )
        sessionFileWatcher.replaceFiles(watchURLs)
        var localTasks: [TaskRecord] = []
        for local in localActivities {
            if let index = tasks.firstIndex(where: { $0.id == local.threadID }) {
                var task = tasks.remove(at: index)
                if task.runState?.isActive != true
                    && task.runState != .awaitingAuthorization
                    && task.runState != .awaitingInput {
                    task.runState = local.state
                } else if local.state.needsAttention {
                    task.runState = local.state
                }
                task.projectPath = task.projectPath ?? local.cwd
                task.model = task.model ?? local.model
                task.reasoningEffort = task.reasoningEffort ?? local.reasoningEffort
                task.tokenUsage = local.totalTokens ?? task.tokenUsage
                task.lastTokenUsage = local.lastUsageTokens
                task.finishedAt = max(task.finishedAt, local.modifiedAt)
                task.startedAt = local.startedAt ?? task.startedAt
                task.conversation = local.conversation
                localTasks.append(task)
            } else {
                localTasks.append(localTaskRecord(local))
            }
        }
        tasks.insert(contentsOf: localTasks, at: 0)
        return Array(tasks.prefix(limit))
    }

    private func localTaskRecord(_ local: LocalCodexActivity) -> TaskRecord {
        let path = local.cwd
        return TaskRecord(
            id: local.threadID,
            projectName: path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex",
            projectPath: path,
            gitBranch: nil,
            model: local.model,
            tokenUsage: local.totalTokens,
            durationSeconds: 0,
            succeeded: true,
            filesChanged: 0,
            summary: "正在 Codex 中处理",
            finishedAt: local.modifiedAt,
            runState: local.state,
            activeFlags: nil,
            startedAt: local.startedAt,
            conversation: local.conversation,
            reasoningEffort: local.reasoningEffort,
            lastTokenUsage: local.lastUsageTokens
        )
    }

    private func handleSessionFileChange(_ url: URL) {
        Task { [weak self] in
            guard let self else { return }
            if let activity = await LocalCodexActivityReader.shared.activitySnapshot(at: url) {
                let record = self.localTaskRecord(activity)
                self.queue.async {
                    if let limits = activity.rateLimits {
                        self.eventContinuation?.yield(.localRateLimitsUpdated(limits))
                    }
                    self.eventContinuation?.yield(.localTaskStateChanged(record))
                }
            } else {
                // 目录变化通常表示创建了新会话文件；由轻量扫描发现并接入监听。
                self.queue.async {
                    self.eventContinuation?.yield(.threadsChanged)
                }
            }
        }
    }

    func eventStream() -> AsyncStream<CodexServerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.eventContinuation = nil
            }
        }
    }

    // MARK: - RPC core

    private func rpcRaw(
        method: String,
        params: [String: Any],
        timeout: TimeInterval? = nil,
        logTraffic: Bool = true
    ) async throws -> Data {
        guard process?.isRunning == true else {
            throw CodexServerError.notConnected
        }
        let timeoutInterval = timeout ?? defaultRPCTimeout
        let id: Int = queue.sync {
            let i = nextID
            nextID += 1
            return i
        }
        let payload = try RPCWire.encodeRequest(id: id, method: method, params: params)
        if logTraffic {
            PulseLog.write("→ RPC #\(id) \(method)")
        }

        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.pending[id] = cont
                self.pendingMethods[id] = method
                if !logTraffic {
                    self.silentPendingIDs.insert(id)
                }

                // 超时：避免 id 解析失败或服务端无响应时永久挂起
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if let hung = self.pending.removeValue(forKey: id) {
                        self.pendingTimeouts.removeValue(forKey: id)
                        self.pendingMethods.removeValue(forKey: id)
                        self.silentPendingIDs.remove(id)
                        if logTraffic {
                            PulseLog.write("✗ RPC #\(id) \(method) timeout after \(Int(timeoutInterval))s")
                        }
                        hung.resume(throwing: CodexServerError.timeout)
                    }
                }
                self.pendingTimeouts[id] = timeout
                self.queue.asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)

                do {
                    try self.stdinHandle?.write(contentsOf: payload)
                } catch {
                    self.pendingTimeouts.removeValue(forKey: id)?.cancel()
                    self.pending.removeValue(forKey: id)
                    self.pendingMethods.removeValue(forKey: id)
                    self.silentPendingIDs.remove(id)
                    cont.resume(throwing: CodexServerError.processFailed(error.localizedDescription))
                }
            }
        }
    }

    private func cachedRateLimits(maxAge: TimeInterval) -> RateLimitSnapshot? {
        cacheQueue.sync {
            guard let cache = rateLimitsCache,
                  Date().timeIntervalSince(cache.fetchedAt) <= maxAge else { return nil }
            return cache.value
        }
    }

    private func storeRateLimitsCache(_ limits: RateLimitSnapshot) {
        cacheQueue.sync {
            rateLimitsCache = (limits, Date())
            rateLimitsRetryAfter = nil
            rateLimitsFailureCount = 0
        }
    }

    private func isRateLimitsBackoffActive() -> Bool {
        cacheQueue.sync {
            guard let retryAfter = rateLimitsRetryAfter else { return false }
            return retryAfter > Date()
        }
    }

    private func deferRateLimitsRetry() -> TimeInterval {
        cacheQueue.sync {
            rateLimitsFailureCount += 1
            let exponent = min(rateLimitsFailureCount - 1, 4)
            let delay = min(
                rateLimitsMaxBackoff,
                rateLimitsFailureBackoff * pow(2, Double(exponent))
            )
            rateLimitsRetryAfter = Date().addingTimeInterval(delay)
            return delay
        }
    }

    private func mergeRateLimitsCache(_ incoming: RateLimitSnapshot) {
        guard !incoming.buckets.isEmpty else { return }
        cacheQueue.sync {
            guard let cached = rateLimitsCache else {
                rateLimitsCache = (incoming, Date())
                rateLimitsRetryAfter = nil
                rateLimitsFailureCount = 0
                return
            }

            var buckets = cached.value.buckets
            for bucket in incoming.buckets {
                if let index = buckets.firstIndex(where: { $0.id == bucket.id }) {
                    buckets[index] = bucket
                } else if let index = buckets.firstIndex(where: { $0.name == bucket.name }) {
                    buckets[index] = bucket
                } else {
                    buckets.append(bucket)
                }
            }
            let merged = RateLimitSnapshot(
                buckets: buckets,
                resetCards: incoming.resetCards.isEmpty
                    ? cached.value.resetCards
                    : incoming.resetCards,
                updatedAt: Date()
            )
            rateLimitsCache = (merged, Date())
            rateLimitsRetryAfter = nil
            rateLimitsFailureCount = 0
        }
    }

    private func cachedUsage(maxAge: TimeInterval) -> UsageStats? {
        cacheQueue.sync {
            guard let cache = usageCache,
                  cache.dayKey == UsageStats.dayFormatter().string(from: Date()),
                  Date().timeIntervalSince(cache.fetchedAt) <= maxAge else { return nil }
            return cache.value
        }
    }

    private func storeUsageCache(_ usage: UsageStats) {
        cacheQueue.sync {
            let now = Date()
            usageCache = (
                usage,
                now,
                UsageStats.dayFormatter().string(from: now)
            )
        }
    }

    private func writeNotification(method: String, params: [String: Any]) throws {
        let payload = try RPCWire.encodeNotification(method: method, params: params)
        try stdinHandle?.write(contentsOf: payload)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            throw CodexServerError.invalidResponse("\(T.self): \(error.localizedDescription) — \(preview)")
        }
    }

    // MARK: - Stdout line reader

    private func startStdoutReader() {
        guard let handle = stdoutHandle else { return }
        let fd = handle.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailableStdout()
        }
        source.setCancelHandler {
            // handle closed elsewhere
        }
        source.resume()
        stdoutSource = source
    }

    private func readAvailableStdout() {
        guard let handle = stdoutHandle else { return }
        let chunk = handle.availableData
        if chunk.isEmpty {
            // EOF
            handleProcessExit(code: process?.terminationStatus ?? -1)
            return
        }
        readBuffer.append(chunk)
        while let range = readBuffer.range(of: Data([0x0A])) {
            let line = readBuffer.subdata(in: readBuffer.startIndex..<range.lowerBound)
            readBuffer.removeSubrange(readBuffer.startIndex...range.lowerBound)
            if !line.isEmpty {
                handleLine(line)
            }
        }
    }

    private func handleLine(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            let preview = String(data: line.prefix(200), encoding: .utf8) ?? ""
            PulseLog.write("non-json line: \(preview)")
            return
        }

        // Response: has id + (result|error)
        // NSJSONSerialization often gives id as Double/NSNumber — must not only cast Int
        if let id = Self.jsonRPCId(obj["id"]) {
            pendingTimeouts.removeValue(forKey: id)?.cancel()
            pendingMethods.removeValue(forKey: id)
            let logTraffic = silentPendingIDs.remove(id) == nil
            if let cont = pending.removeValue(forKey: id) {
                if let err = obj["error"] as? [String: Any] {
                    let code = (err["code"] as? Int)
                        ?? (err["code"] as? NSNumber)?.intValue
                        ?? -1
                    let msg = err["message"] as? String ?? "RPC error"
                    if logTraffic { PulseLog.write("← RPC #\(id) error \(code): \(msg)") }
                    cont.resume(throwing: CodexServerError.rpcError(code, msg))
                } else if let result = obj["result"] {
                    if logTraffic { PulseLog.write("← RPC #\(id) ok") }
                    if let data = try? JSONSerialization.data(withJSONObject: result) {
                        cont.resume(returning: data)
                    } else if result is NSNull {
                        cont.resume(returning: Data("{}".utf8))
                    } else {
                        cont.resume(throwing: CodexServerError.invalidResponse("unserializable result"))
                    }
                } else {
                    cont.resume(returning: Data("{}".utf8))
                }
            } else {
                PulseLog.write("← RPC #\(id) late/unknown response")
            }
            return
        }

        // Notification / server request
        if let method = obj["method"] as? String {
            let params = obj["params"] as? [String: Any] ?? [:]
            if obj["id"] == nil {
                PulseLog.write("← notify \(method)")
                handleNotification(method: method, params: params)
            } else {
                PulseLog.write("Unhandled server request: \(method)")
            }
        }
    }

    /// JSON-RPC id 可能是 Int / Double / NSNumber / String
    private static func jsonRPCId(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        case let s as String: return Int(s)
        default: return nil
        }
    }

    /// Token 数值可能以 Int / NSNumber / Double / String 形式出现
    private static func flexibleInt64(_ any: Any?) -> Int64? {
        switch any {
        case let i as Int64: return i
        case let i as Int: return Int64(i)
        case let n as NSNumber: return n.int64Value
        case let d as Double: return Int64(d)
        case let s as String: return Int64(s)
        default: return nil
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "account/updated":
            // 通知先于 Store 的强制刷新到达；立即失效，避免任何并发轮询命中旧账号缓存。
            invalidateAccountScopedState()
            eventContinuation?.yield(.accountUpdated)

        case "account/rateLimits/updated":
            if let rateLimits = params["rateLimits"] {
                if let data = try? JSONSerialization.data(withJSONObject: ["rateLimits": rateLimits]),
                   let wire = try? RateLimitsWireParser.parse(data) {
                    let snap = ProtocolMapper.rateLimits(from: wire)
                    mergeRateLimitsCache(snap)
                    eventContinuation?.yield(.rateLimitsUpdated(snap))
                }
            }

        case "thread/status/changed":
            // 状态通知在不同 CLI 版本中的 params 结构不同，统一重新读取 thread/list。
            eventContinuation?.yield(.threadsChanged)

        case "thread/tokenUsage/updated":
            let threadID = params["threadId"] as? String ?? "unknown"
            let turnID = params["turnId"] as? String
            if let usage = params["tokenUsage"] as? [String: Any],
               let total = usage["total"] as? [String: Any],
               let totalTokens = Self.flexibleInt64(total["totalTokens"]),
               totalTokens >= 0 {
                eventContinuation?.yield(.tokenUsageUpdated(
                    threadID: threadID,
                    turnID: turnID,
                    totalTokens: totalTokens
                ))
            }

        case "turn/started":
            if let task = mapTurn(params, state: .thinking) {
                eventContinuation?.yield(.turnStarted(task))
            }

        case "turn/completed":
            let status = ((params["turn"] as? [String: Any])?["status"] as? String)?.lowercased()
            let runState: CodexRunState = {
                switch status {
                case "failed": return .failed
                case "interrupted": return .stopped
                case "completed": return .completed
                default: return .completed
                }
            }()
            if let task = mapTurn(params, state: runState) {
                eventContinuation?.yield(.turnCompleted(task))
            }

        case "item/agentMessage/delta":
            if let threadID = params["threadId"] as? String,
               let itemID = params["itemId"] as? String,
               let delta = params["delta"] as? String,
               !delta.isEmpty {
                eventContinuation?.yield(.agentMessageDelta(
                    threadID: threadID,
                    itemID: itemID,
                    delta: delta
                ))
            }

        case "item/started":
            let step = itemSummary(params)
            eventContinuation?.yield(.itemStarted(step))

        case "item/completed":
            let step = itemSummary(params)
            eventContinuation?.yield(.itemCompleted(step))

        default:
            break
        }
    }

    private func mapTurn(_ params: [String: Any], state: CodexRunState) -> CurrentTaskInfo? {
        let turn = params["turn"] as? [String: Any]
        let id = (turn?["id"] as? String) ?? UUID().uuidString
        let status = (turn?["status"] as? String) ?? state.rawValue

        // Best-effort fields — schema varies by version
        let cwd = turn?["cwd"] as? String
            ?? (params["thread"] as? [String: Any])?["cwd"] as? String
        let project = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let model = turn?["model"] as? String

        var runState = state
        switch status.lowercased() {
        case "inprogress", "in_progress": runState = .thinking
        case "completed": runState = .completed
        case "failed": runState = .failed
        case "interrupted": runState = .stopped
        default: break
        }

        return CurrentTaskInfo(
            id: id,
            projectName: project,
            projectPath: cwd,
            gitBranch: nil,
            model: model,
            reasoningEffort: turn?["effort"] as? String ?? turn?["reasoningEffort"] as? String,
            startedAt: Date(),
            state: runState,
            currentStep: nil,
            filesChanged: 0,
            linesAdded: 0,
            linesRemoved: 0,
            lastStatusMessage: status
        )
    }

    private func itemSummary(_ params: [String: Any]) -> String {
        if let item = params["item"] as? [String: Any] {
            if let type = item["type"] as? String {
                if let path = item["path"] as? String {
                    return "\(type): \(URL(fileURLWithPath: path).lastPathComponent)"
                }
                if let cmd = item["command"] as? String {
                    return "\(type): \(cmd.prefix(80))"
                }
                return type
            }
        }
        return "item"
    }

    private func handleProcessExit(code: Int32) {
        isConnected = false
        for (_, item) in pendingTimeouts { item.cancel() }
        pendingTimeouts.removeAll()
        for (_, cont) in pending {
            cont.resume(throwing: CodexServerError.processFailed("app-server exited (\(code))"))
        }
        pending.removeAll()
        PulseLog.write("app-server exited code=\(code)")
        eventContinuation?.yield(.connectionLost("app-server exited (\(code))"))
    }

    private func startStderrLogger() {
        guard let handle = stderrHandle else { return }
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let s = String(data: data, encoding: .utf8) {
                    PulseLog.write("[app-server stderr] \(s.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
    }

    // MARK: - CLI discovery

    static func findCodexCLI() throws -> String {
        try cliDiscoveryQueue.sync {
            if let cachedCLIPath,
               FileManager.default.isExecutableFile(atPath: cachedCLIPath) {
                return cachedCLIPath
            }

            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var candidates = [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                home + "/.local/bin/codex",
                home + "/.npm-global/bin/codex",
                home + "/.nvm/current/bin/codex",
                home + "/.volta/bin/codex",
                home + "/.asdf/shims/codex",
                home + "/.local/share/pnpm/codex",
                home + "/Library/pnpm/codex",
                home + "/.bun/bin/codex"
            ]
            let nvmVersions = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".nvm/versions/node", isDirectory: true)
            let versionDirectories = (try? FileManager.default.contentsOfDirectory(
                at: nvmVersions,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            candidates.append(contentsOf: versionDirectories
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/codex").path })

            if let resolved = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                cachedCLIPath = resolved
                return resolved
            }

            // 不启动 login shell，避免加载用户 shell profile、密码管理器、direnv
            // 等与 Codex-Pulse 无关的授权流程。仅使用现有 PATH 做最后兜底。
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = ["codex"]
            task.currentDirectoryURL = safeCodexWorkingDirectory()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                throw CodexServerError.cliNotFound
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
                throw CodexServerError.cliNotFound
            }
            cachedCLIPath = path
            return path
        }
    }

    static func isCLIInstalled() -> Bool {
        (try? findCodexCLI()) != nil
    }

    private static func probeCLIVersion(at path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--version"]
        task.currentDirectoryURL = safeCodexWorkingDirectory()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeCodexWorkingDirectory() -> URL {
        let fileManager = FileManager.default
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { NSString(string: $0).expandingTildeInPath }
        let codexHome = configured.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        if fileManager.fileExists(atPath: codexHome.path) {
            return codexHome
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let fallback = support.appendingPathComponent("CodexPulse/Runtime", isDirectory: true)
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
