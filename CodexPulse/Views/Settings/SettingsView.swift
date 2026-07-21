import SwiftUI
#if os(macOS)
import AppKit
import ServiceManagement
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @Environment(PulseStore.self) private var store
    @Environment(ArtificialAnalysisLeaderboardStore.self) private var modelRankings
    @Environment(CodexResetPredictionStore.self) private var resetPrediction
    @Environment(AppUpdateService.self) private var appUpdates
    @State private var notificationPermission: PulseNotificationPermission = .unknown
    @State private var launchMessage: String?
    @State private var historyCount = 0
    @State private var historyMessage: String?
    @State private var isConfirmingHistoryClear = false
    @State private var rateSampleCount = 0
    @State private var isConfirmingRateSampleClear = false
    @State private var artificialAnalysisAPIKey = ""
    @State private var isConfirmingArtificialKeyRemoval = false
    @State private var thirdPartyXRSSTemplate = ""
    @State private var isShowingWeatherLocationPicker = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section("外观") {
                Picker("界面主题", selection: $store.settings.resolvedVisualTheme) {
                    ForEach(PulseVisualTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .onChange(of: store.settings.resolvedVisualTheme) { _, _ in
                    store.saveSettings()
                }

                Picker("明暗模式", selection: $store.settings.resolvedAppearanceMode) {
                    ForEach(PulseAppearanceMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.settings.resolvedAppearanceMode) { _, _ in
                    store.saveSettings()
                }

                Toggle("启用思考灯带", isOn: $store.settings.resolvedActivityBandEnabled)
                    .onChange(of: store.settings.resolvedActivityBandEnabled) { _, _ in
                        store.saveSettings()
                    }

                Picker("灯带效果", selection: $store.settings.resolvedActivityBandStyle) {
                    ForEach(ActivityBandStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .disabled(!store.settings.resolvedActivityBandEnabled)
                .onChange(of: store.settings.resolvedActivityBandStyle) { _, _ in
                    store.saveSettings()
                }

                Picker("缩小展示", selection: $store.settings.resolvedMiniCapsuleStyle) {
                    ForEach(MiniCapsuleStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: store.settings.resolvedMiniCapsuleStyle) { _, _ in
                    store.saveSettings()
                }
            }

            Section("信息任务栏") {
                Toggle(
                    "天气 · 地区 · 星期 · 当前时间",
                    isOn: Binding(
                        get: { store.settings.resolvedInformationBarEnabled },
                        set: { setInformationBarEnabled($0) }
                    )
                )

                Text("开启后天气氛围会融入悬浮胶囊左侧，并隐藏状态灯；关闭后恢复当前胶囊样式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.settings.resolvedInformationBarEnabled,
                   let location = store.settings.weatherLocation {
                    LabeledContent("当前地区", value: location.displayName)
                    Button {
                        isShowingWeatherLocationPicker = true
                    } label: {
                        Label("更改地区", systemImage: "mappin.and.ellipse")
                    }
                } else if store.settings.weatherLocation == nil {
                    Button {
                        isShowingWeatherLocationPicker = true
                    } label: {
                        Label("选择地区", systemImage: "mappin.and.ellipse")
                    }
                }

                Text("地区搜索会发送输入的城市名；天气请求只发送确认后的经纬度，不读取或上传 Codex 内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 3) {
                    Text("Weather data by")
                    Link("Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
                    Text("· Location data by")
                    Link("GeoNames", destination: URL(string: "https://www.geonames.org/")!)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("Open-Meteo 免费开放接口主要适用于非商业用途；商业发行请遵循其订阅与许可条款。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("数据") {
                LabeledContent("刷新策略", value: "处理中 5 秒 · 空闲 15 秒 ×3")
                Text("空闲补刷完成后进入静默，仅由任务事件或手动刷新唤醒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("CLI 不可用时使用演示数据", isOn: $store.settings.useMockWhenCLIUnavailable)
                    .onChange(of: store.settings.useMockWhenCLIUnavailable) { _, _ in
                        store.saveSettings()
                        Task { await store.reconnect() }
                    }

                Picker("任务历史保留", selection: $store.settings.historyRetentionDays) {
                    ForEach(AppConstants.historyRetentionOptions, id: \.self) { days in
                        Text(days == 0 ? "不保存" : "\(days) 天").tag(days)
                    }
                }
                .onChange(of: store.settings.historyRetentionDays) { _, _ in
                    store.updateHistoryRetention()
                    refreshHistoryCount()
                }

                LabeledContent("本地历史", value: "\(historyCount) 条")
                Button("导出任务历史…") {
                    exportHistory()
                }
                Button("导出近 7 日周报…") {
                    exportUsageReport()
                }
                Button("清除任务历史…", role: .destructive) {
                    isConfirmingHistoryClear = true
                }
                .disabled(historyCount == 0)
                if let historyMessage {
                    Text(historyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "启用额度消耗预测",
                    isOn: $store.settings.resolvedRateLimitForecastEnabled
                )
                .onChange(of: store.settings.resolvedRateLimitForecastEnabled) { _, _ in
                    store.updateRateLimitForecastSetting()
                    refreshRateSampleCount()
                }
                LabeledContent("额度预测样本", value: "\(rateSampleCount) 条 · 自动保留 14 天")
                Button("清除额度预测样本…", role: .destructive) {
                    isConfirmingRateSampleClear = true
                }
                .disabled(rateSampleCount == 0)
            }

            Section("系统") {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: updateLaunchAtLogin
                ))
                if let launchMessage {
                    Text(launchMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("当前版本", value: "v\(appUpdates.currentVersion)")
                HStack {
                    Button("检查更新") {
                        Task { await appUpdates.checkForUpdates(userInitiated: true) }
                    }
                    .disabled(appUpdates.isChecking)

                    Button("查看 GitHub Releases") {
                        appUpdates.openReleasesPage()
                    }

                    if appUpdates.isChecking {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(appUpdates.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Artificial Analysis") {
                LabeledContent(
                    "API Key",
                    value: modelRankings.hasAPIKey ? "已安全保存" : "未配置"
                )

                SecureField("粘贴新的 Data API Key", text: $artificialAnalysisAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()
                    .onSubmit { saveArtificialAnalysisAPIKey() }

                HStack {
                    Button(modelRankings.hasAPIKey ? "更新 API Key" : "保存 API Key") {
                        saveArtificialAnalysisAPIKey()
                    }
                    .disabled(
                        artificialAnalysisAPIKey
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || modelRankings.isLoading
                    )

                    Button("刷新排行榜") {
                        Task { await modelRankings.refresh(force: true) }
                    }
                    .disabled(!modelRankings.hasAPIKey || modelRankings.isLoading)

                    if modelRankings.hasAPIKey {
                        Button("删除 Key…", role: .destructive) {
                            isConfirmingArtificialKeyRemoval = true
                        }
                    }
                }

                if let snapshot = modelRankings.snapshot {
                    LabeledContent(
                        "本地缓存",
                        value: "OpenAI \(snapshot.models.filter { $0.isOpenAI }.count) 个模型 · \(PulseFormatters.relativeDate(snapshot.fetchedAt))"
                    )
                }

                if modelRankings.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在验证并同步模型数据…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let error = modelRankings.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(PulseTheme.red)
                } else if let message = modelRankings.statusMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let keyURL = URL(string: "https://artificialanalysis.ai/api-key-management-redirect") {
                    Link(destination: keyURL) {
                        Label("创建或管理 Artificial Analysis API Key", systemImage: "arrow.up.right.square")
                    }
                }

                Text("Key 只保存在当前 Mac 的 Keychain，并通过 x-api-key 请求官方接口；不会写入源码、UserDefaults、日志、Widget 或导出文件。排行榜数据缓存 12 小时，以节省每日请求额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            resetPredictionSettingsSection

            Section("通知") {
                Toggle("启用系统通知", isOn: $store.settings.resolvedNotificationsEnabled)
                    .onChange(of: store.settings.resolvedNotificationsEnabled) { _, enabled in
                        store.saveSettings()
                        if enabled, notificationPermission == .notDetermined {
                            Task { await requestNotificationPermission() }
                        }
                    }

                LabeledContent("系统权限", value: notificationPermission.displayName)
                if notificationPermission == .notDetermined {
                    Button("允许通知") {
                        Task { await requestNotificationPermission() }
                    }
                } else if notificationPermission == .denied {
                    Button("打开系统通知设置") {
                        openNotificationSettings()
                    }
                }

                Toggle("提示音", isOn: $store.settings.soundEnabled)
                    .disabled(!store.settings.resolvedNotificationsEnabled)
                    .onChange(of: store.settings.soundEnabled) { _, _ in
                        store.saveSettings()
                    }

                DisclosureGroup("额度预警阈值") {
                    ForEach(AppConstants.alertThresholdOptions, id: \.self) { threshold in
                        Toggle("已使用达到 \(Int(threshold))%", isOn: thresholdBinding(threshold))
                    }
                }

                Picker("长任务提醒", selection: $store.settings.resolvedLongTaskAlertMinutes) {
                    ForEach(AppConstants.longTaskAlertMinuteOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分钟").tag(minutes)
                    }
                }
                .onChange(of: store.settings.resolvedLongTaskAlertMinutes) { _, _ in
                    store.saveSettings()
                }

                Picker("Token 速度提醒", selection: $store.settings.resolvedTokenSpikeThresholdPerMinute) {
                    ForEach(AppConstants.tokenSpikeThresholdOptions, id: \.self) { threshold in
                        Text(threshold == 0
                             ? "关闭"
                             : "\(PulseFormatters.tokens(threshold))/分钟").tag(threshold)
                    }
                }
                .onChange(of: store.settings.resolvedTokenSpikeThresholdPerMinute) { _, _ in
                    store.saveSettings()
                }

                Picker("重置卡到期提醒", selection: $store.settings.resolvedResetCardExpiryAlertDays) {
                    ForEach(AppConstants.resetCardExpiryAlertDayOptions, id: \.self) { days in
                        Text(days == 0 ? "关闭" : "提前 \(days) 天").tag(days)
                    }
                }
                .onChange(of: store.settings.resolvedResetCardExpiryAlertDays) { _, _ in
                    store.saveSettings()
                }
            }

            Section("Webhook") {
                TextField("https://example.com/codex-pulse", text: webhookURLBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.saveWebhookSettings()
                    }

                Toggle("启用 Webhook", isOn: $store.settings.webhookEnabled)
                    .onChange(of: store.settings.webhookEnabled) { _, _ in
                        store.saveWebhookSettings()
                    }

                Toggle(
                    "包含项目名称",
                    isOn: $store.settings.resolvedWebhookIncludeProjectName
                )
                .disabled(!store.settings.webhookEnabled)
                .onChange(of: store.settings.resolvedWebhookIncludeProjectName) { _, _ in
                    store.saveWebhookSettings()
                }

                Button("发送测试消息") {
                    store.saveWebhookSettings()
                    Task { await store.testWebhook() }
                }
                .disabled(webhookURLBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let status = store.lastWebhookStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("仅发送事件、时间和数值；默认不发送项目名，也不会发送账号、路径、任务摘要、对话或源码。支持 HTTPS，以及本机 localhost HTTP。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("菜单栏") {
                LabeledContent("剩余额度", value: "始终显示")
            }

            Section("关于") {
                LabeledContent("应用", value: AppConstants.appName)
                LabeledContent("模式", value: store.isUsingMock ? "演示" : "真实 App Server")
                LabeledContent("数据服务", value: store.syncHealthSummary)
                LabeledContent("日志", value: PulseLog.logFileURL.path)
                    .font(.caption2)
                    .lineLimit(2)
                Text("本地优先 · 不上传源码与对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 680)
        .onAppear {
            syncLaunchAtLoginStatus()
            refreshHistoryCount()
            refreshRateSampleCount()
            thirdPartyXRSSTemplate = resetPrediction.thirdPartyXRSSTemplate
            resetPrediction.start()
            Task { await refreshNotificationPermission() }
        }
        .sheet(isPresented: $isShowingWeatherLocationPicker) {
            WeatherLocationPickerView(initialLocation: store.settings.weatherLocation) { location in
                store.settings.weatherLocation = location
                store.settings.resolvedInformationBarEnabled = true
                store.saveSettings()
                isShowingWeatherLocationPicker = false
            }
            .preferredColorScheme(store.settings.resolvedAppearanceMode.colorScheme)
        }
        .confirmationDialog(
            "确定清除全部本地任务历史？",
            isPresented: $isConfirmingHistoryClear,
            titleVisibility: .visible
        ) {
            Button("清除全部历史", role: .destructive) {
                store.clearTaskHistory()
                refreshHistoryCount()
                historyMessage = "本地任务历史已清除"
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不会删除 Codex 中的任务，且无法撤销。")
        }
        .confirmationDialog(
            "确定清除全部额度预测样本？",
            isPresented: $isConfirmingRateSampleClear,
            titleVisibility: .visible
        ) {
            Button("清除预测样本", role: .destructive) {
                store.clearRateLimitSamples()
                refreshRateSampleCount()
                historyMessage = "额度预测样本已清除，将重新开始积累"
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这不会影响账号额度，只会重置本机消耗速度预测。")
        }
        .confirmationDialog(
            "确定删除 Artificial Analysis API Key？",
            isPresented: $isConfirmingArtificialKeyRemoval,
            titleVisibility: .visible
        ) {
            Button("从 Keychain 删除", role: .destructive) {
                modelRankings.removeAPIKey()
                artificialAnalysisAPIKey = ""
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("排行榜缓存会保留，但在重新填写 Key 前无法刷新。")
        }
    }

    private var resetPredictionSettingsSection: some View {
        Section("额外额度重置预测") {
            Toggle(
                "启用官方信号监控",
                isOn: Binding(
                    get: { resetPrediction.isEnabled },
                    set: { resetPrediction.setEnabled($0) }
                )
            )

            Toggle(
                "启用第三方 X RSS",
                isOn: Binding(
                    get: { resetPrediction.isThirdPartyXRSSEnabled },
                    set: { resetPrediction.setThirdPartyXRSSEnabled($0) }
                )
            )

            TextField("RSS 代理模板", text: $thirdPartyXRSSTemplate)
                .textFieldStyle(.roundedBorder)
                .disabled(!resetPrediction.isThirdPartyXRSSEnabled)
                .onSubmit { saveThirdPartyXRSSTemplate() }

            HStack {
                Button("保存代理模板") { saveThirdPartyXRSSTemplate() }
                    .disabled(!canSaveThirdPartyXRSSTemplate)

                Menu("使用预设") {
                    Button("Nitter") { useRSSPreset(CodexResetPredictionStore.defaultNitterTemplate) }
                    Button("RSSHub") { useRSSPreset(CodexResetPredictionStore.defaultRSSHubTemplate) }
                }

                Button("刷新预测") {
                    Task { await resetPrediction.refresh(force: true) }
                }
                .disabled(!resetPrediction.isEnabled || resetPrediction.isLoading)
            }

            LabeledContent("运行模式", value: predictionRunMode)
            LabeledContent(
                "当前结果",
                value: "\(resetPrediction.snapshot.predictionIndex)/100 · \(resetPrediction.snapshot.level.displayName)"
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("监控来源")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(predictionSources)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            predictionSyncStatus

            Text("代理模板必须包含 {username}，例如 https://nitter.net/{username}/rss。第三方实例可能依赖服务端 X 账号或 Cookie，可能延迟、缺失、篡改或随时失效；RSS 信号会明确标记，且不能单独触发“官方确认”。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("每 30 分钟读取一次。这里显示的是透明规则计算的“重置预测指数”，不是概率，正常 5 小时与每周额度恢复不参与评分。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setInformationBarEnabled(_ enabled: Bool) {
        if enabled && store.settings.weatherLocation == nil {
            // 先让用户选地区；取消选择时保持开关关闭，避免出现“已开启但没有天气位置”的空状态。
            isShowingWeatherLocationPicker = true
            return
        }
        store.settings.resolvedInformationBarEnabled = enabled
        store.saveSettings()
    }

    @ViewBuilder
    private var predictionSyncStatus: some View {
        if resetPrediction.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在同步并分析官方与第三方 RSS 信号…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let error = resetPrediction.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(PulseTheme.red)
        } else if let message = resetPrediction.statusMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !resetPrediction.snapshot.sourceWarnings.isEmpty {
            Label(
                resetPrediction.snapshot.sourceWarnings.joined(separator: " · "),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(PulseTheme.orange)
            .lineLimit(3)
        }
    }

    private var predictionRunMode: String {
        resetPrediction.isThirdPartyXRSSEnabled ? "免费官方源 + 第三方 X RSS" : "仅免费官方源"
    }

    private var predictionSources: String {
        let official = "OpenAI Status · Codex 更新日志 · OpenAI Help Center · OpenAI News · OpenAI Codex GitHub"
        guard resetPrediction.isThirdPartyXRSSEnabled else { return official }
        return "\(official) · @OpenAI · @OpenAIDevs · @sama · @thsottiaux"
    }

    private var canSaveThirdPartyXRSSTemplate: Bool {
        resetPrediction.isThirdPartyXRSSEnabled
            && !thirdPartyXRSSTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var webhookURLBinding: Binding<String> {
        Binding(
            get: { store.settings.webhookURL ?? "" },
            set: { store.settings.webhookURL = $0 }
        )
    }

    private func saveArtificialAnalysisAPIKey() {
        let key = artificialAnalysisAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task {
            if await modelRankings.saveAPIKey(key) {
                artificialAnalysisAPIKey = ""
            }
        }
    }

    private func saveThirdPartyXRSSTemplate() {
        if resetPrediction.saveThirdPartyXRSSTemplate(thirdPartyXRSSTemplate) {
            thirdPartyXRSSTemplate = resetPrediction.thirdPartyXRSSTemplate
        }
    }

    private func useRSSPreset(_ template: String) {
        thirdPartyXRSSTemplate = template
        saveThirdPartyXRSSTemplate()
    }

    private func thresholdBinding(_ threshold: Double) -> Binding<Bool> {
        Binding(
            get: { store.settings.alertThresholds.contains(threshold) },
            set: { enabled in
                if enabled {
                    if !store.settings.alertThresholds.contains(threshold) {
                        store.settings.alertThresholds.append(threshold)
                    }
                } else {
                    store.settings.alertThresholds.removeAll { $0 == threshold }
                }
                store.settings.alertThresholds.sort()
                store.saveSettings()
            }
        )
    }

    @MainActor
    private func refreshNotificationPermission() async {
        notificationPermission = await NotificationService.shared.authorizationStatus()
    }

    @MainActor
    private func requestNotificationPermission() async {
        _ = await NotificationService.shared.requestAuthorization()
        await refreshNotificationPermission()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        #if os(macOS)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            store.settings.launchAtLogin = enabled
            store.saveSettings()
            syncLaunchAtLoginStatus()
        } catch {
            launchMessage = "设置失败：\(error.localizedDescription)"
            syncLaunchAtLoginStatus()
        }
        #else
        store.settings.launchAtLogin = enabled
        store.saveSettings()
        #endif
    }

    private func syncLaunchAtLoginStatus() {
        #if os(macOS)
        switch SMAppService.mainApp.status {
        case .enabled:
            store.settings.launchAtLogin = true
            launchMessage = nil
        case .requiresApproval:
            store.settings.launchAtLogin = true
            launchMessage = "需要在“系统设置 → 通用 → 登录项”中允许"
        case .notRegistered, .notFound:
            store.settings.launchAtLogin = false
        @unknown default:
            store.settings.launchAtLogin = false
        }
        store.saveSettings()
        #endif
    }

    private func openNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func refreshHistoryCount() {
        historyCount = store.taskHistoryCount()
    }

    private func refreshRateSampleCount() {
        rateSampleCount = store.rateLimitSampleCount()
    }

    private func exportHistory() {
        #if os(macOS)
        guard historyCount > 0 else {
            historyMessage = "暂无可导出的任务历史"
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.title = "导出 Codex-Pulse 任务历史"
        panel.nameFieldStringValue = "codex-pulse-history-\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportTaskHistory(to: url)
            historyMessage = "已导出到 \(url.lastPathComponent)"
        } catch {
            historyMessage = "导出失败：\(error.localizedDescription)"
        }
        #endif
    }

    private func exportUsageReport() {
        #if os(macOS)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.title = "导出 Codex-Pulse 近 7 日周报"
        panel.nameFieldStringValue = "codex-pulse-report-\(formatter.string(from: Date())).md"
        let markdownType = UTType(filenameExtension: "md") ?? UTType.plainText
        panel.allowedContentTypes = [markdownType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportUsageReport(to: url)
            historyMessage = "周报已导出到 \(url.lastPathComponent)"
        } catch {
            historyMessage = "周报导出失败：\(error.localizedDescription)"
        }
        #endif
    }
}
