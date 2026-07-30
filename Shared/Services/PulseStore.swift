import Foundation
import Observation

/// 应用核心状态：连接 App Server、聚合快照、写共享存储、触发通知
@MainActor
@Observable
final class PulseStore {
    var snapshot: PulseSnapshot = .empty
    var settings: PulseSettings = SettingsStore.shared.load()
    var lastError: String?
    var isRefreshing = false
    var isUsingMock = false
    var cliPath: String?
    var connectionDetail: String = "未连接"
    var lastWebhookStatus: String?
    var reconnectAttempt = 0
    var nextReconnectAt: Date?
    var lastRealConnectedAt: Date?
    var primaryRateLimitForecast: RateLimitForecast?
    var syncHealth: [PulseSyncService: PulseEndpointSyncHealth] = Dictionary(
        uniqueKeysWithValues: PulseSyncService.allCases.map { ($0, PulseEndpointSyncHealth.empty) }
    )

    var syncHealthSummary: String {
        let unavailable = PulseSyncService.allCases.filter {
            syncHealth[$0, default: .empty].level == .unavailable
        }
        if !unavailable.isEmpty {
            return "\(unavailable.map(\.displayName).joined(separator: "、"))同步异常"
        }
        let delayed = PulseSyncService.allCases.filter {
            syncHealth[$0, default: .empty].level == .delayed
        }
        if !delayed.isEmpty {
            return "\(delayed.map(\.displayName).joined(separator: "、"))同步波动"
        }
        let hasSuccess = syncHealth.values.contains { $0.lastSuccessAt != nil }
        return hasSuccess ? "数据同步正常" : "等待首次同步"
    }

    var syncHealthDetail: String {
        PulseSyncService.allCases.map { service in
            let health = syncHealth[service, default: .empty]
            if health.consecutiveFailures > 0 {
                return "\(service.displayName)连续失败 \(health.consecutiveFailures) 次"
            }
            return "\(service.displayName)正常"
        }.joined(separator: " · ")
    }

