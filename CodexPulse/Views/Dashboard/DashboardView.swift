import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

/// 完整数据看板 — restrained macOS workspace
struct DashboardView: View {
    @Environment(PulseStore.self) private var store
    @Environment(ArtificialAnalysisLeaderboardStore.self) private var modelRankings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pulseVisualTheme) private var visualTheme
    @State private var appeared = false
    @State private var taskSearchText = ""
    @State private var taskHistoryFilter: TaskHistoryFilter = .all
    @State private var reportCopied = false

    var body: some View {
        ZStack {
            DashboardBackdrop()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    usageOverview
                    if AppConstants.showsResetPredictionPanels {
                        ResetPredictionView()
                    }
                    ModelLeaderboardsView()
                    workspace
                }
                .frame(maxWidth: 1_100)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .environment(\.pulseVisualTheme, store.settings.resolvedVisualTheme)
        .tint(store.settings.resolvedVisualTheme.accent)
        .frame(minWidth: 860, minHeight: 620)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            store.start()
            modelRankings.start()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 13) {
            appIcon

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex-Pulse")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.4)

                HStack(spacing: 6) {
                    StatusOrb(color: store.snapshot.statusColor, size: 7)
                    Text(store.isUsingMock ? "演示数据" : store.snapshot.connectionState.displayName)
                    Text("·")
                    Text(lastUpdatedText)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(PulseTheme.status(store.snapshot.statusColor))
                    .frame(width: 6, height: 6)
                    .shadow(color: PulseTheme.status(store.snapshot.statusColor).opacity(0.7), radius: 4)
                Text(store.snapshot.taskStatusLabel)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(subtleFill, in: Capsule())
            .overlay { Capsule().strokeBorder(subtleBorder, lineWidth: 1) }

            Menu {
                Button {
                    store.settings.resolvedActivityBandEnabled.toggle()
                    store.saveSettings()
                } label: {
                    Label(
                        store.settings.resolvedActivityBandEnabled ? "关闭思考灯带" : "开启思考灯带",
                        systemImage: store.settings.resolvedActivityBandEnabled ? "checkmark.circle.fill" : "circle"
                    )
                }

                Divider()

                ForEach(ActivityBandStyle.allCases) { style in
                    Button {
                        store.settings.resolvedActivityBandStyle = style
                        store.settings.resolvedActivityBandEnabled = true
                        store.saveSettings()
                    } label: {
                        Label(
                            style.displayName,
                            systemImage: store.settings.resolvedActivityBandStyle == style
                                ? "checkmark"
                                : "circle.fill"
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 12, weight: .semibold))
                    Text(
                        store.settings.resolvedActivityBandEnabled
                            ? "灯带 · \(store.settings.resolvedActivityBandStyle.displayName)"
                            : "灯带 · 关闭"
                    )
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(subtleFill, in: Capsule())
            .overlay { Capsule().strokeBorder(subtleBorder, lineWidth: 1) }
            .help("思考灯带设置")

            Menu {
                ForEach(PulseVisualTheme.allCases) { theme in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            store.settings.resolvedVisualTheme = theme
                        }
                        store.saveSettings()
                    } label: {
                        Label(
                            theme.displayName,
                            systemImage: store.settings.resolvedVisualTheme == theme
                                ? "checkmark"
                                : "circle.fill"
                        )
                    }
                }

                Divider()

                ForEach(PulseAppearanceMode.allCases) { mode in
                    Button {
                        store.settings.resolvedAppearanceMode = mode
                        store.saveSettings()
                    } label: {
                        Label(
                            mode.displayName,
                            systemImage: store.settings.resolvedAppearanceMode == mode
                                ? "checkmark"
                                : mode.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(subtleFill, in: Circle())
            .overlay { Circle().strokeBorder(subtleBorder, lineWidth: 1) }
            .help("切换界面主题和明暗模式")

            Button {
                Task { await store.refreshAll(forceRemote: true) }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(subtleFill, in: Circle())
            .overlay { Circle().strokeBorder(subtleBorder, lineWidth: 1) }
            .help("刷新数据")
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        #if os(macOS)
        Image("BrandIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: PulseTheme.blue.opacity(0.22), radius: 10, y: 4)
        #else
        Image(systemName: "gauge.with.dots.needle.67percent")
            .frame(width: 42, height: 42)
        #endif
    }

    private var lastUpdatedText: String {
        guard store.snapshot.updatedAt != .distantPast else { return "等待首次同步" }
        return "更新于 \(PulseFormatters.shortTime(store.snapshot.updatedAt))"
    }

    // MARK: - Usage overview

    private var usageOverview: some View {
        DashboardPanel(title: "用量概览", systemImage: "gauge") {
            HStack(alignment: .top, spacing: 28) {
                limitSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(separatorColor)
                    .frame(width: 1, height: 154)

                tokenSummary
                    .frame(width: 390, alignment: .leading)
            }
        }
    }

    private var limitSummary: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let primary = store.snapshot.rateLimits.primaryBucket {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(PulseFormatters.percent(primary.remainingPercent))
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PulseTheme.usage(primary.remainingPercent))
                        .contentTransition(.numericText())
                    Text("剩余")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 7)
                }

                LiquidProgressBar(remainingPercent: primary.remainingPercent, height: 9)

                HStack {
                    Label(primary.name, systemImage: "clock")
                    Spacer()
                    Text("\(PulseFormatters.percent(primary.usedPercent)) 已用 · \(PulseFormatters.countdown(primary.resetCountdown)) 后重置")
                        .monospacedDigit()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

                if let forecast = store.primaryRateLimitForecast,
                   let summary = store.primaryRateLimitForecastSummary {
                    Label(
                        summary,
                        systemImage: forecast.willExhaustBeforeReset
                            ? "exclamationmark.triangle.fill"
                            : "chart.line.uptrend.xyaxis"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(forecast.willExhaustBeforeReset ? PulseTheme.red : Color.secondary)
                    .help(
                        "\(forecast.confidence.displayName)置信度 · \(forecast.sampleCount) 个样本 · "
                        + "每小时约消耗 \(String(format: "%.2f%%", forecast.burnRatePercentPerHour))"
                    )
                } else if store.settings.resolvedRateLimitForecastEnabled,
                          primary.usedPercent > 0 {
                    Label("额度预测正在积累样本", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .help("至少需要 3 个样本和 10 分钟跨度")
                }

                if store.snapshot.rateLimits.buckets.count > 1 {
                    ForEach(Array(store.snapshot.rateLimits.buckets.dropFirst())) { bucket in
                        compactLimitRow(bucket)
                    }
                } else if !hasFiveHourWindow {
                    Label("5 小时窗口当前未由接口返回", systemImage: "info.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            } else {
                if store.snapshot.account.authMode == .apiKey {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("API 按量计费", systemImage: "key.horizontal.fill")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(chartAccent)
                        Text("API Key 不使用 ChatGPT 每周或 5 小时额度")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("今日、近 7 天与累计 Token 继续在右侧统计；账单与成本以 OpenAI API Usage / Costs 为准。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "等待额度数据",
                        systemImage: "gauge",
                        description: Text("连接 Codex 后会自动同步")
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private func compactLimitRow(_ bucket: RateLimitBucket) -> some View {
        HStack(spacing: 8) {
            Text(bucket.name)
                .lineLimit(1)
            Spacer()
            Text("剩余 \(PulseFormatters.percent(bucket.remainingPercent))")
                .monospacedDigit()
                .foregroundStyle(PulseTheme.usage(bucket.remainingPercent))
            Text("·")
                .foregroundStyle(.quaternary)
            Text(PulseFormatters.countdown(bucket.resetCountdown))
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var hasFiveHourWindow: Bool {
        store.snapshot.rateLimits.buckets.contains { bucket in
            guard let duration = bucket.windowDurationSeconds else {
                return bucket.name.contains("5 小时")
            }
            return abs(duration - 5 * 3_600) <= 5 * 60
        }
    }

    private var tokenSummary: some View {
        let usage = store.snapshot.usage
        let input = usage.localTodayInputTokens
        let cached = usage.localTodayCachedInputTokens
        let uncached = input.map { max(0, $0 - (cached ?? 0)) }
        let cacheHitRate = usage.localTodayCacheHitRate

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日 TOKEN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.tertiary)
                    Text(PulseFormatters.tokens(usage.todayTokens))
                        .font(.system(size: 35, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(chartAccent)
                        .contentTransition(.numericText())
                    if let velocity = usage.tokenVelocityPerMinute {
                        Label(
                            "\(PulseFormatters.tokens(velocity))/分钟",
                            systemImage: "speedometer"
                        )
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tokenVelocityColor(velocity))
                            .monospacedDigit()
                    }
                }
                .frame(width: 118, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text("缓存命中率")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(cacheHitText(cacheHitRate))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PulseTheme.green)
                            .contentTransition(.numericText())
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.09))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            PulseTheme.green.opacity(0.72),
                                            PulseTheme.green
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: proxy.size.width
                                        * CGFloat(min(1, max(0, cacheHitRate ?? 0)))
                                )
                                .shadow(
                                    color: PulseTheme.green.opacity(0.22),
                                    radius: 4
                                )
                        }
                    }
                    .frame(height: 5)

                    HStack(alignment: .top, spacing: 8) {
                        cacheCostMetric(
                            "缓存",
                            PulseFormatters.tokens(cached)
                        )
                        cacheCostMetric(
                            "未缓存",
                            PulseFormatters.tokens(uncached)
                        )
                        cacheCostMetric(
                            "今日成本",
                            dashboardCurrency(usage.localTodayEstimatedCostUSD),
                            tint: Color(hex: 0x159D9A)
                        )
                        cacheCostMetric(
                            "累计成本",
                            dashboardCurrency(usage.localTotalEstimatedCostUSD),
                            tint: Color(hex: 0x159D9A)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)

            HStack(spacing: 0) {
                tokenMetric("昨日", PulseFormatters.tokens(usage.yesterdayTokens))
                metricDivider
                tokenMetric("近 7 天", PulseFormatters.tokens(usage.last7DaysTokens))
                metricDivider
                tokenMetric("累计 Token", PulseFormatters.tokens(usage.totalTokens))
                metricDivider
                tokenMetric("连续", usage.currentStreakDays.map { "\($0) 天" } ?? "—")
            }
        }
        .frame(minHeight: 154, alignment: .top)
    }

    private func cacheCostMetric(
        _ label: String,
        _ value: String,
        tint: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cacheHitText(_ rate: Double?) -> String {
        guard let rate, rate.isFinite else { return "—" }
        return String(format: "%.1f%%", min(1, max(0, rate)) * 100)
    }

    private func dashboardCurrency(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let normalized = max(0, value)
        if normalized >= 1_000 {
            return String(format: "$%.2fK", normalized / 1_000)
        }
        if normalized >= 100 {
            return String(format: "$%.1f", normalized)
        }
        if normalized >= 1 {
            return String(format: "$%.2f", normalized)
        }
        if normalized >= 0.01 {
            return String(format: "$%.3f", normalized)
        }
        return String(format: "$%.4f", normalized)
    }

    private func tokenMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tokenVelocityColor(_ velocity: Int64) -> Color {
        let threshold = store.settings.resolvedTokenSpikeThresholdPerMinute
        guard threshold > 0 else { return Color.secondary }
        return velocity >= threshold ? PulseTheme.red : Color.secondary
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(separatorColor)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }

    // MARK: - Workspace

    private var workspace: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                trendPanel
                recentTasksPanel
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                currentTaskPanel
                accountPanel
                insightsPanel
            }
            .frame(width: 320)
        }
    }

    private var trendPanel: some View {
        let buckets = store.snapshot.usage.filledLast7Days()
        return DashboardPanel(title: "近 7 日趋势", systemImage: "chart.xyaxis.line") {
            HStack(alignment: .firstTextBaseline) {
                trendMetric("7 日合计", PulseFormatters.tokens(store.snapshot.usage.last7DaysTokens))
                Spacer()
                trendMetric("单日峰值", PulseFormatters.tokens(store.snapshot.usage.peakDailyTokens))
            }

            Chart(buckets) { bucket in
                AreaMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [PulseTheme.blue.opacity(0.28), PulseTheme.blue.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .foregroundStyle(chartAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .symbolSize(22)
                .foregroundStyle(chartAccent)
            }
            .frame(height: 205)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) { value in
                    AxisValueLabel {
                        if let date = value.as(String.self) {
                            Text(String(date.suffix(5)))
                                .font(.system(size: 9.5))
                        }
                    }
                    AxisTick().foregroundStyle(separatorColor)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(separatorColor)
                    AxisValueLabel {
                        if let amount = value.as(Int64.self) {
                            Text(PulseFormatters.tokens(amount))
                                .font(.system(size: 9.5))
                        }
                    }
                }
            }
        }
    }

    private func trendMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var recentTasksPanel: some View {
        let filtered = filteredRecentTasks
        let tasks = Array(filtered.prefix(8).enumerated())
        return DashboardPanel(title: "任务历史", systemImage: "clock.arrow.circlepath") {
            HStack(spacing: 8) {
                TextField("搜索项目、路径或摘要", text: $taskSearchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                Picker("状态", selection: $taskHistoryFilter) {
                    ForEach(TaskHistoryFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 105)

                Text("\(filtered.count)/\(store.snapshot.recentTasks.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if store.snapshot.recentTasks.isEmpty {
                ContentUnavailableView("暂无任务历史", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if tasks.isEmpty {
                ContentUnavailableView("没有匹配的任务", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks, id: \.element.id) { index, task in
                        recentTaskRow(task)
                        if index < tasks.count - 1 {
                            Divider().overlay(separatorColor)
                        }
                    }
                }
            }
        }
    }

    private var filteredRecentTasks: [TaskRecord] {
        let query = taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.snapshot.recentTasks.filter { task in
            let matchesFilter: Bool
            switch taskHistoryFilter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = isLiveTask(task)
            case .completed:
                matchesFilter = !isLiveTask(task) && task.succeeded
            case .failed:
                matchesFilter = task.runState == .failed || !task.succeeded
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return [task.projectName, task.projectPath, task.gitBranch, task.model, task.summary]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    private func isLiveTask(_ task: TaskRecord) -> Bool {
        task.runState?.isActive == true
            || task.runState == .awaitingAuthorization
            || task.runState == .awaitingInput
    }

    private func recentTaskRow(_ task: TaskRecord) -> some View {
        let isLive = task.runState?.isActive == true
            || task.runState == .awaitingAuthorization
            || task.runState == .awaitingInput
        return HStack(spacing: 12) {
            Image(systemName: taskIcon(task))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(PulseTheme.status(task.indicatorColor))
                .frame(width: 22, height: 22)
                .background(PulseTheme.status(task.indicatorColor).opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(task.projectName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if let summary = task.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(isLive
                ? (task.runState?.rawValue ?? "处理中")
                 : PulseFormatters.relativeDate(task.finishedAt))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    isLive
                        ? PulseTheme.status(task.indicatorColor)
                        : Color.secondary.opacity(0.6)
                )
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .help(task.projectPath ?? task.summary ?? task.projectName)
    }

    private var currentTaskPanel: some View {
        let task = store.snapshot.currentTask
        let showsDataTunnel = task.state.isActive
            || task.state == .awaitingAuthorization
            || task.state == .awaitingInput
        return DashboardPanel(title: "当前任务", systemImage: "terminal") {
            HStack(spacing: 10) {
                StatusOrb(color: task.state.indicatorColor, size: 9)
                Text(task.state.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                if let startedAt = task.startedAt,
                   task.state.isActive || task.state == .awaitingAuthorization || task.state == .awaitingInput {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(PulseFormatters.duration(context.date.timeIntervalSince(startedAt)))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PulseTheme.blue)
                            .monospacedDigit()
                    }
                }
            }

            Text(task.state.detailDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsDataTunnel {
                TaskDataTunnelView(
                    tint: PulseTheme.status(task.state.indicatorColor),
                    isAnimating: task.state.isActive && !reduceMotion,
                    isPausedForAttention: task.state == .awaitingAuthorization || task.state == .awaitingInput
                )
                .frame(height: 68)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
            }

            Divider().overlay(separatorColor)

            infoRow("项目", task.projectName ?? "—")
            infoRow("分支", task.gitBranch ?? "—")
            infoRow("模型", task.model ?? "—")

            if let step = task.currentStep, !step.isEmpty {
                Text(step)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .background(subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: showsDataTunnel)
    }

    private func taskIcon(_ task: TaskRecord) -> String {
        switch task.runState {
        case .some(let state) where state.isActive:
            return "waveform.path.ecg"
        case .some(.awaitingAuthorization), .some(.awaitingInput):
            return "exclamationmark"
        case .some(.failed), .some(.networkError):
            return "xmark"
        default:
            return task.succeeded ? "checkmark" : "xmark"
        }
    }

    private var accountPanel: some View {
        DashboardPanel(title: "账号与连接", systemImage: "person.crop.circle") {
            VStack(spacing: 10) {
                infoRow("邮箱", store.snapshot.account.displayEmail)
                infoRow("套餐", store.snapshot.account.planType.displayName)
                infoRow("认证", store.snapshot.account.authMode.displayName)
                infoRow("CLI", store.snapshot.account.cliVersion ?? "—")
                infoRow("数据服务", store.syncHealthSummary)
                infoRow("重置卡", "×\(store.snapshot.rateLimits.availableResetCardCount)")
                if let expiration = store.snapshot.rateLimits.nextResetCardExpiration {
                    infoRow("最早到期", PulseFormatters.relativeDate(expiration))
                }
                if let nextReconnectAt = store.nextReconnectAt {
                    infoRow("自动重连", "第 \(store.reconnectAttempt) 次 · \(PulseFormatters.relativeDate(nextReconnectAt))")
                } else if let lastConnectedAt = store.lastRealConnectedAt, !store.isUsingMock {
                    infoRow("真实连接", PulseFormatters.relativeDate(lastConnectedAt))
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 6, height: 6)
                Text(store.connectionDetail)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .help(store.syncHealthDetail)
        }
    }

    private var insightsPanel: some View {
        let insights = store.taskUsageInsights()
        return DashboardPanel(title: "近 7 日洞察", systemImage: "sparkles") {
            HStack(spacing: 12) {
                insightMetric(
                    "已结束",
                    "\(insights.finishedTasks)",
                    color: .primary
                )
                insightMetric(
                    "成功率",
                    insights.successRate.map { String(format: "%.0f%%", $0) } ?? "—",
                    color: (insights.successRate ?? 100) < 80 ? PulseTheme.red : PulseTheme.green
                )
                insightMetric(
                    "失败",
                    "\(insights.failedTasks)",
                    color: insights.failedTasks > 0 ? PulseTheme.red : Color.secondary
                )
            }

            Divider().overlay(separatorColor)

            infoRow(
                "平均耗时",
                insights.averageDurationSeconds.map(PulseFormatters.duration) ?? "—"
            )
            infoRow(
                "高频项目",
                insights.topProjectName.map {
                    "\($0) · \(insights.topProjectTaskCount)"
                } ?? "—"
            )

            Button {
                copyUsageReport()
            } label: {
                Label(
                    reportCopied ? "已复制近 7 日周报" : "复制近 7 日周报",
                    systemImage: reportCopied ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func insightMetric(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyUsageReport() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.usageReportMarkdown(), forType: .string)
        reportCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            reportCopied = false
        }
        #endif
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11.5))
    }

    private var subtleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.045)
    }

    private var subtleBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.07)
    }

    private var separatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.075)
    }

    private var chartAccent: Color {
        visualTheme.accent
    }

    private var connectionIndicatorColor: Color {
        switch store.snapshot.connectionState {
        case .connected: return PulseTheme.green
        case .degraded: return PulseTheme.yellow
        case .disconnected, .connecting, .error: return PulseTheme.gray
        }
    }
}

private enum TaskHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case failed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .active: return "处理中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

// MARK: - Current task data tunnel

/// 轻量版 Data Tunnel：左侧多路上下文汇聚到模型节点，再沿单路响应流输出。
/// 仅承担任务状态表达，不表示真实 Token 速度。
struct TaskDataTunnelView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color
    let isAnimating: Bool
    let isPausedForAttention: Bool

    private let lineCount = 16
    private let particleCount = 10

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("上下文")
                Spacer()
                Text("模型")
                Spacer()
                Text(isPausedForAttention ? "等待继续" : "响应流")
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
                Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                    drawTunnel(
                        context: &context,
                        size: size,
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPausedForAttention ? "任务数据流已暂停，等待用户操作" : "任务上下文正在汇聚到模型并生成响应")
    }

    private func drawTunnel(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 1, size.height > 1 else { return }

        let centerY = size.height * 0.52
        let mergeX = size.width * 0.46
        let lineColor = tint.opacity(colorScheme == .dark ? 0.26 : 0.2)

        for index in 0..<lineCount {
            let lane = lineCount == 1
                ? CGFloat.zero
                : CGFloat(index) / CGFloat(lineCount - 1) * 2 - 1
            let path = incomingPath(lane: lane, size: size, mergeX: mergeX, centerY: centerY)
            context.stroke(path, with: .color(lineColor), lineWidth: 0.65)
        }

        let mergePoint = CGPoint(x: mergeX, y: centerY)
        let outputEnd = CGPoint(x: size.width, y: centerY)
        var output = Path()
        output.move(to: mergePoint)
        output.addLine(to: outputEnd)
        context.stroke(
            output,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.58), tint.opacity(0.14)]),
                startPoint: mergePoint,
                endPoint: outputEnd
            ),
            lineWidth: 0.85
        )

        drawGlow(context: &context, at: mergePoint, radius: 2.2, opacity: 0.75)

        for index in 0..<particleCount {
            let base = Double(index) / Double(particleCount)
            let progress = CGFloat((base + time * 0.22).truncatingRemainder(dividingBy: 1))
            let laneIndex = (index * 7 + 3) % lineCount
            let lane = CGFloat(laneIndex) / CGFloat(lineCount - 1) * 2 - 1
            let point = tunnelPoint(
                progress: progress,
                lane: lane,
                size: size,
                mergeX: mergeX,
                centerY: centerY
            )
            let tailProgress = max(0, progress - 0.035)
            let tail = tunnelPoint(
                progress: tailProgress,
                lane: lane,
                size: size,
                mergeX: mergeX,
                centerY: centerY
            )

            var trail = Path()
            trail.move(to: tail)
            trail.addLine(to: point)
            context.stroke(
                trail,
                with: .linearGradient(
                    Gradient(colors: [.clear, tint.opacity(0.9)]),
                    startPoint: tail,
                    endPoint: point
                ),
                lineWidth: 1.25
            )
            drawGlow(context: &context, at: point, radius: 1.45, opacity: 0.95)
        }
    }

    private func incomingPath(lane: CGFloat, size: CGSize, mergeX: CGFloat, centerY: CGFloat) -> Path {
        let start = CGPoint(x: 0, y: centerY + lane * size.height * 0.43)
        let control1 = CGPoint(x: size.width * 0.16, y: start.y)
        let control2 = CGPoint(x: mergeX - size.width * 0.12, y: centerY + lane * size.height * 0.055)
        let end = CGPoint(x: mergeX, y: centerY)

        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    private func tunnelPoint(
        progress: CGFloat,
        lane: CGFloat,
        size: CGSize,
        mergeX: CGFloat,
        centerY: CGFloat
    ) -> CGPoint {
        let mergeProgress: CGFloat = 0.58
        if progress <= mergeProgress {
            let t = progress / mergeProgress
            let p0 = CGPoint(x: 0, y: centerY + lane * size.height * 0.43)
            let p1 = CGPoint(x: size.width * 0.16, y: p0.y)
            let p2 = CGPoint(x: mergeX - size.width * 0.12, y: centerY + lane * size.height * 0.055)
            let p3 = CGPoint(x: mergeX, y: centerY)
            return cubicPoint(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
        }

        let t = (progress - mergeProgress) / (1 - mergeProgress)
        return CGPoint(x: mergeX + (size.width - mergeX) * t, y: centerY)
    }

    private func cubicPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let inverse = 1 - t
        let a = inverse * inverse * inverse
        let b = 3 * inverse * inverse * t
        let c = 3 * inverse * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    private func drawGlow(context: inout GraphicsContext, at point: CGPoint, radius: CGFloat, opacity: Double) {
        let coreRect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: radius * 2.4))
            glow.fill(
                Path(ellipseIn: coreRect.insetBy(dx: -radius, dy: -radius)),
                with: .color(tint.opacity(opacity * 0.72))
            )
        }
        context.fill(Path(ellipseIn: coreRect), with: .color(tint.opacity(opacity)))
    }
}

struct DashboardPanel<Content: View>: View {
    @Environment(\.pulseVisualTheme) private var visualTheme
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(visualTheme.accent)
                    .frame(width: 20, height: 20)
                    .background(visualTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            PulseThemedSurface(
                shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
                role: .card
            )
        }
    }
}

private struct DashboardBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.pulseVisualTheme) private var visualTheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: visualTheme.backdropColors(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [visualTheme.accent.opacity(colorScheme == .dark ? 0.2 : 0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )

            RadialGradient(
                colors: [visualTheme.surfaceTint.opacity(colorScheme == .dark ? 0.7 : 0.5), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
