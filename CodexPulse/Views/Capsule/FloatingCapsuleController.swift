#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    static let pulseCapsuleToggleDetails = Notification.Name("com.codexpulse.capsule.toggle-details")
    static let pulseCapsuleToggleMini = Notification.Name("com.codexpulse.capsule.toggle-mini")
    static let pulseCatRoamingActivityChanged = Notification.Name("com.codexpulse.cat-roaming.activity")
}

private let compactPetSceneSize = CGSize(width: 216, height: 129.6)
private let compactBlackHoleSceneSize = CGSize(width: 216, height: 184)
private let compactPetPadding: CGFloat = 12

private func compactPetGrowthScale(for size: CGSize) -> CGFloat? {
    for sceneSize in [compactPetSceneSize, compactBlackHoleSceneSize] {
        let horizontal = (
            size.width - compactPetPadding * 2
        ) / sceneSize.width
        let vertical = (
            size.height - compactPetPadding * 2
        ) / sceneSize.height
        if horizontal >= 0.98,
           horizontal <= 10.02,
           vertical >= 0.98,
           vertical <= 10.02,
           abs(horizontal - vertical) <= 0.035 {
            return (horizontal + vertical) / 2
        }
    }
    return nil
}

/// 无边框面板会优先把背景单击解释为拖动。这里在 AppKit 事件入口区分
/// “短距离单击”和“真实拖动”，确保 SwiftUI 无论包含何种原生子视图都能收到展开指令。
private final class InteractiveCapsulePanel: NSPanel {
    var onCapsuleClick: (() -> Void)?
    var onCapsuleDoubleClick: (() -> Void)?
    var onManualInteraction: (() -> Void)?
    var onManualDragMoved: ((NSPoint) -> Void)?
    var onManualDragEnded: ((NSPoint) -> Void)?
    var usesCompactHitRegion = false
    var compactHitRegionSize = CGSize(width: 240, height: 153.6)
    private var capsuleMouseDownScreenLocation: NSPoint?
    private var capsuleMouseDownFrameOrigin: NSPoint?
    private var capsuleMouseDownAt: TimeInterval?
    private var pendingSingleClick: DispatchWorkItem?
    private var suppressNextSingleClick = false

