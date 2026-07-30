import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

/// 菜单栏迷你面板 — Liquid Glass / Control Center 风格
struct MenuBarPanelView: View {
    @Environment(PulseStore.self) private var store
    @Environment(ArtificialAnalysisLeaderboardStore.self) private var modelRankings
    @Environment(CodexResetPredictionStore.self) private var resetPrediction
    @Environment(\.openWindow) private var openWindow
    @State private var isResetCardsExpanded = false
    @State private var isCapsuleVisible = false
    @State private var isShowingWeatherLocationPicker = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let guideKind = OnboardingGuideView.kind(for: store) {
                    hairline
                    OnboardingGuideView(kind: guideKind)
                    if let err = store.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(PulseTheme.red)
                            .padding(.top, 8)
                    }
                } else {
                    hairline
                    accountRow
                    hairline
                    rateLimitSection
                    if AppConstants.showsResetPredictionPanels {
                        hairline
                        resetPredictionSection
                    }
                    hairline
                    tokenRow
                    hairline
                    openAIModelIQSection
                    hairline
                    tokenTrendSection
                    hairline
                    taskSection
                    if let err = store.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(PulseTheme.red)
                            .padding(.top, 8)
                    }
                }
                hairline
                themeControls
                hairline
                activityBandControls
                hairline
                miniCapsuleControls
                hairline
                petControls
                hairline
                informationBarControls
                #if os(macOS)
                hairline
                followCodexLaunchControls
                #endif
                hairline
                actions
            }
            .padding(14)
        }
        // MenuBarExtra 会跟随内容高度重建原生弹窗。重置卡收起时若弹窗
        // 同时缩短，AppKit 可能把本次点击判定为关闭面板。固定外壳高度，
        // 只让内部内容滚动，可以保证展开/收起不会关闭整个工具。
        .frame(width: 332, height: menuPanelHeight)
        .background {
            GlassPanelBackground()
        }
        .environment(\.pulseVisualTheme, store.settings.resolvedVisualTheme)
        .tint(store.settings.resolvedVisualTheme.accent)
        .onAppear {
            modelRankings.start()
            resetPrediction.start()
        }
        .sheet(isPresented: $isShowingWeatherLocationPicker) {
            WeatherLocationPickerView(initialLocation: store.settings.weatherLocation) { location in
                store.settings.weatherLocation = location
                store.settings.resolvedInformationBarEnabled = true
                store.saveSettings()
                isShowingWeatherLocationPicker = false
            }
        }
    }

    private var menuPanelHeight: CGFloat {
        #if os(macOS)
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 12
        let preferredHeight: CGFloat = OnboardingGuideView.kind(for: store) == nil ? 1_040 : 520
        return min(preferredHeight, max(480, availableHeight))
        #else
        return 720
        #endif
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex-Pulse")
                    .font(.system(size: 14, weight: .semibold))
                Text(store.isUsingMock ? "演示模式 · Mock" : store.connectionDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusOrb(color: store.snapshot.statusColor)
                .padding(.top, 3)
        }
    }

    private var accountRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.snapshot.account.displayEmail)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(store.snapshot.account.planType.displayName) · \(store.snapshot.account.authMode.displayName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var rateLimitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let buckets = store.snapshot.rateLimits.buckets
            if buckets.isEmpty {
                if store.snapshot.account.authMode == .apiKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("API 按量计费", systemImage: "key.horizontal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PulseTheme.blue)
                        Text("不使用 ChatGPT 每周 / 5 小时额度，Token 用量在下方统计")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("暂无额度数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(buckets) { bucket in
                    limitRow(bucket: bucket, compact: bucket.id != buckets.first?.id)
                }
                if !buckets.contains(where: isFiveHourBucket) {
                    HStack {
                        Text("5 小时用量")
                        Spacer()
                        Text("当前接口未返回")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                }
            }
            if store.snapshot.rateLimits.availableResetCardCount > 0 {
                resetCardSection
            }
        }
    }

    /// 重置卡：点击行展开每张卡的具体到期时间与适用额度类型。
    private var resetCardSection: some View {
        let limits = store.snapshot.rateLimits
        let cards = limits.resetCards
            .filter(\.isAvailable)
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                isResetCardsExpanded.toggle()
            } label: {
                HStack {
                    Text("重置卡 ×\(limits.availableResetCardCount)")
                    Spacer()
                    if let expiration = limits.nextResetCardExpiration {
                        Text("最近 \(PulseFormatters.absoluteDateTime(expiration)) 到期")
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(isResetCardsExpanded ? 90 : 0))
                        .animation(.easeOut(duration: 0.16), value: isResetCardsExpanded)
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isResetCardsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(PulseTheme.blue.opacity(0.8))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("重置卡 \(index + 1)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Text(resetCardExpiryText(card))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(resetCardExpiryColor(card))
                                }
                                if let acquiredAt = card.acquiredAt {
                                    Text("获取于 \(PulseFormatters.absoluteDateTime(acquiredAt))")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                }
                                if !card.applicableLimitTypes.isEmpty {
                                    Text("适用：\(card.applicableLimitTypes.joined(separator: "、"))")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                }
            }
        }
    }

    private func resetCardExpiryText(_ card: RateLimitResetCard) -> String {
        guard let expiresAt = card.expiresAt else { return "无到期时间" }
        return "\(PulseFormatters.absoluteDateTime(expiresAt)) 到期"
    }

    private func resetCardExpiryColor(_ card: RateLimitResetCard) -> Color {
        guard let expiresAt = card.expiresAt else { return Color.secondary }
        let remaining = expiresAt.timeIntervalSinceNow
        if remaining < 24 * 3600 { return PulseTheme.red }
        if remaining < 3 * 24 * 3600 { return PulseTheme.orange }
        return Color.secondary
    }

    private func isFiveHourBucket(_ bucket: RateLimitBucket) -> Bool {
        if bucket.name.contains("5 小时") { return true }
        guard let duration = bucket.windowDurationSeconds else { return false }
        return abs(duration - 5 * 3600) <= 5 * 60
    }

    private var resetPredictionSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(resetPredictionColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("额外额度重置预测")
                    .font(.system(size: 11, weight: .semibold))
                Text("不含正常 5 小时及每周恢复")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if resetPrediction.isLoading {
                ProgressView().controlSize(.mini)
            } else if resetPrediction.isEnabled {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(resetPrediction.snapshot.predictionIndex)/100")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(resetPredictionColor)
                    Text(resetPrediction.snapshot.level.displayName)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("未启用")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var resetPredictionColor: Color {
        switch resetPrediction.snapshot.level {
        case .none: return Color.secondary
        case .low: return PulseTheme.blue
        case .possible: return PulseTheme.orange
        case .high, .veryHigh: return PulseTheme.red
        case .confirmed: return PulseTheme.green
        }
    }

    private func limitRow(bucket: RateLimitBucket, compact: Bool) -> some View {
        let remaining = bucket.remainingPercent
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.name)
                    .font(.system(size: compact ? 10.5 : 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("剩余 \(PulseFormatters.percent(remaining))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PulseTheme.usage(remaining))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(PulseFormatters.countdown(bucket.resetCountdown))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            LiquidProgressBar(remainingPercent: remaining, height: compact ? 5 : 9)
            if !compact,
               let forecast = store.primaryRateLimitForecast,
               let summary = store.primaryRateLimitForecastSummary {
                Label(
                    summary,
                    systemImage: forecast.willExhaustBeforeReset
                        ? "exclamationmark.triangle.fill"
                        : "chart.line.uptrend.xyaxis"
                )
                .font(.system(size: 10))
                .foregroundStyle(
                    forecast.willExhaustBeforeReset
                        ? PulseTheme.red
                        : Color.secondary.opacity(0.7)
                )
                .lineLimit(1)
            }
        }
    }

    private var tokenRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                glassMetric(label: "今日 Token", value: PulseFormatters.tokens(store.snapshot.usage.todayTokens))
                glassMetric(label: "累计", value: PulseFormatters.tokens(store.snapshot.usage.totalTokens))
                glassMetric(label: "连续", value: store.snapshot.usage.currentStreakDays.map { "\($0) 天" } ?? "—")
            }
            if let velocity = store.snapshot.usage.tokenVelocityPerMinute {
                Label(
                    "当前速度 \(PulseFormatters.tokens(velocity)) Token/分钟",
                    systemImage: "speedometer"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            if let note = store.snapshot.usage.sourceNote, !store.snapshot.usage.hasAnyTokenMetric {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }

    private func glassMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openAIQualityLeaders: [ArtificialAnalysisModel] {
        guard let snapshot = modelRankings.snapshot else { return [] }
        return Array(
            snapshot.qualityLeaders
                .filter { $0.isOpenAI }
                .prefix(6)
        )
    }

    private var openAIModelIQSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(PulseTheme.blue)
                Text("OpenAI 模型排行")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("AA Intelligence Index")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            if modelRankings.isLoading && openAIQualityLeaders.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text("正在同步模型 IQ…")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            } else if openAIQualityLeaders.isEmpty {
                Text(modelRankings.hasAPIKey ? "暂无 OpenAI IQ 数据" : "请先在设置中填写 Artificial Analysis API Key")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: 6) {
                    Text("模型")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("IQ")
                        .frame(width: 38, alignment: .trailing)
                    Text("编程")
                        .frame(width: 42, alignment: .trailing)
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.leading, 27)

                ForEach(Array(openAIQualityLeaders.enumerated()), id: \.element.id) { index, model in
                    OpenAIModelIQRow(rank: index + 1, model: model)
                }
            }
        }
    }

    private var tokenTrendSection: some View {
        let buckets = store.snapshot.usage.filledLast7Days()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(PulseTheme.blue)
                Text("近 7 天 Token")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("合计 \(PulseFormatters.tokens(store.snapshot.usage.last7DaysTokens))")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Chart(buckets) { bucket in
                AreaMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [PulseTheme.blue.opacity(0.25), PulseTheme.blue.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .foregroundStyle(PulseTheme.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 82)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let day = value.as(String.self) {
                            Text(String(day.suffix(5)))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .accessibilityLabel("近 7 天 Token 用量图表")
            .accessibilityValue("合计 \(PulseFormatters.tokens(store.snapshot.usage.last7DaysTokens))")
        }
    }

    private var taskSection: some View {
        let task = store.snapshot.currentTask
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.state.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(task.state.isActive ? PulseTheme.blue : Color.primary)
                Spacer()
                if let startedAt = task.startedAt,
                   task.state.isActive || task.state == .awaitingAuthorization || task.state == .awaitingInput {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(PulseFormatters.duration(context.date.timeIntervalSince(startedAt)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Text(task.state.detailDescription)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let name = task.projectName {
                Text("\(name)\(task.model.map { " · \($0)" } ?? "")\(task.reasoningEffort.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if store.snapshot.activeTaskCount > 1 {
                Text("另有 \(store.snapshot.activeTaskCount - 1) 个任务正在处理")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(PulseTheme.blue)
            }
            if let step = task.currentStep {
                Text(step)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                            }
                    }
                    .padding(.top, 4)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 5) {
            Button {
                Task { await store.refreshAll(forceRemote: true) }
            } label: {
                toolbarTextLabel("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(MenuBarToolbarPressStyle())
            .help("刷新数据")

            Button {
                #if os(macOS)
                if let win = NSApp.windows.first(where: { $0.title == "Codex-Pulse" }) {
                    win.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "dashboard")
                }
                NSApp.activate(ignoringOtherApps: true)
                #else
                openWindow(id: "dashboard")
                #endif
            } label: {
                toolbarTextLabel("看板", systemImage: "rectangle.grid.2x2")
            }
            .buttonStyle(MenuBarToolbarPressStyle())
            .help("打开 CodexPulse 看板")

            Button {
                Task { await store.reconnect() }
            } label: {
                toolbarTextLabel("重连", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(MenuBarToolbarPressStyle())
            .help("重新连接 Codex")

            #if os(macOS)
            Button {
                FloatingCapsuleController.shared.toggle(store: store)
                isCapsuleVisible = FloatingCapsuleController.shared.isVisible
            } label: {
                toolbarIconLabel(
                    isCapsuleVisible ? "capsule.fill" : "capsule",
                    tint: isCapsuleVisible ? PulseTheme.blue : .secondary
                )
            }
            .buttonStyle(MenuBarToolbarPressStyle())
            .help(isCapsuleVisible ? "隐藏悬浮胶囊" : "显示悬浮胶囊")
            .onAppear {
                isCapsuleVisible = FloatingCapsuleController.shared.isVisible
            }
            #endif

            Spacer()

            Menu {
                Button("复制近 7 日周报") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.usageReportMarkdown(), forType: .string)
                    #endif
                }
                Button("复制诊断信息") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.copyDiagnostics(), forType: .string)
                    #endif
                }
                Button("打开日志文件") {
                    #if os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([PulseLog.logFileURL])
                    #endif
                }
                Button("打开 Codex") { store.openCodex() }
                Button("打开项目目录") { store.openProjectDirectory() }
                    .disabled(store.quickActionProjectPath == nil)
                Button("在终端中打开项目") { store.openTerminalAtProject() }
                Button("打开额度页面") { store.openUsagePage() }
                #if os(macOS)
                Button(isCapsuleVisible ? "关闭悬浮胶囊" : "打开悬浮胶囊") {
                    FloatingCapsuleController.shared.toggle(store: store)
                    isCapsuleVisible = FloatingCapsuleController.shared.isVisible
                }
                #endif
                Divider()
                Button("退出") {
                    #if os(macOS)
                    CodexPulseLifecycle.quit(store: store)
                    #endif
                }
            } label: {
                toolbarIconLabel("ellipsis", tint: PulseTheme.blue)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")

            #if os(macOS)
            Button {
                CodexPulseLifecycle.quit(store: store)
            } label: {
                toolbarIconLabel("power", tint: PulseTheme.red, destructive: true)
            }
            .buttonStyle(MenuBarToolbarPressStyle())
            .help("退出 CodexPulse")
            .accessibilityLabel("退出 CodexPulse")
            #endif
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
        }
    }

    private func toolbarTextLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 52, height: 30)
            .foregroundStyle(Color.primary.opacity(0.82))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
    }

    private func toolbarIconLabel(
        _ systemImage: String,
        tint: Color,
        destructive: Bool = false
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        destructive
                            ? PulseTheme.red.opacity(0.09)
                            : Color.primary.opacity(0.055)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        destructive
                            ? PulseTheme.red.opacity(0.22)
                            : Color.white.opacity(0.18),
                        lineWidth: 0.6
                    )
            }
    }

    #if os(macOS)
    private var followCodexLaunchControls: some View {
        Toggle(
            "随 Codex 启动",
            isOn: Binding(
                get: { store.settings.resolvedFollowCodexLaunch },
                set: { enabled in
                    store.settings.resolvedFollowCodexLaunch = enabled
                    store.saveSettings()
                    FloatingCapsuleController.shared.setFollowCodexLaunch(
                        enabled,
                        store: store
                    )
                }
            )
        )
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 11, weight: .medium))
        .help("检测到 Codex 打开时自动显示 CodexPulse")
    }
    #endif

    private var activityBandControls: some View {
        HStack(spacing: 10) {
            Toggle(
                "思考灯带",
                isOn: Binding(
                    get: { store.settings.resolvedActivityBandEnabled },
                    set: {
                        store.settings.resolvedActivityBandEnabled = $0
                        store.saveSettings()
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer(minLength: 4)

            Picker(
                "灯带效果",
                selection: Binding(
                    get: { store.settings.resolvedActivityBandStyle },
                    set: {
                        store.settings.resolvedActivityBandStyle = $0
                        store.saveSettings()
                    }
                )
            ) {
                ForEach(ActivityBandStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 86)
            .disabled(!store.settings.resolvedActivityBandEnabled)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private var miniCapsuleControls: some View {
        HStack(spacing: 10) {
            Label("缩小展示", systemImage: "circle.circle")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            Picker(
                "缩小展示",
                selection: Binding(
                    get: {
                        isAPIKeyMode
                            ? store.settings.resolvedAPIMiniCapsuleStyle
                            : store.settings.resolvedMiniCapsuleStyle
                    },
                    set: { style in
                        if isAPIKeyMode {
                            store.settings.resolvedAPIMiniCapsuleStyle = style
                        } else {
                            store.settings.resolvedMiniCapsuleStyle = style
                        }
                        store.saveSettings()
                    }
                )
            ) {
                ForEach(availableMiniCapsuleStyles) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 98)
        }
    }

    private var isAPIKeyMode: Bool {
        store.snapshot.account.authMode == .apiKey
    }

    private var availableMiniCapsuleStyles: [MiniCapsuleStyle] {
        isAPIKeyMode ? MiniCapsuleStyle.apiKeyCases : MiniCapsuleStyle.allCases
    }

    private var petControls: some View {
        HStack(spacing: 10) {
            Label("宠物", systemImage: "pawprint")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            Picker(
                "宠物",
                selection: Binding(
                    get: { store.settings.resolvedPetCharacter },
                    set: {
                        store.settings.resolvedPetCharacter = $0
                        store.saveSettings()
                    }
                )
            ) {
                ForEach(PetCharacter.allCases) { pet in
                    Text(pet.displayName).tag(pet)
                }
            }
            .labelsHidden()
            .frame(width: 98)
        }
    }

    private var informationBarControls: some View {
        HStack(spacing: 10) {
            Toggle(
                "信息任务栏",
                isOn: Binding(
                    get: { store.settings.resolvedInformationBarEnabled },
                    set: { setInformationBarEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer(minLength: 4)

            Button {
                isShowingWeatherLocationPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(store.settings.weatherLocation?.name ?? "选择地区")
                        .lineLimit(1)
                }
                .frame(width: 84)
            }
            .buttonStyle(GlassButtonStyle())
            .help(
                store.settings.weatherLocation.map {
                    "当前地区：\($0.displayName) · 点击更改"
                } ?? "选择天气和当地时间所使用的地区"
            )
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func setInformationBarEnabled(_ enabled: Bool) {
        if enabled && store.settings.weatherLocation == nil {
            isShowingWeatherLocationPicker = true
            return
        }
        store.settings.resolvedInformationBarEnabled = enabled
        store.saveSettings()
    }

    private var themeControls: some View {
        HStack(spacing: 10) {
            Label("界面主题", systemImage: "paintpalette")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            Picker(
                "界面主题",
                selection: Binding(
                    get: { store.settings.resolvedVisualTheme },
                    set: { newTheme in
                        withAnimation(.easeInOut(duration: 0.18)) {
                            store.settings.resolvedVisualTheme = newTheme
                        }
                        store.saveSettings()
                    }
                )
            ) {
                ForEach(PulseVisualTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .labelsHidden()
            .frame(width: 98)
        }
    }
}

private struct OpenAIModelIQRow: View {
    let rank: Int
    let model: ArtificialAnalysisModel

    private var iqText: String {
        model.intelligenceIndex.map { String(format: "%.1f", $0) } ?? "—"
    }

    private var codingText: String {
        model.codingIndex.map { String(format: "%.1f", $0) } ?? "—"
    }

    var body: some View {
        HStack(spacing: 7) {
            Text("#\(rank)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(rank == 1 ? PulseTheme.blue : Color.secondary)
                .frame(width: 20, alignment: .leading)

            Text(model.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(iqText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(PulseTheme.blue)
                .frame(width: 38, alignment: .trailing)

            Text(codingText)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .frame(minHeight: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(rank) 名，\(model.name)，IQ \(iqText)，编程指数 \(codingText)")
    }
}

// MARK: - Glass button

private struct MenuBarToolbarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                    }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