    private var client: (any CodexAppServerClient)?
    private var eventTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var rateLimitMonitorTask: Task<Void, Never>?
    private var dayRolloverTask: Task<Void, Never>?
    private var liveTaskStatusTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var pendingPersist = false
    private var refreshRequestedWhileBusy = false
    private var pendingForceRemoteRefresh = false
    /// 账号通知到达时递增；旧刷新即使稍后返回也不能覆盖新账号的空态/数据。
    private var accountRevision = 0
    private var isAccountTransitioning = false
    private var postTurnRefreshTask: Task<Void, Never>?
    private var localUsageRefreshTask: Task<Void, Never>?
    private var localUsageRefreshRevision = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectRecoveryID: UUID?
    private var startupDataRecoveryTask: Task<Void, Never>?
    private var startupDataRecoveryID: UUID?
    /// 单次应用生命周期内，启动数据恢复最多重建一次 App Server，避免异常环境下循环重启。
    private var didUseStartupRecoveryReconnect = false
    private var unhealthyRecoveryTask: Task<Void, Never>?
    private var unhealthyRecoveryID: UUID?
    private var criticalRecoveryEligibleServices: Set<PulseSyncService> = []
    private var notifiedThresholds: Set<Int> = []
    private var didRestoreNotifiedThresholds = false
    private var notifiedLongTaskIDs: Set<String> = []
    private var notifiedResetCardIDs: Set<String> = []
    private var smoothedTokenVelocity: Double?
    private var isTokenSpikeActive = false
    private var lastTokenSpikeAlertAt: Date?
    /// 防止一次短暂缺失的 thread 状态立即把仍在运行的任务刷成空闲。
    private var lastActiveTaskEvidenceAt: Date?
    /// 各线程最近一次推送的累计 Token（thread/tokenUsage/updated 是累计值）。
    private var threadTokenTotals: [String: Int64] = [:]
    /// 当前所属自然日（yyyy-MM-dd）；跨天时重置“今日”相关状态。
    private var currentDayKey = UsageStats.dayFormatter().string(from: Date())
    /// “今日 Token”采用这台机器当天全部 Codex session 的汇总。session 日志没有
    /// 账号标识，因此切换账号后仍保留该设备口径，不等待应用重启后才恢复显示。
    private let activeTaskEvidenceGraceInterval: TimeInterval = 20
    private var idleFollowUpPollsRemaining = 3
    private let activePollingInterval: TimeInterval = 5
    private let idlePollingInterval: TimeInterval = 15
    private let idleFollowUpPollCount = 3
    /// 任务轮询可以在空闲后静默，但额度必须持续更新。Windows 端空闲时为 8 秒，
    /// macOS 使用相同周期，避免小圆球长期停留在重置前的百分比。
    private let idleRateLimitPollingInterval: TimeInterval = 8
    /// 官方额度后端可能在重置边界后短暂返回旧窗口；到点后缩短重试周期，
    /// 直到响应带回新的 resetsAt 为止。
    private let dueRateLimitRetryInterval: TimeInterval = 3
    private let rateLimitResetGraceInterval: TimeInterval = 0.75
    /// 仅检查本地已知会话文件，不经过额度/Token RPC；0.5 秒足以接近即时反馈。
    private let liveTaskStatusInterval: TimeInterval = 0.5
    private var consecutiveLiveIdlePolls = 0
    /// 本地 final_answer/task_complete 比独立 app-server 的 thread/list 更新更及时。
    /// 短时间内屏蔽同线程仍返回的陈旧 active，新的 task_started 会立即解除。
    private var locallyCompletedTaskAt: [String: Date] = [:]
    private let localCompletionAuthorityInterval: TimeInterval = 2 * 60
    private var didStart = false

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        settings = SettingsStore.shared.load()
        didUseStartupRecoveryReconnect = false
        if let cached = SnapshotStore.shared.load() {
            snapshot = cached
            if cached.updatedAt != .distantPast {
                currentDayKey = UsageStats.dayFormatter().string(from: cached.updatedAt)
            }
            if isTaskInFlight(cached.currentTask.state),
               !cached.isStale(threshold: activeTaskEvidenceGraceInterval) {
                lastActiveTaskEvidenceAt = cached.updatedAt
            }
            if settings.resolvedRateLimitForecastEnabled {
                primaryRateLimitForecast = cached.primaryRateLimitForecast
                    ?? cached.rateLimits.primaryBucket.flatMap {
                        TaskHistoryStore.shared.rateLimitForecast(for: $0)
                    }
                snapshot.primaryRateLimitForecast = primaryRateLimitForecast
            } else {
                primaryRateLimitForecast = nil
                snapshot.primaryRateLimitForecast = nil
            }
        }
        rolloverDayIfNeeded()
        startDayRolloverMonitoring()
        cliPath = try? StdioCodexAppServerClient.findCodexCLI()
        Task { await connect() }
    }

    func stop() {
        didStart = false
        flushPersist()
        eventTask?.cancel()
        pollTask?.cancel()
        rateLimitMonitorTask?.cancel()
        dayRolloverTask?.cancel()
        liveTaskStatusTask?.cancel()
        postTurnRefreshTask?.cancel()
        postTurnRefreshTask = nil
        localUsageRefreshTask?.cancel()
        localUsageRefreshTask = nil
        localUsageRefreshRevision &+= 1
        reconnectTask?.cancel()
        startupDataRecoveryTask?.cancel()
        unhealthyRecoveryTask?.cancel()
        eventTask = nil
        pollTask = nil
        rateLimitMonitorTask = nil
        dayRolloverTask = nil
        liveTaskStatusTask = nil
        reconnectTask = nil
        reconnectRecoveryID = nil
        startupDataRecoveryTask = nil
        startupDataRecoveryID = nil
        unhealthyRecoveryTask = nil
        unhealthyRecoveryID = nil
        criticalRecoveryEligibleServices.removeAll()
        locallyCompletedTaskAt.removeAll()
        nextReconnectAt = nil
        let clientToStop = client
        client = nil
        Task { await clientToStop?.disconnect() }
    }

    func reconnect() async {
        cancelStartupDataRecovery()
        await reconnectCore()
    }

    private func reconnectCore() async {
        cancelRealConnectionRecovery()
        cancelUnhealthyConnectionRecovery()
        eventTask?.cancel()
        pollTask?.cancel()
        rateLimitMonitorTask?.cancel()
        rateLimitMonitorTask = nil
        liveTaskStatusTask?.cancel()
        liveTaskStatusTask = nil
        localUsageRefreshTask?.cancel()
        localUsageRefreshTask = nil
        localUsageRefreshRevision &+= 1
        let previousClient = client
        client = nil
        await previousClient?.disconnect()
        isUsingMock = false
        await connect()
    }

    func connect() async {
        lastError = nil
        var connectingSnapshot = snapshot
        connectingSnapshot.connectionState = .connecting
        connectingSnapshot.updatedAt = Date()
        apply(connectingSnapshot)
        connectionDetail = "正在连接 codex app-server…"
        cliPath = try? StdioCodexAppServerClient.findCodexCLI()

        let stdio = StdioCodexAppServerClient()
        var needsRealRecovery = false
        do {
            try await stdio.connect()
            client = stdio
            isUsingMock = false
            connectionDetail = "已连接 · \(cliPath ?? "codex")"
            lastError = nil
            markRealConnectionRestored()
        } catch {
            let message = error.localizedDescription
            needsRealRecovery = true
            if settings.useMockWhenCLIUnavailable {
                let mock = MockCodexAppServerClient()
                do {
                    try await mock.connect()
                    client = mock
                    isUsingMock = true
                    connectionDetail = "演示模式 · \(message)"
                    lastError = "真实连接失败，已回退 Mock：\(message)"
                } catch {
                    var failedSnapshot = snapshot
                    failedSnapshot.connectionState = .error
                    failedSnapshot.updatedAt = Date()
                    apply(failedSnapshot)
                    connectionDetail = "连接失败"
                    lastError = error.localizedDescription
                    scheduleRealConnectionRecovery()
                    return
                }
            } else {
                var failedSnapshot = snapshot
                failedSnapshot.connectionState = .error
                failedSnapshot.updatedAt = Date()
                apply(failedSnapshot)
                connectionDetail = "连接失败"
                lastError = message
                scheduleRealConnectionRecovery()
                return
            }
        }

        var connectedSnapshot = snapshot
        connectedSnapshot.connectionState = .connected
        connectedSnapshot.updatedAt = Date()
        apply(connectedSnapshot)
        // 实时任务状态必须先启动。首次额度/Token 请求可能持续几十秒，不能让
        // “思考中/等待授权”跟着 profile 请求一起排队。
        listenEvents()
        startLiveTaskStatusMonitoring()
        startPolling()
        startRateLimitMonitoring()
        await refreshAll(forceRemote: true)
        scheduleStartupDataRecoveryIfNeeded()
        if needsRealRecovery {
            scheduleRealConnectionRecovery()
        }
    }

    func refreshAll(forceRemote: Bool = false) async {
        guard let client, client.isConnected else { return }
        if isRefreshing {
            refreshRequestedWhileBusy = true
            pendingForceRemoteRefresh = pendingForceRemoteRefresh || forceRemote
            return
        }
        rolloverDayIfNeeded()
        let refreshDayKey = currentDayKey
        isRefreshing = true
        let refreshAccountRevision = accountRevision
        defer { finishRefreshCycle() }

        let previous = snapshot
        var next = previous
        var errors: [String] = []
        var didRefreshThreads = false
        var didRefreshAccount = false

        // App Server 支持并发 JSON-RPC。慢速额度/用量请求在后台进行，线程结果优先消费。
        // 实时文件监听需要覆盖可切换的历史会话；只取 20 条会让较早会话首次恢复时漏监听。
        async let threadsRequest: [TaskRecord] = client.listRecentThreads(limit: 100)
        async let accountRequest: AccountInfo = client.readAccount()

        // 任务状态优先：额度/Token 接口偶尔会等待至超时，不能让旧的“空闲”状态
        // 因此滞后十几秒。线程查询完成后先发布一次快照，其余数据随后补齐。
        do {
            let receivedTasks = try await threadsRequest
            let liveTasks = suppressStaleActiveStates(in: receivedTasks)
            if client is MockCodexAppServerClient {
                next.recentTasks = liveTasks
            } else {
                let retentionDays = settings.historyRetentionDays
                next.recentTasks = await Task.detached(priority: .utility) {
                    TaskHistoryStore.shared.persistAndMerge(
                        liveTasks: liveTasks,
                        retentionDays: retentionDays,
                        limit: 100
                    )
                }.value
            }
            didRefreshThreads = true
            recordSyncSuccess(.threads)
            PulseLog.write("threads ok: \(next.recentTasks.count)")
        } catch {
            recordSyncFailure(
                .threads,
                message: error.localizedDescription,
                canTriggerRecovery: isRecoverableConnectionError(error)
            )
            errors.append(friendlyError(error, label: "任务"))
            PulseLog.write("threads fail: \(error.localizedDescription)")
        }

        guard isCurrentClient(client),
              accountRevision == refreshAccountRevision,
              currentDayKey == refreshDayKey else { return }

        if let mock = client as? MockCodexAppServerClient {
            next.currentTask = mock.peekCurrentTask()
        } else if didRefreshThreads,
                  let liveTask = next.recentTasks.first(where: {
                      guard let state = $0.runState else { return false }
                      return isTaskInFlight(state)
                  }) {
            next.currentTask = currentTask(from: liveTask, preserving: previous.currentTask)
            lastActiveTaskEvidenceAt = Date()
            PulseLog.write("current task: \(liveTask.id) \(next.currentTask.state.rawValue)")
        } else if didRefreshThreads,
                  isTaskInFlight(previous.currentTask.state),
                  let lastActiveTaskEvidenceAt,
                  Date().timeIntervalSince(lastActiveTaskEvidenceAt) < activeTaskEvidenceGraceInterval {
            next.currentTask = previous.currentTask
            PulseLog.write("current task activity temporarily missing; preserving in-flight state")
        } else if didRefreshThreads {
            var idle = CurrentTaskInfo.empty
            idle.state = next.account.isLoggedIn ? .idle : .notStarted
            next.currentTask = idle
            lastActiveTaskEvidenceAt = nil
        }

        next.connectionState = connectedStateForSyncHealth()
        next.updatedAt = Date()
        next.primaryRateLimitForecast = settings.resolvedRateLimitForecastEnabled
            ? primaryRateLimitForecast
            : nil
        let initiallyPublishedTask = next.currentTask
        let initiallyPublishedRecentTasks = next.recentTasks
        apply(next)

        // 账号先于额度/用量确认。这样即使 account/updated 通知丢失，手动刷新也不会
        // 用旧账号的 12s/60s 客户端缓存填充新账号界面。
        var accountChanged = false
        do {
            let refreshedAccount = try await accountRequest
            accountChanged = !sameAccountIdentity(previous.account, refreshedAccount)
            next.account = refreshedAccount
            didRefreshAccount = true
            recordSyncSuccess(.account)
            if didRefreshThreads, next.currentTask.id == CurrentTaskInfo.empty.id {
                next.currentTask.state = next.account.isLoggedIn ? .idle : .notStarted
            }
            if accountChanged {
                isAccountTransitioning = true
                client.invalidateAccountScopedState()
                next.rateLimits = .empty
                next.usage = .empty
                next.primaryRateLimitForecast = nil
                primaryRateLimitForecast = nil
                threadTokenTotals.removeAll()
                smoothedTokenVelocity = nil
                notifiedThresholds.removeAll()
                didRestoreNotifiedThresholds = false
                PulseLog.write("account identity changed during refresh; old scoped data discarded")
            }
            PulseLog.write("account ok: \(next.account.displayEmail) \(next.account.planType.displayName)")
        } catch {
            recordSyncFailure(
                .account,
                message: error.localizedDescription,
                canTriggerRecovery: isRecoverableConnectionError(error)
            )
            let msg = friendlyError(error, label: "账号")
            errors.append(msg)
            PulseLog.write("account fail: \(error.localizedDescription)")
        }

        guard isCurrentClient(client),
              accountRevision == refreshAccountRevision,
              currentDayKey == refreshDayKey else { return }
        next.updatedAt = Date()
        apply(next)

        var shouldRefreshRemoteUsage = true
        do {
            next.rateLimits = try await client.readRateLimits(
                forceRefresh: forceRemote || accountChanged
            )
            recordSyncSuccess(.rateLimits)
            await updateRateLimitForecastOffMain(from: next.rateLimits)
            next.primaryRateLimitForecast = primaryRateLimitForecast
            let pct = next.rateLimits.primaryBucket.map { String(format: "%.0f%%", $0.usedPercent) } ?? "—"
            PulseLog.write("rateLimits ok: \(pct) buckets=\(next.rateLimits.buckets.count)")
        } catch {
            // 普通轮询在额度端点失败时只做本机轻量补偿；账号切换、手动刷新和
            // turn 结束强刷仍继续请求 usage，避免两个端点被错误地绑定成一起失败。
            shouldRefreshRemoteUsage = forceRemote || accountChanged
            if case CodexServerError.requestDeferred = error {
                // 真实失败已在首次请求时记录；退避轮询不重复累加失败次数或刷日志。
            } else {
                recordSyncFailure(.rateLimits, message: error.localizedDescription)
                // 保留上次额度，不把界面刷成空
                let msg = friendlyError(error, label: "额度")
                errors.append(msg)
                PulseLog.write("rateLimits fail: \(error.localizedDescription)")
            }
        }

        guard isCurrentClient(client),
              accountRevision == refreshAccountRevision,
              currentDayKey == refreshDayKey else { return }

        let isSameAccount = !accountChanged
            && sameAccountIdentity(previous.account, next.account)

        if shouldRefreshRemoteUsage {
            do {
                // Token profile 与额度接口共享较重的远端拉取链路；额度完成后再请求 Token，
                // 避免两个 profile 请求互相阻塞并同时触发客户端超时。
                var usage = try await client.readUsage(forceRefresh: forceRemote || accountChanged)
                if shouldPromoteLocalToday(
                    usage: usage,
                    currentAccount: next.account
                ), let localToday = usage.localTodayTokens {
                    usage.mergeLocalTodayTokens(localToday, promoteToAccountTotals: true)
                }
                if next.account.authMode == .apiKey,
                   let localDaily = usage.localDailyBuckets {
                    usage.mergeLocalDailyBuckets(localDaily, promoteToAccountTotals: true)
                }
                if isSameAccount {
                    usage.preserveMissingSummary(from: previous.usage)
                }
                applyTokenVelocity(to: &usage, previous: previous.usage, sameAccount: isSameAccount)
                next.usage = usage
                if let degradedMessage = usageDegradedMessage(usage) {
                    recordSyncFailure(.usage, message: degradedMessage)
                } else {
                    recordSyncSuccess(.usage)
                }
                PulseLog.write(
                    "usage ok: today=\(usage.todayTokens.map(String.init) ?? "—") total=\(usage.totalTokens.map(String.init) ?? "—") buckets=\(usage.dailyBuckets.count) note=\(usage.sourceNote ?? "-")"
                )
                if !usage.hasAnyTokenMetric {
                    // 不打断主流程，仅保留说明
                    if lastError == nil, let note = usage.sourceNote {
                        PulseLog.write("usage empty: \(note)")
                    }
                }
            } catch {
                recordSyncFailure(.usage, message: error.localizedDescription)
                // usage 常对部分账号不可用，降级为次要提示；保留上次数据
                PulseLog.write("usage fail: \(error.localizedDescription)")
                // 即使远端 RPC 在客户端之外抛错，API Key 仍可从本机 session
                // 日志得到今日总量；同账号 ChatGPT 也保留本机补源。
                var fallback = await client.readLocalUsage(
                    merging: isSameAccount ? previous.usage : .empty
                )
                if shouldPromoteLocalToday(
                    usage: fallback,
                    currentAccount: next.account
                ), let localToday = fallback.localTodayTokens {
                    fallback.mergeLocalTodayTokens(localToday, promoteToAccountTotals: true)
                }
                if next.account.authMode == .apiKey,
                   let localDaily = fallback.localDailyBuckets {
                    fallback.mergeLocalDailyBuckets(localDaily, promoteToAccountTotals: true)
                }
                if fallback.hasAnyTokenMetric || next.usage.updatedAt == .distantPast || !next.usage.hasAnyTokenMetric {
                    fallback.sourceNote = fallback.sourceNote ?? "Token 统计暂不可用：\(error.localizedDescription)"
                    fallback.updatedAt = Date()
                    next.usage = fallback
                }
                next.usage.tokenVelocityPerMinute = nil
                smoothedTokenVelocity = nil
            }
        } else {
            let cachedUsage = isSameAccount ? previous.usage : .empty
            var usage = await client.readLocalUsage(merging: cachedUsage)
            if shouldPromoteLocalToday(
                usage: usage,
                currentAccount: next.account
            ), let localToday = usage.localTodayTokens {
                usage.mergeLocalTodayTokens(localToday, promoteToAccountTotals: true)
            }
            if next.account.authMode == .apiKey,
               let localDaily = usage.localDailyBuckets {
                usage.mergeLocalDailyBuckets(localDaily, promoteToAccountTotals: true)
            }
            applyTokenVelocity(to: &usage, previous: previous.usage, sameAccount: isSameAccount)
            next.usage = usage
        }

        guard isCurrentClient(client),
              accountRevision == refreshAccountRevision,
              currentDayKey == refreshDayKey else { return }

        // 刷新等待期间可能收到 turnStarted/turnCompleted 事件；始终保留最新任务状态，
        // 防止慢请求结束后用本轮开始时的旧“空闲”快照覆盖实时事件。
        if snapshot.currentTask != initiallyPublishedTask
            || snapshot.recentTasks != initiallyPublishedRecentTasks {
            next.currentTask = snapshot.currentTask
            next.recentTasks = snapshot.recentTasks
        }
        next.connectionState = connectedStateForSyncHealth()
        next.updatedAt = Date()
        // 刷新期间设置可能被切换；以当前内存状态为准，避免旧快照覆盖新选择。
        next.primaryRateLimitForecast = settings.resolvedRateLimitForecastEnabled
            ? primaryRateLimitForecast
            : nil

        apply(next)
        if didRefreshAccount {
            isAccountTransitioning = false
        }
        evaluateAlerts(previous: previous, current: next)

        // 静默阶段如果手动刷新或事件刷新发现任务重新开始，恢复 15 秒主动轮询。
        if hasActivelyRunningTask, pollTask == nil {
            startPolling()
        }

        if !isUsingMock {
            if next.connectionState == .degraded {
                lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
                connectionDetail = "已连接 · \(syncHealthSummary)"
            } else if errors.isEmpty {
                lastError = nil
                connectionDetail = "已连接 · \(next.account.displayEmail)"
            } else {
                // 瞬时上游错误：有缓存数据时只做轻提示，不刷红整块
                let hasCachedLimits = !previous.rateLimits.buckets.isEmpty
                if hasCachedLimits && errors.allSatisfy({ $0.contains("额度") || $0.contains("暂时") }) {
                    lastError = nil
                    connectionDetail = "已连接 · 额度同步延迟"
                } else {
                    lastError = errors.joined(separator: " · ")
                    connectionDetail = next.account.isLoggedIn
                        ? "已连接 · 部分数据异常"
                        : "已连接 · 未登录或数据不完整"
                }
            }
        }
    }

    /// 刷新期间到达的账号事件或手动强刷不能被 `isRefreshing` 静默丢弃。
    /// 合并为一次后续刷新，并把普通请求升级为强制远端请求。
    private func finishRefreshCycle() {
        isRefreshing = false
        guard didStart, refreshRequestedWhileBusy else { return }
        let forceRemote = pendingForceRemoteRefresh
        refreshRequestedWhileBusy = false
        pendingForceRemoteRefresh = false
        Task { [weak self] in
            await Task.yield()
            await self?.refreshAll(forceRemote: forceRemote)
        }
    }

    // MARK: - Realtime task status

    /// 独立于额度/Token 的 0.5 秒轻量状态通道，只读取本地 session 尾部缓存。
    /// 它负责空闲、思考、授权/输入等待的及时切换，不会触发 profile 网络请求。
    private func startLiveTaskStatusMonitoring() {
        liveTaskStatusTask?.cancel()
        liveTaskStatusTask = nil
        consecutiveLiveIdlePolls = 0
        guard didStart, !isUsingMock, let monitoredClient = client else { return }

        liveTaskStatusTask = Task { [weak self] in
            guard let self else { return }
            while self.didStart, !Task.isCancelled, self.isCurrentClient(monitoredClient) {
                await self.refreshLiveTaskStatus(using: monitoredClient)
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(self.liveTaskStatusInterval * 1_000_000_000)
                    )
                } catch {
                    break
                }
            }
            if self.isCurrentClient(monitoredClient) {
                self.liveTaskStatusTask = nil
            }
        }
    }

    private func refreshLiveTaskStatus(using monitoredClient: any CodexAppServerClient) async {
        let liveTasks: [TaskRecord]
        do {
            liveTasks = try await monitoredClient.listLiveThreads(limit: 20)
        } catch {
            return
        }
        guard didStart, isCurrentClient(monitoredClient) else { return }
        recordSyncSuccess(.threads)

        let activeTasks = liveTasks.filter {
            guard let state = $0.runState else { return false }
            return isTaskInFlight(state)
        }
        let previous = snapshot
        var next = previous
        mergeLiveTaskStates(liveTasks, into: &next.recentTasks)

        if let active = activeTasks.first {
            consecutiveLiveIdlePolls = 0
            lastActiveTaskEvidenceAt = Date()
            locallyCompletedTaskAt.removeValue(forKey: active.id)
            var liveCurrentTask = currentTask(from: active, preserving: previous.currentTask)
            // 完整刷新会保留推送事件给出的精细阶段；但这里是专门的实时通道，
            // 必须允许“执行命令/等待授权 -> 思考”等新状态立即覆盖旧状态。
            if let liveState = active.runState {
                liveCurrentTask.state = liveState
            }
            next.currentTask = liveCurrentTask
        } else {
            consecutiveLiveIdlePolls += 1
            // 连续两次（约 1 秒）为空才切换，过滤 JSONL 写入过程中的瞬时空窗。
            guard consecutiveLiveIdlePolls >= 2 else { return }
            lastActiveTaskEvidenceAt = nil
            var idle = CurrentTaskInfo.empty
            idle.state = next.account.isLoggedIn ? .idle : .notStarted
            next.currentTask = idle
            for index in next.recentTasks.indices where isTaskInFlight(next.recentTasks[index].runState ?? .idle) {
                next.recentTasks[index].runState = .idle
                next.recentTasks[index].startedAt = nil
            }
        }

        next.connectionState = connectedStateForSyncHealth()
        let liveContentChanged = next.currentTask != previous.currentTask
            || next.recentTasks != previous.recentTasks
            || next.connectionState != previous.connectionState
        guard liveContentChanged else { return }
        next.updatedAt = Date()
        if next.currentTask.state != previous.currentTask.state
            || next.currentTask.id != previous.currentTask.id {
            PulseLog.write(
                "live task state: \(previous.currentTask.state.rawValue) -> \(next.currentTask.state.rawValue)"
            )
        }
        apply(next)
    }

    private func mergeLiveTaskStates(_ liveTasks: [TaskRecord], into storedTasks: inout [TaskRecord]) {
        for live in liveTasks {
            if let index = storedTasks.firstIndex(where: { $0.id == live.id }) {
                storedTasks[index].runState = live.runState
                storedTasks[index].activeFlags = live.activeFlags
                storedTasks[index].startedAt = live.startedAt
                storedTasks[index].finishedAt = max(storedTasks[index].finishedAt, live.finishedAt)
                storedTasks[index].projectPath = storedTasks[index].projectPath ?? live.projectPath
                if storedTasks[index].model == nil { storedTasks[index].model = live.model }
            } else {
                storedTasks.insert(live, at: 0)
            }
        }
        if storedTasks.count > 100 {
            storedTasks.removeSubrange(100...)
        }
    }

    /// 独立 app-server 可能在本地任务结束后几十秒仍返回 active。
    /// 本地完成事件是更直接的数据源，防止完整轮询把 UI 从空闲重新刷回思考中。
    private func suppressStaleActiveStates(in tasks: [TaskRecord], reference: Date = Date()) -> [TaskRecord] {
        locallyCompletedTaskAt = locallyCompletedTaskAt.filter {
            reference.timeIntervalSince($0.value) <= localCompletionAuthorityInterval
        }
        guard !locallyCompletedTaskAt.isEmpty else { return tasks }
        return tasks.map { task in
            guard let completedAt = locallyCompletedTaskAt[task.id],
                  reference.timeIntervalSince(completedAt) <= localCompletionAuthorityInterval,
                  let state = task.runState,
                  isTaskInFlight(state) else { return task }
            var resolved = task
            resolved.runState = .idle
            resolved.startedAt = nil
            return resolved
        }
    }

    // MARK: - Startup data recovery

    /// 启动时 App Server 可能先连通，但 ChatGPT 账号/额度后端尚未就绪。
    /// 对首次完整同步做有限重试；仍失败时自动重建一次连接，等价于用户手动点击“重连”。
    private func scheduleStartupDataRecoveryIfNeeded() {
        guard didStart,
              !isUsingMock,
              !hasFreshStartupData,
              startupDataRecoveryTask == nil else { return }

        let recoveryID = UUID()
        startupDataRecoveryID = recoveryID
        startupDataRecoveryTask = Task { [weak self] in
            guard let self else { return }

            // 首次连接已经做过一次强刷；若仍不完整，2 秒后直接自动执行一次“重连”。
            // 这正是此前用户手动点击重连才能恢复的路径，且单次启动最多执行一次。
            if !self.didUseStartupRecoveryReconnect {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    self.finishStartupDataRecovery(id: recoveryID)
                    return
                }
                guard self.didStart,
                      !Task.isCancelled,
                      self.startupDataRecoveryID == recoveryID else { return }
                if self.hasFreshStartupData {
                    self.finishStartupDataRecovery(id: recoveryID)
                    return
                }

                self.didUseStartupRecoveryReconnect = true
                PulseLog.write("startup data incomplete; restarting app-server connection automatically")
                self.finishStartupDataRecovery(id: recoveryID)
                await self.reconnectCore()
                return
            }

            // 重建连接后仍不完整时只强刷，不再反复重启 App Server。
            let retryDelays: [TimeInterval] = [3, 10, 30]

            for delay in retryDelays {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    self.finishStartupDataRecovery(id: recoveryID)
                    return
                }
                guard self.didStart,
                      !Task.isCancelled,
                      self.startupDataRecoveryID == recoveryID else { return }

                PulseLog.write("startup data incomplete; force refresh after \(Int(delay))s")
                await self.refreshAll(forceRemote: true)
                if self.hasFreshStartupData {
                    PulseLog.write("startup data recovery completed")
                    self.finishStartupDataRecovery(id: recoveryID)
                    return
                }
            }

            guard self.didStart,
                  !Task.isCancelled,
                  self.startupDataRecoveryID == recoveryID else { return }

            PulseLog.write("startup data recovery exhausted; keeping automatic event refresh active")
            self.finishStartupDataRecovery(id: recoveryID)
        }
    }

    private var hasFreshStartupData: Bool {
        let required: [PulseSyncService] = [.account, .threads, .rateLimits, .usage]
        return required.allSatisfy { syncHealth[$0, default: .empty].lastSuccessAt != nil }
    }

    private func cancelStartupDataRecovery() {
        startupDataRecoveryTask?.cancel()
        startupDataRecoveryTask = nil
        startupDataRecoveryID = nil
    }

    private func finishStartupDataRecovery(id: UUID) {
        guard startupDataRecoveryID == id else { return }
        startupDataRecoveryTask = nil
        startupDataRecoveryID = nil
    }

    /// 把 RPC -32603 等转成用户可读文案
    private func friendlyError(_ error: Error, label: String) -> String {
        if case CodexServerError.rpcError(let code, let msg) = error {
            if code == -32603 {
                return "\(label)暂时不可用（服务端繁忙，将自动重试）"
            }
            if code == -32001 {
                return "\(label)繁忙，请稍后"
            }
            return "\(label): \(msg)"
        }
        if case CodexServerError.timeout = error {
            return "\(label)超时"
        }
        return "\(label): \(error.localizedDescription)"
    }

    private func recordSyncSuccess(_ service: PulseSyncService) {
        var health = syncHealth[service, default: .empty]
        health.recordSuccess()
        syncHealth[service] = health
        criticalRecoveryEligibleServices.remove(service)
    }

    private func recordSyncFailure(
        _ service: PulseSyncService,
        message: String,
        canTriggerRecovery: Bool = false
    ) {
        var health = syncHealth[service, default: .empty]
        health.recordFailure(message)
        syncHealth[service] = health

        if service == .account || service == .threads {
            if canTriggerRecovery {
                criticalRecoveryEligibleServices.insert(service)
            } else {
                criticalRecoveryEligibleServices.remove(service)
            }
        }

        if canTriggerRecovery,
           (service == .account || service == .threads),
           health.consecutiveFailures >= 3 {
            scheduleUnhealthyConnectionRecovery()
        }
    }

    private func isRecoverableConnectionError(_ error: Error) -> Bool {
        if case CodexServerError.unauthorized = error { return false }
        if case CodexServerError.rpcError(_, let message) = error {
            let lower = message.lowercased()
            let accountMarkers = ["unauthorized", "forbidden", "permission", "not logged", "login"]
            if accountMarkers.contains(where: { lower.contains($0) }) { return false }
        }
        return true
    }

    private func usageDegradedMessage(_ usage: UsageStats) -> String? {
        guard let note = usage.sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        let lower = note.lowercased()
        let transientMarkers = ["失败", "超时", "暂不可用", "解析失败", "timed out", "timeout", "failed"]
        return transientMarkers.contains(where: { lower.contains($0) }) ? note : nil
    }

    private func connectedStateForSyncHealth() -> PulseSnapshot.ConnectionState {
        let accountFailures = syncHealth[.account, default: .empty].consecutiveFailures
        let threadFailures = syncHealth[.threads, default: .empty].consecutiveFailures
        let rateFailures = syncHealth[.rateLimits, default: .empty].consecutiveFailures
        let usageFailures = syncHealth[.usage, default: .empty].consecutiveFailures
        return accountFailures >= 2 || threadFailures >= 2 || rateFailures >= 3 || usageFailures >= 3
            ? .degraded
            : .connected
    }

    var primaryRateLimitForecastSummary: String? {
        guard let forecast = primaryRateLimitForecast else { return nil }
        if forecast.willExhaustBeforeReset,
           let exhaustionAt = forecast.estimatedExhaustionAt {
            return "按当前速度预计 \(PulseFormatters.countdown(exhaustionAt.timeIntervalSinceNow)) 后耗尽"
        }
        if let remaining = forecast.projectedRemainingAtReset {
            return "重置时预计剩余 \(PulseFormatters.percent(remaining))"
        }
        if let exhaustionAt = forecast.estimatedExhaustionAt {
            return "预计 \(PulseFormatters.countdown(exhaustionAt.timeIntervalSinceNow)) 后耗尽"
        }
        return nil
    }

    private func updateRateLimitForecast(
        from limits: RateLimitSnapshot,
        sampledAt: Date = Date()
    ) {
        guard settings.resolvedRateLimitForecastEnabled else {
            primaryRateLimitForecast = nil
            return
        }
        for bucket in limits.buckets {
            TaskHistoryStore.shared.recordRateLimitSample(bucket, sampledAt: sampledAt)
        }
        primaryRateLimitForecast = limits.primaryBucket.flatMap {
            TaskHistoryStore.shared.rateLimitForecast(for: $0, reference: sampledAt)
        }
    }

    /// 额度采样和预测包含多次 SQLite 查询；轮询路径移出主线程，避免胶囊/菜单动画卡顿。
    private func updateRateLimitForecastOffMain(
        from limits: RateLimitSnapshot,
        sampledAt: Date = Date()
    ) async {
        guard settings.resolvedRateLimitForecastEnabled else {
            primaryRateLimitForecast = nil
            return
        }
        let revision = accountRevision
        let forecast = await Task.detached(priority: .utility) {
            for bucket in limits.buckets {
                TaskHistoryStore.shared.recordRateLimitSample(bucket, sampledAt: sampledAt)
            }
            return limits.primaryBucket.flatMap {
                TaskHistoryStore.shared.rateLimitForecast(for: $0, reference: sampledAt)
            }
        }.value
        guard revision == accountRevision else { return }
        primaryRateLimitForecast = forecast
    }

    private var hasCriticalSyncFailure: Bool {
        (criticalRecoveryEligibleServices.contains(.account)
            && syncHealth[.account, default: .empty].consecutiveFailures >= 3)
            || (criticalRecoveryEligibleServices.contains(.threads)
                && syncHealth[.threads, default: .empty].consecutiveFailures >= 3)
    }

    /// 跨过午夜后，“今日”相关的内存态全部重开：事件基线保留（线程累计值
    /// 不随日期归零），但今日增量重新起算；同时清理只增不减的通知集合。
    @discardableResult
    private func rolloverDayIfNeeded(reference: Date = Date()) -> Bool {
        let key = UsageStats.dayFormatter().string(from: reference)
        guard key != currentDayKey else { return false }
        currentDayKey = key
        var next = snapshot
        var usage = next.usage
        // 昨天的值顺移；今日从 0 重新累计，等待下一次轮询/事件填充。
        usage.resetForNewDay(reference: reference)
        next.usage = usage
        next.updatedAt = reference
        smoothedTokenVelocity = nil
        notifiedThresholds.removeAll()
        notifiedLongTaskIDs.removeAll()
        notifiedResetCardIDs.removeAll()
        apply(next)
        PulseLog.write("day rollover -> \(key)")
        return true
    }

    /// 独立于自适应网络轮询运行。即使应用已进入 silent mode，也会在本地
    /// 午夜立即清空“今日”，休眠跨夜后则在任务恢复的第一轮立刻补做。
    private func startDayRolloverMonitoring() {
        dayRolloverTask?.cancel()
        dayRolloverTask = Task { [weak self] in
            guard let self else { return }
            while self.didStart, !Task.isCancelled {
                let now = Date()
                if self.rolloverDayIfNeeded(reference: now) {
                    let expectedDay = self.currentDayKey
                    await self.refreshLocalUsageAfterDayRollover(expectedDay: expectedDay)
                }

                let calendar = Calendar.current
                let start = calendar.startOfDay(for: now)
                let nextMidnight = calendar.date(byAdding: .day, value: 1, to: start)
                    ?? now.addingTimeInterval(60)
                // Exact midnight wake-up plus a one-minute ceiling provides a
                // fallback for clock/time-zone changes and sleep resumption.
                let delay = min(60, max(0.25, nextMidnight.timeIntervalSince(now) + 0.25))
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    private func refreshLocalUsageAfterDayRollover(expectedDay: String) async {
        guard didStart,
              let client,
              client.isConnected,
              isCurrentClient(client),
              currentDayKey == expectedDay else { return }

        var usage = await client.readLocalUsage(merging: snapshot.usage)
        guard didStart, isCurrentClient(client), currentDayKey == expectedDay else { return }
        if shouldPromoteLocalToday(
            usage: usage,
            currentAccount: snapshot.account
        ), let localToday = usage.localTodayTokens {
            usage.mergeLocalTodayTokens(localToday, promoteToAccountTotals: true)
        }
        if snapshot.account.authMode == .apiKey,
           let localDaily = usage.localDailyBuckets {
            usage.mergeLocalDailyBuckets(localDaily, promoteToAccountTotals: true)
        }

        var next = snapshot
        next.usage = usage
        next.updatedAt = Date()
        apply(next)

        // Refresh the account-scoped profile as a follow-up. If another refresh
        // is active, refreshAll records a queued forced refresh instead.
        await refreshAll(forceRemote: true)
    }

    private func applyTokenVelocity(
        to current: inout UsageStats,
        previous: UsageStats,
        sameAccount: Bool
    ) {
        guard sameAccount,
              let previousLocal = previous.localTodayTokens,
              let currentLocal = current.localTodayTokens,
              currentLocal >= previousLocal,
              previous.updatedAt != .distantPast else {
            current.tokenVelocityPerMinute = nil
            smoothedTokenVelocity = nil
            return
        }

        let elapsed = current.updatedAt.timeIntervalSince(previous.updatedAt)
        guard elapsed >= 1, elapsed <= 5 * 60 else {
            current.tokenVelocityPerMinute = nil
            smoothedTokenVelocity = nil
            return
        }

        let delta = currentLocal - previousLocal
        let rawVelocity = Double(delta) * 60 / elapsed
        let smoothed = smoothedTokenVelocity.map { $0 * 0.55 + rawVelocity * 0.45 } ?? rawVelocity
        smoothedTokenVelocity = smoothed
        current.tokenVelocityPerMinute = Int64(max(0, smoothed).rounded())
    }

    private func currentTask(from record: TaskRecord, preserving existing: CurrentTaskInfo) -> CurrentTaskInfo {
        let isSameTask = existing.id == record.id
        var state = record.runState ?? .thinking
        if isSameTask, state == .thinking, existing.state.isActive {
            // 推送事件能区分命令、文件修改等具体阶段，保留更精确的状态。
            state = existing.state
        }
        let startedAt: Date = {
            if isSameTask {
                return [existing.startedAt, record.startedAt].compactMap { $0 }.min() ?? Date()
            }
            return record.startedAt ?? Date()
        }()
        return CurrentTaskInfo(
            id: record.id,
            projectName: record.projectName,
            projectPath: record.projectPath,
            gitBranch: record.gitBranch,
            model: record.model,
            reasoningEffort: isSameTask ? existing.reasoningEffort : nil,
            startedAt: startedAt,
            state: state,
            currentStep: isSameTask ? existing.currentStep : nil,
            filesChanged: max(record.filesChanged, isSameTask ? existing.filesChanged : 0),
            linesAdded: isSameTask ? existing.linesAdded : 0,
            linesRemoved: isSameTask ? existing.linesRemoved : 0,
            lastStatusMessage: record.summary ?? (isSameTask ? existing.lastStatusMessage : nil),
            conversation: mergedConversation(
                recorded: record.conversation,
                existing: isSameTask ? existing.conversation : nil
            )
        )
    }

    private func mergedConversation(
        recorded: [TaskConversationMessage]?,
        existing: [TaskConversationMessage]?
    ) -> [TaskConversationMessage]? {
        var messages = recorded ?? existing ?? []
        guard let live = existing?.last, live.isStreaming else {
            return messages.isEmpty ? nil : messages
        }
        if let index = messages.lastIndex(where: { $0.id == live.id }) {
            messages[index] = live
        } else if !messages.contains(where: {
            $0.role == live.role && ($0.text == live.text || $0.text.hasPrefix(live.text))
        }) {
            messages.append(live)
        }
        if messages.count > 32 { messages.removeFirst(messages.count - 32) }
        return messages.isEmpty ? nil : messages
    }

    private func isTaskInFlight(_ state: CodexRunState) -> Bool {
        state.isActive || state == .awaitingAuthorization || state == .awaitingInput
    }

    func openCodex() {
        #if os(macOS)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        #endif
    }

    /// 当前任务或最近任务的项目目录；用于快捷操作可用性判断。
    var quickActionProjectPath: String? {
        let candidate = snapshot.currentTask.projectPath
            ?? snapshot.recentTasks.compactMap(\.projectPath).first
        guard let candidate, !candidate.isEmpty else { return nil }
        return candidate
    }

    /// 在访达中打开当前项目目录。
    func openProjectDirectory() {
        #if os(macOS)
        guard let path = quickActionProjectPath else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            connectionDetail = "项目目录不存在：\(url.lastPathComponent)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    /// 在项目目录打开终端（优先 iTerm，回退系统 Terminal）。
    func openTerminalAtProject() {
        #if os(macOS)
        let path = quickActionProjectPath ?? NSHomeDirectory()
        let dirURL = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return }
        let candidates = ["com.googlecode.iterm2", "com.apple.Terminal"]
        for bundleID in candidates {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([dirURL], withApplicationAt: appURL, configuration: config)
                return
            }
        }
        #endif
    }

    /// 打开 ChatGPT Codex 用量/额度网页。
    func openUsagePage() {
        #if os(macOS)
        if let url = URL(string: "https://chatgpt.com/codex/settings/usage") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    func copyDiagnostics() -> String {
        let a = snapshot.account
        let p = snapshot.rateLimits.primaryBucket
        let insights = taskUsageInsights()
        return """
        Codex-Pulse Diagnostics
        -----------------------
        Connected: \(snapshot.connectionState.displayName)
        Detail: \(connectionDetail)
        Mock: \(isUsingMock)
        CLI: \(cliPath ?? "not found")
        Email: \(a.displayEmail)
        Plan: \(a.planType.displayName)
        Auth: \(a.authMode.displayName)
        LoggedIn: \(a.isLoggedIn)
        Primary: \(p.map { PulseFormatters.percent($0.usedPercent) } ?? "—")
        Buckets: \(snapshot.rateLimits.buckets.map(\.name).joined(separator: ", "))
        Today tokens: \(PulseFormatters.tokens(snapshot.usage.todayTokens))
        Local today tokens: \(PulseFormatters.tokens(snapshot.usage.localTodayTokens))
        Token velocity: \(PulseFormatters.tokens(snapshot.usage.tokenVelocityPerMinute))/min
        Total tokens: \(PulseFormatters.tokens(snapshot.usage.totalTokens))
        History records: \(TaskHistoryStore.shared.recordCount())
        7d finished tasks: \(insights.finishedTasks)
        7d success rate: \(insights.successRate.map { String(format: "%.0f%%", $0) } ?? "none")
        Sync health: \(syncHealthDetail)
        System notifications: \(settings.resolvedNotificationsEnabled ? "enabled" : "disabled")
        Reset card alert: \(settings.resolvedResetCardExpiryAlertDays) day(s)
        Webhook: \(settings.webhookEnabled ? "enabled" : "disabled")
        Webhook project name: \(settings.resolvedWebhookIncludeProjectName ? "included" : "hidden")
        Webhook status: \(lastWebhookStatus ?? "none")
        Rate forecast enabled: \(settings.resolvedRateLimitForecastEnabled)
        Rate forecast samples: \(TaskHistoryStore.shared.rateLimitSampleCount())
        Rate forecast: \(primaryRateLimitForecastSummary ?? "collecting")
        Rate burn/hour: \(primaryRateLimitForecast.map { String(format: "%.3f%%", $0.burnRatePercentPerHour) } ?? "none")
        Reconnect attempt: \(reconnectAttempt)
        Next reconnect: \(nextReconnectAt.map { String(describing: $0) } ?? "none")
        Last real connection: \(lastRealConnectedAt.map { String(describing: $0) } ?? "none")
        Task: \(snapshot.currentTask.state.rawValue)
        Updated: \(snapshot.updatedAt)
        Error: \(lastError ?? "none")
        Log file: \(PulseLog.logFileURL.path)

        --- recent log ---
        \(PulseLog.tail())
        """
    }

    // MARK: - Private

    private func apply(_ next: PulseSnapshot) {
        let previous = snapshot
        snapshot = next
        // 轮询每次都会刷新 updatedAt，但实质内容常常没变。
        // 仅在内容真正变化时才写共享快照并重载 Widget。
        guard !previous.hasSameContent(as: next) else { return }
        schedulePersist()
    }

    /// 写盘 + Widget 重载合并节流：任务高峰期 token 事件可能每秒多条，
    /// 内存里的 snapshot 实时更新（UI 立即刷新），落盘与 WidgetKit
    /// 时间线重载合并为最多每 1.5 秒一次，避免磁盘与 Widget 进程被打爆。
    private func schedulePersist() {
        pendingPersist = true
        guard persistTask == nil else { return }
        persistTask = Task { [weak self] in
            defer { self?.persistTask = nil }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.pendingPersist else { return }
            self.pendingPersist = false
            SnapshotStore.shared.save(self.snapshot)
            #if os(macOS)
            WidgetBridge.reload()
            #endif
        }
    }

    /// 退出前立即落盘，不等节流窗口。
    func flushPersist() {
        persistTask?.cancel()
        persistTask = nil
        pendingPersist = false
        SnapshotStore.shared.save(snapshot, synchronous: true)
        #if os(macOS)
        WidgetBridge.reload()
        #endif
    }

    /// turn 结束后在 0.75s 与随后 2.5s 各强刷一次：前者追求即时反馈，
    /// 后者覆盖服务端稍晚落账；多个 turn 连续结束时只保留最后一组。
    private func schedulePostTurnRefresh() {
        postTurnRefreshTask?.cancel()
        postTurnRefreshTask = Task { [weak self] in
            guard let self else { return }
            for delay in [0.75, 2.5] as [TimeInterval] {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refreshAll(forceRemote: true)
            }
        }
    }

    /// Session JSONL 是今日 Token 最直接的数据源。文件监听可能在一次响应中
    /// 连续触发多次，120ms 防抖后只做本地增量读取，不等待额度/账户 RPC。
    private func scheduleLocalUsageRefresh() {
        localUsageRefreshTask?.cancel()
        localUsageRefreshRevision &+= 1
        let refreshRevision = localUsageRefreshRevision
        let refreshAccountRevision = accountRevision
        let refreshDayKey = currentDayKey
        guard let monitoredClient = client, monitoredClient.isConnected else { return }

        localUsageRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.didStart,
                  self.localUsageRefreshRevision == refreshRevision,
                  self.accountRevision == refreshAccountRevision,
                  self.currentDayKey == refreshDayKey,
                  self.isCurrentClient(monitoredClient) else { return }

            let previous = self.snapshot
            var usage = await monitoredClient.readLocalUsage(merging: previous.usage)
            guard self.localUsageRefreshRevision == refreshRevision,
                  self.accountRevision == refreshAccountRevision,
                  self.currentDayKey == refreshDayKey,
                  self.isCurrentClient(monitoredClient) else { return }
            if self.shouldPromoteLocalToday(
                usage: usage,
                currentAccount: previous.account
            ), let localToday = usage.localTodayTokens {
                usage.mergeLocalTodayTokens(localToday, promoteToAccountTotals: true)
            }
            if previous.account.authMode == .apiKey,
               let localDaily = usage.localDailyBuckets {
                usage.mergeLocalDailyBuckets(localDaily, promoteToAccountTotals: true)
            }
            self.applyTokenVelocity(to: &usage, previous: previous.usage, sameAccount: true)
            guard usage != previous.usage else { return }
            var next = previous
            next.usage = usage
            next.updatedAt = Date()
            self.apply(next)
            if self.localUsageRefreshRevision == refreshRevision {
                self.localUsageRefreshTask = nil
            }
        }
    }

    private func listenEvents() {
        eventTask?.cancel()
        guard let client else { return }
        eventTask = Task { [weak self] in
            let stream = client.eventStream()
            for await event in stream {
                guard let self else { return }
                guard self.isCurrentClient(client) else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: CodexServerEvent) async {
        switch event {
        case .accountUpdated:
            prepareForAccountTransition()
            await refreshAll(forceRemote: true)

        case .authenticationChanged:
            PulseLog.write("authentication change detected; rebuilding app-server connection")
            connectionDetail = "正在应用新的登录账号…"
            await reconnectCore()

        case .rateLimitsUpdated(let limits):
            guard !isAccountTransitioning else {
                PulseLog.write("ignored rate-limit notification during account transition")
                break
            }
            // Sparse update from notification — prefer merge by bucket id when non-empty
            let previous = snapshot
            var next = previous
            if limits.buckets.isEmpty {
                // ignore empty
            } else if previous.rateLimits.buckets.isEmpty {
                recordSyncSuccess(.rateLimits)
                next.rateLimits = limits
            } else {
                recordSyncSuccess(.rateLimits)
                var buckets = previous.rateLimits.buckets
                for b in limits.buckets {
                    if let idx = buckets.firstIndex(where: { $0.id == b.id }) {
                        buckets[idx] = b
                    } else if let idx = buckets.firstIndex(where: { $0.name == b.name }) {
                        buckets[idx] = b
                    } else {
                        buckets.append(b)
                    }
                }
                next.rateLimits = RateLimitSnapshot(
                    buckets: buckets,
                    resetCards: previous.rateLimits.resetCards.isEmpty ? limits.resetCards : previous.rateLimits.resetCards,
                    updatedAt: Date()
                )
            }
            if !limits.buckets.isEmpty {
                await updateRateLimitForecastOffMain(from: next.rateLimits)
            }
            next.primaryRateLimitForecast = settings.resolvedRateLimitForecastEnabled
                ? primaryRateLimitForecast
                : nil
            next.connectionState = connectedStateForSyncHealth()
            next.updatedAt = Date()
            apply(next)
            evaluateAlerts(previous: previous, current: next)

        case .threadsChanged:
            // App Server 通知及 session 文件写入统一走本地即时状态通道；
            // 绝不在这里请求额度/Token，避免状态变化被远端接口延迟。
            if let client, client.isConnected {
                await refreshLiveTaskStatus(using: client)
            }
            if hasActivelyRunningTask, pollTask == nil {
                startPolling()
            }
            scheduleLocalUsageRefresh()

        case .localTaskStateChanged(let record):
            recordSyncSuccess(.threads)
            rolloverDayIfNeeded()
            let previous = snapshot
            var next = previous
            if let totalTokens = record.tokenUsage {
                _ = mergeRealtimeThreadTokenTotal(
                    threadID: record.id,
                    totalTokens: totalTokens,
                    into: &next.usage
                )
            }
            mergeLiveTaskStates([record], into: &next.recentTasks)
            let state = record.runState ?? .idle
            let wasCurrentInFlight = previous.currentTask.id == record.id
                && isTaskInFlight(previous.currentTask.state)
            if !isTaskInFlight(state) {
                locallyCompletedTaskAt[record.id] = Date()
            }

            if isTaskInFlight(state) {
                consecutiveLiveIdlePolls = 0
                lastActiveTaskEvidenceAt = Date()
                locallyCompletedTaskAt.removeValue(forKey: record.id)
                var current = currentTask(from: record, preserving: previous.currentTask)
                current.state = state
                next.currentTask = current
            } else if previous.currentTask.id == record.id {
                // final_answer/task_complete 是该线程的确定结束信号，直接切空闲，
                // 不再等待全局扫描或连续两次空闲确认。
                consecutiveLiveIdlePolls = 0
                lastActiveTaskEvidenceAt = nil
                var idle = CurrentTaskInfo.empty
                idle.state = next.account.isLoggedIn ? .idle : .notStarted
                next.currentTask = idle
                if let index = next.recentTasks.firstIndex(where: { $0.id == record.id }) {
                    next.recentTasks[index].runState = .idle
                    next.recentTasks[index].startedAt = nil
                }
            }

            next.connectionState = connectedStateForSyncHealth()
            next.updatedAt = Date()
            if next.currentTask.state != previous.currentTask.state
                || next.currentTask.id != previous.currentTask.id {
                PulseLog.write(
                    "local file state: \(previous.currentTask.state.rawValue) -> \(next.currentTask.state.rawValue)"
                )
            }
            apply(next)
            scheduleLocalUsageRefresh()

            if wasCurrentInFlight, !isTaskInFlight(state) {
                startPolling()
                schedulePostTurnRefresh()
                // 若还有并行任务，立即从本地活动列表选出下一项。
                if let client, client.isConnected {
                    await refreshLiveTaskStatus(using: client)
                }
            } else if isTaskInFlight(state), pollTask == nil {
                startPolling()
            }

        case .turnStarted(let task):
            recordSyncSuccess(.threads)
            lastActiveTaskEvidenceAt = Date()
            locallyCompletedTaskAt.removeValue(forKey: task.id)
            var next = snapshot
            next.connectionState = connectedStateForSyncHealth()
            var t = task
            // Preserve project path from previous if missing
            if t.projectPath == nil {
                t.projectPath = snapshot.currentTask.projectPath
                t.projectName = t.projectName ?? snapshot.currentTask.projectName
            }
            if t.startedAt == nil { t.startedAt = Date() }
            next.currentTask = t
            next.updatedAt = Date()
            apply(next)
            startPolling()

        case .turnCompleted(let task):
            recordSyncSuccess(.threads)
            lastActiveTaskEvidenceAt = nil
            let previous = snapshot
            var next = previous
            next.connectionState = connectedStateForSyncHealth()
            var t = task
            if t.projectPath == nil {
                t.projectPath = previous.currentTask.projectPath
                t.projectName = t.projectName ?? previous.currentTask.projectName
            }
            next.currentTask = t
            if !isUsingMock {
                let record = TaskRecord(
                    id: t.id,
                    projectName: t.projectName ?? "Codex",
                    projectPath: t.projectPath,
                    gitBranch: t.gitBranch,
                    model: t.model,
                    tokenUsage: nil,
                    durationSeconds: t.elapsedSeconds,
                    succeeded: t.state == .completed,
                    filesChanged: t.filesChanged,
                    summary: t.lastStatusMessage,
                    finishedAt: Date(),
                    runState: t.state,
                    activeFlags: nil,
                    startedAt: t.startedAt
                )
                TaskHistoryStore.shared.persist([record], retentionDays: settings.historyRetentionDays)
                next.recentTasks = TaskHistoryStore.shared.persistAndMerge(
                    liveTasks: next.recentTasks,
                    retentionDays: settings.historyRetentionDays,
                    limit: 100
                )
            }
            next.updatedAt = Date()
            apply(next)
            evaluateAlerts(previous: previous, current: next)
            // 完成事件已提供最终状态；之后仅每 30 秒补刷 3 次，不立即额外请求。
            startPolling()
            // 任务结束是额度/Token 真正变动的时刻。客户端缓存 TTL(12s/60s)
            // 会让紧随其后的轮询命中旧值，这里延迟 2 秒强制拉一次远端，
            // 让额度百分比和今日 Token 在任务结束后数秒内到位。
            schedulePostTurnRefresh()

        case .agentMessageDelta(let threadID, let itemID, let delta):
            guard !delta.isEmpty else { break }
            var next = snapshot
            var messages = next.currentTask.conversation ?? []
            if let index = messages.lastIndex(where: { $0.id == itemID }) {
                messages[index].text += delta
                messages[index].isStreaming = true
            } else {
                messages.append(TaskConversationMessage(
                    id: itemID,
                    role: .assistant,
                    text: delta,
                    timestamp: Date(),
                    isStreaming: true
                ))
            }
            if messages.count > 32 { messages.removeFirst(messages.count - 32) }
            next.currentTask.conversation = messages
            next.currentTask.state = .generatingCode
            next.currentTask.lastStatusMessage = "正在输出回复"
            if next.currentTask.id == CurrentTaskInfo.empty.id {
                next.currentTask.id = threadID
            }
            if next.currentTask.startedAt == nil { next.currentTask.startedAt = Date() }
            next.updatedAt = Date()
            apply(next)
            startPolling()

        case .itemStarted(let step):
            recordSyncSuccess(.threads)
            lastActiveTaskEvidenceAt = Date()
            var next = snapshot
            next.connectionState = connectedStateForSyncHealth()
            next.currentTask.currentStep = step
            next.currentTask.lastStatusMessage = step
            if !next.currentTask.state.isActive && next.currentTask.state != .awaitingAuthorization {
                next.currentTask.state = .callingTool
            }
            // Heuristic state from item type string
            let lower = step.lowercased()
            if lower.contains("command") { next.currentTask.state = .executingCommand }
            else if lower.contains("file") || lower.contains("change") { next.currentTask.state = .modifyingFiles }
            else if lower.contains("reason") { next.currentTask.state = .thinking }
            else if lower.contains("message") || lower.contains("agent") { next.currentTask.state = .generatingCode }
            next.updatedAt = Date()
            apply(next)
            // 某些 App Server 版本只发送 itemStarted；立刻切换为 15 秒主动轮询，
            // 不等待原先可能尚未结束的 30 秒空闲补刷计时器。
            startPolling()

        case .itemCompleted:
            if var messages = snapshot.currentTask.conversation,
               let index = messages.indices.last,
               messages[index].role == .assistant,
               messages[index].isStreaming {
                messages[index].isStreaming = false
                var next = snapshot
                next.currentTask.conversation = messages
                next.updatedAt = Date()
                apply(next)
            }

        case .tokenUsageUpdated(let threadID, _, let totalTokens):
            // 事件值是该线程截至当前的累计量；转成增量后并入“今日 Token”。
            rolloverDayIfNeeded()
            var next = snapshot
            guard mergeRealtimeThreadTokenTotal(
                threadID: threadID,
                totalTokens: totalTokens,
                into: &next.usage
            ) else { break }
            next.updatedAt = Date()
            apply(next)

        case .connectionLost(let msg):
            // 断线后线程累计值可能重置或错乱，重连时重新建立基线。
            threadTokenTotals.removeAll()
            var next = snapshot
            next.connectionState = .error
            next.updatedAt = Date()
            apply(next)
            lastError = msg
            connectionDetail = "连接断开"
            pollTask?.cancel()
            rateLimitMonitorTask?.cancel()
            rateLimitMonitorTask = nil
            cancelUnhealthyConnectionRecovery()
            scheduleRealConnectionRecovery()

        case .connectionRestored:
            var next = snapshot
            next.connectionState = .connected
            next.updatedAt = Date()
            apply(next)
            lastError = nil
            connectionDetail = "已重连"
            if let client, client is StdioCodexAppServerClient {
                markRealConnectionRestored()
            }
            await refreshAll(forceRemote: true)
        }
    }

    /// App Server 通知与本地 JSONL 文件监听共享同一线程基线，避免同一批
    /// token_count 被两个实时通道重复累加。首次只建立基线，之后只接受递增值；
    /// 压缩导致计数器重置时由紧随其后的本地完整汇总校正。
    @discardableResult
    private func mergeRealtimeThreadTokenTotal(
        threadID: String,
        totalTokens: Int64,
        into usage: inout UsageStats
    ) -> Bool {
        guard totalTokens >= 0 else { return false }
        guard let previousTotal = threadTokenTotals[threadID] else {
            threadTokenTotals[threadID] = totalTokens
            return false
        }
        if totalTokens < previousTotal {
            // 上下文压缩会重置线程累计器；先切换到新基线，下一次写入即可继续实时累加。
            threadTokenTotals[threadID] = totalTokens
            return false
        }
        guard totalTokens > previousTotal else { return false }

        threadTokenTotals[threadID] = totalTokens
        let delta = totalTokens - previousTotal
        let baseline = usage.todayTokens ?? 0
        usage.mergeEventTodayTokens(baseline + delta)
        if let total = usage.totalTokens {
            usage.totalTokens = total + delta
        }
        return true
    }

    private func prepareForAccountTransition() {
        accountRevision &+= 1
        isAccountTransitioning = true
        client?.invalidateAccountScopedState()
        postTurnRefreshTask?.cancel()
        postTurnRefreshTask = nil
        localUsageRefreshTask?.cancel()
        localUsageRefreshTask = nil
        localUsageRefreshRevision &+= 1
        threadTokenTotals.removeAll()
        smoothedTokenVelocity = nil
        isTokenSpikeActive = false
        lastTokenSpikeAlertAt = nil
        notifiedThresholds.removeAll()
        didRestoreNotifiedThresholds = false
        primaryRateLimitForecast = nil
        syncHealth[.account] = .empty
        syncHealth[.rateLimits] = .empty
        syncHealth[.usage] = .empty

        var next = snapshot
        next.account = .empty
        next.rateLimits = .empty
        next.usage = .empty
        next.primaryRateLimitForecast = nil
        next.updatedAt = Date()
        apply(next)
        lastError = nil
        connectionDetail = "已连接 · 正在切换账号…"
        PulseLog.write("account update detected; cleared account-scoped snapshot")
    }

    private func isCurrentClient(_ candidate: any CodexAppServerClient) -> Bool {
        guard let current = client else { return false }
        return ObjectIdentifier(current) == ObjectIdentifier(candidate)
    }

    private func sameAccountIdentity(_ lhs: AccountInfo, _ rhs: AccountInfo) -> Bool {
        guard lhs.isLoggedIn == rhs.isLoggedIn else { return false }
        guard lhs.isLoggedIn else { return true }
        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }
        return lhs.authMode == rhs.authMode
            && normalized(lhs.email) == normalized(rhs.email)
            && normalized(lhs.workspaceName) == normalized(rhs.workspaceName)
    }

    /// 今日标题数字是“本机当天全部 Codex session”口径。账号切换只隔离远端
    /// 生命周期与历史桶，不应让今日值消失并要求用户重启应用。
    private func shouldPromoteLocalToday(
        usage: UsageStats,
        currentAccount: AccountInfo
    ) -> Bool {
        usage.localTodayTokens != nil && currentAccount.isLoggedIn
    }

    private func markRealConnectionRestored() {
        cancelUnhealthyConnectionRecovery()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectRecoveryID = nil
        reconnectAttempt = 0
        nextReconnectAt = nil
        lastRealConnectedAt = Date()
    }

    private func cancelRealConnectionRecovery() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectRecoveryID = nil
        reconnectAttempt = 0
        nextReconnectAt = nil
    }

    private func cancelUnhealthyConnectionRecovery() {
        unhealthyRecoveryTask?.cancel()
        unhealthyRecoveryTask = nil
        unhealthyRecoveryID = nil
    }

    private func scheduleUnhealthyConnectionRecovery() {
        guard !isUsingMock,
              let current = client as? StdioCodexAppServerClient,
              current.isConnected,
              unhealthyRecoveryTask == nil else {
            return
        }

        let recoveryID = UUID()
        unhealthyRecoveryID = recoveryID
        unhealthyRecoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 给下一次实时事件或短暂服务抖动留出自行恢复的机会。
                try await Task.sleep(nanoseconds: 2_500_000_000)
            } catch {
                if self.unhealthyRecoveryID == recoveryID {
                    self.unhealthyRecoveryTask = nil
                    self.unhealthyRecoveryID = nil
                }
                return
            }

            guard self.didStart,
                  !Task.isCancelled,
                  self.unhealthyRecoveryID == recoveryID,
                  self.hasCriticalSyncFailure else {
                if self.unhealthyRecoveryID == recoveryID {
                    self.unhealthyRecoveryTask = nil
                    self.unhealthyRecoveryID = nil
                }
                return
            }

            PulseLog.write("critical sync endpoints unhealthy; restarting app-server connection")
            self.unhealthyRecoveryTask = nil
            self.unhealthyRecoveryID = nil
            await self.reconnect()
        }
    }

    private func scheduleRealConnectionRecovery() {
        guard didStart, reconnectTask == nil else { return }
        let backoffSeconds: [TimeInterval] = cliPath == nil
            ? [30, 60, 120, 300]
            : [2, 5, 15, 30, 60, 120, 300]
        let recoveryID = UUID()
        reconnectRecoveryID = recoveryID

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  self.didStart,
                  self.reconnectRecoveryID == recoveryID {
                let index = min(self.reconnectAttempt, backoffSeconds.count - 1)
                let delay = backoffSeconds[index]
                self.reconnectAttempt += 1
                self.nextReconnectAt = Date().addingTimeInterval(delay)
                self.connectionDetail = self.isUsingMock
                    ? "演示模式 · \(Int(delay)) 秒后尝试恢复真实连接"
                    : "连接断开 · \(Int(delay)) 秒后自动重连"

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
                guard !Task.isCancelled,
                      self.didStart,
                      self.reconnectRecoveryID == recoveryID else { break }

                self.nextReconnectAt = nil
                if await self.restoreRealConnection() {
                    self.reconnectAttempt = 0
                    self.nextReconnectAt = nil
                    if self.reconnectRecoveryID == recoveryID {
                        self.reconnectTask = nil
                        self.reconnectRecoveryID = nil
                    }
                    return
                }
            }
            if self.reconnectRecoveryID == recoveryID {
                self.nextReconnectAt = nil
                self.reconnectTask = nil
                self.reconnectRecoveryID = nil
            }
        }
    }

    private func restoreRealConnection() async -> Bool {
        if let current = client as? StdioCodexAppServerClient, current.isConnected {
            lastRealConnectedAt = Date()
            return true
        }

        let candidate = StdioCodexAppServerClient()
        do {
            try await candidate.connect()
        } catch {
            await candidate.disconnect()
            lastError = "真实连接恢复失败：\(error.localizedDescription)"
            PulseLog.write("real connection recovery failed: \(error.localizedDescription)")
            return false
        }

        guard didStart, !Task.isCancelled else {
            await candidate.disconnect()
            return false
        }

        let previousClient = client
        cancelUnhealthyConnectionRecovery()
        eventTask?.cancel()
        pollTask?.cancel()
        rateLimitMonitorTask?.cancel()
        rateLimitMonitorTask = nil
        client = candidate
        isUsingMock = false
        cliPath = try? StdioCodexAppServerClient.findCodexCLI()
        var next = snapshot
        next.connectionState = .connected
        next.updatedAt = Date()
        apply(next)
        connectionDetail = "真实连接已自动恢复"
        lastError = nil
        lastRealConnectedAt = Date()

        await previousClient?.disconnect()
        listenEvents()
        startLiveTaskStatusMonitoring()
        startPolling()
        startRateLimitMonitoring()

        // 若旧客户端还有刷新在收尾，等待其退出后再用新客户端拉取，避免跳过首次真实数据。
        Task { [weak self] in
            guard let self else { return }
            while self.didStart, self.isRefreshing, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard self.didStart, !Task.isCancelled else { return }
            await self.refreshAll(forceRemote: true)
        }
        PulseLog.write("real connection recovered automatically")
        return true
    }

    private var hasActivelyRunningTask: Bool {
        snapshot.currentTask.state.isActive
            || snapshot.recentTasks.contains(where: { $0.runState?.isActive == true })
    }

    private func startPolling(resetIdleBudget: Bool = true) {
        pollTask?.cancel()
        pollTask = nil
        if resetIdleBudget {
            idleFollowUpPollsRemaining = idleFollowUpPollCount
        }
        scheduleNextPoll()
    }

    private func scheduleNextPoll() {
        guard didStart, client?.isConnected == true else {
            pollTask = nil
            return
        }

        let wasActive = hasActivelyRunningTask
        let interval: TimeInterval
        if wasActive {
            idleFollowUpPollsRemaining = idleFollowUpPollCount
            interval = activePollingInterval
        } else if idleFollowUpPollsRemaining > 0 {
            interval = idlePollingInterval
        } else {
            pollTask = nil
            PulseLog.write("adaptive polling entered silent mode")
            return
        }

        pollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.runScheduledPoll(wasActive: wasActive)
        }
    }

    private func runScheduledPoll(wasActive: Bool) async {
        pollTask = nil
        await refreshAll()

        // refreshAll 发现活动任务时会自行恢复轮询，避免重复调度。
        if pollTask != nil { return }

        if hasActivelyRunningTask {
            idleFollowUpPollsRemaining = idleFollowUpPollCount
        } else if wasActive {
            // 本轮刚检测到任务结束；从现在开始安排 3 次 30 秒补刷。
            idleFollowUpPollsRemaining = idleFollowUpPollCount
        } else {
            idleFollowUpPollsRemaining = max(0, idleFollowUpPollsRemaining - 1)
        }
        scheduleNextPoll()
    }

    // MARK: - Persistent rate-limit monitoring

    /// 额度刷新不能跟随任务轮询进入 silent mode。小圆球、菜单栏和 Widget 都直接读取
    /// `snapshot.rateLimits`，因此这里持续做一条只请求额度的轻量通道。
    private func startRateLimitMonitoring() {
        rateLimitMonitorTask?.cancel()
        rateLimitMonitorTask = nil
        guard didStart, !isUsingMock, client?.isConnected == true else { return }

        rateLimitMonitorTask = Task { [weak self] in
            guard let self else { return }
            while self.didStart, !Task.isCancelled {
                let delay = self.nextRateLimitMonitorDelay(reference: Date())
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
                guard self.didStart, !Task.isCancelled else { break }
                let forceRemote = self.hasDueRateLimitReset(reference: Date())
                await self.refreshRateLimitsOnly(forceRemote: forceRemote)
            }
            if !self.didStart || Task.isCancelled {
                self.rateLimitMonitorTask = nil
            }
        }
    }

    /// 在额度重置时间附近精确唤醒；如果服务端仍返回旧窗口，则每 3 秒强刷一次。
    private func nextRateLimitMonitorDelay(reference: Date) -> TimeInterval {
        let resetDates = snapshot.rateLimits.buckets.compactMap(\.resetsAt)
        guard let nearestReset = resetDates.min() else {
            return idleRateLimitPollingInterval
        }
        if nearestReset <= reference {
            return dueRateLimitRetryInterval
        }
        let untilReset = nearestReset.timeIntervalSince(reference) + rateLimitResetGraceInterval
        return min(idleRateLimitPollingInterval, max(0.25, untilReset))
    }

    private func hasDueRateLimitReset(reference: Date) -> Bool {
        snapshot.rateLimits.buckets.contains {
            guard let resetsAt = $0.resetsAt else { return false }
            return resetsAt.addingTimeInterval(rateLimitResetGraceInterval) <= reference
        }
    }

    /// 与完整 profile 刷新解耦，避免为了更新一个百分比同时拉取账号、线程和 Token。
    /// 完整刷新正在执行时直接让路；持久监控会在下一周期补上。
    private func refreshRateLimitsOnly(forceRemote: Bool) async {
        guard didStart,
              !isRefreshing,
              !isAccountTransitioning,
              let monitoredClient = client,
              monitoredClient.isConnected else { return }

        let revision = accountRevision
        do {
            let limits = try await monitoredClient.readRateLimits(forceRefresh: forceRemote)
            guard didStart,
                  revision == accountRevision,
                  isCurrentClient(monitoredClient),
                  !limits.buckets.isEmpty else { return }

            await updateRateLimitForecastOffMain(from: limits)
            guard didStart,
                  revision == accountRevision,
                  isCurrentClient(monitoredClient) else { return }

            let previous = snapshot
            var next = previous
            next.rateLimits = limits
            next.primaryRateLimitForecast = settings.resolvedRateLimitForecastEnabled
                ? primaryRateLimitForecast
                : nil
            recordSyncSuccess(.rateLimits)
            next.connectionState = connectedStateForSyncHealth()
            next.updatedAt = Date()
            apply(next)
            evaluateAlerts(previous: previous, current: next)

            if forceRemote {
                let remaining = limits.primaryBucket.map {
                    String(format: "%.0f%%", $0.remainingPercent)
                } ?? "—"
                PulseLog.write("rate-limit reset boundary refresh: remaining=\(remaining)")
            }
        } catch {
            if case CodexServerError.requestDeferred = error {
                return
            }
            recordSyncFailure(.rateLimits, message: error.localizedDescription)
            PulseLog.write("rate-limit monitor refresh failed: \(error.localizedDescription)")
        }
    }

    /// 兼容旧设置调用：重新启动自适应轮询。
    func reschedulePolling() {
        guard didStart, client != nil else { return }
        startPolling()
    }

    func saveSettings() {
        settings.normalizeRefreshInterval()
        SettingsStore.shared.save(settings)
    }

    func updateHistoryRetention() {
        saveSettings()
        TaskHistoryStore.shared.prune(retentionDays: settings.historyRetentionDays)
    }

    func updateRateLimitForecastSetting() {
        saveSettings()
        if settings.resolvedRateLimitForecastEnabled {
            updateRateLimitForecast(from: snapshot.rateLimits)
        } else {
            primaryRateLimitForecast = nil
        }
        var next = snapshot
        next.primaryRateLimitForecast = primaryRateLimitForecast
        next.updatedAt = Date()
        apply(next)
    }

    func rateLimitSampleCount() -> Int {
        TaskHistoryStore.shared.rateLimitSampleCount()
    }

    func clearRateLimitSamples() {
        TaskHistoryStore.shared.clearRateLimitSamples()
        primaryRateLimitForecast = nil
        var next = snapshot
        next.primaryRateLimitForecast = nil
        next.updatedAt = Date()
        apply(next)
    }

    func taskHistoryCount() -> Int {
        TaskHistoryStore.shared.recordCount()
    }

    func clearTaskHistory() {
        TaskHistoryStore.shared.clear()
    }

    func exportTaskHistory(to url: URL) throws {
        try TaskHistoryStore.shared.csvData().write(to: url, options: .atomic)
    }

    func taskUsageInsights(days: Int = 7, reference: Date = Date()) -> TaskUsageInsights {
        TaskUsageInsights.calculate(
            from: analyticsTasks(days: days, reference: reference),
            days: days,
            reference: reference
        )
    }

    func usageReportMarkdown(days: Int = 7, reference: Date = Date()) -> String {
        let insights = taskUsageInsights(days: days, reference: reference)
        let generated = DateFormatter()
        generated.locale = Locale(identifier: "zh_Hans_CN")
        generated.dateFormat = "yyyy-MM-dd HH:mm"

        let successRate = insights.successRate.map { String(format: "%.0f%%", $0) } ?? "—"
        let averageDuration = insights.averageDurationSeconds.map(PulseFormatters.duration) ?? "—"
        let longestDuration = insights.longestDurationSeconds.map(PulseFormatters.duration) ?? "—"
        let topProject = insights.topProjectName.map {
            "\($0)（\(insights.topProjectTaskCount) 个任务）"
        } ?? "—"
        let primary = snapshot.rateLimits.primaryBucket

        return """
        # Codex-Pulse 近 \(insights.periodDays) 日使用报告

        生成时间：\(generated.string(from: reference))

        ## Token 用量

        - 今日：\(PulseFormatters.tokens(snapshot.usage.todayTokens))
        - 近 7 日：\(PulseFormatters.tokens(snapshot.usage.last7DaysTokens))
        - 近 30 日：\(PulseFormatters.tokens(snapshot.usage.last30DaysTokens))
        - 累计：\(PulseFormatters.tokens(snapshot.usage.totalTokens))
        - 当前连续使用：\(snapshot.usage.currentStreakDays.map { "\($0) 天" } ?? "—")

        ## 任务效率

        - 已结束任务：\(insights.finishedTasks)
        - 成功：\(insights.successfulTasks)
        - 失败：\(insights.failedTasks)
        - 成功率：\(successRate)
        - 平均耗时：\(averageDuration)
        - 最长耗时：\(longestDuration)
        - 高频项目：\(topProject)
        - 当前进行中：\(insights.activeTasks)

        ## 当前额度

        - 主额度剩余：\(primary.map { PulseFormatters.percent($0.remainingPercent) } ?? "—")
        - 距离重置：\(PulseFormatters.countdown(primary?.resetCountdown))
        - 可用重置卡：\(snapshot.rateLimits.availableResetCardCount)
        - 消耗预测：\(primaryRateLimitForecastSummary ?? "样本积累中")

        > 报告仅在本机生成；项目名称只会在你主动复制本报告时进入剪贴板。
        """
    }

    func exportUsageReport(to url: URL, days: Int = 7) throws {
        try Data(usageReportMarkdown(days: days).utf8).write(to: url, options: .atomic)
    }

    private func analyticsTasks(days: Int, reference: Date) -> [TaskRecord] {
        let safeDays = max(1, days)
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -(safeDays - 1),
            to: Calendar.current.startOfDay(for: reference)
        ) ?? reference.addingTimeInterval(-TimeInterval(safeDays * 86_400))

        // 活动状态优先使用内存快照；已结束任务优先使用 SQLite 中保留的完整运行状态。
        var combined = snapshot.recentTasks.filter {
            $0.runState?.isActive == true
                || $0.runState == .awaitingAuthorization
                || $0.runState == .awaitingInput
        }
        if settings.historyRetentionDays > 0 {
            combined.append(contentsOf: TaskHistoryStore.shared.tasks(since: cutoff))
        }
        combined.append(contentsOf: snapshot.recentTasks)
        var seen: Set<String> = []
        return combined.filter { seen.insert($0.id).inserted }
    }

    func saveWebhookSettings() {
        if settings.webhookEnabled,
           WebhookService.validatedURL(settings.webhookURL) == nil {
            settings.webhookEnabled = false
            lastWebhookStatus = "地址无效，Webhook 未启用"
        }
        saveSettings()
    }

    func testWebhook() async {
        guard WebhookService.validatedURL(settings.webhookURL) != nil else {
            lastWebhookStatus = "地址无效；请使用 HTTPS 或本机 HTTP"
            return
        }
        lastWebhookStatus = "正在发送测试消息…"
        do {
            try await WebhookService.shared.send(
                rawURL: settings.webhookURL,
                event: "test",
                title: "Codex-Pulse Webhook 测试",
                body: "Webhook 已成功连接。",
                details: [:]
            )
            lastWebhookStatus = "测试成功 · \(PulseFormatters.shortTime(Date()))"
        } catch {
            lastWebhookStatus = error.localizedDescription
        }
    }

    private func sendWebhook(
        event: String,
        title: String,
        body: String,
        project: String? = nil,
        details: [String: String] = [:]
    ) {
        guard settings.webhookEnabled,
              WebhookService.validatedURL(settings.webhookURL) != nil else { return }
        var safeDetails = details
        if settings.resolvedWebhookIncludeProjectName,
           let project, !project.isEmpty {
            safeDetails["project"] = project
        }
        let rawURL = settings.webhookURL
        Task { [weak self] in
            do {
                try await WebhookService.shared.send(
                    rawURL: rawURL,
                    event: event,
                    title: title,
                    body: body,
                    details: safeDetails
                )
                self?.lastWebhookStatus = "最近发送成功 · \(PulseFormatters.shortTime(Date()))"
            } catch {
                self?.lastWebhookStatus = error.localizedDescription
                PulseLog.write("webhook \(event) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 阈值通知去重持久化

    /// 以“额度桶 id + 重置时间”作为窗口标识：同一窗口内重启不重复弹
    /// 70%/85% 提醒；额度重置后窗口标识变化，自动重新武装。
    private func thresholdWindowKey(for bucket: RateLimitBucket?) -> String {
        guard let bucket else { return "none" }
        let reset = bucket.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        return "\(bucket.id)|\(reset)"
    }

    private func persistNotifiedThresholds(for bucket: RateLimitBucket?) {
        let defaults = UserDefaults.standard
        defaults.set(thresholdWindowKey(for: bucket), forKey: "pulse.notifiedThresholds.window")
        defaults.set(notifiedThresholds.sorted(), forKey: "pulse.notifiedThresholds.values")
    }

    /// 启动后首次评估时恢复；仅当仍处于同一额度窗口才生效。
    private func restoreNotifiedThresholdsIfNeeded(for bucket: RateLimitBucket?) {
        guard !didRestoreNotifiedThresholds else { return }
        didRestoreNotifiedThresholds = true
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "pulse.notifiedThresholds.window") == thresholdWindowKey(for: bucket),
              let stored = defaults.array(forKey: "pulse.notifiedThresholds.values") as? [Int] else {
            return
        }
        notifiedThresholds.formUnion(stored)
    }

    private func evaluateAlerts(previous: PulseSnapshot, current: PulseSnapshot) {
        if let used = current.rateLimits.primaryBucket?.usedPercent {
            restoreNotifiedThresholdsIfNeeded(for: current.rateLimits.primaryBucket)
            let previousUsed = previous.rateLimits.primaryBucket?.usedPercent
            let sortedThresholds = settings.alertThresholds.sorted()
            let initialThreshold = sortedThresholds.last(where: { $0 <= used })
            for t in sortedThresholds {
                let key = Int(t)
                let crossedThreshold = previousUsed.map { $0 < t }
                    ?? (initialThreshold.map { $0 == t } ?? false)
                if used >= t && crossedThreshold && !notifiedThresholds.contains(key) {
                    notifiedThresholds.insert(key)
                    persistNotifiedThresholds(for: current.rateLimits.primaryBucket)
                    if settings.resolvedNotificationsEnabled {
                        NotificationService.shared.notifyRateLimit(
                            percent: used,
                            threshold: t,
                            soundEnabled: settings.soundEnabled
                        )
                    }
                    sendWebhook(
                        event: "rate_limit_warning",
                        title: "额度使用达到 \(Int(t))%",
                        body: "主额度已使用 \(Int(used))%。",
                        details: [
                            "used_percent": String(format: "%.1f", used),
                            "threshold_percent": String(format: "%.0f", t)
                        ]
                    )
                }
            }

            // 下降超过回差后允许下一轮重新提醒，避免临界值抖动反复通知。
            var thresholdsChanged = false
            for key in Array(notifiedThresholds) where used < Double(key) - 5 {
                notifiedThresholds.remove(key)
                thresholdsChanged = true
            }
            if thresholdsChanged {
                persistNotifiedThresholds(for: current.rateLimits.primaryBucket)
            }

            let isExhausted = current.rateLimits.primaryBucket?.isLimitReached == true || used >= 100
            let wasExhausted = previous.rateLimits.primaryBucket?.isLimitReached == true || (previousUsed ?? 0) >= 100
            if isExhausted && !wasExhausted {
                if settings.resolvedNotificationsEnabled {
                    NotificationService.shared.notifyExhausted(soundEnabled: settings.soundEnabled)
                }
                sendWebhook(
                    event: "rate_limit_exhausted",
                    title: "额度已耗尽",
                    body: "主额度窗口已触发限额。",
                    details: ["used_percent": String(format: "%.1f", used)]
                )
            }
            if let previousUsed, previousUsed >= 20, used <= 5, previousUsed - used >= 15 {
                if settings.resolvedNotificationsEnabled {
                    NotificationService.shared.notifyRateLimitReset(soundEnabled: settings.soundEnabled)
                }
                sendWebhook(
                    event: "rate_limit_reset",
                    title: "额度已重置",
                    body: "主额度窗口已恢复。",
                    details: ["used_percent": String(format: "%.1f", used)]
                )
            }
        }

        // 任务通知不依赖额度接口，额度同步失败时也应正常工作。
        if previous.currentTask.state.isActive
            && (current.currentTask.state == .completed || current.currentTask.state == .idle) {
            if settings.resolvedNotificationsEnabled {
                NotificationService.shared.notifyTaskCompleted(
                    project: previous.currentTask.projectName,
                    soundEnabled: settings.soundEnabled
                )
            }
            sendWebhook(
                event: "task_completed",
                title: "任务已完成",
                body: "Codex 任务已完成。",
                project: previous.currentTask.projectName,
                details: [
                    "duration_seconds": String(format: "%.0f", previous.currentTask.elapsedSeconds)
                ]
            )
        }
        if current.currentTask.state == .failed && previous.currentTask.state != .failed {
            if settings.resolvedNotificationsEnabled {
                NotificationService.shared.notifyTaskFailed(
                    project: current.currentTask.projectName,
                    soundEnabled: settings.soundEnabled
                )
            }
            sendWebhook(
                event: "task_failed",
                title: "任务执行失败",
                body: "Codex 任务执行失败。",
                project: current.currentTask.projectName
            )
        }
        if current.currentTask.state == .awaitingAuthorization
            && previous.currentTask.state != .awaitingAuthorization {
            if settings.resolvedNotificationsEnabled {
                NotificationService.shared.notifyAwaitingAuth(soundEnabled: settings.soundEnabled)
            }
            sendWebhook(
                event: "awaiting_authorization",
                title: "等待用户授权",
                body: "Codex 正在等待用户确认操作。",
                project: current.currentTask.projectName
            )
        }
        if current.currentTask.state == .awaitingInput
            && previous.currentTask.state != .awaitingInput {
            if settings.resolvedNotificationsEnabled {
                NotificationService.shared.notifyAwaitingInput(soundEnabled: settings.soundEnabled)
            }
            sendWebhook(
                event: "awaiting_input",
                title: "等待用户输入",
                body: "Codex 需要补充信息后才能继续。",
                project: current.currentTask.projectName
            )
        }
        evaluateLongTaskAlerts(current: current)
        evaluateTokenSpikeAlert(current: current)
        evaluateResetCardExpiryAlerts(current: current)
    }

    private func evaluateLongTaskAlerts(current: PulseSnapshot) {
        let thresholdMinutes = settings.resolvedLongTaskAlertMinutes
        guard thresholdMinutes > 0 else {
            notifiedLongTaskIDs.removeAll()
            return
        }

        var candidates: [(id: String, project: String?, startedAt: Date)] = []
        if current.currentTask.state.isActive, let startedAt = current.currentTask.startedAt {
            candidates.append((current.currentTask.id, current.currentTask.projectName, startedAt))
        }
        for task in current.recentTasks where task.runState?.isActive == true {
            guard let startedAt = task.startedAt else { continue }
            candidates.append((task.id, task.projectName, startedAt))
        }

        var activeIDs: Set<String> = []
        for candidate in candidates {
            guard activeIDs.insert(candidate.id).inserted else { continue }
            let elapsed = max(0, Date().timeIntervalSince(candidate.startedAt))
            guard elapsed >= TimeInterval(thresholdMinutes * 60),
                  notifiedLongTaskIDs.insert(candidate.id).inserted else {
                continue
            }
            if settings.resolvedNotificationsEnabled {
                NotificationService.shared.notifyLongTask(
                    taskID: candidate.id,
                    project: candidate.project,
                    minutes: max(thresholdMinutes, Int(elapsed / 60)),
                    soundEnabled: settings.soundEnabled
                )
            }
            sendWebhook(
                event: "long_running_task",
                title: "Codex 任务仍在运行",
                body: "任务运行时间已超过提醒阈值。",
                project: candidate.project,
                details: ["elapsed_minutes": String(Int(elapsed / 60))]
            )
        }
        notifiedLongTaskIDs.formIntersection(activeIDs)
    }

    private func evaluateTokenSpikeAlert(current: PulseSnapshot) {
        let threshold = settings.resolvedTokenSpikeThresholdPerMinute
        guard threshold > 0,
              current.activeTaskCount > 0,
              let velocity = current.usage.tokenVelocityPerMinute else {
            isTokenSpikeActive = false
            return
        }

        if velocity < Int64(Double(threshold) * 0.7) {
            isTokenSpikeActive = false
            return
        }
        guard velocity >= threshold, !isTokenSpikeActive else { return }

        isTokenSpikeActive = true
        if let lastTokenSpikeAlertAt,
           Date().timeIntervalSince(lastTokenSpikeAlertAt) < 15 * 60 {
            return
        }
        lastTokenSpikeAlertAt = Date()
        if settings.resolvedNotificationsEnabled {
            NotificationService.shared.notifyTokenSpike(
                tokensPerMinute: velocity,
                soundEnabled: settings.soundEnabled
            )
        }
        sendWebhook(
            event: "token_velocity_high",
            title: "Token 消耗速度较高",
            body: "本机 Codex Token 消耗速度超过提醒阈值。",
            details: [
                "tokens_per_minute": String(velocity),
                "threshold_per_minute": String(threshold)
            ]
        )
    }

    private func evaluateResetCardExpiryAlerts(current: PulseSnapshot) {
        let thresholdDays = settings.resolvedResetCardExpiryAlertDays
        guard thresholdDays > 0 else {
            notifiedResetCardIDs.removeAll()
            return
        }

        let availableCards = current.rateLimits.resetCards.filter(\.isAvailable)
        let availableIDs = Set(availableCards.map(\.id))
        notifiedResetCardIDs.formIntersection(availableIDs)

        // 没有任何启用的通知渠道时不消费提醒机会；以后开启后仍可收到。
        guard settings.resolvedNotificationsEnabled || settings.webhookEnabled else { return }

        let now = Date()
        let threshold = TimeInterval(thresholdDays * 86_400)
        for card in availableCards {
            guard let expiresAt = card.expiresAt else { continue }
            let remaining = expiresAt.timeIntervalSince(now)
            guard remaining > 0,
                  remaining <= threshold,
                  notifiedResetCardIDs.insert(card.id).inserted else {
                continue
            }

            let daysRemaining = max(1, Int(ceil(remaining / 86_400)))
            if settings.resolvedNotificationsEnabled {
                NotificationService.shared.notifyResetCardExpiry(
                    cardID: card.id,
                    daysRemaining: daysRemaining,
                    soundEnabled: settings.soundEnabled
                )
            }
            sendWebhook(
                event: "reset_card_expiring",
                title: "额度重置卡即将到期",
                body: daysRemaining <= 1
                    ? "一张可用额度重置卡将在 24 小时内到期。"
                    : "一张可用额度重置卡将在约 \(daysRemaining) 天后到期。",
                details: ["days_remaining": String(daysRemaining)]
            )
        }
    }
}

#if os(macOS)
import AppKit
import WidgetKit

enum WidgetBridge {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
