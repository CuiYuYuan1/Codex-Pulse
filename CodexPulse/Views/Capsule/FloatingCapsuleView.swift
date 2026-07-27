import SwiftUI
import Charts
import WebKit

/// 悬浮胶囊 — 玻璃拟态,置顶悬浮。
/// 收起态:呼吸状态灯 · 环形剩余额度 · 今日 Token
/// 点击展开:账号 / 额度窗口 / 任务 / Token 明细卡片
/// 状态灯:绿=空闲 · 橙=思考/运行 · 红=等待授权 · 灰=未连接
struct FloatingCapsuleView: View {
    @Environment(PulseStore.self) private var store
    @Environment(AppUpdateService.self) private var appUpdates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseVisualTheme) private var visualTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    @State private var isShowingUpdateDetails = false
    @State private var isConversationExpanded = false
    @State private var isMiniConversationExpanded = false
    @State private var isMini = false
    @State private var areResetCardsExpanded = false
    @State private var tokenChartRevealed = false
    @State private var hoveredTokenBucketID: String?
    @State private var isHovering = false
    @State private var magneticOffset: CGSize = .zero
    @State private var hoverGlowPoint = CGPoint(x: 0.16, y: 0.5)
    @State private var hoverZoneSize = CGSize(width: 300, height: 64)
    @State private var activityPreviewStartedAt: Date?
    @State private var weatherViewModel = WeatherViewModel()
    @State private var catRoamingActivity: CatRoamingActivity = .resting
    @State private var catFacesLeft = false
    // Cat/fox monitors are intentionally transient while idle. Starting this
    // at `true` could leave the bubble permanently visible when the view first
    // appeared in compact mode without triggering an `isMini` change.
    @State private var isCatMonitorVisible = false
    @State private var catMonitorHideTask: Task<Void, Never>?
    @State private var catTransientAnimation: PetAnimationState?
    @State private var catTransientAnimationTask: Task<Void, Never>?
    @AppStorage("pulse.orb.page") private var orbPageRawValue = OrbPetPage.quota.rawValue

    /// 面板本身透明，但 SwiftUI 光效仍会被 NSPanel 边界裁切。
    /// 这里需要同时容纳磁吸位移、悬停缩放和模糊描边。
    private let hoverHorizontalInset: CGFloat = 24
    private let hoverVerticalInset: CGFloat = 16
    /// 天气开启态保留完整画面；关闭态以内容宽度为主，仅保留最小操作空间。
    private let informationCapsuleWidth: CGFloat = 275
    private let compactCapsuleMinimumWidth: CGFloat = 235
    private let updateIndicatorWidth: CGFloat = 28

    private var hasAvailableUpdate: Bool {
        appUpdates.availableRelease != nil
    }

    private var resolvedInformationCapsuleWidth: CGFloat {
        informationCapsuleWidth + (hasAvailableUpdate ? updateIndicatorWidth : 0)
    }

    private var resolvedCompactCapsuleMinimumWidth: CGFloat {
        compactCapsuleMinimumWidth + (hasAvailableUpdate ? updateIndicatorWidth : 0)
    }

    // MARK: - 状态映射

    enum CapsuleMode {
        case idle       // 绿
        case working    // 橙
        case attention  // 红
        case offline    // 灰

        var color: Color {
            switch self {
            case .idle: return PulseTheme.green
            case .working: return PulseTheme.orange
            case .attention: return PulseTheme.red
            case .offline: return PulseTheme.gray
            }
        }

        var label: String {
            switch self {
            case .idle: return "空闲"
            case .working: return "思考中"
            case .attention: return "等待授权"
            case .offline: return "未连接"
            }
        }

        /// 呼吸周期；nil 表示恒亮不动
        var breathDuration: Double? {
            switch self {
            case .working: return 1.8
            case .attention: return 1.05
            case .idle, .offline: return nil
            }
        }
    }

    private var mode: CapsuleMode {
        let snapshot = store.snapshot
        guard snapshot.connectionState == .connected || snapshot.connectionState == .degraded else {
            return .offline
        }
        let state = snapshot.currentTask.state
        if state.needsAttention { return .attention }
        if state.isActive { return .working }
        return .idle
    }

    private var remainingPercent: Double? {
        store.snapshot.rateLimits.primaryBucket?.remainingPercent
    }

    private var usesAPIKeyUsageFallback: Bool {
        store.snapshot.account.authMode == .apiKey
            && store.snapshot.rateLimits.primaryBucket == nil
    }

    private var activeMiniCapsuleStyle: MiniCapsuleStyle {
        store.snapshot.account.authMode == .apiKey
            ? store.settings.resolvedAPIMiniCapsuleStyle
            : store.settings.resolvedMiniCapsuleStyle
    }

    private var todayTokens: Int64? {
        store.snapshot.usage.todayTokens
    }

    private var petGrowthScale: CGFloat {
        guard !isOrbPet else { return 1 }
        return CGFloat(PetGrowth.scale(forTodayTokens: todayTokens))
    }

    private var informationBarEnabled: Bool {
        store.settings.resolvedInformationBarEnabled
            && store.settings.weatherLocation != nil
    }

    private var weatherLocation: WeatherLocation? {
        store.settings.weatherLocation
    }

    private var showsWeatherMetadata: Bool {
        informationBarEnabled && !isExpanded
    }

    private var isTaskStreamActive: Bool {
        informationBarEnabled && !isExpanded && (mode == .working || mode == .attention)
    }

    private var isMiniTaskConversationAvailable: Bool {
        isMini && (mode == .working || mode == .attention)
    }

    private var isCatPet: Bool {
        switch store.settings.resolvedPetCharacter {
        case .cat, .fox:
            return true
        case .dino, .bunny, .ghost, .robot, .orb, .orb2, .orb3, .orb4, .blackHole:
            return false
        }
    }

    private var isOrbPet: Bool {
        store.settings.resolvedPetCharacter.isOrb
    }

    private var resolvedOrbPage: OrbPetPage {
        let stored = OrbPetPage(rawValue: orbPageRawValue) ?? .quota
        if store.snapshot.account.authMode == .apiKey, stored == .quota {
            return .tokens
        }
        return stored
    }

    private var catRoamingEnabled: Bool {
        isMini
            && !isOrbPet
            && (mode == .idle || mode == .offline)
            && !isMiniConversationExpanded
            && !reduceMotion
    }

    private var petLocomotionCycleDuration: TimeInterval {
        switch store.settings.resolvedPetCharacter {
        case .dino: return 1.06
        case .cat: return 1.0 / 1.12
        case .bunny: return 1.38
        case .ghost: return 1.24
        case .robot: return 0.94
        case .fox: return 1.12
        case .orb, .orb2, .orb3, .orb4: return 1.0
        case .blackHole: return 1.28
        }
    }

    private var petRoamingArcHeight: CGFloat {
        switch store.settings.resolvedPetCharacter {
        case .dino: return 5
        case .cat: return 7
        case .bunny: return 10
        case .ghost: return 18
        case .robot: return 4
        case .fox: return 8
        case .orb, .orb2, .orb3, .orb4: return 0
        case .blackHole: return 5
        }
    }

    private var petMinimumHorizontalTravel: CGFloat {
        switch store.settings.resolvedPetCharacter {
        case .ghost, .blackHole: return 90
        case .dino, .cat, .bunny, .robot, .fox: return 140
        case .orb, .orb2, .orb3, .orb4: return 0
        }
    }

    private var taskConversation: [TaskConversationMessage] {
        store.snapshot.currentTask.conversation ?? []
    }

    private var taskStreamSummary: String {
        let candidate = taskConversation.last(where: { $0.role == .assistant })?.text
            ?? store.snapshot.currentTask.currentStep
            ?? store.snapshot.currentTask.lastStatusMessage
            ?? (mode == .attention ? "等待你确认后继续" : "Codex 正在组织回复…")
        let singleLine = candidate
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return singleLine.isEmpty ? "Codex 正在组织回复…" : singleLine
    }

    private var isRealtimeTokenMode: Bool {
        mode == .working || mode == .attention
    }

    private var displayedTokenText: String {
        isRealtimeTokenMode
            ? PulseFormatters.liveTokens(todayTokens)
            : PulseFormatters.tokens(todayTokens)
    }

    private var needsWeatherData: Bool {
        guard weatherLocation != nil else { return false }
        return informationBarEnabled
            || (isMini && activeMiniCapsuleStyle == .weather)
            || (
                isMini
                && isOrbPet
                && (
                    resolvedOrbPage == .weather
                    || resolvedOrbPage == .temperature
                )
            )
    }

    private var weatherTaskID: String {
        guard needsWeatherData, let location = weatherLocation else { return "weather-off" }
        let displayPage = isOrbPet
            ? "orb-\(resolvedOrbPage.rawValue)"
            : activeMiniCapsuleStyle.rawValue
        return "weather-\(location.id)-\(displayPage)-\(isMini)"
    }

    private var miniCapsule: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let presentation = isOrbPet
                ? orbPresentation(at: context.date)
                : miniPresentation(at: context.date)
            let activeQuota = activePetQuotaPresentation(at: context.date)
            PetCapsuleView(
                character: store.settings.resolvedPetCharacter,
                animationState: petAnimationState(at: context.date),
                idleStyle: activeMiniCapsuleStyle,
                orbPage: resolvedOrbPage,
                idleValue: presentation.value,
                idleProgress: presentation.progress,
                idleColor: presentation.color,
                idleHelp: presentation.help,
                showsIdleContent: mode == .idle || mode == .offline,
                activeQuotaValue: activeQuota?.value,
                activeQuotaColor: activeQuota?.color ?? PulseTheme.green,
                reduceMotion: reduceMotion,
                catRoamingActivity: catRoamingActivity,
                catFacesLeft: catFacesLeft,
                showsTransientMonitor: isCatMonitorVisible,
                growthScale: petGrowthScale
            )
        }
        .padding(12)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
    }

    /// Account sessions briefly rotate the live remaining quota through the
    /// pet monitor while a task is active. API Key sessions have no ChatGPT
    /// quota, so they intentionally retain only the task status page.
    private func activePetQuotaPresentation(at date: Date) -> MiniCapsulePresentation? {
        guard mode == .working || mode == .attention,
              store.snapshot.account.authMode != .apiKey,
              let remainingPercent else {
            return nil
        }
        let startedAt = store.snapshot.currentTask.startedAt ?? date
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        guard elapsed.truncatingRemainder(dividingBy: 8) >= 5 else { return nil }
        let percent = min(100, max(0, remainingPercent))
        return MiniCapsulePresentation(
            value: String(format: "额度%.0f%%", percent),
            progress: percent / 100,
            color: PulseTheme.usage(percent),
            help: String(format: "当前账号剩余额度 %.0f%%", percent)
        )
    }

    private func petAnimationState(at date: Date) -> PetAnimationState {
        if isCatPet, let catTransientAnimation {
            return catTransientAnimation
        }
        let runState = store.snapshot.currentTask.state
        if runState == .failed || runState == .networkError {
            return .error
        }
        switch mode {
        case .working:
            // Focused paw work is punctuated by a longer, readable thinking hold.
            let phase = Int(date.timeIntervalSince1970) % 13
            return (8...11).contains(phase) ? .thinking : .running
        case .attention:
            return runState == .awaitingAuthorization
                ? .waitingAuthorization
                : .waiting
        case .idle, .offline: return .idle
        }
    }

    private func miniPresentation(at date: Date) -> MiniCapsulePresentation {
        switch activeMiniCapsuleStyle {
        case .quota:
            if usesAPIKeyUsageFallback {
                return MiniCapsulePresentation(
                    value: "API",
                    progress: 1,
                    color: visualTheme.accent,
                    help: "API Key 按量计费"
                )
            }
            let percent = min(100, max(0, remainingPercent ?? 0))
            return MiniCapsulePresentation(
                value: remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                progress: percent / 100,
                color: remainingPercent.map(PulseTheme.usage) ?? PulseTheme.gray,
                help: remainingPercent.map { "剩余额度 \(String(format: "%.0f%%", $0))" } ?? "额度暂不可用"
            )

        case .tokens:
            let value = isRealtimeTokenMode
                ? PulseFormatters.liveTokens(todayTokens)
                : PulseFormatters.tokens(todayTokens)
            return MiniCapsulePresentation(
                value: value,
                progress: todayTokens == nil ? 0 : 0.72,
                color: PulseTheme.blue,
                help: "今日 Token \(value)"
            )

        case .status:
            let value: String
            switch mode {
            case .attention: value = "授"
            case .working: value = "思"
            case .idle: value = "•"
            case .offline: value = "—"
            }
            return MiniCapsulePresentation(
                value: value,
                progress: mode == .offline ? 0 : (mode == .idle ? 0.28 : 1),
                color: mode.color,
                help: "任务状态：\(mode.label)"
            )

        case .weather:
            let value = weatherViewModel.snapshot.map { String(format: "%.0f°", $0.temperature) } ?? "—"
            let description = weatherViewModel.snapshot.map {
                "\($0.condition.displayName) \(String(format: "%.0f°C", $0.temperature))"
            } ?? "天气暂不可用"
            return MiniCapsulePresentation(
                value: value,
                progress: weatherViewModel.snapshot == nil ? 0 : 0.64,
                color: weatherViewModel.snapshot?.isDay == false ? Color(hex: 0x9BBEFF) : Color(hex: 0x64C7FF),
                help: description
            )

        case .time:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            let timezone = weatherLocation.flatMap { TimeZone(identifier: $0.timezone) } ?? .current
            formatter.timeZone = timezone
            formatter.dateFormat = "HH:mm"
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timezone
            let components = calendar.dateComponents([.minute], from: date)
            return MiniCapsulePresentation(
                value: formatter.string(from: date),
                progress: Double(components.minute ?? 0) / 60,
                color: visualTheme.accent,
                help: "当地时间 \(formatter.string(from: date))"
            )
        }
    }

    private func orbPresentation(at date: Date) -> MiniCapsulePresentation {
        switch resolvedOrbPage {
        case .quota:
            let percent = min(100, max(0, remainingPercent ?? 0))
            return MiniCapsulePresentation(
                value: remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                progress: percent / 100,
                color: remainingPercent.map(orbQuotaColor) ?? PulseTheme.gray,
                help: remainingPercent.map { "剩余额度 \(String(format: "%.0f%%", $0))" } ?? "额度暂不可用"
            )

        case .tokens:
            let value = isRealtimeTokenMode
                ? PulseFormatters.liveTokens(todayTokens)
                : PulseFormatters.tokens(todayTokens)
            return MiniCapsulePresentation(
                value: value,
                progress: todayTokens == nil ? 0 : 0.72,
                color: PulseTheme.blue,
                help: "今日 Token \(value)"
            )

        case .weather:
            let value = weatherViewModel.snapshot?.condition.compactDisplayName ?? "—"
            let description = weatherViewModel.snapshot.map {
                "\($0.condition.displayName) \(String(format: "%.0f°C", $0.temperature))"
            } ?? "天气暂不可用"
            return MiniCapsulePresentation(
                value: value,
                progress: weatherViewModel.snapshot == nil ? 0 : 0.64,
                color: weatherViewModel.snapshot?.isDay == false
                    ? Color(hex: 0x9BBEFF)
                    : Color(hex: 0x64C7FF),
                help: description
            )

        case .temperature:
            let value = weatherViewModel.snapshot.map {
                String(format: "%.0f°", $0.temperature)
            } ?? "—"
            return MiniCapsulePresentation(
                value: value,
                progress: weatherViewModel.snapshot == nil ? 0 : 0.64,
                color: weatherViewModel.snapshot?.isDay == false
                    ? Color(hex: 0x9BBEFF)
                    : PulseTheme.orange,
                help: weatherViewModel.snapshot.map {
                    "当前温度 \(String(format: "%.0f°C", $0.temperature))"
                } ?? "温度暂不可用"
            )

        case .time:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            let timezone = weatherLocation.flatMap {
                TimeZone(identifier: $0.timezone)
            } ?? .current
            formatter.timeZone = timezone
            formatter.dateFormat = "HH:mm"
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timezone
            let minute = calendar.component(.minute, from: date)
            let value = formatter.string(from: date)
            return MiniCapsulePresentation(
                value: value,
                progress: Double(minute) / 60,
                color: visualTheme.accent,
                help: "当地时间 \(value)"
            )
        }
    }

    private func orbQuotaColor(_ remaining: Double) -> Color {
        if remaining >= 80 { return PulseTheme.green }
        if remaining >= 50 { return PulseTheme.blue }
        if remaining >= 20 { return PulseTheme.orange }
        return PulseTheme.red
    }

    // MARK: - Body

    @ViewBuilder
    private var capsuleScene: some View {
        if isMini {
            VStack(alignment: .trailing, spacing: isMiniConversationExpanded ? -14 : 8) {
                miniCapsule
                    .zIndex(2)
                    .transition(.scale(scale: 0.72, anchor: .topTrailing).combined(with: .opacity))
                if isMiniConversationExpanded && isMiniTaskConversationAvailable {
                    miniTaskConversationCard
                        .zIndex(1)
                        .frame(width: 323, alignment: .trailing)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(
                                        scale: 0.16,
                                        anchor: UnitPoint(x: 0.82, y: 0)
                                    )),
                                removal: .opacity
                                    .combined(with: .scale(
                                        scale: 0.22,
                                        anchor: UnitPoint(x: 0.82, y: 0)
                                    ))
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(
                alignment: .center,
                spacing: isExpanded ? 2 : (showsWeatherMetadata ? 4 : 8)
            ) {
                capsuleBar
                if showsWeatherMetadata {
                    informationMetadata
                        .frame(
                            width: isConversationExpanded && isTaskStreamActive
                                ? 323
                                : informationCapsuleWidth,
                            alignment: .center
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if isExpanded {
                    Group {
                        if isShowingUpdateDetails, appUpdates.availableRelease != nil {
                            updateDetailCard
                        } else {
                            detailCard
                        }
                    }
                    .frame(width: informationBarEnabled ? 422 : nil, alignment: .center)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .move(edge: .top))
                                .combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                    )
                }
            }
        }
    }

    private var animatedCapsuleScene: some View {
        capsuleScene
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isMini)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: isConversationExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isMiniConversationExpanded)
            .animation(.easeInOut(duration: 0.35), value: mode.label)
    }

    private var lifecycleObservedCapsuleScene: some View {
        animatedCapsuleScene
        .onReceive(NotificationCenter.default.publisher(for: .pulseCapsuleToggleDetails)) { _ in
            if isMini {
                handleMiniSingleClick()
            } else {
                toggleDetails()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseCapsuleToggleMini)) { _ in
            toggleMiniMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseCatRoamingActivityChanged)) { note in
            guard let update = note.object as? CatRoamingVisualUpdate else { return }
            // The renderer owns its state transition timing. A second implicit
            // SwiftUI animation here occasionally composited old/new canvases
            // and produced a one-frame flash.
            catRoamingActivity = update.activity
            catFacesLeft = update.facesLeft
        }
        .onAppear {
            synchronizeCatRoaming()
            if isMini, isCatPet {
                revealCatMonitor(for: 3.4)
            }
        }
        .onDisappear {
            catMonitorHideTask?.cancel()
            catMonitorHideTask = nil
            catTransientAnimationTask?.cancel()
            FloatingCapsuleController.shared.setCatRoamingEnabled(false)
        }
        .onChange(of: catRoamingEnabled) { _, _ in
            synchronizeCatRoaming()
        }
        .onChange(of: store.settings.resolvedPetCharacter) { _, character in
            synchronizeCatRoaming()
            FloatingCapsuleController.shared.updateCompactHitRegion(for: character)
        }
        .onChange(of: isMini) { _, mini in
            guard mini, isCatPet else { return }
            revealCatMonitor(for: 3.4)
        }
        .onChange(of: mode.label) { oldMode, newMode in
            guard isMini, isCatPet, oldMode != newMode, mode == .idle else { return }
            revealCatMonitor(for: 3.2)
        }
        .modifier(
            CatTaskStateObserver(
                state: store.snapshot.currentTask.state,
                action: handleCatTaskStateChange
            )
        )
        .onChange(of: remainingPercent) { oldValue, newValue in
            guard isMini,
                  isCatPet,
                  mode == .idle,
                  activeMiniCapsuleStyle == .quota,
                  let oldValue,
                  let newValue,
                  abs(newValue - oldValue) >= 1 else { return }
            revealCatMonitor(for: 2.8)
        }
        .onChange(of: todayTokens) { oldValue, newValue in
            guard isMini,
                  isCatPet,
                  mode == .idle,
                  activeMiniCapsuleStyle == .tokens,
                  let oldValue,
                  let newValue,
                  abs(newValue - oldValue) >= 1_000 else { return }
            revealCatMonitor(for: 2.8)
        }
    }

    private var activityObservedCapsuleScene: some View {
        lifecycleObservedCapsuleScene
        .onChange(of: store.settings.resolvedActivityBandStyle) { _, _ in
            previewActivityBand()
        }
        .onChange(of: store.settings.resolvedActivityBandEnabled) { _, enabled in
            if enabled { previewActivityBand() }
            else { activityPreviewStartedAt = nil }
        }
    }

    var body: some View {
        activityObservedCapsuleScene
        .onChange(of: appUpdates.availableRelease) { _, release in
            guard release == nil, isShowingUpdateDetails else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isShowingUpdateDetails = false
                isExpanded = false
            }
        }
        .onChange(of: isTaskStreamActive) { _, active in
            guard !active, isConversationExpanded else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                isConversationExpanded = false
            }
        }
        .onChange(of: isMiniTaskConversationAvailable) { _, active in
            guard !active, isMiniConversationExpanded else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                isMiniConversationExpanded = false
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, isConversationExpanded else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                isConversationExpanded = false
            }
        }
        .task(id: weatherTaskID) {
            guard needsWeatherData, let location = weatherLocation else {
                weatherViewModel.clear()
                return
            }
            await weatherViewModel.monitor(location: location)
        }
    }

    // MARK: - 胶囊主体

    private var capsuleBar: some View {
        ZStack {
            capsuleContent
                .offset(magneticOffset)
        }
            // 仅给磁吸位移和悬停放大预留透明绘制空间，避免胶囊两端被 NSPanel 裁切。
            // 该区域没有材质、填充或阴影，不会形成外围背景层。
            .padding(.horizontal, hoverHorizontalInset)
            .padding(.top, hoverVerticalInset)
            // 展开后磁吸与悬停放大均已停用，不再保留 16pt 的透明安全区。
            .padding(.bottom, isExpanded ? 0 : (showsWeatherMetadata ? 4 : hoverVerticalInset))
            .contentShape(Rectangle())
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { hoverZoneSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            hoverZoneSize = newSize
                        }
                }
            }
            .onContinuousHover { phase in
                updateMagneticHover(phase)
            }
    }

    private var capsuleContent: some View {
        HStack(spacing: informationBarEnabled ? 0 : 10) {
            capsuleLeadingVisual
            if informationBarEnabled {
                Color.clear
                    .frame(width: 14, height: 1)
            }
            quotaRing
            if informationBarEnabled {
                Spacer(minLength: 8)
            }
            divider
            if informationBarEnabled {
                Spacer(minLength: 8)
            }
            tokenReadout
            if informationBarEnabled {
                Spacer(minLength: 8)
            }
            updateIndicator
            if informationBarEnabled && hasAvailableUpdate {
                Color.clear
                    .frame(width: 8, height: 1)
            }
            chevron
        }
        .padding(.horizontal, informationBarEnabled ? 14 : 10)
        .frame(width: informationBarEnabled ? resolvedInformationCapsuleWidth : nil)
        .frame(minWidth: informationBarEnabled ? nil : resolvedCompactCapsuleMinimumWidth)
        .fixedSize(horizontal: !informationBarEnabled, vertical: false)
        .frame(height: 64)
        .background(capsuleBackground)
        .overlay {
            CapsuleHoverGlow(
                center: UnitPoint(x: hoverGlowPoint.x, y: hoverGlowPoint.y),
                isVisible: isHovering && !isExpanded
            )
            .allowsHitTesting(false)
        }
        .overlay {
            CapsuleActivityMarquee(
                style: store.settings.resolvedActivityBandStyle,
                isActive: store.settings.resolvedActivityBandEnabled
                    && (mode == .working || mode == .attention || activityPreviewStartedAt != nil),
                isAttention: mode == .attention,
                reduceMotion: reduceMotion,
                phaseOrigin: activityPreviewStartedAt
            )
            .allowsHitTesting(false)
        }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isHovering && !isExpanded ? 1.025 : 1.0)
        .help(
            isMini
                ? "\(store.settings.resolvedPetCharacter.displayName) · 右键切换宠物 · 双击恢复完整胶囊"
                : "Codex \(mode.label) · 点击\(isExpanded ? "收起" : "展开")详情 · 右键更多操作"
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: hasAvailableUpdate)
    }

    private func toggleMiniMode() {
        let nextValue = !isMini
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isExpanded = false
            isShowingUpdateDetails = false
            isMiniConversationExpanded = false
            isMini = nextValue
        }
        areResetCardsExpanded = false
        tokenChartRevealed = false
        hoveredTokenBucketID = nil
        resetMagneticOffset()
        PulseLog.write("capsule mini mode \(isMini ? "enabled" : "disabled")")
    }

    private func handleMiniSingleClick() {
        if isOrbPet {
            cycleOrbPage()
            return
        }

        if isMiniTaskConversationAvailable {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                isMiniConversationExpanded.toggle()
            }
            PulseLog.write("mini pet conversation \(isMiniConversationExpanded ? "expanded" : "collapsed")")
            return
        }

        if isCatPet && (mode == .idle || mode == .offline) && !isCatMonitorVisible {
            revealCatMonitor(for: 3.4)
            PulseLog.write("mini cat display revealed")
            return
        }

        let apiMode = store.snapshot.account.authMode == .apiKey
        let styles: [MiniCapsuleStyle] = apiMode
            ? [.tokens, .weather, .time]
            : [.quota, .tokens, .weather, .time]
        let current = activeMiniCapsuleStyle
        let next = styles[(styles.firstIndex(of: current).map { $0 + 1 } ?? 0) % styles.count]
        if apiMode {
            store.settings.resolvedAPIMiniCapsuleStyle = next
        } else {
            store.settings.resolvedMiniCapsuleStyle = next
        }
        store.saveSettings()
        if isCatPet {
            revealCatMonitor(for: 3.4)
        }
        PulseLog.write("mini pet display cycled to \(next.rawValue)")
    }

    private func cycleOrbPage() {
        let pages: [OrbPetPage] = store.snapshot.account.authMode == .apiKey
            ? [.tokens, .weather, .temperature, .time]
            : OrbPetPage.allCases
        let current = resolvedOrbPage
        let index = pages.firstIndex(of: current) ?? 0
        let next = pages[(index + 1) % pages.count]
        orbPageRawValue = next.rawValue
        PulseLog.write("orb pet display cycled to \(next.rawValue)")
    }

    private func synchronizeCatRoaming() {
        FloatingCapsuleController.shared.setCatRoamingEnabled(
            catRoamingEnabled,
            cycleDuration: petLocomotionCycleDuration,
            arcHeight: petRoamingArcHeight,
            minimumHorizontalDistance: petMinimumHorizontalTravel
        )
        if !catRoamingEnabled {
            catRoamingActivity = .resting
            catFacesLeft = false
        }
        if !isCatPet {
            catMonitorHideTask?.cancel()
            catMonitorHideTask = nil
            isCatMonitorVisible = true
        } else if isMini, (mode == .idle || mode == .offline) {
            // Rebuilding the compact scene must never resurrect a stale idle
            // monitor. Only an explicit reveal action owns the visible timer.
            if catMonitorHideTask == nil {
                isCatMonitorVisible = false
            }
        }
    }

    private func revealCatMonitor(for seconds: Double) {
        guard isCatPet else { return }
        catMonitorHideTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isCatMonitorVisible = true
        }
        let nanoseconds = UInt64(max(0.5, seconds) * 1_000_000_000)
        catMonitorHideTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            catMonitorHideTask = nil
            guard isMini, isCatPet, mode == .idle || mode == .offline else { return }
            withAnimation(.easeOut(duration: 0.26)) {
                isCatMonitorVisible = false
            }
        }
    }

    private func playCatTransient(_ state: PetAnimationState, for seconds: Double) {
        catTransientAnimationTask?.cancel()
        catTransientAnimation = state
        let delay = UInt64(max(0.8, seconds) * 1_000_000_000)
        catTransientAnimationTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            catTransientAnimation = nil
        }
    }

    private func handleCatTaskStateChange(
        _ oldState: CodexRunState,
        _ newState: CodexRunState
    ) {
        guard isMini, isCatPet, oldState != newState else { return }
        switch newState {
        case .completed:
            playCatTransient(.success, for: 3.2)
        case .failed, .networkError:
            playCatTransient(.error, for: 4.2)
        default:
            catTransientAnimationTask?.cancel()
            catTransientAnimation = nil
        }
    }

    private func toggleDetails() {
        guard !isMini else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            if isExpanded {
                isExpanded = false
                isShowingUpdateDetails = false
            } else {
                isConversationExpanded = false
                isShowingUpdateDetails = false
                isExpanded = true
            }
        }
        PulseLog.write("capsule details \(isExpanded ? "expanded" : "collapsed")")
        if isExpanded {
            resetMagneticOffset()
        } else {
            areResetCardsExpanded = false
            tokenChartRevealed = false
            hoveredTokenBucketID = nil
        }
    }

    @ViewBuilder
    private var capsuleLeadingVisual: some View {
        if informationBarEnabled {
            weatherLeadingVisual
        } else {
            statusLamp
        }
    }

    private var capsuleBackground: some View {
        ZStack(alignment: .leading) {
            CapsuleGlass(
                shape: Capsule(style: .continuous),
                glowColor: mode == .attention ? PulseTheme.red : nil,
                glowPulse: false,
                castsShadow: false
            )
            if informationBarEnabled {
                WeatherAtmosphereView(
                    condition: weatherViewModel.snapshot?.condition ?? .partlyCloudy,
                    isDay: weatherViewModel.snapshot?.isDay ?? true,
                    reduceMotion: reduceMotion
                )
                .frame(width: 102, height: 64)
                .mask {
                    LinearGradient(
                        colors: [.black, .black.opacity(0.96), .black.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
        .clipShape(Capsule(style: .continuous))
    }

    /// 天气场景占胶囊左侧约三成，右侧以透明渐隐融入玻璃，不额外制造一张卡片。
    private var weatherLeadingVisual: some View {
        Color.clear
        .frame(width: informationBarEnabled ? 62 : 30, height: 64)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var weatherMetadata: some View {
        if weatherLocation != nil {
            weatherMetadataPill
                .frame(width: informationCapsuleWidth, alignment: .center)
                .padding(.top, 0)
        }
    }

    @ViewBuilder
    private var weatherMetadataPill: some View {
        if let location = weatherLocation {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: weatherViewModel.snapshot?.condition.symbolName ?? "cloud.sun")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(visualTheme.accent)
                        Text(weatherTemperatureText)
                            .monospacedDigit()
                        if let freshness = weatherFreshnessStatus(at: context.date) {
                            Image(systemName: freshness.icon)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(PulseTheme.orange)
                                .help(freshness.message)
                        }
                    }
                    Text("•")
                        .foregroundStyle(Color.primary.opacity(0.32))
                    Text(location.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 64)
                        .layoutPriority(0)
                    Text("•")
                        .foregroundStyle(Color.primary.opacity(0.32))
                    Text(localDateText(context.date, timezoneIdentifier: location.timezone))
                        .monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.92 : 0.84))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background {
                    PulseThemedSurface(
                        shape: Capsule(style: .continuous),
                        role: .capsule,
                        castsShadow: true
                    )
                }
                .help(weatherFreshnessStatus(at: context.date)?.message ?? "天气数据来自 Open-Meteo")
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(location.displayName)，\(weatherTemperatureText)\(weatherFreshnessStatus(at: context.date) == nil ? "" : "，天气可能不是最新数据")，\(localDateText(context.date, timezoneIdentifier: location.timezone))"
                )
            }
        }
    }

    @ViewBuilder
    private var informationMetadata: some View {
        if isTaskStreamActive {
            taskInformationIsland
        } else {
            weatherMetadata
        }
    }

    /// One persistent surface owns both states, so the conversation grows out of
    /// the information pill instead of presenting as a second card below it.
    private var taskInformationIsland: some View {
        let shape = RoundedRectangle(
            cornerRadius: isConversationExpanded ? 22 : 999,
            style: .continuous
        )
        return ZStack {
            if isConversationExpanded {
                taskConversationCard
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            } else {
                taskStreamStrip
                    .transition(.opacity)
            }
        }
        .frame(
            width: isConversationExpanded ? 323 : nil,
            height: isConversationExpanded ? 246 : nil
        )
        .background {
            PulseThemedSurface(
                shape: shape,
                role: isConversationExpanded ? .panel : .capsule,
                castsShadow: true
            )
        }
        .clipShape(shape)
        .contentShape(shape)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: isConversationExpanded)
        .help(isConversationExpanded ? "收起实时对话" : "展开实时对话")
    }

    private var taskStreamStrip: some View {
        weatherMetadataPill
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        isConversationExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        StreamingTaskSummary(
                            text: taskStreamSummary,
                            color: Color.primary.opacity(colorScheme == .dark ? 0.94 : 0.86),
                            activityColor: mode == .attention ? PulseTheme.red : visualTheme.accent
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 30)

                        HStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(mode == .attention ? PulseTheme.red.opacity(0.18) : visualTheme.accent.opacity(0.18))
                                    .frame(width: 16, height: 16)
                                Image(systemName: mode == .attention ? "exclamationmark" : "waveform")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(mode == .attention ? PulseTheme.red : visualTheme.accent)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.secondary.opacity(0.72))
                                .rotationEffect(.degrees(isConversationExpanded ? 180 : 0))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: true, vertical: false)
            .help(isConversationExpanded ? "收起实时对话" : "展开实时对话")
            .accessibilityLabel("Codex 实时回复：\(taskStreamSummary)")
            .accessibilityValue(isConversationExpanded ? "已展开" : "已收起")
    }

    private var taskConversationCard: some View {
        TaskConversationCard(
            width: 323,
            messages: taskConversation,
            isStreaming: mode == .working,
            accent: visualTheme.accent,
            showsSurface: false,
            onClose: {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    isConversationExpanded = false
                }
            }
        )
    }

    private var miniTaskConversationCard: some View {
        TaskConversationCard(
            width: 323,
            messages: taskConversation,
            isStreaming: mode == .working,
            accent: mode == .attention ? PulseTheme.red : visualTheme.accent,
            onClose: {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    isMiniConversationExpanded = false
                }
            }
        )
    }

    private var weatherTemperatureText: String {
        if let snapshot = weatherViewModel.snapshot {
            return String(format: "%.0f°C", snapshot.temperature)
        }
        return weatherViewModel.isLoading ? "天气…" : "天气暂不可用"
    }

    private func weatherFreshnessStatus(at reference: Date) -> (icon: String, message: String)? {
        if let error = weatherViewModel.errorMessage {
            return ("wifi.slash", "天气同步失败，当前显示上次成功结果：\(error)")
        }
        guard let snapshot = weatherViewModel.snapshot else { return nil }
        if weatherViewModel.isLoading {
            return ("arrow.clockwise", "正在同步，当前显示上次成功结果")
        }
        let age = max(0, reference.timeIntervalSince(snapshot.observedAt))
        if age >= 24 * 60 * 60 {
            return ("clock.badge.exclamationmark", "天气数据已超过 24 小时，当前结果可能已过期")
        }
        if age >= 30 * 60 {
            return ("clock", "天气数据来自 \(PulseFormatters.relativeDate(snapshot.observedAt)) 的缓存")
        }
        return nil
    }

    private func localDateText(_ date: Date, timezoneIdentifier: String) -> String {
        let timezone = TimeZone(identifier: timezoneIdentifier) ?? .current
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.timeZone = timezone
        weekdayFormatter.dateFormat = "EEEE"
        let day = weekdayFormatter.string(from: date)
            .replacingOccurrences(of: "星期", with: "周")
            .replacingOccurrences(of: "礼拜", with: "周")
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.timeZone = timezone
        timeFormatter.dateFormat = "HH:mm"
        return "\(day) \(timeFormatter.string(from: date))"
    }

    private func previewActivityBand() {
        guard store.settings.resolvedActivityBandEnabled else {
            activityPreviewStartedAt = nil
            return
        }
        let startedAt = Date()
        activityPreviewStartedAt = startedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.22) {
            guard activityPreviewStartedAt == startedAt else { return }
            activityPreviewStartedAt = nil
        }
    }

    /// 对应 GSAP mapRange + overwrite：每个指针事件只覆盖最新目标，避免累计位移抖动。
    private func updateMagneticHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            isHovering = true
            guard !isExpanded else {
                resetMagneticOffset()
                return
            }
            // 透明安全边距不参与 mapRange，否则可见胶囊区域的磁吸幅度会被稀释。
            let horizontalInset = hoverHorizontalInset
            let verticalInset = hoverVerticalInset
            let width = max(1, hoverZoneSize.width - horizontalInset * 2)
            let height = max(1, hoverZoneSize.height - verticalInset * 2)
            let normalizedX = min(1, max(-1, ((location.x - horizontalInset) / width - 0.5) * 2))
            let normalizedY = min(1, max(-1, ((location.y - verticalInset) / height - 0.5) * 2))
            let glowX = min(1, max(0, (location.x - horizontalInset) / width))
            let glowY = min(1, max(0, (location.y - verticalInset) / height))
            let projectedGlowPoint = nearestCapsuleEdgePoint(
                x: glowX,
                y: glowY,
                width: width,
                height: height
            )
            withAnimation(.linear(duration: 0.08)) {
                hoverGlowPoint = projectedGlowPoint
            }
            withAnimation(.easeOut(duration: 0.18)) {
                magneticOffset = CGSize(width: normalizedX * 12, height: normalizedY * 8)
            }
        case .ended:
            isHovering = false
            withAnimation(.easeOut(duration: 0.24)) {
                hoverGlowPoint = CGPoint(x: 0.16, y: 0.5)
            }
            resetMagneticOffset()
        }
    }

    /// 将鼠标位置投影到最近的胶囊边缘外侧，防止下沿高光同时照亮上沿。
    private func nearestCapsuleEdgePoint(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        let distances = [
            x * width,
            (1 - x) * width,
            y * height,
            (1 - y) * height
        ]
        let nearestEdge = distances.enumerated().min { $0.element < $1.element }?.offset ?? 0
        let xOvershoot = 4 / width
        let yOvershoot = 4 / height

        switch nearestEdge {
        case 0: return CGPoint(x: -xOvershoot, y: y)
        case 1: return CGPoint(x: 1 + xOvershoot, y: y)
        case 2: return CGPoint(x: x, y: -yOvershoot)
        default: return CGPoint(x: x, y: 1 + yOvershoot)
        }
    }

    private func resetMagneticOffset() {
        withAnimation(.interpolatingSpring(stiffness: 155, damping: 13)) {
            magneticOffset = .zero
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
    }

    @ViewBuilder
    private var updateIndicator: some View {
        if let release = appUpdates.availableRelease {
            Button {
                FloatingCapsuleController.shared.suppressNextCapsuleClick()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isShowingUpdateDetails = true
                    isExpanded = true
                }
                resetMagneticOffset()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(visualTheme.accent)
                    Circle()
                        .fill(PulseTheme.orange)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 0.5))
                        .offset(x: 1, y: -1)
                }
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("发现新版本 v\(release.version) · 点击查看更新内容")
            .accessibilityLabel("发现新版本 v\(release.version)")
            .accessibilityHint("点击查看更新内容")
            .transition(.scale(scale: 0.76).combined(with: .opacity))
        }
    }

    private var divider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 22)
    }

    // MARK: - 呼吸状态灯(签名元素)

    private var statusLamp: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: mode.breathDuration == nil || reduceMotion
            )
        ) { timeline in
            statusLampContent(pulse: statusPulse(at: timeline.date))
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("状态：\(mode.label)")
    }

    private func statusLampContent(pulse: CGFloat) -> some View {
        let isBreathing = mode.breathDuration != nil
        let strength: CGFloat = mode == .attention ? 1 : 0.78

        return ZStack {
            // 柔和底光：思考中较慢，等待授权更明显。
            Circle()
                .fill(mode.color.opacity(0.18 + Double(pulse * strength) * 0.3))
                .frame(width: 24, height: 24)
                .blur(radius: 5.5)
                .scaleEffect(0.9 + pulse * strength * 0.48)

            // 向外扩散的细环让状态变化更容易被余光识别，但不会闪烁。
            Circle()
                .stroke(mode.color.opacity(isBreathing ? Double((1 - pulse) * strength) * 0.5 : 0), lineWidth: 1.15)
                .frame(width: 17, height: 17)
                .scaleEffect(1 + pulse * strength * 0.58)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [mode.color.opacity(0.95), mode.color],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 7
                    )
                )
                .frame(width: 13, height: 13)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                }
                .shadow(
                    color: mode.color.opacity(0.55 + Double(pulse * strength) * 0.35),
                    radius: 4 + pulse * strength * 7
                )
                .scaleEffect(1 + pulse * strength * 0.09)
        }
    }

    private func statusPulse(at date: Date) -> CGFloat {
        guard let duration = mode.breathDuration else { return 0 }
        guard !reduceMotion else { return 0.38 }
        let elapsed = date.timeIntervalSinceReferenceDate
        let progress = elapsed.truncatingRemainder(dividingBy: duration) / duration
        // 0 → 1 → 0 的连续正弦曲线，没有闪烁或突然跳变。
        return CGFloat((sin(progress * .pi * 2 - .pi / 2) + 1) / 2)
    }

    // MARK: - 环形剩余额度

    private var quotaRing: some View {
        let displayedValue = usesAPIKeyUsageFallback
            ? "API"
            : (remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—")
        let needsWideRing = displayedValue.count >= 4
        let diameter: CGFloat = needsWideRing ? 40 : 36
        let progress = CGFloat(min(100, max(0, remainingPercent ?? 0)) / 100)
        let ringColor = usesAPIKeyUsageFallback
            ? visualTheme.accent
            : PulseTheme.usage(remainingPercent ?? 0)

        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                .padding(1.5)
            Circle()
                .trim(from: 0, to: usesAPIKeyUsageFallback ? 1 : progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(1.5)
                .shadow(color: ringColor.opacity(0.22), radius: 3)
            Text(displayedValue)
                .font(
                    .system(
                        size: needsWideRing ? 9.5 : 10.5,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: diameter - 8)
                .contentTransition(.numericText())
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.28), value: diameter)
        .animation(.easeOut(duration: 0.5), value: remainingPercent)
        .layoutPriority(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            usesAPIKeyUsageFallback ? "API Key 按量计费" : "剩余额度 \(displayedValue)"
        )
    }

    // MARK: - 今日 Token

    private var tokenReadout: some View {
        HStack(spacing: 5) {
            CoffeeBeanIcon(color: visualTheme.accent)
                .frame(width: 15, height: 17)
                .allowsHitTesting(false)
            Text(displayedTokenText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: 66)
                .contentTransition(.numericText(countsDown: false))
                .animation(
                    isRealtimeTokenMode && !reduceMotion
                        ? .easeOut(duration: 0.22)
                        : nil,
                    value: todayTokens
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .help(
            usesAPIKeyUsageFallback
                ? "API Key 模式：今日值来自本机全部 session 的 token_count，账单以 OpenAI API Usage / Costs 为准"
                : "今日 Token 取 Codex App Server 与本机当天全部 session 汇总中的较大值；切换账号后立即更新"
        )
    }

    // MARK: - 展开详情卡

    private var detailCard: some View {
        let snapshot = store.snapshot
        return VStack(alignment: .leading, spacing: 0) {
            // 账号
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.account.displayEmail)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(snapshot.account.planType.displayName) · \(snapshot.account.authMode.displayName)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(mode.label)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(mode.color.opacity(0.16)))
                    .foregroundStyle(mode.color)
            }
            .padding(.bottom, 10)

            accountDetails(snapshot.account)
                .padding(.bottom, 12)

            dataTrustStatus(snapshot)
                .padding(.bottom, 12)

            cardDivider

            // 额度窗口
            VStack(alignment: .leading, spacing: 9) {
                ForEach(snapshot.rateLimits.buckets.prefix(3)) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bucket.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("剩 \(String(format: "%.0f%%", bucket.remainingPercent))")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(PulseTheme.usage(bucket.remainingPercent))
                            if let countdown = bucket.resetCountdown {
                                Text("· \(PulseFormatters.countdown(countdown))后重置")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        LiquidProgressBar(remainingPercent: bucket.remainingPercent, height: 5, animated: false)
                    }
                }
                if snapshot.rateLimits.buckets.isEmpty {
                    if usesAPIKeyUsageFallback {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("API 按量计费", systemImage: "key.horizontal.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(PulseTheme.blue)
                            Text("不使用 ChatGPT 每周 / 5 小时额度；Token 用量继续在下方统计")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("暂无额度数据")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 12)

            if !usesAPIKeyUsageFallback {
                cardDivider

                resetCardsSection(snapshot.rateLimits.resetCards)
                    .padding(.vertical, 12)
            }

            cardDivider

            tokenTrendSection(snapshot.usage)
                .padding(.vertical, 12)

            cardDivider

            // Token 与任务
            HStack(spacing: 0) {
                metric("今日", PulseFormatters.tokens(todayTokens))
                metricDivider
                metric("累计", PulseFormatters.tokens(snapshot.usage.totalTokens))
                metricDivider
                taskOrOnlineMetric(snapshot)
            }
            .padding(.vertical, 12)

            if mode == .working || mode == .attention {
                cardDivider
                VStack(alignment: .leading, spacing: 8) {
                    if let project = snapshot.currentTask.projectName {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(project)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                            if let model = snapshot.currentTask.model {
                                Text(model)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if let started = snapshot.currentTask.startedAt {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(PulseFormatters.duration(context.date.timeIntervalSince(started)))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }

                    TaskDataTunnelView(
                        tint: PulseTheme.status(snapshot.currentTask.state.indicatorColor),
                        isAnimating: snapshot.currentTask.state.isActive && !reduceMotion,
                        isPausedForAttention: snapshot.currentTask.state == .awaitingAuthorization
                            || snapshot.currentTask.state == .awaitingInput
                    )
                    .frame(height: 68)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                }
                .padding(.vertical, 10)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.24),
                    value: snapshot.currentTask.state.rawValue
                )
            }
        }
        .padding(18)
        .frame(width: 340)
        .background {
            CapsuleGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var updateDetailCard: some View {
        let release = appUpdates.availableRelease
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(visualTheme.accent.opacity(0.14))
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(visualTheme.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("发现新版本")
                        .font(.system(size: 13, weight: .semibold))
                    Text("v\(appUpdates.currentVersion)  →  v\(release?.version ?? "—")")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            cardDivider

            VStack(alignment: .leading, spacing: 8) {
                Text(release?.title ?? "CodexPulse 更新")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(2)
                ScrollView {
                    Text(updateNotesText(release))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 72, maxHeight: 160)

                if appUpdates.installationStage != .idle {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(appUpdates.installationMessage ?? "正在准备更新…")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            if appUpdates.installationStage == .downloading {
                                Text("\(Int((appUpdates.downloadProgress * 100).rounded()))%")
                                    .monospacedDigit()
                            }
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(
                            appUpdates.installationStage == .failed
                                ? PulseTheme.red
                                : Color.secondary
                        )

                        if appUpdates.installationStage == .downloading
                            || appUpdates.installationStage == .ready {
                            ProgressView(value: appUpdates.downloadProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(
                                    appUpdates.installationStage == .ready
                                        ? PulseTheme.green
                                        : visualTheme.accent
                                )
                            Text(updateDownloadSizeText)
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical, 14)

            cardDivider

            HStack(spacing: 10) {
                Button("跳过此版本") {
                    appUpdates.skipAvailableVersion()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        isShowingUpdateDetails = false
                        isExpanded = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    appUpdates.installationStage == .downloading
                        || appUpdates.installationStage == .installing
                )

                Spacer(minLength: 0)

                Button(appUpdates.primaryUpdateActionTitle) {
                    appUpdates.performPrimaryUpdateAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appUpdates.isPrimaryUpdateActionDisabled)
            }
            .padding(.top, 14)
        }
        .padding(18)
        .frame(width: 340)
        .background {
            CapsuleGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    private var updateDownloadSizeText: String {
        let written = ByteCountFormatter.string(
            fromByteCount: appUpdates.downloadedByteCount,
            countStyle: .file
        )
        guard appUpdates.expectedDownloadByteCount > 0 else { return written }
        let total = ByteCountFormatter.string(
            fromByteCount: appUpdates.expectedDownloadByteCount,
            countStyle: .file
        )
        return "\(written) / \(total)"
    }

    private func updateNotesText(_ release: AppRelease?) -> AttributedString {
        let source = release?.displayNotes ?? "新版本已发布，可前往 GitHub 下载并安装。"
        return (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }

    /// 让用户在看到数字时同时知道数据口径，尤其避免把 Mock 或断线
    /// 快照误认为实时额度。详情卡里保留一行即可，不干扰收起态信息密度。
    private func dataTrustStatus(_ snapshot: PulseSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            dataTrustStatusContent(snapshot, reference: context.date)
        }
    }

    private func dataTrustStatusContent(_ snapshot: PulseSnapshot, reference: Date) -> some View {
        let icon: String
        let color: Color
        let title: String
        let dataUpdatedAt = [snapshot.rateLimits.updatedAt, snapshot.usage.updatedAt]
            .filter { $0 != .distantPast }
            .max() ?? snapshot.updatedAt
        let dataIsStale = dataUpdatedAt == .distantPast
            || reference.timeIntervalSince(dataUpdatedAt) > 30 * 60

        if store.isUsingMock {
            icon = "exclamationmark.triangle.fill"
            color = PulseTheme.orange
            title = "演示数据 · 连接真实 Codex 后显示实际用量"
        } else if snapshot.connectionState == .error || snapshot.connectionState == .disconnected {
            icon = "wifi.slash"
            color = PulseTheme.orange
            title = dataUpdatedAt == .distantPast
                ? "尚未同步到 Codex 数据"
                : "连接异常 · 显示最近一次数据"
        } else if dataUpdatedAt == .distantPast {
            icon = "arrow.triangle.2.circlepath"
            color = Color.secondary
            title = "等待首次同步"
        } else {
            icon = dataIsStale ? "clock.badge.exclamationmark" : "checkmark.circle"
            color = dataIsStale ? PulseTheme.orange : Color.secondary
            title = "数据同步于 \(PulseFormatters.relativeDate(dataUpdatedAt, relativeTo: reference))"
        }

        return VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .help(store.lastError ?? title)

            if snapshot.account.authMode == .apiKey, snapshot.usage.todayTokens != nil {
                Text("API Key 今日值：本机全部 session 汇总 · 非 OpenAI 账单")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metricDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 24)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func taskOrOnlineMetric(_ snapshot: PulseSnapshot) -> some View {
        if mode == .working || mode == .attention {
            if let startedAt = snapshot.currentTask.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    metric(
                        "任务时间",
                        PulseFormatters.duration(context.date.timeIntervalSince(startedAt))
                    )
                }
            } else {
                metric("任务时间", "—")
            }
        } else {
            metric(
                "在线天数",
                snapshot.usage.currentStreakDays.map { "\($0) 天" } ?? "—"
            )
        }
    }

    private func accountDetails(_ account: AccountInfo) -> some View {
        VStack(spacing: 7) {
            accountRow("账号", account.displayEmail)
            accountRow("套餐与认证", "\(account.planType.displayName) · \(account.authMode.displayName)")
            if let workspace = account.workspaceName, !workspace.isEmpty {
                accountRow("工作区", workspace)
            }
//            if let cli = account.cliVersion, !cli.isEmpty {
//                accountRow("Codex CLI", cli)
//            }
//            accountRow("最近同步", PulseFormatters.relativeDate(account.lastSyncedAt))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func accountRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    /// 默认仅显示重置卡摘要；点击后展示全部明细。可用卡优先，其次按到期时间排序。
    private func resetCardsSection(_ cards: [RateLimitResetCard]) -> some View {
        let sortedCards = cards.sorted { lhs, rhs in
            if lhs.isAvailable != rhs.isAvailable {
                return lhs.isAvailable && !rhs.isAvailable
            }
            return (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
        }
        let availableCount = cards.filter(\.isAvailable).count

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.38, extraBounce: 0.05)) {
                    areResetCardsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(PulseTheme.blue)
                        .rotationEffect(.degrees(areResetCardsExpanded && !reduceMotion ? -18 : 0))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("重置卡")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(sortedCards.isEmpty ? "暂无明细" : "\(availableCount) 张可用 · 共 \(cards.count) 张")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    if let nextExpiration = sortedCards
                        .filter({ $0.isAvailable })
                        .compactMap(\.expiresAt)
                        .first {
                        Text("最近 \(PulseFormatters.relativeDate(nextExpiration))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(areResetCardsExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(areResetCardsExpanded ? "收起重置卡明细" : "展开重置卡明细")

            if areResetCardsExpanded {
                Group {
                    if sortedCards.isEmpty {
                        Text("暂无重置卡数据")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sortedCards.enumerated()), id: \.element.id) { index, card in
                                resetCardRow(card, index: index)
                                if index < sortedCards.count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 1)
                                        .padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .clipped()
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                            .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
    }

    /// Codrops Scroll Graph 风格：图表出现时从左向右揭示路径，日期节点依次进入。
    private func tokenTrendSection(_ usage: UsageStats) -> some View {
        let buckets = usage.filledLast7Days()
        let peak = max(1, buckets.map(\.tokens).max() ?? 0)
        let chartCeiling = max(peak + 1, Int64(Double(peak) * 1.15))
        let hoveredBucket = hoveredTokenBucketID.flatMap { selectedID in
            buckets.first { $0.id == selectedID }
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(PulseTheme.blue)
                    .scaleEffect(tokenChartRevealed || reduceMotion ? 1 : 0.82)
                    .opacity(tokenChartRevealed || reduceMotion ? 1 : 0.25)
                Text("近 7 日 Token")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer()
                ZStack(alignment: .trailing) {
                    Text("合计 \(PulseFormatters.tokens(usage.last7DaysTokens))")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .opacity(hoveredBucket == nil ? 1 : 0)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(hoveredBucket?.dateString ?? "0000-00-00")
                            .foregroundStyle(.secondary)
                        Text("\((hoveredBucket?.tokens ?? 0).formatted(.number.grouping(.automatic))) Token")
                            .foregroundStyle(PulseTheme.blue)
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .opacity(hoveredBucket == nil ? 0 : 1)
                }
                .frame(width: 138, height: 24, alignment: .trailing)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredTokenBucketID)
            }

            Chart(buckets) { bucket in
                AreaMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [PulseTheme.blue.opacity(0.24), PulseTheme.blue.opacity(0.015)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .foregroundStyle(PulseTheme.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if bucket.id == hoveredTokenBucketID {
                    RuleMark(x: .value("悬停日期", bucket.dateString))
                        .foregroundStyle(PulseTheme.blue.opacity(0.32))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                PointMark(
                    x: .value("日期", bucket.dateString),
                    y: .value("Token", bucket.tokens)
                )
                .symbolSize(bucket.id == hoveredTokenBucketID ? 58 : 18)
                .foregroundStyle(PulseTheme.blue)
            }
            .frame(height: 118)
            .chartYScale(domain: Int64(0)...chartCeiling)
            .chartPlotStyle { plotArea in
                plotArea
                    .padding(.top, 4)
                    .padding(.bottom, 3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let day = value.as(String.self) {
                            Text(String(day.suffix(5)))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    AxisTick().foregroundStyle(Color.primary.opacity(0.08))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.065))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else {
                                    hoveredTokenBucketID = nil
                                    return
                                }
                                let plotRect = geometry[plotFrame]
                                guard plotRect.contains(location), plotRect.width > 0 else {
                                    hoveredTokenBucketID = nil
                                    return
                                }

                                let plotX = location.x - plotRect.minX
                                if let date = proxy.value(atX: plotX, as: String.self),
                                   let bucket = buckets.first(where: { $0.dateString == date }) {
                                    hoveredTokenBucketID = bucket.id
                                } else {
                                    let progress = min(1, max(0, plotX / plotRect.width))
                                    let index = Int((progress * CGFloat(max(0, buckets.count - 1))).rounded())
                                    hoveredTokenBucketID = buckets.indices.contains(index) ? buckets[index].id : nil
                                }
                            case .ended:
                                hoveredTokenBucketID = nil
                            }
                        }
                }
            }
            .mask(alignment: .leading) {
                Rectangle()
                    .scaleEffect(x: tokenChartRevealed || reduceMotion ? 1 : 0.001, anchor: .leading)
            }
            .accessibilityLabel("近 7 日 Token 使用量图表")
            .accessibilityValue("合计 \(PulseFormatters.tokens(usage.last7DaysTokens))")
        }
        .onAppear {
            guard !tokenChartRevealed else { return }
            if reduceMotion {
                tokenChartRevealed = true
            } else {
                withAnimation(.easeOut(duration: 0.72).delay(0.1)) {
                    tokenChartRevealed = true
                }
            }
        }
    }

    private func resetCardRow(_ card: RateLimitResetCard, index: Int) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: card.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(card.isAvailable ? PulseTheme.green : Color.secondary)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("重置卡 \(index + 1)")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(card.isAvailable ? "可用" : "不可用")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(card.isAvailable ? PulseTheme.green : Color.secondary)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("到期")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Text(resetCardExpirationText(card))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(resetCardExpirationColor(card))
                    Spacer(minLength: 0)
                }

                if !card.applicableLimitTypes.isEmpty {
                    Text("适用：\(card.applicableLimitTypes.joined(separator: "、"))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func resetCardExpirationText(_ card: RateLimitResetCard) -> String {
        guard let expiresAt = card.expiresAt else { return "官方明细暂未返回" }
        let absolute = PulseFormatters.absoluteDateTime(expiresAt)
        guard expiresAt > Date() else { return "\(absolute)（已到期）" }
        return "\(absolute)（\(PulseFormatters.relativeDate(expiresAt))）"
    }

    private func resetCardExpirationColor(_ card: RateLimitResetCard) -> Color {
        guard let expiresAt = card.expiresAt else { return .secondary }
        let remaining = expiresAt.timeIntervalSinceNow
        if remaining <= 0 || remaining < 24 * 3600 { return PulseTheme.red }
        if remaining < 3 * 24 * 3600 { return PulseTheme.orange }
        return .secondary
    }
}

private struct CatTaskStateObserver: ViewModifier {
    let state: CodexRunState
    let action: (CodexRunState, CodexRunState) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: state, action)
    }
}

// MARK: - 双击极简胶囊

private struct CoffeeBeanIcon: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let beanRect = CGRect(
                x: size.width * 0.17,
                y: size.height * 0.08,
                width: size.width * 0.66,
                height: size.height * 0.84
            )
            context.fill(
                Path(ellipseIn: beanRect),
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.96), Color.brown.opacity(0.88)]),
                    startPoint: CGPoint(x: beanRect.minX, y: beanRect.minY),
                    endPoint: CGPoint(x: beanRect.maxX, y: beanRect.maxY)
                )
            )

            var seam = Path()
            seam.move(to: CGPoint(x: beanRect.midX - 1.2, y: beanRect.minY + 1.4))
            seam.addCurve(
                to: CGPoint(x: beanRect.midX + 1.2, y: beanRect.maxY - 1.4),
                control1: CGPoint(x: beanRect.maxX - 1.4, y: beanRect.midY - 3),
                control2: CGPoint(x: beanRect.minX + 1.4, y: beanRect.midY + 3)
            )
            context.stroke(
                seam,
                with: .color(Color.white.opacity(0.58)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
        }
        .rotationEffect(.degrees(-24))
        .shadow(color: color.opacity(0.28), radius: 3)
        .accessibilityHidden(true)
    }
}

private struct MiniCapsulePresentation {
    let value: String
    let progress: Double
    let color: Color
    let help: String
}

/// 极简态始终只保留一个核心值；不同样式用环形语法区分，而不是堆叠标签。
private struct MiniCapsuleCircleView: View {
    @Environment(\.pulseVisualTheme) private var visualTheme

    let style: MiniCapsuleStyle
    let presentation: MiniCapsulePresentation
    let isWorking: Bool
    let isAttention: Bool
    let activityStyle: ActivityBandStyle
    let activityBandEnabled: Bool
    let isPreviewingActivity: Bool
    let reduceMotion: Bool

    private var isActive: Bool {
        activityBandEnabled && (isWorking || isAttention || isPreviewingActivity)
    }

    var body: some View {
        ZStack {
            PulseThemedSurface(
                shape: Circle(),
                role: .capsule,
                castsShadow: true
            )

            styleTrack
            styleProgress

            Text(presentation.value)
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .frame(width: 49)
                .contentTransition(.numericText(countsDown: false))

            if isActive {
                activeOrbit
            }
        }
        .padding(3)
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.7)
                .padding(3)
        }
        .animation(.easeOut(duration: 0.45), value: presentation.progress)
        .animation(.easeInOut(duration: 0.22), value: isActive)
        .animation(
            (isWorking || isAttention) && !reduceMotion
                ? .easeOut(duration: 0.22)
                : nil,
            value: presentation.value
        )
    }

    @ViewBuilder
    private var styleTrack: some View {
        switch style {
        case .quota:
            Circle()
                .stroke(Color.primary.opacity(0.13), lineWidth: 4)
                .padding(8)
        case .tokens:
            Circle()
                .stroke(
                    Color.primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [2, 3])
                )
                .padding(8)
        case .status:
            Circle()
                .stroke(presentation.color.opacity(0.22), lineWidth: 2)
                .padding(10)
        case .weather:
            Circle()
                .stroke(
                    Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 4.2])
                )
                .padding(8)
        case .time:
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    .padding(7)
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 2.5)
                    .padding(11)
            }
        }
    }

    @ViewBuilder
    private var styleProgress: some View {
        let progress = CGFloat(min(1, max(0, presentation.progress)))
        switch style {
        case .quota:
            progressCircle(progress, width: 4, padding: 8)
        case .tokens:
            progressCircle(progress, width: 2.2, padding: 8, dash: [2, 3])
        case .status:
            progressCircle(progress, width: 2, padding: 10)
        case .weather:
            progressCircle(progress, width: 2.5, padding: 8, dash: [0.5, 4.2])
        case .time:
            progressCircle(progress, width: 2.5, padding: 7)
        }
    }

    private func progressCircle(
        _ progress: CGFloat,
        width: CGFloat,
        padding: CGFloat,
        dash: [CGFloat] = []
    ) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                presentation.color,
                style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash)
            )
            .rotationEffect(.degrees(-90))
            .padding(padding)
            .shadow(color: presentation.color.opacity(0.35), radius: 3)
    }

    @ViewBuilder
    private var activeOrbit: some View {
        if isAttention {
            attentionOrbit
        } else {
            thinkingOrbit
        }
    }

    private var thinkingOrbit: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let rotation = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.65)
                    / 1.65 * 360
            Circle()
                .stroke(
                    AngularGradient(
                        colors: activityColors,
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
                .padding(3.5)
                .shadow(
                    color: activityShadowColor.opacity(0.5),
                    radius: 5
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var attentionOrbit: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = elapsed.truncatingRemainder(dividingBy: 1.15) / 1.15
            let pulse = reduceMotion ? 0.72 : (sin(phase * .pi * 2 - .pi / 2) + 1) / 2
            Circle()
                .stroke(
                    PulseTheme.red.opacity(0.5 + pulse * 0.5),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                )
                .scaleEffect(0.96 + pulse * 0.085)
                .padding(3.5)
                .shadow(
                    color: PulseTheme.red.opacity(0.35 + pulse * 0.4),
                    radius: 3 + pulse * 4
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var activityColors: [Color] {
        let accent = visualTheme.accent
        switch activityStyle {
        case .classic:
            return [accent, Color.cyan, PulseTheme.orange, Color(red: 1, green: 0.88, blue: 0.54), accent]
        case .aurora:
            return [accent, Color(red: 0.13, green: 0.89, blue: 0.7), Color(red: 0.55, green: 0.35, blue: 1), Color(red: 0.72, green: 1, blue: 0.88), accent]
        case .lava:
            return [accent, PulseTheme.red, Color(red: 1, green: 0.48, blue: 0), Color(red: 1, green: 0.69, blue: 0), Color(red: 1, green: 0.94, blue: 0.65), accent]
        case .neon:
            return [accent, Color(red: 0.55, green: 0.35, blue: 1), Color(red: 1, green: 0.2, blue: 0.72), Color.white, accent]
        case .mono:
            return [accent.opacity(0.42), accent.opacity(0.78), accent, accent.opacity(0.72), accent.opacity(0.42)]
        }
    }

    private var activityShadowColor: Color {
        switch activityStyle {
        case .classic: return visualTheme.accent
        case .aurora: return Color(red: 0.13, green: 0.89, blue: 0.7)
        case .lava: return PulseTheme.orange
        case .neon: return Color(red: 1, green: 0.2, blue: 0.72)
        case .mono: return visualTheme.accent
        }
    }

    private var valueFont: Font {
        switch style {
        case .quota: return .system(size: 14, weight: .bold, design: .rounded)
        case .tokens: return .system(size: 10.5, weight: .semibold, design: .rounded)
        case .status: return .system(size: 17, weight: .bold, design: .rounded)
        case .weather: return .system(size: 11.5, weight: .bold, design: .rounded)
        case .time: return .system(size: 9.5, weight: .semibold, design: .rounded)
        }
    }

    private var valueColor: Color {
        switch style {
        case .status, .tokens: return presentation.color
        case .quota, .weather, .time: return .primary
        }
    }
}

// MARK: - 动态天气氛围层

/// 使用 Meteocons 自带动画的 Fill SVG。素材随应用离线分发，运行时不会请求图标 CDN。
private struct WeatherAtmosphereView: View {
    let condition: WeatherCondition
    let isDay: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            atmosphericGradient

            AnimatedWeatherSVGView(
                assetName: weatherAssetName,
                reduceMotion: reduceMotion
            )
            .frame(width: 104, height: 72)
            .offset(x: -3)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.12), Color.black.opacity(0.52)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var weatherAssetName: String {
        switch condition {
        case .clear:
            return isDay ? "clear-day" : "clear-night"
        case .partlyCloudy:
            return isDay ? "partly-cloudy-day" : "partly-cloudy-night"
        case .cloudy:
            return isDay ? "overcast-day" : "overcast-night"
        case .fog:
            return isDay ? "fog-day" : "fog-night"
        case .drizzle:
            return isDay ? "partly-cloudy-day-drizzle" : "partly-cloudy-night-drizzle"
        case .rain, .showers:
            return isDay ? "partly-cloudy-day-rain" : "partly-cloudy-night-rain"
        case .snow:
            return isDay ? "partly-cloudy-day-snow" : "partly-cloudy-night-snow"
        case .thunderstorm:
            return isDay ? "thunderstorms-day-rain" : "thunderstorms-night-rain"
        }
    }

    private var atmosphericGradient: some View {
        let colors: [Color]
        if isDay {
            switch condition {
            case .rain, .showers, .thunderstorm:
                colors = [Color(hex: 0x1E4A72), Color(hex: 0x111C2C)]
            case .snow:
                colors = [Color(hex: 0x6689A8), Color(hex: 0x1E344D)]
            default:
                colors = [Color(hex: 0x296AA6), Color(hex: 0x14263A)]
            }
        } else {
            colors = condition == .thunderstorm
                ? [Color(hex: 0x171D3D), Color(hex: 0x080B17)]
                : [Color(hex: 0x172D55), Color(hex: 0x080D1B)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

/// SwiftUI 暂不直接播放 SMIL SVG，因此用系统 WebKit 渲染本地文件，不引入额外运行库。
private final class ClickThroughWeatherWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct AnimatedWeatherSVGView: NSViewRepresentable {
    let assetName: String
    let reduceMotion: Bool

    final class Coordinator {
        var renderKey: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = ClickThroughWeatherWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.isHidden = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let renderKey = "\(assetName)-\(reduceMotion)"
        guard context.coordinator.renderKey != renderKey else { return }
        context.coordinator.renderKey = renderKey

        guard
            let url = Bundle.main.url(forResource: assetName, withExtension: "svg"),
            let svg = try? String(contentsOf: url, encoding: .utf8)
        else {
            webView.loadHTMLString("", baseURL: nil)
            return
        }

        let pauseScript = reduceMotion
            ? "document.querySelector('svg')?.pauseAnimations();"
            : ""
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="color-scheme" content="dark">
          <style>
            html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
            svg { display: block; width: 100%; height: 100%; transform: scale(1.08); transform-origin: center; }
          </style>
        </head>
        <body>
          \(svg)
          <script>window.addEventListener('load', () => { \(pauseScript) });</script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
}

/// 信息栏展开后的当前 turn 对话。固定外框尺寸避免每个文本 delta 都触发
/// NSPanel 重排；内容只在内部滚动，胶囊本体因此保持原位。
private struct StreamingTaskSummary: View {
    let text: String
    let color: Color
    let activityColor: Color

    private var latestText: String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 34 else { return normalized }
        return "…" + String(normalized.suffix(34))
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .center) {
                Text(latestText)
                    .id(latestText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: 13, alignment: .center)
            .padding(.horizontal, 2)
            .clipped()
            .animation(.easeOut(duration: 0.18), value: latestText)

            StreamingActivityDots(color: activityColor)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }
}

private struct StreamingActivityDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate * 4.4
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = (sin(time - Double(index) * 0.82) + 1) / 2
                    Circle()
                        .fill(color)
                        .frame(width: 2.5, height: 2.5)
                        .opacity(reduceMotion ? 0.62 : 0.22 + wave * 0.78)
                        .offset(y: reduceMotion ? 0 : -wave * 1.4)
                }
            }
        }
        .frame(width: 12, height: 10)
        .accessibilityHidden(true)
    }
}

private struct TaskConversationCard: View {
    let width: CGFloat
    let messages: [TaskConversationMessage]
    let isStreaming: Bool
    let accent: Color
    var showsSurface = true
    let onClose: () -> Void

    private let bottomAnchor = "task-conversation-bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text("当前对话")
                    .font(.system(size: 11, weight: .semibold))
                if isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                        Text("实时输出")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(accent)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help("收起实时对话")
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider().opacity(0.35)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 9) {
                        if messages.isEmpty {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(accent)
                                Text("Codex 正在组织回复…")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 142)
                        } else {
                            ForEach(messages) { message in
                                TaskConversationBubble(message: message, accent: accent)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .padding(11)
                }
                .scrollIndicators(.automatic)
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: messages) { _, _ in
                    scrollToBottom(proxy, animated: true)
                }
            }
        }
        .frame(width: width, height: 246)
        .background {
            if showsSurface {
                PulseThemedSurface(
                    shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
                    role: .panel,
                    castsShadow: true
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前 Codex 对话")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }
}

private struct TaskConversationBubble: View {
    let message: TaskConversationMessage
    let accent: Color

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 4) {
                if message.role == .assistant, message.isStreaming {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                }
                Text(message.role == .user ? "你" : "Codex")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(message.role == .user ? accent : Color.secondary)
            }
            Text(message.text)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.9))
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            message.role == .user
                                ? accent.opacity(0.13)
                                : Color.primary.opacity(0.055)
                        )
                }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - 胶囊下沿任务跑马灯

