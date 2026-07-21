import Foundation

/// Map official app-server wire types → domain models
enum ProtocolMapper {
    static func account(from wire: WireGetAccountResponse, cliVersion: String? = nil) -> AccountInfo {
        guard let acc = wire.account else {
            return AccountInfo(
                email: nil,
                planType: .unknown,
                authMode: .none,
                isLoggedIn: false,
                workspaceName: nil,
                cliVersion: cliVersion,
                lastSyncedAt: Date()
            )
        }
        switch acc {
        case .apiKey:
            return AccountInfo(
                email: nil,
                planType: .unknown,
                authMode: .apiKey,
                isLoggedIn: true,
                workspaceName: nil,
                cliVersion: cliVersion,
                lastSyncedAt: Date()
            )
        case .chatgpt(let email, let plan):
            return AccountInfo(
                email: email,
                planType: mapPlan(plan),
                authMode: .chatGPT,
                isLoggedIn: true,
                workspaceName: nil,
                cliVersion: cliVersion,
                lastSyncedAt: Date()
            )
        case .amazonBedrock:
            return AccountInfo(
                email: nil,
                planType: .unknown,
                authMode: .apiKey,
                isLoggedIn: true,
                workspaceName: "Amazon Bedrock",
                cliVersion: cliVersion,
                lastSyncedAt: Date()
            )
        case .unknown:
            return AccountInfo(
                email: nil,
                planType: .unknown,
                authMode: .none,
                isLoggedIn: wire.requiresOpenaiAuth == false,
                workspaceName: nil,
                cliVersion: cliVersion,
                lastSyncedAt: Date()
            )
        }
    }

    static func rateLimits(from wire: WireGetAccountRateLimitsResponse) -> RateLimitSnapshot {
        var buckets: [RateLimitBucket] = []

        // 两套字段可能各自只带一部分窗口，不能二选一。
        if let snap = wire.rateLimits {
            buckets.append(contentsOf: windows(from: snap, fallbackId: snap.limitId ?? "codex"))
        }
        if let byId = wire.rateLimitsByLimitId, !byId.isEmpty {
            for (key, snap) in byId.sorted(by: { $0.key < $1.key }) {
                buckets.append(contentsOf: windows(from: snap, fallbackId: key))
            }
        }
        buckets = deduplicatedAndSorted(buckets)

        var cards: [RateLimitResetCard] = []
        if let summary = wire.rateLimitResetCredits {
            if let detail = summary.credits {
                for c in detail {
                    cards.append(
                        RateLimitResetCard(
                            id: c.id ?? UUID().uuidString,
                            acquiredAt: c.grantedAt.map { Date(timeIntervalSince1970: $0) },
                            expiresAt: c.expiresAt.map { Date(timeIntervalSince1970: $0) },
                            applicableLimitTypes: c.resetType.map { [$0] } ?? [],
                            isAvailable: (c.status ?? "available").lowercased() == "available"
                        )
                    )
                }
            } else if let count = summary.availableCount, count > 0 {
                for i in 0..<count {
                    cards.append(
                        RateLimitResetCard(
                            id: "reset-credit-\(i)",
                            acquiredAt: nil,
                            expiresAt: nil,
                            applicableLimitTypes: [],
                            isAvailable: true
                        )
                    )
                }
            }
        }

        return RateLimitSnapshot(buckets: buckets, resetCards: cards, updatedAt: Date())
    }

    static func mergeRateLimits(existing: RateLimitSnapshot, update: WireRateLimitSnapshot) -> RateLimitSnapshot {
        var buckets = existing.buckets
        let newWindows = windows(from: update, fallbackId: update.limitId ?? "codex")
        for nw in newWindows {
            if let idx = buckets.firstIndex(where: { $0.id == nw.id }) {
                buckets[idx] = nw
            } else if let idx = buckets.firstIndex(where: {
                guard let oldDuration = $0.windowDurationSeconds,
                      let newDuration = nw.windowDurationSeconds else {
                    return $0.name == nw.name
                }
                return abs(oldDuration - newDuration) < 60
            }) {
                buckets[idx] = RateLimitBucket(
                    id: buckets[idx].id,
                    name: nw.name,
                    usedPercent: nw.usedPercent,
                    windowDurationSeconds: nw.windowDurationSeconds,
                    resetsAt: nw.resetsAt,
                    isLimitReached: nw.isLimitReached,
                    remainingCredits: nw.remainingCredits
                )
            } else {
                buckets.append(nw)
            }
        }
        return RateLimitSnapshot(
            buckets: deduplicatedAndSorted(buckets),
            resetCards: existing.resetCards,
            updatedAt: Date()
        )
    }

