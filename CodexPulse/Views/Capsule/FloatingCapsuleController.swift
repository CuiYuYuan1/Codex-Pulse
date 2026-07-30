#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    static let pulseCapsuleToggleDetails = Notification.Name("com.codexpulse.capsule.toggle-details")
    static let pulseCapsuleToggleMini = Notification.Name("com.codexpulse.capsule.toggle-mini")
    static let pulseCatRoamingActivityChanged = Notification.Name("com.codexpulse.cat-roaming.activity")
    static let pulseCodexDockReorder = Notification.Name("com.codexpulse.codex-dock.reorder")
    static let pulseCodexDockDetachmentProgress = Notification.Name("com.codexpulse.codex-dock.detachment-progress")
}

private let compactPetSceneSize = CGSize(width: 216, height: 129.6)
private let compactBlackHoleSceneSize = CGSize(width: 216, height: 184)
private let compactPetPadding: CGFloat = 12

struct CodexDockReorderUpdate: Sendable {
    let startX: CGFloat
    let currentX: CGFloat
    let ended: Bool
}

private struct CodexDesktopWindow {
    let id: CGWindowID
    let ownerPID: pid_t
    let frame: NSRect
}

private struct CodexDockTarget {
    let edge: CodexDockEdge
    let frame: NSRect
}

private enum CodexDesktopWindowLocator {
    static func isCodexApplication(_ application: NSRunningApplication) -> Bool {
        let bundle = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        return application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && (bundle.contains("openai.codex")
                || bundle.hasSuffix(".codex")
                || name == "codex")
    }

    static func windows() -> [CodexDesktopWindow] {
        let applications = NSWorkspace.shared.runningApplications.filter(isCodexApplication)
        let pids = Set(applications.map(\.processIdentifier))
        guard !pids.isEmpty,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pids.contains(pid_t(ownerPID.int32Value)) else {
                return nil
            }
            return window(from: info, expectedPID: pid_t(ownerPID.int32Value))
        }
    }

    /// Once attached, reading only the bound WindowServer record is cheap enough
    /// to follow a ProMotion drag without rescanning every visible application.
    static func window(id: CGWindowID, ownerPID: pid_t) -> CodexDesktopWindow? {
        guard let info = (
            CGWindowListCopyWindowInfo([.optionIncludingWindow], id)
                as? [[String: Any]]
        )?.first else {
            return nil
        }
        return window(from: info, expectedPID: ownerPID)
    }

    private static func window(
        from info: [String: Any],
        expectedPID: pid_t
    ) -> CodexDesktopWindow? {
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
              pid_t(ownerPID.int32Value) == expectedPID,
              let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue != false,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue,
              width >= 420,
              height >= 280 else {
            return nil
        }
        let primaryTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        return CodexDesktopWindow(
            id: CGWindowID(windowNumber.uint32Value),
            ownerPID: expectedPID,
            frame: NSRect(
                x: x,
                y: Double(primaryTop) - y - height,
                width: width,
                height: height
            )
        )
    }
}

private struct CodexDockAttachmentPreviewView: View {
    let edge: CodexDockEdge

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.48),
                    Color.cyan.opacity(0.10),
                    Color.purple.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 6) {
                Image(systemName: "link")
                Text("松开以吸附")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.72))
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, Color.cyan.opacity(0.75), Color.purple.opacity(0.55), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1.5)
        }
        .clipShape(CodexDockExtensionShape(edge: edge))
    }
}

/// 信息栏保持在 Codex 下层；这条不可交互的独立光带位于真实接缝上层，
/// 避免被 Codex 的窗口阴影遮住，同时不改变主面板的导航层级。
private struct CodexDockSeamOverlayView: View {
    let edge: CodexDockEdge

