import AppKit
import QuartzCore
import SwiftUI

enum PetAnimationState: String {
    case idle
    case thinking
    case running
    case waiting
    case waitingAuthorization = "waiting_auth"
    case success
    case error
    case sleeping
    case stretch
    case grooming
    case hop
    case wave
    case curious

    func legacyResourceSuffix(for character: PetCharacter) -> String {
        guard character != .cat && character != .fox else { return rawValue }
        switch self {
        case .thinking, .running:
            return "typing"
        case .waiting, .waitingAuthorization:
            return "auth"
        case .curious, .grooming, .stretch:
            return "scratch"
        case .idle, .success, .error, .sleeping, .hop, .wave:
            return "idle"
        }
    }
}

struct PetWorkingAnimationSample {
    let frame: Int
    let nextFrame: Int
    let frameBlend: Double
    let leftKeyStrength: Double
    let rightKeyStrength: Double
}

enum PetWorkingCadence {
    /// One deliberate left tap, one deliberate right tap, then a readable
    /// pause. The light is tied to the two actual contact frames.
    private static let frameDurations = [
        0.52, 0.22, 0.18, 0.34,
        0.22, 0.18, 0.34, 0.80,
    ]

    static func sample(at elapsed: Double) -> PetWorkingAnimationSample {
        let total = frameDurations.reduce(0, +)
        var cursor = elapsed.truncatingRemainder(dividingBy: total)
        if cursor < 0 { cursor += total }

        for (frame, duration) in frameDurations.enumerated() {
            if cursor < duration {
                let progress = max(0, min(1, cursor / duration))
                let contact = sin(progress * .pi)
                let rawBlend = max(0, min(1, (progress - 0.52) / 0.48))
                let frameBlend = rawBlend * rawBlend * (3 - 2 * rawBlend)
                return PetWorkingAnimationSample(
                    frame: frame,
                    nextFrame: (frame + 1) % frameDurations.count,
                    frameBlend: frameBlend,
                    leftKeyStrength: frame == 2 ? contact : 0,
                    rightKeyStrength: frame == 5 ? contact : 0
                )
            }
            cursor -= duration
        }
        return PetWorkingAnimationSample(
            frame: 7,
            nextFrame: 0,
            frameBlend: 0,
            leftKeyStrength: 0,
            rightKeyStrength: 0
        )
    }
}

/// 小猫空闲态的轻量场景状态。只有小猫试验版会使用这些状态，
/// 其余宠物继续沿用原来的固定展示逻辑。
enum CatRoamingActivity: String, Sendable {
    case resting
    case strolling
    case investigating
    case pawingDesktopItem
    case dockPlay
    case dockPounce
    case sleeping
    case stretching
    case grooming
    case waving
    case hopping
}

struct CatRoamingVisualUpdate: Sendable {
    let activity: CatRoamingActivity
    let facesLeft: Bool
}

/// 480×288 像素宠物场景按 45% 显示。V2 宠物素材只负责角色动作，
/// 数值载体由程序固定绘制，因此实时内容不会随 GIF 换帧跳位。
/// 每种角色拥有独立载体外形，但都留在场景右侧的安全区域内。
struct PetCapsuleView: View {
    let character: PetCharacter
    let animationState: PetAnimationState
    let idleStyle: MiniCapsuleStyle
    let orbPage: OrbPetPage
    let idleValue: String
    let idleProgress: Double
    let idleColor: Color
    let idleHelp: String
    let showsIdleContent: Bool
    let activeQuotaValue: String?
    let activeQuotaColor: Color
    let reduceMotion: Bool
    let catRoamingActivity: CatRoamingActivity
    let catFacesLeft: Bool
    let showsTransientMonitor: Bool
    let growthScale: CGFloat

    private var sceneSize: CGSize {
        character == .blackHole
            ? CGSize(width: 216, height: 184)
            : CGSize(width: 216, height: 129.6)
    }