    func suppressNextCapsuleClick() {
        suppressNextSingleClick = true
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.suppressNextSingleClick = false
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let compactInteractionActive = isCompactInteractionActive
        let ownsPetPointerTracking = compactInteractionActive || isPetConversationLayout
        switch event.type {
        case .leftMouseDown:
            if event.clickCount >= 2 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
            }
            let isInside = isInsideCapsule(event)
            if isInside {
                onManualInteraction?()
                capsuleMouseDownScreenLocation = NSEvent.mouseLocation
                capsuleMouseDownFrameOrigin = frame.origin
                capsuleMouseDownAt = event.timestamp
            } else {
                clearCapsuleClickCandidate()
            }
            // Compact mode owns pointer tracking so the tiny NSHostingView cannot
            // consume the drag before the borderless panel gets a chance to move.
            if ownsPetPointerTracking && isInside { return }
        case .leftMouseDragged:
            if ownsPetPointerTracking,
               let startLocation = capsuleMouseDownScreenLocation,
               let startOrigin = capsuleMouseDownFrameOrigin {
                let currentLocation = NSEvent.mouseLocation
                let delta = NSPoint(
                    x: currentLocation.x - startLocation.x,
                    y: currentLocation.y - startLocation.y
                )
                if hypot(delta.x, delta.y) > 2 {
                    onManualDragMoved?(currentLocation)
                    setFrameOrigin(clampedCompactOrigin(NSPoint(
                        x: startOrigin.x + delta.x,
                        y: startOrigin.y + delta.y
                    ), pointer: currentLocation))
                }
                return
            }
        case .leftMouseUp:
            let start = capsuleMouseDownScreenLocation
            let startedInsideCapsule = start != nil
            let startedAt = capsuleMouseDownAt
            let pointer = NSEvent.mouseLocation
            let dragDistance = start.map { pointDistance($0, pointer) } ?? 0
            let didDrag = startedInsideCapsule && dragDistance > 4
            let shouldToggle = start.map { pointDistance($0, pointer) <= 4 } == true
                && startedAt.map { event.timestamp - $0 <= 0.8 } == true
                && isInsideCapsule(event)
            clearCapsuleClickCandidate()
            if !ownsPetPointerTracking || !startedInsideCapsule {
                super.sendEvent(event)
            }
            if didDrag {
                onManualDragEnded?(pointer)
            }
            if shouldToggle {
                if suppressNextSingleClick {
                    suppressNextSingleClick = false
                    return
                }
                if event.clickCount >= 2 {
                    pendingSingleClick?.cancel()
                    pendingSingleClick = nil
                    PulseLog.write("capsule panel double click captured")
                    onCapsuleDoubleClick?()
                } else {
                    let work = DispatchWorkItem { [weak self] in
                        PulseLog.write("capsule panel click captured")
                        self?.onCapsuleClick?()
                    }
                    pendingSingleClick?.cancel()
                    pendingSingleClick = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                }
            }
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    private func isInsideCapsule(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let bounds = contentView.bounds
        if isCompactInteractionActive {
            return bounds.insetBy(dx: 1, dy: 1).contains(point)
        }
        if isPetConversationLayout {
            let petWidth: CGFloat = min(compactHitRegionSize.width, bounds.width)
            let petHeight: CGFloat = min(compactHitRegionSize.height, bounds.height)
            let originY = contentView.isFlipped ? 0 : bounds.height - petHeight
            return NSRect(
                x: bounds.width - petWidth,
                y: originY,
                width: petWidth,
                height: petHeight
            ).contains(point)
        }
        if bounds.width <= 100, bounds.height <= 100 {
            return bounds.insetBy(dx: 1, dy: 1).contains(point)
        }
        let horizontalInset: CGFloat = 24
        let topInset: CGFloat = 16
        let capsuleHeight: CGFloat = 64
        let originY = contentView.isFlipped
            ? topInset
            : bounds.height - topInset - capsuleHeight
        let hitRect = NSRect(
            x: horizontalInset,
            y: originY,
            width: max(0, bounds.width - horizontalInset * 2),
            height: capsuleHeight
        )
        return hitRect.contains(point)
    }

    private func pointDistance(_ lhs: NSPoint, _ rhs: NSPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    /// During a SwiftUI size transition the explicit flag can arrive one layout pass
    /// after the native panel frame. The frame fallback keeps the whole transparent
    /// pet canvas draggable, including character pixels handled by `NSImageView`.
    private var isCompactInteractionActive: Bool {
        usesCompactHitRegion || compactPetGrowthScale(for: frame.size) != nil
    }

    /// 迷你宠物展开实时对话后，窗口会变高，但宠物仍固定在右上角。
    /// 只把该区域识别成胶囊，避免拦截下方对话的滚动和关闭按钮。
    private var isPetConversationLayout: Bool {
        frame.width >= min(315, compactHitRegionSize.width) - 10
            && frame.height >= compactHitRegionSize.height + 180
            && frame.height <= compactHitRegionSize.height + 360
    }

    /// 使用 macOS 全局屏幕坐标判断拖动目标。窗口只要仍有足够区域落在任意
    /// 显示器上就保持连续跟手；只有即将完全丢出所有屏幕时才夹回鼠标所在屏幕。
    /// 不能使用 `panel.screen` 单屏夹取，否则窗口永远无法越过当前屏幕边缘。
    private func clampedCompactOrigin(_ proposed: NSPoint, pointer: NSPoint) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return proposed }
        let proposedFrame = NSRect(origin: proposed, size: frame.size)
        let minimumVisibleWidth = min(CGFloat(44), frame.width)
        let minimumVisibleHeight = min(CGFloat(44), frame.height)
        let remainsReachable = screens.contains { screen in
            let intersection = proposedFrame.intersection(screen.visibleFrame)
            return intersection.width >= minimumVisibleWidth
                && intersection.height >= minimumVisibleHeight
        }
        if remainsReachable { return proposed }

        let targetScreen = screens.first(where: { $0.frame.contains(pointer) })
            ?? screens.max(by: {
                proposedFrame.intersection($0.visibleFrame).width
                    * proposedFrame.intersection($0.visibleFrame).height
                    < proposedFrame.intersection($1.visibleFrame).width
                    * proposedFrame.intersection($1.visibleFrame).height
            })
            ?? screen
            ?? NSScreen.main
        guard let visible = targetScreen?.visibleFrame else { return proposed }
        return NSPoint(
            x: min(max(proposed.x, visible.minX), visible.maxX - frame.width),
            y: min(max(proposed.y, visible.minY), visible.maxY - frame.height)
        )
    }

    private func clearCapsuleClickCandidate() {
        capsuleMouseDownScreenLocation = nil
        capsuleMouseDownFrameOrigin = nil
        capsuleMouseDownAt = nil
    }
}

/// 无边框置顶悬浮胶囊窗口。
/// - 所有空间可见(含全屏 App 旁),不抢焦点
/// - 拖动任意位置移动,位置持久化
/// - 双击切换迷你态,右键菜单可隐藏
@MainActor
final class FloatingCapsuleController {
    static let shared = FloatingCapsuleController()

