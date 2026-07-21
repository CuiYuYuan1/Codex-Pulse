import Foundation

/// Mock 实现：用于预览、开发与无 CLI 时的演示
/// 生产环境替换为 StdioCodexAppServerClient
final class MockCodexAppServerClient: CodexAppServerClient, @unchecked Sendable {
    private(set) var isConnected = false
    private var eventContinuation: AsyncStream<CodexServerEvent>.Continuation?
    private var simulateTimer: Timer?
    private var tick = 0

    private var mockAccount = AccountInfo(
        email: "dev@example.com",
        planType: .pro,
        authMode: .chatGPT,
        isLoggedIn: true,
        workspaceName: "Personal",
        cliVersion: "0.45.0",
        lastSyncedAt: Date()
    )

    private var mockPrimaryUsed: Double = 62
    private var mockSecondaryUsed: Double = 28
    private var mockTask = CurrentTaskInfo(
        id: "task-demo-1",
        projectName: "Codex-Pulse",
        projectPath: "~/Projects/CodexPulse",
        gitBranch: "main",
        model: "o3",
        reasoningEffort: "high",
        startedAt: Date().addingTimeInterval(-420),
        state: .generatingCode,
        currentStep: "编写菜单栏面板",
        filesChanged: 6,
        linesAdded: 312,
        linesRemoved: 48,
        lastStatusMessage: "Updating MenuBarPanelView…"
    )