    private var resolvedGrowthScale: CGFloat {
        min(10, max(1, growthScale))
    }

    private var grownSceneSize: CGSize {
        CGSize(
            width: sceneSize.width * resolvedGrowthScale,
            height: sceneSize.height * resolvedGrowthScale
        )
    }

    private var displayFrame: CGRect {
        switch character {
        case .dino: return CGRect(x: 126, y: 23, width: 76, height: 34)
        case .cat: return CGRect(x: 123, y: 17, width: 81, height: 36)
        case .bunny: return CGRect(x: 122, y: 21, width: 82, height: 34)
        case .ghost: return CGRect(x: 125, y: 17, width: 79, height: 36)
        case .robot: return CGRect(x: 122, y: 21, width: 82, height: 34)
        case .fox: return CGRect(x: 124, y: 19, width: 80, height: 34)
        case .orb, .orb2, .orb3, .orb4: return .zero
        case .blackHole: return .zero
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            petArtwork

            if shouldShowMonitor {
                programmaticMonitor
                    .transition(
                        .scale(scale: 0.76, anchor: .bottomLeading)
                            .combined(with: .opacity)
                    )

                ZStack {
                    Text(monitorValue)
                        .font(monitorValueFont)
                        .monospacedDigit()
                        .foregroundStyle(monitorColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .id(monitorValue)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                        .shadow(color: monitorColor.opacity(0.45), radius: 0.8)
                }
                .frame(
                    width: displayFrame.width,
                    height: displayFrame.height,
                    alignment: .center
                )
                .clipped()
                .offset(x: displayFrame.minX, y: displayFrame.minY)
                .transition(.opacity)
            }

            catSceneAccent
        }
        .frame(
            width: character == .blackHole ? grownSceneSize.width : sceneSize.width,
            height: character == .blackHole ? grownSceneSize.height : sceneSize.height
        )
        .scaleEffect(character == .blackHole ? 1 : resolvedGrowthScale)
        .frame(width: grownSceneSize.width, height: grownSceneSize.height)
        .contentShape(Rectangle())
        .animation(
            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82),
            value: resolvedGrowthScale
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
            value: shouldShowMonitor
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.24),
            value: monitorValue
        )
        .help(
            "\(character.displayName) · 成长 \(Int((resolvedGrowthScale * 100).rounded()))% · \(idleHelp) · 双击恢复完整胶囊"
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(character.displayName)，成长 \(Int((resolvedGrowthScale * 100).rounded()))%，\(showsIdleContent ? idleHelp : animationStateLabel)"
        )
        .accessibilityHint("双击恢复完整胶囊")
        .dropDestination(for: URL.self) { urls, _ in
            guard character == .blackHole else { return false }
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            NotificationCenter.default.post(
                name: .pulseBlackHoleDrop,
                object: BlackHoleDropEvent(
                    phase: .absorbed,
                    fileCount: files.count
                )
            )
            NSWorkspace.shared.recycle(files) { _, error in
                if let error {
                    PulseLog.write(
                        "black-hole trash failed: \(error.localizedDescription)"
                    )
                    NotificationCenter.default.post(
                        name: .pulseBlackHoleDrop,
                        object: BlackHoleDropEvent(
                            phase: .failed,
                            fileCount: files.count
                        )
                    )
                } else {
                    PulseLog.write(
                        "black-hole moved \(files.count) item(s) to Trash"
                    )
                }
            }
            return true
        } isTargeted: { targeted in
            guard character == .blackHole else { return }
            NotificationCenter.default.post(
                name: .pulseBlackHoleDrop,
                object: BlackHoleDropEvent(
                    phase: targeted ? .targeting : .idle,
                    fileCount: 0
                )
            )
        }
    }

    private var petArtwork: some View {
        Group {
            if character == .blackHole {
                BlackHolePetView(
                    animationState: animationState,
                    reduceMotion: reduceMotion,
                    sceneSize: grownSceneSize,
                    roamingActivity: catRoamingActivity,
                    facesLeft: catFacesLeft
                )
            } else if character.isOrb {
                OrbPetView(
                    style: OrbPetStyle(rawValue: character.orbStyleIndex ?? 1) ?? .glassRing,
                    animationState: animationState,
                    page: orbPage,
                    value: idleValue,
                    progress: idleProgress,
                    dataColor: idleColor,
                    reduceMotion: reduceMotion
                )
            } else if character == .cat {
                ProceduralCatView(
                    animationState: animationState,
                    roamingActivity: catRoamingActivity,
                    facesLeft: catFacesLeft,
                    showsIdleContent: showsIdleContent,
                    reduceMotion: reduceMotion
                )
            } else {
                AnimePetView(
                    character: character,
                    animationState: animationState,
                    roamingActivity: catRoamingActivity,
                    facesLeft: catFacesLeft,
                    showsIdleContent: showsIdleContent,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
    }

    @ViewBuilder
    private var catSceneAccent: some View {
        if character == .cat, showsIdleContent {
            switch catRoamingActivity {
            case .investigating:
                HStack(spacing: 2.5) {
                    Circle().frame(width: 2.5, height: 2.5)
                    Circle().frame(width: 3.5, height: 3.5)
                    Circle().frame(width: 2.5, height: 2.5)
                }
                .foregroundStyle(Color.white.opacity(0.74))
                .offset(x: 87, y: 84)
                .transition(.opacity)

            case .pawingDesktopItem, .dockPlay, .dockPounce:
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.8))
                    .offset(x: 85, y: 80)
                    .transition(.scale.combined(with: .opacity))

            case .resting, .strolling, .sleeping, .stretching, .grooming, .waving, .hopping:
                EmptyView()
            }
        }
        if character == .fox, showsIdleContent {
            switch catRoamingActivity {
            case .investigating:
                HStack(spacing: 3) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 2, height: 2)
                }
                .foregroundStyle(Color(red: 0.42, green: 0.80, blue: 0.96).opacity(0.6))
                .offset(x: 88, y: 82)
                .transition(.opacity)

            case .pawingDesktopItem, .dockPlay, .dockPounce:
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.90, blue: 1.0).opacity(0.75))
                    .offset(x: 85, y: 80)
                    .transition(.scale.combined(with: .opacity))

            default:
                EmptyView()
            }
        }
    }

    private var shouldShowMonitor: Bool {
        guard character != .blackHole, !character.isOrb else { return false }
        return (character != .cat && character != .fox)
            || !showsIdleContent
            || showsTransientMonitor
    }

    private var monitorValue: String {
        guard !showsIdleContent else { return idleValue }
        if let activeQuotaValue { return activeQuotaValue }
        switch animationState {
        case .thinking: return "思考中"
        case .running: return "工作中"
        case .waiting: return "等待输入"
        case .waitingAuthorization: return "等待授权"
        case .success: return "完成啦"
        case .error: return "出错了"
        case .sleeping: return "打盹"
        case .stretch: return "伸懒腰"
        case .grooming: return "整理毛发"
        case .hop: return "玩耍"
        case .wave: return "你好"
        case .curious: return "看看"
        case .idle: return idleValue
        }
    }

    private var monitorColor: Color {
        guard !showsIdleContent else { return idleColor }
        if activeQuotaValue != nil { return activeQuotaColor }
        return animationState == .waitingAuthorization || animationState == .error
            ? PulseTheme.red
            : PulseTheme.orange
    }

    private var monitorValueFont: Font {
        guard showsIdleContent else {
            if activeQuotaValue != nil {
                return .system(size: 10.5, weight: .bold, design: .rounded)
            }
            return .system(
                size: animationState == .waitingAuthorization ? 9.5 : 11,
                weight: .bold,
                design: .rounded
            )
        }
        return idleValueFont
    }

    @ViewBuilder
    private var programmaticMonitor: some View {
        switch character {
        case .dino:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(red: 0.025, green: 0.045, blue: 0.065).opacity(0.96))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(red: 0.35, green: 0.82, blue: 1).opacity(0.72), lineWidth: 0.8)
                Rectangle()
                    .fill(Color.cyan.opacity(0.7))
                    .frame(width: 14, height: 1)
                    .offset(x: -44, y: 9)
                HStack(spacing: 3) {
                    Circle().fill(Color.cyan)
                    Circle().fill(Color.gray.opacity(0.7))
                    Circle().fill(Color.gray.opacity(0.42))
                }
                .frame(height: 3)
                .offset(y: 6)
            }
            .monitorFrame(displayFrame)

        case .cat:
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.10, blue: 0.19).opacity(0.96))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color(red: 0.77, green: 0.63, blue: 1).opacity(0.82), lineWidth: 0.9)
                PetBubbleTail()
                    .fill(Color(red: 0.12, green: 0.10, blue: 0.19).opacity(0.98))
                    .frame(width: 12, height: 9)
                    .offset(x: -4, y: 5)
            }
            .monitorFrame(displayFrame)

        case .bunny:
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.13, green: 0.075, blue: 0.055).opacity(0.96))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(red: 1, green: 0.55, blue: 0.27).opacity(0.84), lineWidth: 0.9)
                HStack(spacing: 1) {
                    Capsule().fill(Color.green.opacity(0.86)).frame(width: 2, height: 7).rotationEffect(.degrees(-28))
                    Capsule().fill(Color.green.opacity(0.68)).frame(width: 2, height: 7).rotationEffect(.degrees(24))
                }
                .offset(x: 2, y: -5)
            }
            .monitorFrame(displayFrame)

        case .ghost:
            ZStack(alignment: .bottomLeading) {
                Capsule(style: .continuous)
                    .fill(Color(red: 0.055, green: 0.09, blue: 0.15).opacity(0.9))
                Capsule(style: .continuous)
                    .stroke(Color.cyan.opacity(0.66), lineWidth: 0.8)
                HStack(spacing: 2) {
                    Circle().fill(Color.cyan.opacity(0.28)).frame(width: 3, height: 3)
                    Circle().fill(Color.cyan.opacity(0.5)).frame(width: 4, height: 4)
                }
                .offset(x: -9, y: 8)
            }
            .monitorFrame(displayFrame)

        case .robot:
            ZStack {
                PetHUDShape()
                    .fill(Color(red: 0.025, green: 0.055, blue: 0.09).opacity(0.98))
                PetHUDShape()
                    .stroke(Color(red: 0.28, green: 0.9, blue: 1).opacity(0.82), lineWidth: 0.9)
                HStack(spacing: 2) {
                    Rectangle().fill(Color.cyan).frame(width: 4, height: 1)
                    Rectangle().fill(Color.cyan.opacity(0.45)).frame(width: 7, height: 1)
                }
                .offset(x: 24, y: -13)
            }
            .monitorFrame(displayFrame)

        case .fox:
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.16, green: 0.36, blue: 0.54).opacity(0.94),
                                Color(red: 0.07, green: 0.17, blue: 0.28).opacity(0.97)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.90, blue: 1.0).opacity(0.9),
                                Color(red: 0.25, green: 0.60, blue: 0.85).opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
                Circle()
                    .fill(Color(red: 0.65, green: 0.95, blue: 1.0).opacity(0.9))
                    .frame(width: 3, height: 3)
                    .offset(x: -31, y: -11)
                Circle()
                    .fill(Color(red: 0.45, green: 0.75, blue: 0.95).opacity(0.6))
                    .frame(width: 2, height: 2)
                    .offset(x: 31, y: 11)
            }
            .monitorFrame(displayFrame)

        case .orb, .orb2, .orb3, .orb4, .blackHole:
            EmptyView()
        }
    }

    private var idleValueFont: Font {
        switch idleStyle {
        case .status:
            return .system(size: 21, weight: .bold, design: .rounded)
        case .time:
            return .system(size: 13.8, weight: .bold, design: .monospaced)
        case .tokens:
            return .system(size: 15, weight: .bold, design: .rounded)
        case .quota, .weather:
            return .system(size: 18, weight: .bold, design: .rounded)
        }
    }

    private var animationStateLabel: String {
        switch animationState {
        case .idle: return "空闲"
        case .thinking: return "思考中"
        case .running: return "工作中"
        case .waiting: return "等待输入"
        case .waitingAuthorization: return "等待授权"
        case .success: return "完成"
        case .error: return "出错"
        case .sleeping: return "打盹"
        case .stretch: return "伸懒腰"
        case .grooming: return "整理毛发"
        case .hop: return "小跳"
        case .wave: return "挥爪"
        case .curious: return "好奇巡视"
        }
    }
}