    private var panel: NSPanel?
    private weak var activeStore: PulseStore?
    private let frameKey = "pulse.capsule.frame"
    private let visibleKey = "pulse.capsule.visible"
    private var catRoamingEnabled = false
    private var catRoamingCycleDuration: TimeInterval = 1.0 / 1.12
    private var catRoamingArcHeight: CGFloat = 7
    private var catRoamingMinimumHorizontalDistance: CGFloat = 140
    private var catRoamingTask: Task<Void, Never>?
    private var catRoamingResumeTask: Task<Void, Never>?
    private var catManualInteractionTask: Task<Void, Never>?
    private var currentCatRoamingActivity: CatRoamingActivity = .resting
    private var catInteractionCooldownUntil = Date.distantPast
    private var manualDragEncounteredDestination: CatRoamingDestination?
    private var framePersistenceTask: Task<Void, Never>?
    private var systemWakeObserver: NSObjectProtocol?
    private var lastContentSize: CGSize?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 首次运行默认显示；用户在面板中手动关闭后，后续启动尊重该选择。
    func restoreIfNeeded(store: PulseStore) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: visibleKey) == nil {
            defaults.set(true, forKey: visibleKey)
        }
        guard defaults.bool(forKey: visibleKey) else { return }
        show(store: store)
    }

    func toggle(store: PulseStore) {
        if isVisible {
            hide()
        } else {
            show(store: store)
        }
    }

    func show(store: PulseStore) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        activeStore = store
        let content = CapsuleHostView(
            store: store,
            onSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
            onQuit: {
                CodexPulseLifecycle.quit(store: store)
            }
        ) {
            FloatingCapsuleRoot(store: store)
        }
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 10, height: 44)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = InteractiveCapsulePanel(
            contentRect: initialFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false           // 阴影由 SwiftUI 自绘,避免方形窗口阴影
        panel.level = .statusBar          // 高于普通窗口,低于屏保
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.onCapsuleClick = { [weak self] in
            if self?.wakeSleepingPetFromClick() == true { return }
            self?.scheduleCatRoamingResume(after: 4)
            NotificationCenter.default.post(name: .pulseCapsuleToggleDetails, object: nil)
        }
        panel.onCapsuleDoubleClick = { [weak self] in
            self?.scheduleCatRoamingResume(after: 4)
            NotificationCenter.default.post(name: .pulseCapsuleToggleMini, object: nil)
        }
        panel.onManualInteraction = { [weak self] in
            self?.pauseCatRoamingForManualInteraction()
        }
        panel.onManualDragMoved = { [weak self] pointer in
            self?.rememberManualPetEncounter(at: pointer)
        }
        panel.onManualDragEnded = { [weak self] pointer in
            self?.handleManualPetDrop(at: pointer)
        }
        panel.contentView = hosting
        let initialContentSize = hosting.fittingSize
        panel.setContentSize(initialContentSize)
        lastContentSize = initialContentSize

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleFramePersistence() }
        }

        self.panel = panel
        installSystemWakeObserverIfNeeded()
        panel.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: visibleKey)
    }

    /// SwiftUI 展开/收起时同步调整无边框面板尺寸，并固定右上角，避免详情卡被旧窗口裁掉。
    private func resizePanel(to contentSize: CGSize, animated: Bool = true) {
        guard let panel,
              contentSize.width > 1,
              contentSize.height > 1 else { return }
        lastContentSize = contentSize

        let oldFrame = panel.frame
        let targetUsesCompactHitRegion = isCompactPetSize(contentSize)
        if let interactivePanel = panel as? InteractiveCapsulePanel {
            interactivePanel.usesCompactHitRegion = targetUsesCompactHitRegion
            let growthScale = CGFloat(PetGrowth.scale(
                forTodayTokens: activeStore?.snapshot.usage.todayTokens
            ))
            interactivePanel.compactHitRegionSize = targetUsesCompactHitRegion
                ? contentSize
                : CGSize(
                    width: compactPetSceneSize.width * growthScale
                        + compactPetPadding * 2,
                    height: compactPetSceneSize.height * growthScale
                        + compactPetPadding * 2
                )
        }
        guard abs(oldFrame.width - contentSize.width) > 0.5
                || abs(oldFrame.height - contentSize.height) > 0.5 else { return }

        var target = NSRect(
            x: oldFrame.maxX - contentSize.width,
            y: oldFrame.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )

        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if target.minX < visible.minX { target.origin.x = visible.minX }
            if target.maxX > visible.maxX { target.origin.x = visible.maxX - target.width }
            if target.minY < visible.minY { target.origin.y = visible.minY }
            if target.maxY > visible.maxY { target.origin.y = visible.maxY - target.height }
        }
        let isMiniMorph = isCompactPetFrame(oldFrame)
            || isCompactPetFrame(target)
            || oldFrame.width <= 100
            || target.width <= 100
        let isPetConversationMorph = (
            isCompactPetFrame(oldFrame) && isPetConversationFrame(target)
        ) || (
            isPetConversationFrame(oldFrame) && isCompactPetFrame(target)
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Conversation expansion is a SwiftUI-owned island morph. Animating the
        // NSPanel envelope at the same time adds a second vertical interpolator,
        // which makes the surface look like a window dropping down and moves the
        // compact pet with it. Resize that transparent envelope immediately and
        // leave the visible transition to FloatingCapsuleView.
        if animated && isMiniMorph && !isPetConversationMorph && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.2,
                    0.82,
                    0.2,
                    1
                )
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func isCompactPetFrame(_ frame: NSRect) -> Bool {
        compactPetGrowthScale(for: frame.size) != nil
    }

    private func isPetConversationFrame(_ frame: NSRect) -> Bool {
        frame.width >= 315 && frame.width <= 355
            && frame.height >= 385 && frame.height <= 435
    }

    private func isCompactPetSize(_ size: CGSize) -> Bool {
        compactPetGrowthScale(for: size) != nil
    }

    func hide() {
        stopCatRoaming()
        framePersistenceTask?.cancel()
        framePersistenceTask = nil
        removeSystemWakeObserver()
        persistFrame()
        panel?.orderOut(nil)
        panel = nil
        activeStore = nil
        lastContentSize = nil
        UserDefaults.standard.set(false, forKey: visibleKey)
    }

    func suppressNextCapsuleClick() {
        (panel as? InteractiveCapsulePanel)?.suppressNextCapsuleClick()
    }

    func prepareForTermination() {
        stopCatRoaming()
        framePersistenceTask?.cancel()
        framePersistenceTask = nil
        removeSystemWakeObserver()
        persistFrame()
    }

    private func installSystemWakeObserverIfNeeded() {
        guard systemWakeObserver == nil else { return }
        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restorePanelGeometryAfterSystemWake()
            }
        }
    }

    private func removeSystemWakeObserver() {
        guard let systemWakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(systemWakeObserver)
        self.systemWakeObserver = nil
    }

    private func restorePanelGeometryAfterSystemWake() {
        guard let panel, let stableSize = lastContentSize else { return }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        // Backing-scale/display changes can briefly leave a borderless panel
        // with its pre-sleep pixel dimensions interpreted as points. Restore
        // the last SwiftUI content size immediately, without a scale animation.
        resizePanel(to: stableSize, animated: false)
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            // AppKit can publish one delayed backing-scale/layout pass after
            // didWake. Reapply the pre-sleep point size instead of trusting
            // that transient fittingSize, which may contain pixel dimensions.
            self.resizePanel(to: stableSize, animated: false)
            panel.contentView?.needsLayout = true
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - 小猫桌面漫游试验

    /// 只使用 NSScreen 提供的可见区域和系统保留边缘来定位常见的
    /// 桌面图标栅格与 Dock 图标带。不会读取桌面文件、Finder 数据或
    /// 辅助功能树，因此不会触发文件访问/辅助功能授权。
    func setCatRoamingEnabled(
        _ enabled: Bool,
        cycleDuration: TimeInterval = 1.0 / 1.12,
        arcHeight: CGFloat = 7,
        minimumHorizontalDistance: CGFloat = 140
    ) {
        catRoamingCycleDuration = max(0.4, min(2.0, cycleDuration))
        catRoamingArcHeight = max(0, min(24, arcHeight))
        catRoamingMinimumHorizontalDistance = max(70, min(220, minimumHorizontalDistance))
        guard catRoamingEnabled != enabled else { return }
        catRoamingEnabled = enabled
        catRoamingResumeTask?.cancel()
        catRoamingResumeTask = nil
        catManualInteractionTask?.cancel()
        catManualInteractionTask = nil
        manualDragEncounteredDestination = nil
        catRoamingTask?.cancel()
        catRoamingTask = nil

        guard enabled else {
            publishCatRoaming(.resting, facesLeft: false)
            return
        }
        startCatRoaming()
    }

    private func startCatRoaming() {
        guard catRoamingEnabled, catRoamingTask == nil else { return }
        catRoamingTask = Task { @MainActor [weak self] in
            await self?.runCatRoamingLoop()
        }
    }

    private func stopCatRoaming() {
        catRoamingEnabled = false
        catRoamingTask?.cancel()
        catRoamingTask = nil
        catRoamingResumeTask?.cancel()
        catRoamingResumeTask = nil
        catManualInteractionTask?.cancel()
        catManualInteractionTask = nil
        manualDragEncounteredDestination = nil
        publishCatRoaming(.resting, facesLeft: false)
    }

    private func pauseCatRoamingForManualInteraction() {
        guard catRoamingEnabled else { return }
        catRoamingTask?.cancel()
        catRoamingTask = nil
        catRoamingResumeTask?.cancel()
        catManualInteractionTask?.cancel()
        catManualInteractionTask = nil
        manualDragEncounteredDestination = nil
        if currentCatRoamingActivity != .sleeping {
            publishCatRoaming(.resting, facesLeft: false)
        }
    }

    private func runCatRoamingLoop() async {
        defer { catRoamingTask = nil }

        // 刚进入空闲态后很快给出第一次真实步态，便于用户感知；
        // 后续仍保留较长的自然停留，不会持续满屏乱跑。
        guard await waitForCat(seconds: Double.random(in: 1.5...3.0)) else { return }
        var owesFirstInteraction = true

        while catRoamingEnabled, !Task.isCancelled {
            let roll = Double.random(in: 0...1)

            // Feline micro-actions use unequal probabilities and unequal holds so
            // the companion never reads as a short deterministic playlist.
            if !owesFirstInteraction, roll < 0.10 {
                publishCatRoaming(.stretching, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 2.2...2.9)) else { return }
                publishCatRoaming(.sleeping, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 13.0...23.0)) else { return }
                publishCatRoaming(.stretching, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 2.2...2.9)) else { return }
                publishCatRoaming(.resting, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 7.0...13.0)) else { return }
                continue
            }
            if !owesFirstInteraction, roll < 0.21 {
                publishCatRoaming(.grooming, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 6.0...9.0)) else { return }
                publishCatRoaming(.resting, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 7.0...14.0)) else { return }
                continue
            }
            if !owesFirstInteraction, roll < 0.31 {
                publishCatRoaming(.stretching, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 4.2...6.2)) else { return }
                publishCatRoaming(.resting, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 6.0...12.0)) else { return }
                continue
            }
            if !owesFirstInteraction, roll < 0.39 {
                publishCatRoaming(.waving, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 3.2...5.0)) else { return }
                publishCatRoaming(.resting, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 6.5...13.0)) else { return }
                continue
            }
            if !owesFirstInteraction, roll < 0.47 {
                publishCatRoaming(.hopping, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 2.8...4.5)) else { return }
                publishCatRoaming(.resting, facesLeft: false)
                guard await waitForCat(seconds: Double.random(in: 7.0...14.0)) else { return }
                continue
            }

            guard let panel,
                  let targetScreen = roamingScreen(for: panel) else { return }

            var destinationKind: CatRoamingDestination
            if owesFirstInteraction {
                destinationKind = Bool.random() ? .desktopItem : .dockIcon
            } else if roll < 0.56 {
                destinationKind = .desktopItem
            } else if roll < 0.68 {
                destinationKind = .dockIcon
            } else {
                destinationKind = .wander
            }

            let start = panel.frame.origin
            var target = catRoamingTarget(
                for: destinationKind,
                panelSize: panel.frame.size,
                screen: targetScreen
            )
            let initialHorizontal = abs(target.origin.x - start.x)
            let initialVertical = abs(target.origin.y - start.y)
            if initialHorizontal < catRoamingMinimumHorizontalDistance,
               initialVertical > 54 {
                // Moving between two icon slots in the same column read like an
                // elevator. Skip that interaction this turn and choose a real
                // horizontal stroll; a later trip can approach the icon from
                // a natural side angle.
                destinationKind = .wander
                target = catRoamingTarget(
                    for: .wander,
                    panelSize: panel.frame.size,
                    screen: targetScreen
                )
            }
            // Travel direction must come from the actual start/end positions.
            // Dock targets used to randomize this value and desktop targets
            // hard-coded right, which made the cat visibly walk backwards.
            let horizontalDelta = target.origin.x - start.x
            let movementFacesLeft = abs(horizontalDelta) > 2
                ? horizontalDelta < 0
                : target.facesLeft
            publishCatRoaming(.strolling, facesLeft: movementFacesLeft)
            guard await moveCatPanel(from: start, to: target.origin) else { return }

            let encounterCanPlay = Date() >= catInteractionCooldownUntil
            switch destinationKind {
            case .desktopItem:
                if encounterCanPlay {
                    guard await performCatEncounter(
                        .desktopItem,
                        facesLeft: movementFacesLeft
                    ) else { return }
                    catInteractionCooldownUntil = Date().addingTimeInterval(
                        Double.random(in: 15...30)
                    )
                } else {
                    publishCatRoaming(.resting, facesLeft: movementFacesLeft)
                    guard await waitForCat(seconds: Double.random(in: 0.8...1.6)) else { return }
                }
            case .dockIcon:
                if encounterCanPlay {
                    guard await performCatEncounter(
                        .dockIcon,
                        facesLeft: movementFacesLeft
                    ) else { return }
                    catInteractionCooldownUntil = Date().addingTimeInterval(
                        Double.random(in: 15...30)
                    )
                } else {
                    publishCatRoaming(.resting, facesLeft: movementFacesLeft)
                    guard await waitForCat(seconds: Double.random(in: 0.8...1.6)) else { return }
                }
            case .wander:
                publishCatRoaming(.resting, facesLeft: movementFacesLeft)
                guard await waitForCat(seconds: Double.random(in: 5.0...12.0)) else { return }
            }
            owesFirstInteraction = false
            publishCatRoaming(.resting, facesLeft: false)
            guard await waitForCat(seconds: Double.random(in: 3.0...6.0)) else { return }
        }
    }

    private enum CatRoamingDestination {
        case wander
        case desktopItem
        case dockIcon
    }

    private func rememberManualPetEncounter(at pointer: NSPoint) {
        guard catRoamingEnabled,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main else { return }
        let destination = manualDropDestination(at: pointer, screen: screen)
        switch destination {
        case .dockIcon:
            // Dock wins even when the pointer later leaves it before mouse-up.
            manualDragEncounteredDestination = .dockIcon
        case .desktopItem:
            if manualDragEncounteredDestination == nil {
                manualDragEncounteredDestination = .desktopItem
            }
        case .wander:
            break
        }
    }

    private func handleManualPetDrop(at pointer: NSPoint) {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? panel.flatMap { roamingScreen(for: $0) }
            ?? NSScreen.main
        guard catRoamingEnabled, let screen = targetScreen else { return }
        catRoamingResumeTask?.cancel()
        catRoamingResumeTask = nil
        catManualInteractionTask?.cancel()

        let destination = manualDragEncounteredDestination
            ?? manualDropDestination(at: pointer, screen: screen)
        manualDragEncounteredDestination = nil
        let wakesFromSleep = currentCatRoamingActivity == .sleeping
        let facesLeft = manualInteractionFacesLeft(pointer: pointer)
        catManualInteractionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.catManualInteractionTask = nil
                self.scheduleCatRoamingResume(after: 3.5)
            }
            if wakesFromSleep {
                self.publishCatRoaming(.stretching, facesLeft: facesLeft)
                guard await self.waitForCat(seconds: 2.5) else { return }
            }
            if Date() >= self.catInteractionCooldownUntil {
                guard await self.performCatEncounter(
                    destination,
                    facesLeft: facesLeft
                ) else { return }
                self.catInteractionCooldownUntil = Date().addingTimeInterval(
                    Double.random(in: 15...30)
                )
            }
            self.publishCatRoaming(.resting, facesLeft: facesLeft)
        }
    }

    private func performCatEncounter(
        _ destination: CatRoamingDestination,
        facesLeft: Bool
    ) async -> Bool {
        let totalDuration = Double.random(in: 5...10)
        switch destination {
        case .desktopItem:
            publishCatRoaming(.investigating, facesLeft: facesLeft)
            guard await waitForCat(seconds: totalDuration * 0.18) else { return false }
            publishCatRoaming(.pawingDesktopItem, facesLeft: facesLeft)
            guard await waitForCat(seconds: totalDuration * 0.64) else { return false }
            publishCatRoaming(.investigating, facesLeft: facesLeft)
            return await waitForCat(seconds: totalDuration * 0.18)
        case .dockIcon:
            publishCatRoaming(.investigating, facesLeft: facesLeft)
            guard await waitForCat(seconds: totalDuration * 0.18) else { return false }
            publishCatRoaming(.dockPounce, facesLeft: facesLeft)
            guard await waitForCat(seconds: totalDuration * 0.50) else { return false }
            publishCatRoaming(.dockPlay, facesLeft: facesLeft)
            return await waitForCat(seconds: totalDuration * 0.32)
        case .wander:
            return true
        }
    }

    private func wakeSleepingPetFromClick() -> Bool {
        guard catRoamingEnabled,
              currentCatRoamingActivity == .sleeping else { return false }
        catRoamingResumeTask?.cancel()
        catRoamingResumeTask = nil
        catManualInteractionTask?.cancel()
        catManualInteractionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.catManualInteractionTask = nil
                self.scheduleCatRoamingResume(after: 3.5)
            }
            self.publishCatRoaming(.stretching, facesLeft: false)
            guard await self.waitForCat(seconds: 2.5) else { return }
            self.publishCatRoaming(.resting, facesLeft: false)
        }
        return true
    }

    private func manualDropDestination(
        at pointer: NSPoint,
        screen: NSScreen
    ) -> CatRoamingDestination {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let leftGap = max(0, visible.minX - frame.minX)
        let rightGap = max(0, frame.maxX - visible.maxX)
        let bottomGap = max(0, visible.minY - frame.minY)
        let edge: DockEdge
        if leftGap > max(rightGap, bottomGap), leftGap > 8 {
            edge = .left
        } else if rightGap > max(leftGap, bottomGap), rightGap > 8 {
            edge = .right
        } else {
            edge = .bottom
        }
        let dockThreshold: CGFloat = 110
        let isDockDrop: Bool
        switch edge {
        case .left:
            isDockDrop = pointer.x <= visible.minX + dockThreshold
        case .right:
            isDockDrop = pointer.x >= visible.maxX - dockThreshold
        case .bottom:
            isDockDrop = pointer.y <= visible.minY + dockThreshold
        }
        // A manual drop elsewhere on the desktop is an explicit request to
        // inspect what is underneath. This works with arbitrarily arranged
        // Finder items without reading filenames or requesting Accessibility.
        return isDockDrop ? .dockIcon : .desktopItem
    }

    private func manualInteractionFacesLeft(pointer: NSPoint) -> Bool {
        guard let panel else { return false }
        return pointer.x < panel.frame.midX
    }

    private func scheduleCatRoamingResume(after seconds: TimeInterval) {
        catRoamingResumeTask?.cancel()
        catRoamingResumeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)
                )
            } catch {
                return
            }
            guard let self, self.catRoamingEnabled else { return }
            self.catRoamingResumeTask = nil
            self.startCatRoaming()
        }
    }

    private struct CatRoamingTarget {
        let origin: NSPoint
        let facesLeft: Bool
    }

    private enum DockEdge {
        case bottom
        case left
        case right
    }

    private func roamingScreen(for panel: NSPanel) -> NSScreen? {
        panel.screen
            ?? NSScreen.screens.max(by: {
                panel.frame.intersection($0.visibleFrame).width
                    * panel.frame.intersection($0.visibleFrame).height
                    < panel.frame.intersection($1.visibleFrame).width
                    * panel.frame.intersection($1.visibleFrame).height
            })
            ?? NSScreen.main
    }

    private func catRoamingTarget(
        for destination: CatRoamingDestination,
        panelSize: NSSize,
        screen: NSScreen
    ) -> CatRoamingTarget {
        let visibleFrame = screen.visibleFrame
        let inset: CGFloat = 14
        let minX = visibleFrame.minX + inset
        let maxX = max(minX, visibleFrame.maxX - panelSize.width - inset)
        let minY = visibleFrame.minY + inset
        let maxY = max(minY, visibleFrame.maxY - panelSize.height - inset)

        switch destination {
        case .wander:
            let current = panel?.frame.origin ?? NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)
            let roomLeft = max(0, current.x - minX)
            let roomRight = max(0, maxX - current.x)
            let direction: CGFloat
            if roomLeft < catRoamingMinimumHorizontalDistance {
                direction = 1
            } else if roomRight < catRoamingMinimumHorizontalDistance {
                direction = -1
            } else {
                direction = Bool.random() ? -1 : 1
            }
            let available = direction < 0 ? roomLeft : roomRight
            let travel = min(available, CGFloat.random(in: catRoamingMinimumHorizontalDistance...320))
            // When there is not enough horizontal room, keep this turn level
            // instead of making the companion look like it takes an elevator.
            let verticalOffset: CGFloat = travel >= 70 ? CGFloat.random(in: -48...48) : 0
            let origin = NSPoint(
                x: min(maxX, max(minX, current.x + direction * travel)),
                y: min(maxY, max(minY, current.y + verticalOffset))
            )
            return CatRoamingTarget(
                origin: origin,
                facesLeft: origin.x < current.x
            )
        case .desktopItem:
            // Finder 默认把桌面项目放进右上方约 76pt 的栅格。让角色
            // 本体靠近该栅格，允许透明面板的显示器部分暂时伸出屏幕。
            let availableSlots = max(1, min(7, Int((visibleFrame.height - 120) / 76)))
            let slot = Int.random(in: 0..<availableSlots)
            let iconCenterY = visibleFrame.maxY - 56 - CGFloat(slot) * 76
            return CatRoamingTarget(
                origin: NSPoint(
                    x: visibleFrame.maxX - panelSize.width * 0.60,
                    y: min(maxY, max(minY, iconCenterY - panelSize.height * 0.58))
                ),
                facesLeft: false
            )
        case .dockIcon:
            return dockInteractionTarget(
                screen: screen,
                panelSize: panelSize,
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY
            )
        }
    }

    private func dockInteractionTarget(
        screen: NSScreen,
        panelSize: NSSize,
        minX: CGFloat,
        maxX: CGFloat,
        minY: CGFloat,
        maxY: CGFloat
    ) -> CatRoamingTarget {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let leftInset = max(0, visible.minX - frame.minX)
        let rightInset = max(0, frame.maxX - visible.maxX)
        let bottomInset = max(0, visible.minY - frame.minY)

        let edge: DockEdge
        if leftInset > max(rightInset, bottomInset), leftInset > 8 {
            edge = .left
        } else if rightInset > max(leftInset, bottomInset), rightInset > 8 {
            edge = .right
        } else {
            edge = .bottom
        }

        switch edge {
        case .bottom:
            let slotOffset = CGFloat(Int.random(in: -3...3)) * 54
            let iconCenterX = visible.midX + slotOffset
            return CatRoamingTarget(
                origin: NSPoint(
                    x: min(maxX, max(minX, iconCenterX - panelSize.width * 0.43)),
                    y: visible.minY - 24
                ),
                facesLeft: Bool.random()
            )
        case .left:
            let slotOffset = CGFloat(Int.random(in: -3...3)) * 54
            let iconCenterY = visible.midY + slotOffset
            return CatRoamingTarget(
                origin: NSPoint(
                    x: visible.minX - panelSize.width * 0.38,
                    y: min(maxY, max(minY, iconCenterY - panelSize.height * 0.55))
                ),
                facesLeft: true
            )
        case .right:
            let slotOffset = CGFloat(Int.random(in: -3...3)) * 54
            let iconCenterY = visible.midY + slotOffset
            return CatRoamingTarget(
                origin: NSPoint(
                    x: visible.maxX - panelSize.width * 0.60,
                    y: min(maxY, max(minY, iconCenterY - panelSize.height * 0.55))
                ),
                facesLeft: false
            )
        }
    }

    private func moveCatPanel(from start: NSPoint, to target: NSPoint) async -> Bool {
        guard let panel else { return false }
        let distance = hypot(target.x - start.x, target.y - start.y)
        guard distance > 8 else { return true }
        let requestedDuration = min(8.5, max(1.8, TimeInterval(distance / 105)))
        let gaitCycle = catRoamingCycleDuration
        let completeCycles = max(2, Int((requestedDuration / gaitCycle).rounded()))
        // End only after a complete number of gait cycles. This prevents a
        // half-raised paw from flashing into the next idle/action pose.
        let duration = Double(completeCycles) * gaitCycle
        let startedAt = CACurrentMediaTime()

        while catRoamingEnabled, !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - startedAt
            let progress = min(1, elapsed / duration)
            // smoothstep: 起步和停下都有缓冲，不像窗口被直接推过去。
            let eased = progress * progress * (3 - 2 * progress)
            // A shallow arc prevents desktop travel from reading as a rigid
            // straight-line window slide. The authored gait still owns footfall.
            let arc = sin(progress * .pi) * catRoamingArcHeight
            panel.setFrameOrigin(NSPoint(
                x: start.x + (target.x - start.x) * eased,
                y: start.y + (target.y - start.y) * eased + arc
            ))
            if progress >= 1 { return true }
            guard await waitForCat(seconds: 1.0 / 60.0) else { return false }
        }
        return false
    }

    private func waitForCat(seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return catRoamingEnabled && !Task.isCancelled
        } catch {
            return false
        }
    }

    private func publishCatRoaming(_ activity: CatRoamingActivity, facesLeft: Bool) {
        currentCatRoamingActivity = activity
        NotificationCenter.default.post(
            name: .pulseCatRoamingActivityChanged,
            object: CatRoamingVisualUpdate(activity: activity, facesLeft: facesLeft)
        )
    }

    // MARK: - 位置持久化

    /// 拖动和自动漫游都会连续触发 didMove。只在位置稳定后写一次，
    /// 避免漫游动画期间以 60fps 刷写 UserDefaults。
    private func scheduleFramePersistence() {
        framePersistenceTask?.cancel()
        framePersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            self?.framePersistenceTask = nil
            self?.persistFrame()
        }
    }

    private func persistFrame() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }

    private func initialFrame() -> NSRect {
        if let stored = UserDefaults.standard.string(forKey: frameKey) {
            let rect = NSRectFromString(stored)
            // 确认仍落在某块屏幕内(外接屏拔掉后回默认位置)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                return rect
            }
        }
        // 默认:主屏右上角,菜单栏正下方
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screen.maxX - 240,
            y: screen.maxY - 52,
            width: 200,
            height: 44
        )
    }
}