    func connect() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
        isConnected = true
        startSimulation()
        eventContinuation?.yield(.connectionRestored)
    }

    func disconnect() async {
        isConnected = false
        simulateTimer?.invalidate()
        simulateTimer = nil
        eventContinuation?.finish()
        eventContinuation = nil
    }

    func readAccount() async throws -> AccountInfo {
        guard isConnected else { throw CodexServerError.notConnected }
        var a = mockAccount
        a.lastSyncedAt = Date()
        return a
    }

    func readRateLimits(forceRefresh: Bool) async throws -> RateLimitSnapshot {
        guard isConnected else { throw CodexServerError.notConnected }
        return makeRateLimits()
    }

    func readUsage(forceRefresh: Bool) async throws -> UsageStats {
        guard isConnected else { throw CodexServerError.notConnected }
        return makeUsage()
    }

    func readLocalUsage(merging cached: UsageStats) async -> UsageStats {
        cached.hasAnyTokenMetric ? cached : makeUsage()
    }

    func invalidateAccountScopedState() {}

    func listRecentThreads(limit: Int) async throws -> [TaskRecord] {
        guard isConnected else { throw CodexServerError.notConnected }
        return Array(makeRecentTasks().prefix(limit))
    }

    func listLiveThreads(limit: Int) async throws -> [TaskRecord] {
        try await listRecentThreads(limit: limit)
    }

    func eventStream() -> AsyncStream<CodexServerEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    // MARK: - Mock data builders

    private func makeRateLimits() -> RateLimitSnapshot {
        let primary = RateLimitBucket(
            id: "primary-5h",
            name: "5 小时用量",
            usedPercent: mockPrimaryUsed,
            windowDurationSeconds: 5 * 3600,
            resetsAt: Date().addingTimeInterval(2 * 3600 + 18 * 60),
            isLimitReached: mockPrimaryUsed >= 100,
            remainingCredits: nil
        )
        let secondary = RateLimitBucket(
            id: "weekly",
            name: "每周用量",
            usedPercent: mockSecondaryUsed,
            windowDurationSeconds: 7 * 24 * 3600,
            resetsAt: Date().addingTimeInterval(3 * 24 * 3600),
            isLimitReached: false,
            remainingCredits: nil
        )
        let card = RateLimitResetCard(
            id: "card-1",
            acquiredAt: Date().addingTimeInterval(-86400),
            expiresAt: Date().addingTimeInterval(6 * 86400),
            applicableLimitTypes: ["primary-5h"],
            isAvailable: true
        )
        return RateLimitSnapshot(
            buckets: [primary, secondary],
            resetCards: [card],
            updatedAt: Date()
        )
    }

    private func makeUsage() -> UsageStats {
        let calendar = Calendar.current
        var buckets: [DailyTokenBucket] = []
        let base: [Int64] = [120_000, 85_000, 210_000, 156_000, 98_000, 175_000, 142_000]
        for i in 0..<7 {
            let day = calendar.date(byAdding: .day, value: i - 6, to: Date())!
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            buckets.append(DailyTokenBucket(dateString: f.string(from: day), tokens: base[i]))
        }
        return UsageStats(
            totalTokens: 4_820_000,
            todayTokens: 142_000,
            yesterdayTokens: 175_000,
            last7DaysTokens: base.reduce(0, +),
            last30DaysTokens: 3_650_000,
            peakDailyTokens: 310_000,
            currentStreakDays: 12,
            longestStreakDays: 28,
            longestTaskDurationSeconds: 45 * 60,
            dailyBuckets: buckets,
            updatedAt: Date(),
            sourceNote: nil
        )
    }

    private func makeRecentTasks() -> [TaskRecord] {
        [
            TaskRecord(
                id: "r1",
                projectName: "Codex-Pulse",
                projectPath: "~/Projects/CodexPulse",
                gitBranch: "main",
                model: "o3",
                tokenUsage: 48_200,
                durationSeconds: 720,
                succeeded: true,
                filesChanged: 8,
                summary: "实现菜单栏额度面板",
                finishedAt: Date().addingTimeInterval(-3600)
            ),
            TaskRecord(
                id: "r2",
                projectName: "api-gateway",
                projectPath: "~/work/api-gateway",
                gitBranch: "feat/auth",
                model: "gpt-4.1",
                tokenUsage: 22_100,
                durationSeconds: 340,
                succeeded: true,
                filesChanged: 3,
                summary: "修复 JWT 刷新逻辑",
                finishedAt: Date().addingTimeInterval(-7200)
            ),
            TaskRecord(
                id: "r3",
                projectName: "mobile-app",
                projectPath: "~/work/mobile-app",
                gitBranch: "develop",
                model: "o3",
                tokenUsage: 61_000,
                durationSeconds: 1100,
                succeeded: false,
                filesChanged: 2,
                summary: "集成推送失败后回滚",
                finishedAt: Date().addingTimeInterval(-15000)
            )
        ]
    }

    private func startSimulation() {
        // 用 Task 代替 Timer，便于跨平台与 Sendable
        Task { [weak self] in
            while let self, self.isConnected {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self.tickSimulation()
            }
        }
    }

    private func tickSimulation() async {
        tick += 1
        // 缓慢增加额度
        mockPrimaryUsed = min(99, mockPrimaryUsed + Double.random(in: 0.05...0.4))
        mockSecondaryUsed = min(80, mockSecondaryUsed + Double.random(in: 0.01...0.1))

        let states: [CodexRunState] = [
            .thinking, .generatingCode, .executingCommand, .modifyingFiles, .callingTool
        ]
        if tick % 4 == 0 {
            mockTask.state = states.randomElement() ?? .thinking
            mockTask.currentStep = [
                "分析项目结构",
                "编写 MenuBar 面板",
                "更新 Widget 数据",
                "运行单元测试",
                "格式化代码"
            ].randomElement()
            mockTask.filesChanged += Int.random(in: 0...1)
            mockTask.linesAdded += Int.random(in: 5...40)
        }
        if tick % 5 == 0 {
            eventContinuation?.yield(.rateLimitsUpdated(makeRateLimits()))
        }
        if tick % 3 == 0 {
            eventContinuation?.yield(.turnStarted(mockTask))
        }
    }

    /// 供 UI 预览直接拉取「当前任务」扩展（非协议方法）
    func peekCurrentTask() -> CurrentTaskInfo { mockTask }
}