private extension View {
    func monitorFrame(_ frame: CGRect) -> some View {
        self
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }
}

private struct PetBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.35, y: rect.height * 0.45)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.55))
        path.closeSubpath()
        return path
    }
}

private struct PetHUDShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut: CGFloat = 6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

private struct AnimatedPetGIFView: NSViewRepresentable {
    let resourceName: String
    let reduceMotion: Bool

    func makeNSView(context: Context) -> CrossfadingPetImageView {
        CrossfadingPetImageView()
    }

    func updateNSView(_ imageView: CrossfadingPetImageView, context: Context) {
        imageView.setResource(resourceName, reduceMotion: reduceMotion)
    }
}

/// `NSImageView` defaults its intrinsic size to the GIF's 480×288 canvas. A SwiftUI
/// frame would then clip the centered native view instead of shrinking the whole scene.
/// Removing that intrinsic size lets the representable accept the compact proposal and
/// keeps every pet plus its monitor visible inside the compact panel.
private final class ScalableAnimatedImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Two transparent image layers crossfade state changes while the panel keeps a
/// stable size. This removes the one-frame pose flash that occurs when an
/// animated NSImage is replaced in place.
private final class CrossfadingPetImageView: NSView {
    private var foreground = ScalableAnimatedImageView()
    private var background = ScalableAnimatedImageView()
    private var resourceName: String?
    private var transitionGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configure(background)
        configure(foreground)
        background.alphaValue = 0
        addSubview(background)
        addSubview(foreground)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        foreground.frame = bounds
        background.frame = bounds
    }

    func setResource(_ name: String, reduceMotion: Bool) {
        foreground.animates = !reduceMotion
        background.animates = !reduceMotion
        guard resourceName != name else { return }
        resourceName = name
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let image = NSImage(contentsOf: url) else {
            foreground.image = nil
            background.image = nil
            return
        }

        guard foreground.image != nil, !reduceMotion else {
            foreground.image = image
            foreground.alphaValue = 1
            foreground.animates = !reduceMotion
            background.image = nil
            background.alphaValue = 0
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        background.image = image
        background.animates = true
        background.alphaValue = 0
        background.layer?.zPosition = 2
        foreground.layer?.zPosition = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            foreground.animator().alphaValue = 0
            background.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            let previousForeground = self.foreground
            self.foreground = self.background
            self.background = previousForeground
            self.background.image = nil
            self.background.alphaValue = 0
            self.foreground.alphaValue = 1
            self.foreground.layer?.zPosition = 2
            self.background.layer?.zPosition = 1
        }
    }

    private func configure(_ imageView: ScalableAnimatedImageView) {
        imageView.imageFrameStyle = .none
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.layer?.minificationFilter = .nearest
        imageView.layer?.magnificationFilter = .nearest
    }
}
