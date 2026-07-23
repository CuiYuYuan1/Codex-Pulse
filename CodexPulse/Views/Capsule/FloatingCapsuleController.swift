#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    static let pulseCapsuleToggleDetails = Notification.Name("com.codexpulse.capsule.toggle-details")
    static let pulseCapsuleToggleMini = Notification.Name("com.codexpulse.capsule.toggle-mini")
}

/// 无边框面板会优先把背景单击解释为拖动。这里在 AppKit 事件入口区分
/// “短距离单击”和“真实拖动”，确保 SwiftUI 无论包含何种原生子视图都能收到展开指令。
private final class InteractiveCapsulePanel: NSPanel {
    var onCapsuleClick: (() -> Void)?
    var onCapsuleDoubleClick: (() -> Void)?
    var usesCompactHitRegion = false
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
                    )))
                }
                return
            }
        case .leftMouseUp:
            let start = capsuleMouseDownScreenLocation
            let startedInsideCapsule = start != nil
            let startedAt = capsuleMouseDownAt
            let shouldToggle = start.map { pointDistance($0, NSEvent.mouseLocation) <= 4 } == true
                && startedAt.map { event.timestamp - $0 <= 0.8 } == true
                && isInsideCapsule(event)
            clearCapsuleClickCandidate()
            if !ownsPetPointerTracking || !startedInsideCapsule {
                super.sendEvent(event)
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
            let petWidth: CGFloat = min(240, bounds.width)
            let petHeight: CGFloat = min(154, bounds.height)
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
        usesCompactHitRegion || (
            frame.width >= 220 && frame.width <= 260
                && frame.height >= 135 && frame.height <= 175
        )
    }

    /// 迷你宠物展开实时对话后，窗口会变高，但宠物仍固定在右上角。
    /// 只把该区域识别成胶囊，避免拦截下方对话的滚动和关闭按钮。
    private var isPetConversationLayout: Bool {
        frame.width >= 315 && frame.width <= 355
            && frame.height >= 385 && frame.height <= 435
    }

    private func clampedCompactOrigin(_ proposed: NSPoint) -> NSPoint {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return proposed }
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
    private let frameKey = "pulse.capsule.frame"
    private let visibleKey = "pulse.capsule.visible"

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

        let content = CapsuleHostView(onSizeChange: { [weak self] size in
            self?.resizePanel(to: size)
        }) {
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
        panel.onCapsuleClick = {
            NotificationCenter.default.post(name: .pulseCapsuleToggleDetails, object: nil)
        }
        panel.onCapsuleDoubleClick = {
            NotificationCenter.default.post(name: .pulseCapsuleToggleMini, object: nil)
        }
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.persistFrame() }
        }

        self.panel = panel
        panel.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: visibleKey)
    }

    /// SwiftUI 展开/收起时同步调整无边框面板尺寸，并固定右上角，避免详情卡被旧窗口裁掉。
    private func resizePanel(to contentSize: CGSize) {
        guard let panel,
              contentSize.width > 1,
              contentSize.height > 1 else { return }

        let oldFrame = panel.frame
        let targetUsesCompactHitRegion = isCompactPetSize(contentSize)
        (panel as? InteractiveCapsulePanel)?.usesCompactHitRegion = targetUsesCompactHitRegion
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
        if isMiniMorph && !isPetConversationMorph && !reduceMotion {
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
        frame.width >= 225 && frame.width <= 255
            && frame.height >= 140 && frame.height <= 170
    }

    private func isPetConversationFrame(_ frame: NSRect) -> Bool {
        frame.width >= 315 && frame.width <= 355
            && frame.height >= 385 && frame.height <= 435
    }

    private func isCompactPetSize(_ size: CGSize) -> Bool {
        size.width >= 225 && size.width <= 255
            && size.height >= 140 && size.height <= 170
    }

    func hide() {
        persistFrame()
        panel?.orderOut(nil)
        panel = nil
        UserDefaults.standard.set(false, forKey: visibleKey)
    }

    func suppressNextCapsuleClick() {
        (panel as? InteractiveCapsulePanel)?.suppressNextCapsuleClick()
    }

    // MARK: - 位置持久化

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
    let onSizeChange: (CGSize) -> Void
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
                Button("打开看板") { openDashboard() }
                Divider()
                Button("隐藏胶囊") {
                    FloatingCapsuleController.shared.hide()
                }
            }
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