/// 仅沿胶囊下半圈显示一段往返渐变，表达任务仍在持续处理。
/// 与鼠标跟随描边分层绘制，避免指针在下方时同时点亮整圈边框。
private struct CapsuleActivityMarquee: View {
    let style: ActivityBandStyle
    let isActive: Bool
    let isAttention: Bool
    let reduceMotion: Bool
    let phaseOrigin: Date?

    private let frameInterval = 1.0 / 60.0

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: frameInterval,
                paused: !isActive || reduceMotion
            )
        ) { timeline in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
                drawMarquee(
                    context: &context,
                    size: size,
                    progress: marqueeProgress(at: timeline.date)
                )
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: isActive ? 0.22 : 0.3), value: isActive)
        .accessibilityHidden(true)
    }

    private func marqueeProgress(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0.5 }
        let legDuration = isAttention ? 2.8 : 2.2
        let elapsed = phaseOrigin.map { max(0, date.timeIntervalSince($0)) }
            ?? date.timeIntervalSinceReferenceDate
        let phase = (elapsed / legDuration)
            .truncatingRemainder(dividingBy: 2)
        // 光带在端点已收成零长度并完全透明，因此可以匀速换向；
        // 不再使用 ease-in-out，避免端点减速与收缩叠加后产生“卡一下”的错觉。
        return CGFloat(phase <= 1 ? phase : 2 - phase)
    }

    private func drawMarquee(
        context: inout GraphicsContext,
        size: CGSize,
        progress: CGFloat
    ) {
        guard size.width > 2, size.height > 2, isActive else { return }

        let inset: CGFloat = 1.15
        let radius = max(0, size.height / 2 - inset)
        let leftX = inset
        let rightX = size.width - inset
        let middleY = size.height / 2
        let bottomY = size.height - inset
        guard rightX - leftX > radius * 2 else { return }

        // 从左侧半圆中点开始，沿左下圆弧、水平底边、右下圆弧到右侧半圆中点。
        // kappa 用三次贝塞尔曲线逼近四分之一圆，避免光带在直线与圆弧交界处顿挫。
        let kappa: CGFloat = 0.552_284_8
        var lowerCapsule = Path()
        lowerCapsule.move(to: CGPoint(x: leftX, y: middleY))
        lowerCapsule.addCurve(
            to: CGPoint(x: leftX + radius, y: bottomY),
            control1: CGPoint(x: leftX, y: middleY + radius * kappa),
            control2: CGPoint(x: leftX + radius * (1 - kappa), y: bottomY)
        )
        lowerCapsule.addLine(to: CGPoint(x: rightX - radius, y: bottomY))
        lowerCapsule.addCurve(
            to: CGPoint(x: rightX, y: middleY),
            control1: CGPoint(x: rightX - radius * (1 - kappa), y: bottomY),
            control2: CGPoint(x: rightX, y: middleY + radius * kappa)
        )

        // 单个连续径向渐变沿真实下半圆移动，和鼠标跟随描边采用相同绘制思路。
        // 不再拆分颜色切片，因此不会出现分段或像素块。
        let endpointEnvelope = max(0, sin(Double(progress) * .pi))
        let endpointOpacity = pow(endpointEnvelope, 0.65)
        let arcLength = radius * .pi / 2
        let straightLength = max(0, rightX - leftX - radius * 2)
        let totalLength = arcLength * 2 + straightLength
        let distance = progress * totalLength
        let gradientCenter: CGPoint
        if distance < arcLength {
            let angle = CGFloat.pi - (distance / arcLength) * (.pi / 2)
            gradientCenter = CGPoint(
                x: leftX + radius + cos(angle) * radius,
                y: middleY + sin(angle) * radius
            )
        } else if distance < arcLength + straightLength {
            gradientCenter = CGPoint(
                x: leftX + radius + distance - arcLength,
                y: bottomY
            )
        } else {
            let arcDistance = distance - arcLength - straightLength
            let angle = (.pi / 2) - (arcDistance / arcLength) * (.pi / 2)
            gradientCenter = CGPoint(
                x: rightX - radius + cos(angle) * radius,
                y: middleY + sin(angle) * radius
            )
        }

        let palette = activityPalette
        let gradient = Gradient(stops: [
            .init(color: palette.hot.opacity(endpointOpacity), location: 0),
            .init(color: palette.core.opacity(endpointOpacity), location: 0.28),
            .init(color: palette.middle.opacity(endpointOpacity), location: 0.56),
            .init(color: palette.edge.opacity(endpointOpacity * 0.8), location: 0.78),
            .init(color: .clear, location: 1)
        ])
        let gradientRadius = max(
            CGFloat(1),
            CGFloat(isAttention ? 58 : 66) * CGFloat(endpointEnvelope)
        )
        let shading = GraphicsContext.Shading.radialGradient(
            gradient,
            center: gradientCenter,
            startRadius: 0,
            endRadius: gradientRadius
        )

        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 1.2))
            glow.stroke(
                lowerCapsule,
                with: shading,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
        }
        context.stroke(
            lowerCapsule,
            with: shading,
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )
    }

    private var activityPalette: (hot: Color, core: Color, middle: Color, edge: Color) {
        if isAttention {
            return (
                Color(red: 1, green: 0.94, blue: 0.74),
                PulseTheme.red,
                PulseTheme.orange,
                PulseTheme.red
            )
        }
        switch style {
        case .classic:
            return (Color(red: 1, green: 0.88, blue: 0.54), PulseTheme.orange, .cyan, PulseTheme.blue)
        case .aurora:
            return (Color(red: 0.72, green: 1, blue: 0.88), .cyan, Color(red: 0.55, green: 0.35, blue: 1), PulseTheme.blue)
        case .lava:
            return (Color(red: 1, green: 0.94, blue: 0.65), Color(red: 1, green: 0.58, blue: 0.04), PulseTheme.orange, PulseTheme.red)
        case .neon:
            return (.white, Color(red: 1, green: 0.2, blue: 0.72), Color(red: 0.56, green: 0.3, blue: 1), PulseTheme.blue)
        case .mono:
            return (Color(red: 1, green: 0.93, blue: 0.72), PulseTheme.orange, PulseTheme.orange.opacity(0.82), PulseTheme.orange.opacity(0.45))
        }
    }
}

