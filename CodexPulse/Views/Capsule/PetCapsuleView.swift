import AppKit
import SwiftUI

enum PetAnimationState: String {
    case idle
    case thinking
    case scratch
    case authorization = "auth"

    var richResourceSuffix: String {
        self == .thinking ? "typing" : rawValue
    }
}

/// 480×288 像素宠物场景按 45% 显示。V2 宠物素材只负责角色动作，
/// 数值载体由程序固定绘制，因此实时内容不会随 GIF 换帧跳位。
/// 每种角色拥有独立载体外形，但都留在场景右侧的安全区域内。
struct PetCapsuleView: View {
    let character: PetCharacter
    let animationState: PetAnimationState
    let idleStyle: MiniCapsuleStyle
    let idleValue: String
    let idleColor: Color
    let idleHelp: String
    let showsIdleContent: Bool
    let activeQuotaValue: String?
    let activeQuotaColor: Color
    let reduceMotion: Bool

    private let sceneSize = CGSize(width: 216, height: 129.6)

    private var displayFrame: CGRect {
        switch character {
        case .dino: return CGRect(x: 126, y: 23, width: 76, height: 34)
        case .cat: return CGRect(x: 123, y: 17, width: 81, height: 36)
        case .bunny: return CGRect(x: 122, y: 21, width: 82, height: 34)
        case .ghost: return CGRect(x: 125, y: 17, width: 79, height: 36)
        case .robot: return CGRect(x: 122, y: 21, width: 82, height: 34)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AnimatedPetGIFView(
                resourceName: animationResourceName,
                reduceMotion: reduceMotion
            )
            .frame(width: sceneSize.width, height: sceneSize.height)

            programmaticMonitor

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
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.24),
                value: monitorValue
            )
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
        .contentShape(Rectangle())
        .help("\(character.displayName) · \(idleHelp) · 双击恢复完整胶囊")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.displayName)，\(showsIdleContent ? idleHelp : animationStateLabel)")
        .accessibilityHint("双击恢复完整胶囊")
    }

    private var animationResourceName: String {
        "codex_\(character.rawValue)_v2_\(animationState.richResourceSuffix)"
    }

    private var monitorValue: String {
        guard !showsIdleContent else { return idleValue }
        if let activeQuotaValue { return activeQuotaValue }
        switch animationState {
        case .thinking: return "思考中"
        case .scratch: return "想一下"
        case .authorization: return "等待授权"
        case .idle: return idleValue
        }
    }

    private var monitorColor: Color {
        guard !showsIdleContent else { return idleColor }
        if activeQuotaValue != nil { return activeQuotaColor }
        return animationState == .authorization ? PulseTheme.red : PulseTheme.orange
    }

    private var monitorValueFont: Font {
        guard showsIdleContent else {
            if activeQuotaValue != nil {
                return .system(size: 10.5, weight: .bold, design: .rounded)
            }
            return .system(size: animationState == .authorization ? 9.5 : 11, weight: .bold, design: .rounded)
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
        case .scratch: return "挠头思考"
        case .authorization: return "等待授权"
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

    final class Coordinator {
        var resourceName: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = ScalableAnimatedImageView()
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
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        imageView.animates = !reduceMotion
        guard context.coordinator.resourceName != resourceName else { return }
        context.coordinator.resourceName = resourceName
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "gif") else {
            imageView.image = nil
            return
        }
        imageView.image = NSImage(contentsOf: url)
        imageView.animates = !reduceMotion
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