    static func usage(from wire: WireGetAccountTokenUsageResponse) -> UsageStats {
        let summary = wire.summary
        let daily: [DailyTokenBucket] = (wire.dailyUsageBuckets ?? []).compactMap { b in
            guard let date = b.startDate, !date.isEmpty else { return nil }
            return DailyTokenBucket(
                dateString: UsageStats.normalizeDay(date),
                tokens: b.tokens?.value ?? 0
            )
        }

        var stats = UsageStats(
            totalTokens: summary?.resolvedLifetime ?? summary?.lifetimeTokens?.value,
            todayTokens: summary?.todayTokens?.value,
            yesterdayTokens: nil,
            last7DaysTokens: nil,
            last30DaysTokens: nil,
            peakDailyTokens: summary?.peakDailyTokens?.value,
            currentStreakDays: summary?.currentStreakDays.map { Int($0.value) },
            longestStreakDays: summary?.longestStreakDays.map { Int($0.value) },
            longestTaskDurationSeconds: summary?.longestRunningTurnSec.map { TimeInterval($0.value) },
            dailyBuckets: daily,
            updatedAt: Date(),
            sourceNote: nil
        )
        stats.recomputeAggregatesIfNeeded()

        // 即使日桶全 0 也算有数据（显示 0 而非 —）
        if stats.todayTokens == nil, !daily.isEmpty {
            // recompute 应已填；双保险
            let filled = stats.filledLast7Days()
            let todayKey = UsageStats.dayFormatter().string(from: Date())
            stats.todayTokens = filled.first(where: { $0.dateString == todayKey })?.tokens
            stats.last7DaysTokens = filled.reduce(0) { $0 + $1.tokens }
        }

        if !stats.hasAnyTokenMetric && daily.isEmpty && summary == nil {
            stats.sourceNote = "暂无 Token 活跃数据（接口未返回用量）"
        } else if !stats.hasAnyTokenMetric {
            // summary 存在但字段全 null、日桶空 → 显示 0 更友好
            if stats.totalTokens == nil { stats.totalTokens = 0 }
            if stats.todayTokens == nil { stats.todayTokens = 0 }
            if stats.last7DaysTokens == nil { stats.last7DaysTokens = 0 }
            stats.dailyBuckets = stats.filledLast7Days()
            stats.sourceNote = "账号暂无 Token 用量记录"
        }
        return stats
    }

    /// 空 usage + 说明（RPC 失败时）
    static func emptyUsage(note: String) -> UsageStats {
        var u = UsageStats.empty
        u.sourceNote = note
        u.updatedAt = Date()
        return u
    }

    static func tasks(from wire: WireThreadListResponse) -> [TaskRecord] {
        (wire.data ?? []).map { t in
            let path = t.cwd?.value
            let name = t.name
                ?? t.gitInfo?.repositoryUrl?.split(separator: "/").last.map(String.init)
                ?? path.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? "Untitled"
            let ts = t.recencyAt?.value ?? t.updatedAt?.value ?? t.createdAt?.value
            let finished = ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
            let status = t.status?.value ?? ""
            let flags = t.status?.activeFlags ?? []
            let runState = mapThreadState(status: status, activeFlags: flags)
            return TaskRecord(
                id: t.id ?? UUID().uuidString,
                projectName: name,
                projectPath: path,
                gitBranch: t.gitInfo?.branch,
                model: t.modelProvider,
                tokenUsage: nil,
                durationSeconds: 0,
                succeeded: !["failed", "systemerror"].contains(status.lowercased()),
                filesChanged: 0,
                summary: t.preview,
                finishedAt: finished,
                runState: runState,
                activeFlags: flags.isEmpty ? nil : flags
            )
        }
    }