// MARK: - Google 风格鼠标跟随描边

/// Google AI 搜索按钮采用彩色锥形渐变与轻微模糊层。
/// 这里保留相同的颜色节奏，但只在悬停时显示，并用鼠标位置驱动局部高光中心。
private struct CapsuleHoverGlow: View {
    let center: UnitPoint
    let isVisible: Bool

    private let blue = Color(red: 49 / 255, green: 134 / 255, blue: 1)
    private let violet = Color(red: 147 / 255, green: 120 / 255, blue: 1)
    private let pink = Color(red: 249 / 255, green: 107 / 255, blue: 214 / 255)
    private let coral = Color(red: 1, green: 107 / 255, blue: 43 / 255)
    private let yellow = Color(red: 254 / 255, green: 199 / 255, blue: 0)
    private let green = Color(red: 14 / 255, green: 188 / 255, blue: 95 / 255)
    private let cyan = Color(red: 0, green: 169 / 255, blue: 187 / 255)

    var body: some View {
        ZStack {
            // 彩色锥形渐变只通过鼠标附近的径向遮罩显露，不再点亮整个胶囊。
            Capsule(style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [blue, violet, pink, coral, yellow, green, cyan, blue],
                        center: .center
                    ),
                    lineWidth: 2.35
                )
                .saturation(1.25)
                .brightness(0.12)
                .mask {
                    RadialGradient(
                        colors: [Color.white, Color.white.opacity(0.92), Color.clear],
                        center: center,
                        startRadius: 0,
                        endRadius: 48
                    )
                }

            // 鼠标附近更亮；远离指针后自然透明，形成“光沿边缘追随”的感觉。
            Capsule(style: .continuous)
                .stroke(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            green.opacity(0.95),
                            cyan.opacity(0.9),
                            blue.opacity(0.52),
                            Color.clear
                        ],
                        center: center,
                        startRadius: 0,
                        endRadius: 44
                    ),
                    lineWidth: 3.2
                )
                .brightness(0.1)

            // 外侧柔光放在独立层，避免把玻璃主体本身染成彩色。
            Capsule(style: .continuous)
                .stroke(
                    RadialGradient(
                        colors: [
                            green.opacity(0.95),
                            cyan.opacity(0.78),
                            blue.opacity(0.45),
                            Color.clear
                        ],
                        center: center,
                        startRadius: 0,
                        endRadius: 52
                    ),
                    lineWidth: 4.4
                )
                .blur(radius: 5)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1.006 : 0.992)
        .animation(.easeOut(duration: isVisible ? 0.16 : 0.28), value: isVisible)
    }
}

// MARK: - 玻璃背景(胶囊与卡片共用)

private struct CapsuleGlass<S: InsettableShape>: View {
    let shape: S
    var glowColor: Color? = nil
    var glowPulse: Bool = false
    var castsShadow: Bool = true

    var body: some View {
        PulseThemedSurface(shape: shape, role: .capsule, castsShadow: false)
            .shadow(
                color: castsShadow
                    ? (glowColor.map { $0.opacity(glowPulse ? 0.5 : 0.22) } ?? Color.black.opacity(0.2))
                    : .clear,
                radius: castsShadow ? (glowColor != nil ? 14 : 13) : 0,
                y: castsShadow ? (glowColor != nil ? 0 : 6) : 0
            )
            .shadow(color: castsShadow ? Color.white.opacity(0.12) : .clear, radius: castsShadow ? 1 : 0, y: castsShadow ? -1 : 0)
    }
}