/// 承载胶囊内容，监听 SwiftUI 实际尺寸并保留右键操作。
private struct CapsuleHostView<Content: View>: View {
    let store: PulseStore
    let onSizeChange: (CGSize) -> Void
    let onQuit: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: CapsuleContentSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(CapsuleContentSizeKey.self, perform: onSizeChange)
            .contextMenu {
                Menu("切换宠物", systemImage: "pawprint") {
                    ForEach(PetCharacter.allCases) { character in
                        Button {
                            selectPet(character)
                        } label: {
                            if store.settings.resolvedPetCharacter == character {
                                Label(character.displayName, systemImage: "checkmark")
                            } else {
                                Text(character.displayName)
                            }
                        }
                    }
                }
                Divider()
                Button("打开看板") { openDashboard() }
                Divider()
                Button("隐藏胶囊") {
                    FloatingCapsuleController.shared.hide()
                }
                Divider()
                Button("退出 CodexPulse", role: .destructive) {
                    onQuit()
                }
            }
    }

    private func selectPet(_ character: PetCharacter) {
        guard store.settings.resolvedPetCharacter != character else { return }
        store.settings.resolvedPetCharacter = character
        store.saveSettings()
        PulseLog.write("pet switched from capsule menu to \(character.rawValue)")
    }

    private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.title == "Codex-Pulse" }) {
            win.makeKeyAndOrderFront(nil)
        }
    }
}

private struct CapsuleContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct FloatingCapsuleRoot: View {
    let store: PulseStore

    var body: some View {
        FloatingCapsuleView()
            .environment(store)
            .environment(AppUpdateService.shared)
            .environment(\.pulseVisualTheme, store.settings.resolvedVisualTheme)
            .tint(store.settings.resolvedVisualTheme.accent)
            .preferredColorScheme(store.settings.resolvedAppearanceMode.colorScheme)
    }
}
#endif