    // MARK: - Helpers

    private static func mapThreadState(status: String, activeFlags: [String]) -> CodexRunState? {
        let normalizedStatus = status.lowercased()
        let normalizedFlags = Set(activeFlags.map { $0.lowercased() })

        switch normalizedStatus {
        case "active":
            if normalizedFlags.contains("waitingonapproval") {
                return .awaitingAuthorization
            }
            if normalizedFlags.contains("waitingonuserinput") {
                return .awaitingInput
            }
            return .thinking
        case "idle":
            return .idle
        case "systemerror", "failed":
            return .failed
        case "notloaded":
            // 另一个 Codex 进程中的线程通常会是 notLoaded，交给本机会话活动补源。
            return nil
        default:
            return nil
        }
    }

    private static func windows(from snap: WireRateLimitSnapshot, fallbackId: String) -> [RateLimitBucket] {
        var result: [RateLimitBucket] = []
        if let p = snap.primary {
            result.append(bucket(
                id: bucketID(limitId: fallbackId, role: "primary", window: p),
                name: displayName(for: p, fallback: snap.limitName ?? "主额度窗口"),
                window: p,
                limitReached: snap.rateLimitReachedType != nil
            ))
        }
        if let s = snap.secondary {
            result.append(bucket(
                id: bucketID(limitId: fallbackId, role: "secondary", window: s),
                name: displayName(for: s, fallback: "次级额度"),
                window: s,
                limitReached: false
            ))
        }
        return result
    }

    private static func bucket(id: String, name: String, window: WireRateLimitWindow, limitReached: Bool) -> RateLimitBucket {
        let used = window.usedPercent ?? 0
        let duration: TimeInterval? = window.windowDurationMins.map { $0 * 60 }
        let resets = window.resetsAt.map { Date(timeIntervalSince1970: $0) }
        return RateLimitBucket(
            id: id,
            name: name,
            usedPercent: used,
            windowDurationSeconds: duration,
            resetsAt: resets,
            isLimitReached: limitReached || used >= 100,
            remainingCredits: nil
        )
    }

    private static func bucketID(limitId: String, role: String, window: WireRateLimitWindow) -> String {
        if let minutes = window.windowDurationMins {
            return "\(limitId)-\(Int(minutes.rounded()))m"
        }
        return "\(limitId)-\(role)"
    }

    private static func displayName(for window: WireRateLimitWindow, fallback: String) -> String {
        guard let minutes = window.windowDurationMins, minutes > 0 else { return fallback }
        if abs(minutes - 300) <= 5 { return "5 小时用量" }
        if abs(minutes - 10_080) <= 5 { return "每周用量" }
        if minutes < 1_440 {
            let hours = max(1, Int((minutes / 60).rounded()))
            return "\(hours) 小时用量"
        }
        let days = max(1, Int((minutes / 1_440).rounded()))
        return "\(days) 日用量"
    }

    private static func deduplicatedAndSorted(_ buckets: [RateLimitBucket]) -> [RateLimitBucket] {
        var byID: [String: RateLimitBucket] = [:]
        for bucket in buckets {
            byID[bucket.id] = bucket
        }
        return byID.values.sorted {
            let lhs = $0.windowDurationSeconds ?? .greatestFiniteMagnitude
            let rhs = $1.windowDurationSeconds ?? .greatestFiniteMagnitude
            if lhs != rhs { return lhs < rhs }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func mapPlan(_ raw: String?) -> AccountInfo.PlanType {
        guard let raw else { return .unknown }
        switch raw.lowercased() {
        case "free": return .free
        case "plus", "go": return .plus
        case "pro", "prolite": return .pro
        case "business", "self_serve_business_usage_based": return .business
        case "team": return .team
        case "enterprise", "enterprise_cbp_usage_based", "edu": return .business
        default: return .unknown
        }
    }
}
