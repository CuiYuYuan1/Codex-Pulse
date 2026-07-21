import WidgetKit
import SwiftUI

struct CodexPulseWidget: Widget {
    let kind = "CodexPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseTimelineProvider()) { entry in
            PulseWidgetRootView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "codexpulse://dashboard"))
        }
        .configurationDisplayName("Codex-Pulse")
        .description("查看额度、Token、运行任务和最近活动。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let snapshot: PulseSnapshot
}

struct PulseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: Date(), snapshot: SnapshotStore.shared.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let snapshot = SnapshotStore.shared.load() ?? .empty
        let now = Date()
        // 主应用会主动 reload；额外提供 5 分钟粒度条目，保证倒计时和过期状态及时变化。
        let entries = (0...6).compactMap { offset -> PulseEntry? in
            guard let date = Calendar.current.date(byAdding: .minute, value: offset * 5, to: now) else {
                return nil
            }
            return PulseEntry(date: date, snapshot: snapshot)
        }
        let reloadDate = Calendar.current.date(byAdding: .minute, value: 35, to: now) ?? now.addingTimeInterval(2_100)
        completion(Timeline(entries: entries, policy: .after(reloadDate)))
    }
}

private struct PulseWidgetRootView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemSmall:
            PulseWidgetSmallView(entry: entry)
        case .systemLarge:
            PulseWidgetLargeView(entry: entry)
        default:
            PulseWidgetMediumView(entry: entry)
        }
    }
}

private struct PulseWidgetSmallView: View {
    let entry: PulseEntry

    var body: some View {
        let snapshot = entry.snapshot
        let primary = snapshot.rateLimits.primaryBucket

        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(entry: entry, compact: true)

            if let primary {
                Text(PulseFormatters.percent(primary.remainingPercent))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PulseTheme.usage(primary.remainingPercent))
                    .minimumScaleFactor(0.75)
                Text("\(primary.name) · 剩余")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                LiquidProgressBar(remainingPercent: primary.remainingPercent, height: 6, animated: false)
                Text("重置 \(countdown(primary, at: entry.date))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Spacer(minLength: 4)
                Text("等待连接")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("打开 Codex-Pulse 获取数据")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
            }

            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: taskIcon(snapshot.currentTask.state))
                    .foregroundStyle(PulseTheme.status(snapshot.currentTask.state.indicatorColor))
                Text(snapshot.taskStatusLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(PulseFormatters.tokens(snapshot.usage.todayTokens))
                    .monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(snapshot, at: entry.date))
    }
}

private struct PulseWidgetMediumView: View {
    let entry: PulseEntry

