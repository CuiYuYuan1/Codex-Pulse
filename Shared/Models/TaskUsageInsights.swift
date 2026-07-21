import Foundation

/// 从本地任务历史聚合出的滚动周期洞察；不上传路径、摘要或对话。
struct TaskUsageInsights: Equatable, Sendable {
    var periodDays: Int
    var finishedTasks: Int
    var successfulTasks: Int
    var failedTasks: Int
    var activeTasks: Int
    var successRate: Double?
    var averageDurationSeconds: TimeInterval?
    var longestDurationSeconds: TimeInterval?
    var topProjectName: String?
    var topProjectTaskCount: Int

    static func calculate(
        from tasks: [TaskRecord],
        days: Int = 7,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskUsageInsights {
        let safeDays = max(1, days)
        let startOfToday = calendar.startOfDay(for: reference)
        let cutoff = calendar.date(byAdding: .day, value: -(safeDays - 1), to: startOfToday)
            ?? reference.addingTimeInterval(-TimeInterval(safeDays * 86_400))

        let activeTasks = tasks.filter(\.isLive).count
        let periodTasks = tasks.filter { !$0.isLive && $0.finishedAt >= cutoff && $0.finishedAt <= reference }
        let successful = periodTasks.filter(\.isSuccessfulOutcome)
        let failed = periodTasks.filter(\.isFailedOutcome)
        let outcomeTasks = successful + failed

        let durations = outcomeTasks.map(\.durationSeconds).filter { $0 > 0 }
        let averageDuration = durations.isEmpty
            ? nil
            : durations.reduce(0, +) / Double(durations.count)

        var projectCounts: [String: Int] = [:]
        for task in outcomeTasks {
            let name = task.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            projectCounts[name, default: 0] += 1
        }
        let topProject = projectCounts.sorted {
            if $0.value == $1.value { return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            return $0.value > $1.value
        }.first

        return TaskUsageInsights(
            periodDays: safeDays,
            finishedTasks: outcomeTasks.count,
            successfulTasks: successful.count,
            failedTasks: failed.count,
            activeTasks: activeTasks,
            successRate: outcomeTasks.isEmpty
                ? nil
                : Double(successful.count) / Double(outcomeTasks.count) * 100,
            averageDurationSeconds: averageDuration,
            longestDurationSeconds: durations.max(),
            topProjectName: topProject?.key,
            topProjectTaskCount: topProject?.value ?? 0
        )
    }
}

private extension TaskRecord {
    var isLive: Bool {
        runState?.isActive == true
            || runState == .awaitingAuthorization
            || runState == .awaitingInput
    }

    var isFailedOutcome: Bool {
        runState == .failed || runState == .networkError || !succeeded
    }

    var isSuccessfulOutcome: Bool {
        guard !isFailedOutcome else { return false }
        switch runState {
        case .some(.stopped), .some(.notStarted), .some(.connecting):
            return false
        default:
            return succeeded
        }
    }
}