    private var gradient: Gradient {
        Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Color(red: 0.06, green: 0.94, blue: 0.94), location: 0.025),
            .init(color: Color(red: 0.03, green: 0.72, blue: 1.00), location: 0.22),
            .init(color: Color(red: 0.35, green: 0.34, blue: 1.00), location: 0.43),
            .init(color: Color(red: 0.82, green: 0.16, blue: 1.00), location: 0.62),
            .init(color: Color(red: 1.00, green: 0.20, blue: 0.68), location: 0.78),
            .init(color: Color(red: 0.08, green: 0.92, blue: 1.00), location: 0.975),
            .init(color: .clear, location: 1)
        ])
    }

    var body: some View {
        GeometryReader { proxy in
            if edge.isVertical {
                auroraBand(
                    length: max(0, proxy.size.height - 24),
                    vertical: true
                )
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
            } else {
                auroraBand(
                    length: max(0, proxy.size.width - 24),
                    vertical: false
                )
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func auroraBand(length: CGFloat, vertical: Bool) -> some View {
        let start: UnitPoint = vertical ? .top : .leading
        let end: UnitPoint = vertical ? .bottom : .trailing
        let glowWidth = vertical ? 3.6 : length
        let glowHeight = vertical ? length : 3.6
        let coreWidth = vertical ? 1.45 : length
        let coreHeight = vertical ? length : 1.45
        let highlightWidth = vertical ? 0.28 : length
        let highlightHeight = vertical ? length : 0.28

        return ZStack {
            LinearGradient(gradient: gradient, startPoint: start, endPoint: end)
                .frame(width: glowWidth, height: glowHeight)
                .blur(radius: 1.25)
                .opacity(0.62)
            LinearGradient(gradient: gradient, startPoint: start, endPoint: end)
                .frame(
                    width: vertical ? 2.0 : length,
                    height: vertical ? length : 2.0
                )
                .blur(radius: 0.32)
                .opacity(0.92)
            LinearGradient(gradient: gradient, startPoint: start, endPoint: end)
                .frame(width: coreWidth, height: coreHeight)
                .shadow(color: Color.cyan.opacity(0.52), radius: 0.9)
                .shadow(color: Color.purple.opacity(0.45), radius: 1.25)
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.70),
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.62),
                    .clear
                ],
                startPoint: start,
                endPoint: end
            )
            .frame(width: highlightWidth, height: highlightHeight)
            .blendMode(.screen)
        }
        .compositingGroup()
    }
}

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
    var onCodexDockReorder: ((_ startX: CGFloat, _ currentX: CGFloat, _ ended: Bool) -> Void)?
    var onCodexDockDetach: ((_ pointer: NSPoint, _ translation: CGSize, _ ended: Bool) -> Void)?
    var usesCompactHitRegion = false
    var usesOrbCircularHitRegion = false
    var usesCodexDockInteraction = false
    var codexDockIsVertical = false
    var compactHitRegionSize = CGSize(width: 240, height: 153.6)
    private var capsuleMouseDownScreenLocation: NSPoint?
    private var capsuleMouseDownFrameOrigin: NSPoint?
    private var capsuleMouseDownAt: TimeInterval?
    private var pendingSingleClick: DispatchWorkItem?
    private var suppressNextSingleClick = false
    private enum CodexDockDragAxis {
        case reorder
        case detach
    }
    private var codexDockDragAxis: CodexDockDragAxis?

    func suppressNextCapsuleClick() {
        suppressNextSingleClick = true
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.suppressNextSingleClick = false
        }
    }

    func beginRebasedCompactDrag(at pointer: NSPoint) {
        capsuleMouseDownScreenLocation = pointer
        capsuleMouseDownFrameOrigin = frame.origin
        capsuleMouseDownAt = ProcessInfo.processInfo.systemUptime
        codexDockDragAxis = nil
    }

    override func sendEvent(_ event: NSEvent) {
        if usesCodexDockInteraction {
            handleCodexDockEvent(event)
            return
        }
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
                    setFrameOrigin(clampedCompactOrigin(NSPoint(
                        x: startOrigin.x + delta.x,
                        y: startOrigin.y + delta.y
                    ), pointer: currentLocation))
                    // Publish after the panel has moved so attachment geometry
                    // never trails the pointer by one drag event.
                    onManualDragMoved?(currentLocation)
                }
                return
            }
            if capsuleMouseDownScreenLocation != nil {
                // 普通胶囊由 AppKit 的 isMovableByWindowBackground 负责实际移动，
                // 先让 AppKit 更新窗口位置，再计算吸附距离，避免预览慢一帧。
                super.sendEvent(event)
                onManualDragMoved?(NSEvent.mouseLocation)
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

    private func handleCodexDockEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            guard isInsideCapsule(event) else {
                super.sendEvent(event)
                return
            }
            capsuleMouseDownScreenLocation = NSEvent.mouseLocation
            capsuleMouseDownFrameOrigin = frame.origin
            capsuleMouseDownAt = event.timestamp
            codexDockDragAxis = nil

        case .leftMouseDragged:
            guard let start = capsuleMouseDownScreenLocation else { return }
            let pointer = NSEvent.mouseLocation
            let delta = CGSize(
                width: pointer.x - start.x,
                height: pointer.y - start.y
            )
            guard hypot(delta.width, delta.height) > 3 else { return }
            if codexDockDragAxis == nil {
                if codexDockIsVertical {
                    codexDockDragAxis = abs(delta.width) > abs(delta.height) * 1.05
                        ? .detach
                        : .reorder
                } else {
                    codexDockDragAxis = abs(delta.height) > abs(delta.width) * 1.05
                        ? .detach
                        : .reorder
                }
            }
            switch codexDockDragAxis {
            case .reorder:
                onCodexDockReorder?(
                    codexDockIsVertical ? frame.maxY - start.y : start.x - frame.minX,
                    codexDockIsVertical ? frame.maxY - pointer.y : pointer.x - frame.minX,
                    false
                )
            case .detach:
                onCodexDockDetach?(pointer, delta, false)
            case nil:
                break
            }

        case .leftMouseUp:
            guard let start = capsuleMouseDownScreenLocation else {
                super.sendEvent(event)
                return
            }
            let pointer = NSEvent.mouseLocation
            let delta = CGSize(
                width: pointer.x - start.x,
                height: pointer.y - start.y
            )
            switch codexDockDragAxis {
            case .reorder:
                onCodexDockReorder?(
                    codexDockIsVertical ? frame.maxY - start.y : start.x - frame.minX,
                    codexDockIsVertical ? frame.maxY - pointer.y : pointer.x - frame.minX,
                    true
                )
            case .detach:
                onCodexDockDetach?(pointer, delta, true)
            case nil:
                break
            }
            codexDockDragAxis = nil
            clearCapsuleClickCandidate()

        default:
            super.sendEvent(event)
        }
    }

    private func isInsideCapsule(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let bounds = contentView.bounds
        if usesCodexDockInteraction {
            return bounds.insetBy(dx: 1, dy: 1).contains(point)
        }
        if isCompactInteractionActive {
            if usesOrbCircularHitRegion {
                let center = NSPoint(x: bounds.midX, y: bounds.midY)
                return hypot(point.x - center.x, point.y - center.y) <= 31
            }
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
    private let codexDockAttachedKey = "pulse.codexDock.attached"
    private let codexDockWidthKey = "pulse.codexDock.width"
    private let codexDockHeightKey = "pulse.codexDock.height"
    private let codexDockEdgeKey = "pulse.codexDock.edge"
    private let codexDockHorizontalThickness: CGFloat = 44
    private let codexDockVerticalThickness: CGFloat = 54
    private let codexDockOverlap: CGFloat = 16
    private let codexDockSeamSurfaceThickness: CGFloat = 8
    private let codexDockProximity: CGFloat = 30
    private var codexDockPreviewPanel: NSPanel?
    private var codexDockSeamPanel: NSPanel?
    private var codexDockSeamActivationObserver: NSObjectProtocol?
    private var codexDockCandidateFrame: NSRect?
    private var codexDockCandidateEdge: CodexDockEdge?
    private var codexDockCandidateWindow: CodexDesktopWindow?
    private var attachedCodexWindow: CodexDesktopWindow?
    private var codexDockTrackingTask: Task<Void, Never>?
    private var codexLaunchObserver: NSObjectProtocol?
    private var codexDockPreviousContentSize: CGSize?
    private var isCodexDockTransitioning = false
    private var cachedCodexWindows: [CodexDesktopWindow] = []
    private var lastCodexWindowFrameRefreshAt = Date.distantPast
    private let codexWindowFrameRefreshInterval: TimeInterval = 0.12
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
            if UserDefaults.standard.bool(forKey: codexDockAttachedKey),
               let window = attachedCodexWindow {
                let edge = CodexDockEdge(
                    rawValue: UserDefaults.standard.string(forKey: codexDockEdgeKey) ?? ""
                ) ?? .bottom
                showCodexDockSeam(for: window, edge: edge, animated: false)
                configureAttachedWindowLevel(panel, above: window)
            } else {
                panel.level = .statusBar
                panel.orderFrontRegardless()
            }
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
        panel.usesOrbCircularHitRegion = store.settings.resolvedPetCharacter.isOrb
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
            // WindowServer enumeration is relatively expensive. Prime the
            // target list once at drag start, then reuse it between refreshes.
            _ = self?.codexWindows(forceRefresh: true)
        }
        panel.onManualDragMoved = { [weak self] pointer in
            self?.rememberManualPetEncounter(at: pointer)
            self?.updateCodexDockPreview()
        }
        panel.onManualDragEnded = { [weak self] pointer in
            guard let self else { return }
            // Native AppKit window dragging can deliver its final frame only
            // immediately before mouse-up. Re-evaluate once with that final
            // geometry so a valid release can never miss the attachment.
            self.updateCodexDockPreview(forceRefresh: true)
            if self.attachToPreviewedCodexWindow() { return }
            self.handleManualPetDrop(at: pointer)
        }
        panel.onCodexDockReorder = { startX, currentX, ended in
            NotificationCenter.default.post(
                name: .pulseCodexDockReorder,
                object: CodexDockReorderUpdate(
                    startX: startX,
                    currentX: currentX,
                    ended: ended
                )
            )
        }
        panel.onCodexDockDetach = { [weak self] pointer, translation, ended in
            self?.handleCodexDockDetach(
                pointer: pointer,
                translation: translation,
                ended: ended
            )
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
        restoreCodexDockAttachmentIfPossible()
    }

    func setFollowCodexLaunch(_ enabled: Bool, store: PulseStore) {
        activeStore = store
        if !enabled {
            if let codexLaunchObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(codexLaunchObserver)
                self.codexLaunchObserver = nil
            }
            return
        }
        guard codexLaunchObserver == nil else { return }
        codexLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak store] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
            CodexDesktopWindowLocator.isCodexApplication(application) else {
                return
            }
            Task { @MainActor [weak self, weak store] in
                guard let self, let store else { return }
                self.show(store: store)
                PulseLog.write("Codex launched; showing CodexPulse follower")
            }
        }
    }

    /// SwiftUI 展开/收起时同步调整无边框面板尺寸，并固定右上角，避免详情卡被旧窗口裁掉。
    private func resizePanel(to contentSize: CGSize, animated: Bool = true) {
        guard let panel,
              contentSize.width > 1,
              contentSize.height > 1 else { return }
        lastContentSize = contentSize
        if UserDefaults.standard.bool(forKey: codexDockAttachedKey)
            || isCodexDockTransitioning {
            return
        }

        let oldFrame = panel.frame
        let targetUsesCompactHitRegion = isCompactPetSize(contentSize)
        if let interactivePanel = panel as? InteractiveCapsulePanel {
            interactivePanel.usesCompactHitRegion = targetUsesCompactHitRegion
            interactivePanel.usesOrbCircularHitRegion =
                activeStore?.settings.resolvedPetCharacter.isOrb == true
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
        stopCodexDockTracking()
        hideCodexDockPreview()
        hideCodexDockSeam(immediately: true)
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

    func updateCompactHitRegion(for character: PetCharacter) {
        (panel as? InteractiveCapsulePanel)?.usesOrbCircularHitRegion = character.isOrb
    }

    func prepareForTermination() {
        stopCatRoaming()
        stopCodexDockTracking()
        hideCodexDockPreview()
        hideCodexDockSeam(immediately: true)
        if let codexLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(codexLaunchObserver)
            self.codexLaunchObserver = nil
        }
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

    // MARK: - Codex window attachment

    private func codexWindows(forceRefresh: Bool = false) -> [CodexDesktopWindow] {
        let now = Date()
        if forceRefresh
            || now.timeIntervalSince(lastCodexWindowFrameRefreshAt)
                >= codexWindowFrameRefreshInterval {
            cachedCodexWindows = CodexDesktopWindowLocator.windows()
            lastCodexWindowFrameRefreshAt = now
        }
        return cachedCodexWindows
    }

    private func updateCodexDockPreview(forceRefresh: Bool = false) {
        guard !UserDefaults.standard.bool(forKey: codexDockAttachedKey),
              !isCodexDockTransitioning,
              let panel else {
            hideCodexDockPreview()
            return
        }
        let candidates = codexWindows(forceRefresh: forceRefresh)
            .flatMap { window in
                codexDockTargets(for: window.frame).map {
                    (window: window, target: $0)
                }
            }
        guard let closest = candidates.min(by: {
            rectDistance(panel.frame, $0.target.frame)
                < rectDistance(panel.frame, $1.target.frame)
        }),
        rectDistance(panel.frame, closest.target.frame) <= codexDockProximity else {
            hideCodexDockPreview()
            return
        }
        codexDockCandidateWindow = closest.window
        codexDockCandidateFrame = closest.target.frame
        codexDockCandidateEdge = closest.target.edge
        showCodexDockPreview(target: closest.target)
    }

    private func showCodexDockPreview(target: CodexDockTarget) {
        let frame = target.frame
        if let preview = codexDockPreviewPanel {
            if abs(preview.frame.minX - frame.minX) > 0.5
                || abs(preview.frame.minY - frame.minY) > 0.5
                || abs(preview.frame.width - frame.width) > 0.5
                || abs(preview.frame.height - frame.height) > 0.5 {
                preview.setFrame(frame, display: true)
            }
            preview.contentView = NSHostingView(
                rootView: CodexDockAttachmentPreviewView(edge: target.edge)
            )
            if preview.alphaValue < 1 {
                preview.animator().alphaValue = 1
            }
            return
        }
        let preview = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        preview.isOpaque = false
        preview.backgroundColor = .clear
        preview.hasShadow = false
        preview.level = .statusBar
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        preview.ignoresMouseEvents = true
        preview.hidesOnDeactivate = false
        preview.contentView = NSHostingView(
            rootView: CodexDockAttachmentPreviewView(edge: target.edge)
        )
        preview.alphaValue = 0
        preview.orderFrontRegardless()
        codexDockPreviewPanel = preview
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            preview.animator().alphaValue = 1
        }
    }

    private func hideCodexDockPreview(immediately: Bool = false) {
        codexDockCandidateFrame = nil
        codexDockCandidateEdge = nil
        codexDockCandidateWindow = nil
        guard let preview = codexDockPreviewPanel else { return }
        codexDockPreviewPanel = nil
        if immediately {
            preview.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            preview.animator().alphaValue = 0
        } completionHandler: {
            preview.orderOut(nil)
        }
    }

    @discardableResult
    private func attachToPreviewedCodexWindow() -> Bool {
        guard let dockFrame = codexDockCandidateFrame,
              let edge = codexDockCandidateEdge,
              let window = codexDockCandidateWindow,
              let panel,
              !isCodexDockTransitioning else {
            hideCodexDockPreview()
            return false
        }

        persistFrame()
        codexDockPreviousContentSize = lastContentSize ?? panel.frame.size
        stopCatRoaming()
        isCodexDockTransitioning = true
        codexDockCandidateFrame = nil
        codexDockCandidateEdge = nil
        codexDockCandidateWindow = nil
        attachedCodexWindow = window
        // Remove the guide before the real surface starts morphing; keeping both
        // panels visible created the "two stacked capsules" freeze.
        hideCodexDockPreview(immediately: true)
        UserDefaults.standard.set(dockFrame.width, forKey: codexDockWidthKey)
        UserDefaults.standard.set(dockFrame.height, forKey: codexDockHeightKey)
        UserDefaults.standard.set(edge.rawValue, forKey: codexDockEdgeKey)
        UserDefaults.standard.set(true, forKey: codexDockAttachedKey)
        showCodexDockSeam(for: window, edge: edge)
        configureAttachedWindowLevel(panel, above: window)
        panel.isMovableByWindowBackground = false
        if let interactive = panel as? InteractiveCapsulePanel {
            interactive.usesCodexDockInteraction = true
            interactive.codexDockIsVertical = edge.isVertical
            interactive.usesCompactHitRegion = false
        }
        panel.contentView?.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0.01
                : 0.27
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20,
                0.82,
                0.24,
                1
            )
            // A single uninterrupted envelope expansion lets the dock read as
            // growing out of the capsule instead of swapping between windows.
            panel.animator().setFrame(dockFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.isCodexDockTransitioning = false
                self?.startCodexDockTracking()
            }
        }
        return true
    }

    private func restoreCodexDockAttachmentIfPossible() {
        guard UserDefaults.standard.bool(forKey: codexDockAttachedKey),
              let panel else { return }
        let candidates = codexWindows(forceRefresh: true)
        guard let window = candidates.first else {
            UserDefaults.standard.set(false, forKey: codexDockAttachedKey)
            return
        }
        attachedCodexWindow = window
        let savedEdge = CodexDockEdge(
            rawValue: UserDefaults.standard.string(forKey: codexDockEdgeKey) ?? ""
        ) ?? .bottom
        let availableTargets = codexDockTargets(for: window.frame)
        guard let target = availableTargets.first(where: { $0.edge == savedEdge })
            ?? availableTargets.first else {
            UserDefaults.standard.set(false, forKey: codexDockAttachedKey)
            return
        }
        let dockFrame = target.frame
        UserDefaults.standard.set(dockFrame.width, forKey: codexDockWidthKey)
        UserDefaults.standard.set(dockFrame.height, forKey: codexDockHeightKey)
        UserDefaults.standard.set(target.edge.rawValue, forKey: codexDockEdgeKey)
        showCodexDockSeam(for: window, edge: target.edge, animated: false)
        configureAttachedWindowLevel(panel, above: window)
        panel.isMovableByWindowBackground = false
        if let interactive = panel as? InteractiveCapsulePanel {
            interactive.usesCodexDockInteraction = true
            interactive.codexDockIsVertical = target.edge.isVertical
            interactive.usesCompactHitRegion = false
        }
        panel.setFrame(dockFrame, display: true)
        startCodexDockTracking()
    }

    private func startCodexDockTracking() {
        stopCodexDockTracking()
        codexDockTrackingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var missingFrames = 0
            var lastOrderingRefresh = CACurrentMediaTime()
            while !Task.isCancelled,
                  UserDefaults.standard.bool(forKey: self.codexDockAttachedKey),
                  let panel = self.panel {
                let current = panel.frame
                let edge = CodexDockEdge(
                    rawValue: UserDefaults.standard.string(
                        forKey: self.codexDockEdgeKey
                    ) ?? ""
                ) ?? .bottom
                let trackedWindow: CodexDesktopWindow?
                if let attached = self.attachedCodexWindow {
                    trackedWindow = CodexDesktopWindowLocator.window(
                        id: attached.id,
                        ownerPID: attached.ownerPID
                    )
                } else {
                    trackedWindow = self.codexWindows(forceRefresh: true).min(by: {
                        self.rectDistance(
                            current,
                            self.codexDockFrame($0.frame, edge: edge)
                        ) < self.rectDistance(
                            current,
                            self.codexDockFrame($1.frame, edge: edge)
                        )
                    })
                }
                if let window = trackedWindow {
                    self.attachedCodexWindow = window
                    if !self.isCodexDockAvailable(window.frame, edge: edge) {
                        self.detachCodexDock(
                            at: NSPoint(x: current.midX, y: current.midY),
                            restoreSavedPosition: true
                        )
                        return
                    }
                    missingFrames = 0
                    let target = self.codexDockFrame(window.frame, edge: edge)
                    self.updateCodexDockSeamFrame(window.frame, edge: edge)
                    let now = CACurrentMediaTime()
                    if now - lastOrderingRefresh >= 0.25 {
                        self.configureAttachedWindowLevel(panel, above: window)
                        lastOrderingRefresh = now
                    }
                    if abs(target.minX - current.minX) > 0.5
                        || abs(target.minY - current.minY) > 0.5
                        || abs(target.width - current.width) > 0.5
                        || abs(target.height - current.height) > 0.5 {
                        if abs(target.width - current.width) > 0.5 {
                            UserDefaults.standard.set(
                                target.width,
                                forKey: self.codexDockWidthKey
                            )
                        }
                        if abs(target.height - current.height) > 0.5 {
                            UserDefaults.standard.set(
                                target.height,
                                forKey: self.codexDockHeightKey
                            )
                        }
                        // Direct frame assignment at display cadence avoids the
                        // delayed staircase created by overlapping animations.
                        panel.setFrame(target, display: true)
                    }
                } else {
                    missingFrames += 1
                    if missingFrames >= 12 {
                        self.detachCodexDock(
                            at: NSPoint(x: current.midX, y: current.midY),
                            restoreSavedPosition: true
                        )
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 8_333_333)
            }
        }
    }

    private func configureAttachedWindowLevel(
        _ panel: NSPanel,
        above window: CodexDesktopWindow
    ) {
        if panel.level != .normal {
            panel.level = .normal
        }
        // The attachment surface extends behind Codex. Ordering it underneath
        // lets the real Codex corner mask the overlap and removes the two
        // transparent shoulder wedges without painting over the host window.
        panel.order(.below, relativeTo: Int(window.id))
        updateCodexDockSeamVisibility(for: window)
    }

    private func showCodexDockSeam(
        for window: CodexDesktopWindow,
        edge: CodexDockEdge,
        animated: Bool = true
    ) {
        installCodexDockSeamActivationObserverIfNeeded()
        let frame = codexDockSeamFrame(window.frame, edge: edge)
        if let seam = codexDockSeamPanel {
            seam.contentView = transparentHostingView(
                rootView: CodexDockSeamOverlayView(edge: edge)
            )
            seam.setFrame(frame, display: true)
            seam.level = .floating
            updateCodexDockSeamVisibility(for: window)
            if seam.isVisible, seam.alphaValue < 1 {
                seam.animator().alphaValue = 1
            }
            return
        }

        let seam = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        seam.isOpaque = false
        seam.backgroundColor = .clear
        seam.hasShadow = false
        seam.level = .floating
        seam.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        seam.ignoresMouseEvents = true
        seam.hidesOnDeactivate = false
        seam.contentView = transparentHostingView(
            rootView: CodexDockSeamOverlayView(edge: edge)
        )
        seam.alphaValue = animated ? 0 : 1
        codexDockSeamPanel = seam
        updateCodexDockSeamVisibility(for: window)

        guard animated, seam.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0.01
                : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            seam.animator().alphaValue = 1
        }
    }

    private func installCodexDockSeamActivationObserverIfNeeded() {
        guard codexDockSeamActivationObserver == nil else { return }
        codexDockSeamActivationObserver =
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let window = self.attachedCodexWindow else { return }
                    self.updateCodexDockSeamVisibility(for: window)
                }
            }
    }

    private func updateCodexDockSeamVisibility(for window: CodexDesktopWindow) {
        guard let seam = codexDockSeamPanel else { return }
        // Electron can briefly report a helper process as the foreground app.
        // Match the Codex application family instead of requiring the foreground
        // PID to equal the WindowServer owner PID, otherwise the seam is hidden
        // even though the attached Codex window is still active.
        let codexIsFrontmost = NSWorkspace.shared.frontmostApplication
            .map(CodexDesktopWindowLocator.isCodexApplication) ?? false
        let shouldShow = codexIsFrontmost
            && panel?.isVisible == true
            && UserDefaults.standard.bool(forKey: codexDockAttachedKey)
        if shouldShow {
            if !seam.isVisible {
                seam.alphaValue = 1
                seam.orderFrontRegardless()
            }
        } else if seam.isVisible {
            seam.orderOut(nil)
        }
    }

    private func transparentHostingView<Content: View>(
        rootView: Content
    ) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        return hosting
    }

    private func updateCodexDockSeamFrame(
        _ windowFrame: NSRect,
        edge: CodexDockEdge
    ) {
        guard let seam = codexDockSeamPanel else { return }
        let target = codexDockSeamFrame(windowFrame, edge: edge)
        guard abs(target.minX - seam.frame.minX) > 0.5
                || abs(target.minY - seam.frame.minY) > 0.5
                || abs(target.width - seam.frame.width) > 0.5
                || abs(target.height - seam.frame.height) > 0.5 else {
            return
        }
        seam.setFrame(target, display: true)
    }

    private func codexDockSeamFrame(
        _ windowFrame: NSRect,
        edge: CodexDockEdge
    ) -> NSRect {
        let thickness = codexDockSeamSurfaceThickness
        let half = thickness * 0.5
        switch edge {
        case .bottom:
            return NSRect(
                x: windowFrame.minX,
                y: windowFrame.minY - half,
                width: windowFrame.width,
                height: thickness
            )
        case .top:
            return NSRect(
                x: windowFrame.minX,
                y: windowFrame.maxY - half,
                width: windowFrame.width,
                height: thickness
            )
        case .left:
            return NSRect(
                x: windowFrame.minX - half,
                y: windowFrame.minY,
                width: thickness,
                height: windowFrame.height
            )
        case .right:
            return NSRect(
                x: windowFrame.maxX - half,
                y: windowFrame.minY,
                width: thickness,
                height: windowFrame.height
            )
        }
    }

    private func hideCodexDockSeam(immediately: Bool = false) {
        if let observer = codexDockSeamActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            codexDockSeamActivationObserver = nil
        }
        guard let seam = codexDockSeamPanel else { return }
        codexDockSeamPanel = nil
        if immediately {
            seam.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            seam.animator().alphaValue = 0
        } completionHandler: {
            seam.orderOut(nil)
        }
    }

    private func stopCodexDockTracking() {
        codexDockTrackingTask?.cancel()
        codexDockTrackingTask = nil
    }

    private func handleCodexDockDetach(
        pointer: NSPoint,
        translation: CGSize,
        ended: Bool
    ) {
        guard UserDefaults.standard.bool(forKey: codexDockAttachedKey),
              !isCodexDockTransitioning else { return }
        let edge = CodexDockEdge(
            rawValue: UserDefaults.standard.string(forKey: codexDockEdgeKey) ?? ""
        ) ?? .bottom
        let distance = edge.isVertical
            ? abs(translation.width)
            : abs(translation.height)
        let progress = min(1, distance / codexDockProximity)
        NotificationCenter.default.post(
            name: .pulseCodexDockDetachmentProgress,
            object: progress
        )
        if ended {
            if progress >= 1 {
                detachCodexDock(at: pointer, restoreSavedPosition: false)
            } else {
                NotificationCenter.default.post(
                    name: .pulseCodexDockDetachmentProgress,
                    object: CGFloat.zero
                )
            }
        }
    }

    private func detachCodexDock(
        at pointer: NSPoint,
        restoreSavedPosition: Bool
    ) {
        guard let panel,
              UserDefaults.standard.bool(forKey: codexDockAttachedKey),
              !isCodexDockTransitioning else { return }
        isCodexDockTransitioning = true
        stopCodexDockTracking()
        hideCodexDockSeam(immediately: true)
        attachedCodexWindow = nil
        panel.level = .statusBar
        panel.orderFrontRegardless()
        NotificationCenter.default.post(
            name: .pulseCodexDockDetachmentProgress,
            object: CGFloat(1)
        )

        let savedFrame = initialFrame()
        let restoredSize = codexDockPreviousContentSize
            ?? (savedFrame.width > 100 && savedFrame.height > 40
                ? savedFrame.size
                : CGSize(width: 283, height: 116))
        let targetOrigin: NSPoint
        if restoreSavedPosition {
            targetOrigin = savedFrame.origin
        } else {
            targetOrigin = NSPoint(
                x: pointer.x - restoredSize.width / 2,
                y: pointer.y - restoredSize.height / 2
            )
        }
        let target = NSRect(origin: targetOrigin, size: restoredSize)
        // Switch the SwiftUI surface and contract the same visible panel. Never
        // drop alpha to zero: that caused the blank frame captured by the user.
        UserDefaults.standard.set(false, forKey: codexDockAttachedKey)
        panel.contentView?.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0.01
                : 0.27
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20,
                0.82,
                0.24,
                1
            )
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel else { return }
                panel.isMovableByWindowBackground = true
                if let interactive = panel as? InteractiveCapsulePanel {
                    interactive.usesCodexDockInteraction = false
                    interactive.codexDockIsVertical = false
                }
                self.isCodexDockTransitioning = false
                NotificationCenter.default.post(
                    name: .pulseCodexDockDetachmentProgress,
                    object: CGFloat.zero
                )
            }
        }
    }

    private func codexDockTargets(for windowFrame: NSRect) -> [CodexDockTarget] {
        CodexDockEdge.allCases.compactMap { edge in
            guard isCodexDockAvailable(windowFrame, edge: edge) else { return nil }
            return CodexDockTarget(
                edge: edge,
                frame: codexDockFrame(windowFrame, edge: edge)
            )
        }
    }

    private func codexDockFrame(
        _ windowFrame: NSRect,
        edge: CodexDockEdge
    ) -> NSRect {
        switch edge {
        case .bottom:
            return NSRect(
                x: windowFrame.minX,
                y: windowFrame.minY - codexDockHorizontalThickness,
                width: windowFrame.width,
                height: codexDockHorizontalThickness + codexDockOverlap
            )
        case .top:
            return NSRect(
                x: windowFrame.minX,
                y: windowFrame.maxY - codexDockOverlap,
                width: windowFrame.width,
                height: codexDockHorizontalThickness + codexDockOverlap
            )
        case .left:
            return NSRect(
                x: windowFrame.minX - codexDockVerticalThickness,
                y: windowFrame.minY,
                width: codexDockVerticalThickness + codexDockOverlap,
                height: windowFrame.height
            )
        case .right:
            return NSRect(
                x: windowFrame.maxX - codexDockOverlap,
                y: windowFrame.minY,
                width: codexDockVerticalThickness + codexDockOverlap,
                height: windowFrame.height
            )
        }
    }

    private func isFullScreenCodexWindow(_ frame: NSRect) -> Bool {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersection(frame).width * $0.frame.intersection(frame).height
                >= frame.width * frame.height * 0.7
        }) else { return false }
        return frame.width >= screen.frame.width - 4
            && frame.height >= screen.frame.height - 8
    }

    private func isCodexDockAvailable(
        _ frame: NSRect,
        edge: CodexDockEdge
    ) -> Bool {
        guard !isFullScreenCodexWindow(frame),
              let screen = NSScreen.screens.first(where: {
                  $0.frame.intersection(frame).width * $0.frame.intersection(frame).height
                      >= frame.width * frame.height * 0.7
              }) else {
            return false
        }
        let dock = codexDockFrame(frame, edge: edge)
        return dock.minX >= screen.visibleFrame.minX - 1
            && dock.maxX <= screen.visibleFrame.maxX + 1
            && dock.minY >= screen.visibleFrame.minY - 1
            && dock.maxY <= screen.visibleFrame.maxY + 1
    }

    private func rectDistance(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let dx = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
        let dy = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
        return hypot(dx, dy)
    }

    // MARK: - 位置持久化

    /// 拖动和自动漫游都会连续触发 didMove。只在位置稳定后写一次，
    /// 避免漫游动画期间以 60fps 刷写 UserDefaults。
    private func scheduleFramePersistence() {
        guard !UserDefaults.standard.bool(forKey: codexDockAttachedKey) else { return }
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
        guard let panel,
              !UserDefaults.standard.bool(forKey: codexDockAttachedKey) else { return }
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