    var body: some View {
        let snapshot = entry.snapshot
        let primary = snapshot.rateLimits.primaryBucket
        let secondary = snapshot.rateLimits.secondaryBucket

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(entry: entry)

                if let primary {
                    Text(PulseFormatters.percent(primary.remainingPercent))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PulseTheme.usage(primary.remainingPercent))
                    Text("\(primary.name) · 剩余")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    LiquidProgressBar(remainingPercent: primary.remainingPercent, height: 7, animated: false)
                    Text("重置 \(countdown(primary, at: entry.date))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let forecastText = forecastSummary(
                        snapshot.primaryRateLimitForecast,
                        at: entry.date
                    ) {
                        Label(
                            forecastText,
                            systemImage: snapshot.primaryRateLimitForecast?.willExhaustBeforeReset == true
                                ? "exclamationmark.triangle.fill"
                                : "chart.line.uptrend.xyaxis"
                        )
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(
                            snapshot.primaryRateLimitForecast?.willExhaustBeforeReset == true
                                ? PulseTheme.red
                                : .secondary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("等待连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                WidgetMetric("次级剩余", secondary.map { PulseFormatters.percent($0.remainingPercent) } ?? "—")
                WidgetMetric("今日 Token", PulseFormatters.tokens(snapshot.usage.todayTokens))
                WidgetMetric("任务", snapshot.taskStatusLabel, tint: PulseTheme.status(snapshot.currentTask.state.indicatorColor))
                WidgetMetric("模型", snapshot.currentTask.model ?? "—")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(snapshot, at: entry.date))
    }
}

private struct PulseWidgetLargeView: View {
    let entry: PulseEntry

    var body: some View {
        let snapshot = entry.snapshot
        let buckets = Array(snapshot.rateLimits.buckets.prefix(2))
        let recentTasks = Array(snapshot.recentTasks.prefix(3))

        VStack(alignment: .leading, spacing: 13) {
            WidgetHeader(entry: entry)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    if buckets.isEmpty {
                        ContentUnavailableView("等待额度数据", systemImage: "gauge")
                            .frame(maxWidth: .infinity, minHeight: 92)
                    } else {
                        ForEach(buckets) { bucket in
                            WidgetLimitRow(
                                bucket: bucket,
                                reference: entry.date,
                                forecast: bucket.id == snapshot.rateLimits.primaryBucket?.id
                                    ? snapshot.primaryRateLimitForecast
                                    : nil
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    WidgetMetric("今日 Token", PulseFormatters.tokens(snapshot.usage.todayTokens))
                    WidgetMetric("近 7 天", PulseFormatters.tokens(snapshot.usage.last7DaysTokens))
                    WidgetMetric("累计", PulseFormatters.tokens(snapshot.usage.totalTokens))
                    WidgetMetric("连续", snapshot.usage.currentStreakDays.map { "\($0) 天" } ?? "—")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 7) {
                Text("当前任务")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatusOrb(color: snapshot.currentTask.state.indicatorColor, size: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.taskStatusLabel)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(taskDetail(snapshot.currentTask))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if snapshot.currentTask.state.isActive {
                        Text(duration(snapshot.currentTask, at: entry.date))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PulseTheme.blue)
                    }
                }
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 7) {
                Text("最近任务")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                if recentTasks.isEmpty {
                    Text("暂无任务记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentTasks) { task in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(PulseTheme.status(task.indicatorColor))
                                .frame(width: 6, height: 6)
                            Text(task.projectName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(task.runState?.isActive == true
                                 ? (task.runState?.rawValue ?? "处理中")
                                 : PulseFormatters.relativeDate(task.finishedAt))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(4)
        .accessibilityElement(children: .contain)
    }
}

private struct WidgetHeader: View {
    let entry: PulseEntry
    var compact = false

    var body: some View {
        let stale = entry.snapshot.isStale(reference: entry.date)
        HStack(spacing: 6) {
            Text("Codex-Pulse")
                .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if stale {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 9.5))
                    .foregroundStyle(PulseTheme.orange)
                    .help("数据超过 30 分钟未更新")
            }
            StatusOrb(color: stale ? .gray : entry.snapshot.statusColor, size: compact ? 6 : 8)
        }
    }
}

private struct WidgetMetric: View {
    let label: String
    let value: String
    var tint: Color?

    init(_ label: String, _ value: String, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct WidgetLimitRow: View {
    let bucket: RateLimitBucket
    let reference: Date
    let forecast: RateLimitForecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bucket.name)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("剩余 \(PulseFormatters.percent(bucket.remainingPercent))")
                    .foregroundStyle(PulseTheme.usage(bucket.remainingPercent))
                    .monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .semibold))
            LiquidProgressBar(remainingPercent: bucket.remainingPercent, height: 6, animated: false)
            Text("重置 \(countdown(bucket, at: reference))")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
            if let forecastText = forecastSummary(forecast, at: reference) {
                Label(
                    forecastText,
                    systemImage: forecast?.willExhaustBeforeReset == true
                        ? "exclamationmark.triangle.fill"
                        : "chart.line.uptrend.xyaxis"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    forecast?.willExhaustBeforeReset == true
                        ? PulseTheme.red
                        : Color.secondary
                )
                .lineLimit(1)
            }
        }
    }
}

private func forecastSummary(_ forecast: RateLimitForecast?, at reference: Date) -> String? {
    guard let forecast else { return nil }
    if let exhaustionAt = forecast.estimatedExhaustionAt,
       forecast.willExhaustBeforeReset {
        let remaining = max(0, exhaustionAt.timeIntervalSince(reference))
        return "预计 \(PulseFormatters.countdown(remaining)) 后耗尽"
    }
    if let remaining = forecast.projectedRemainingAtReset {
        return "重置时约剩 \(PulseFormatters.percent(remaining))"
    }
    if let exhaustionAt = forecast.estimatedExhaustionAt {
        let remaining = max(0, exhaustionAt.timeIntervalSince(reference))
        return "预计 \(PulseFormatters.countdown(remaining)) 后耗尽"
    }
    return nil
}

private func countdown(_ bucket: RateLimitBucket, at reference: Date) -> String {
    guard let resetsAt = bucket.resetsAt else { return "—" }
    return PulseFormatters.countdown(max(0, resetsAt.timeIntervalSince(reference)))
}

private func duration(_ task: CurrentTaskInfo, at reference: Date) -> String {
    guard let startedAt = task.startedAt else { return "—" }
    return PulseFormatters.duration(max(0, reference.timeIntervalSince(startedAt)))
}

private func taskDetail(_ task: CurrentTaskInfo) -> String {
    [task.projectName, task.model, task.gitBranch]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        .nilIfEmpty ?? task.state.detailDescription
}

private func taskIcon(_ state: CodexRunState) -> String {
    if state.isActive { return "waveform.path.ecg" }
    if state.needsAttention { return "exclamationmark.triangle.fill" }
    return state == .idle || state == .completed ? "checkmark.circle.fill" : "circle.dashed"
}

private func accessibilitySummary(_ snapshot: PulseSnapshot, at reference: Date) -> String {
    let quota = snapshot.rateLimits.primaryBucket
        .map { "\($0.name)剩余\(Int($0.remainingPercent))%" }
        ?? "暂无额度数据"
    let forecast = forecastSummary(snapshot.primaryRateLimitForecast, at: reference)
        .map { "，\($0)" }
        ?? ""
    return "Codex-Pulse，\(quota)\(forecast)，今日 Token \(PulseFormatters.tokens(snapshot.usage.todayTokens))，\(snapshot.taskStatusLabel)"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@main
struct CodexPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexPulseWidget()
    }
}
