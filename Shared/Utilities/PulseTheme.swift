import SwiftUI

// MARK: - Design tokens (see design-system/MASTER.md)

enum PulseTheme {
    static let green = Color(hex: 0x30D158)
    static let blue = Color(hex: 0x0A84FF)
    static let yellow = Color(hex: 0xFFD60A)
    static let orange = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)
    static let gray = Color(hex: 0x8E8E93)

    static let radiusPopover: CGFloat = 16
    static let radiusCard: CGFloat = 20
    static let radiusWidget: CGFloat = 24
    static let radiusBar: CGFloat = 99

    static func status(_ color: PulseStatusColor) -> Color {
        switch color {
        case .green: return green
        case .blue: return blue
        case .yellow: return yellow
        case .red: return red
        case .gray: return gray
        }
    }

    static func usage(_ remainingPercent: Double) -> Color {
        // 剩余：≥80% 绿 · 20–80% 橙 · <20% 红
        switch UsageLevel.fromRemaining(remainingPercent) {
        case .healthy: return green
        case .caution, .warning: return orange
        case .critical, .exhausted: return red
        }
    }
}

private struct PulseVisualThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: PulseVisualTheme = .classic
}

extension EnvironmentValues {
    var pulseVisualTheme: PulseVisualTheme {
        get { self[PulseVisualThemeEnvironmentKey.self] }
        set { self[PulseVisualThemeEnvironmentKey.self] = newValue }
    }
}

extension PulseVisualTheme {
    var accent: Color {
        switch self {
        case .classic: return PulseTheme.blue
        case .midnight: return Color(hex: 0x45B7FF)
        case .graphite: return Color(hex: 0xAEB7C2)
        case .forest: return Color(hex: 0x4DE0B1)
        case .amethyst: return Color(hex: 0xB68CFF)
        }
    }

    var surfaceTint: Color {
        switch self {
        case .classic: return .clear
        case .midnight: return Color(hex: 0x155A91).opacity(0.18)
        case .graphite: return Color(hex: 0x777E86).opacity(0.12)
        case .forest: return Color(hex: 0x25725C).opacity(0.17)
        case .amethyst: return Color(hex: 0x6C4499).opacity(0.17)
        }
    }

    func dashboardCardTint(for colorScheme: ColorScheme) -> Color {
        if self == .classic {
            return colorScheme == .dark
                ? Color(hex: 0x111925).opacity(0.54)
                : Color.white.opacity(0.38)
        }
        return surfaceTint.opacity(colorScheme == .dark ? 1 : 0.62)
    }

    func backdropColors(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .light {
            switch self {
            case .classic: return [Color(hex: 0xF4F8FC), Color(hex: 0xE7EEF6)]
            case .midnight: return [Color(hex: 0xEAF5FF), Color(hex: 0xDDECF8)]
            case .graphite: return [Color(hex: 0xF2F3F4), Color(hex: 0xE5E7E9)]
            case .forest: return [Color(hex: 0xEAF7F1), Color(hex: 0xDCEBE5)]
            case .amethyst: return [Color(hex: 0xF4EEFB), Color(hex: 0xE8E0F3)]
            }
        }
        switch self {
        case .classic: return [Color(hex: 0x0D1521), Color(hex: 0x080C12)]
        case .midnight: return [Color(hex: 0x0B243C), Color(hex: 0x050F1C)]
        case .graphite: return [Color(hex: 0x25282C), Color(hex: 0x151719)]
        case .forest: return [Color(hex: 0x0D3029), Color(hex: 0x061B18)]
        case .amethyst: return [Color(hex: 0x2B1B43), Color(hex: 0x170E25)]
        }
    }
}

extension PulseAppearanceMode {
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme surfaces

enum PulseSurfaceRole {
    case capsule
    case panel
    case card
}

/// 五套主题不仅切换颜色，也分别使用玻璃、HUD、哑光、柔雾与棱镜材质。
struct PulseThemedSurface<S: InsettableShape>: View {
    @Environment(\.pulseVisualTheme) private var visualTheme
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let role: PulseSurfaceRole
    var prominent = false
    var castsShadow = true

    var body: some View {
        ZStack {
            base
            texture
            border
            highlight
        }
        .clipShape(shape)
        .shadow(color: castsShadow ? shadowColor : .clear, radius: castsShadow ? shadowRadius : 0, y: castsShadow ? shadowY : 0)
        .shadow(color: castsShadow ? rimShadowColor : .clear, radius: castsShadow ? rimShadowRadius : 0)
    }

    @ViewBuilder
    private var base: some View {
        switch visualTheme {
        case .classic:
            switch role {
            case .capsule: shape.fill(.thinMaterial)
            case .panel: shape.fill(prominent ? .regularMaterial : .ultraThinMaterial)
            case .card: shape.fill(.regularMaterial)
            }
        case .midnight:
            shape.fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: 0x123A5B).opacity(0.96), Color(hex: 0x061421).opacity(0.98)]
                        : [Color(hex: 0xF0F9FF).opacity(0.96), Color(hex: 0xDCEFFA).opacity(0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .graphite:
            shape.fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: 0x454A50), Color(hex: 0x25292D)]
                        : [Color(hex: 0xF2F3F4), Color(hex: 0xD6D9DC)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .forest:
            shape.fill(.thinMaterial)
            shape.fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: 0x285C4E).opacity(0.82), Color(hex: 0x0A2B25).opacity(0.9)]
                        : [Color(hex: 0xE8F8F0).opacity(0.82), Color(hex: 0xCDE9DE).opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .amethyst:
            shape.fill(.regularMaterial)
            shape.fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: 0x543579).opacity(0.86), Color(hex: 0x1D102F).opacity(0.93)]
                        : [Color(hex: 0xF2E7FF).opacity(0.9), Color(hex: 0xDCDFF8).opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    @ViewBuilder
    private var texture: some View {
        switch visualTheme {
        case .classic:
            if role == .capsule {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), .clear, Color.black.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        case .midnight:
            PulseScanlineTexture(color: visualTheme.accent)
                .clipShape(shape)
            shape.fill(
                RadialGradient(
                    colors: [visualTheme.accent.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: role == .capsule ? 150 : 360
                )
            )
        case .graphite:
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.1), .clear, Color.black.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .forest:
            shape.fill(
                RadialGradient(
                    colors: [Color(hex: 0x8AF0C8).opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: role == .capsule ? 130 : 320
                )
            )
            shape.fill(
                RadialGradient(
                    colors: [Color(hex: 0x1A9B7B).opacity(0.12), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: role == .capsule ? 150 : 360
                )
            )
        case .amethyst:
            shape.fill(
                AngularGradient(
                    colors: [
                        Color(hex: 0xFF5FC7).opacity(0.12),
                        Color(hex: 0x67A7FF).opacity(0.16),
                        Color(hex: 0xB66FFF).opacity(0.12),
                        Color(hex: 0xFF5FC7).opacity(0.12)
                    ],
                    center: .topTrailing
                )
            )
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.13), .clear, Color(hex: 0x72D7FF).opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    @ViewBuilder
    private var border: some View {
        switch visualTheme {
        case .classic:
            shape.strokeBorder(
                LinearGradient(
                    colors: role == .capsule
                        ? [Color.white.opacity(0.6), Color.white.opacity(0.15), Color.white.opacity(0.06)]
                        : role == .panel
                            ? [Color.white.opacity(0.55), Color.white.opacity(0.18), Color.white.opacity(0.08)]
                            : [Color.white.opacity(0.28), Color.white.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: role == .capsule ? 1.2 : 1
            )
        case .midnight:
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.34), visualTheme.accent.opacity(0.7), visualTheme.accent.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
            )
            shape.inset(by: 2).strokeBorder(visualTheme.accent.opacity(0.12), lineWidth: 0.6)
        case .graphite:
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.05), Color.black.opacity(0.44)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
            shape.inset(by: 2).strokeBorder(Color.black.opacity(0.2), lineWidth: 0.6)
        case .forest:
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.38), visualTheme.accent.opacity(0.38), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
            )
        case .amethyst:
            shape.strokeBorder(
                AngularGradient(colors: [Color(hex: 0xFF83D5), Color(hex: 0x72D8FF), Color(hex: 0xB77AFF), Color(hex: 0xFF83D5)], center: .center),
                lineWidth: role == .capsule ? 1.2 : 1
            )
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if visualTheme == .classic, role == .panel {
            VStack {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        } else if visualTheme == .graphite {
            shape.inset(by: 1).strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34), lineWidth: 0.7)
        }
    }

    private var shadowColor: Color {
        switch visualTheme {
        case .classic: return .black.opacity(role == .panel ? 0.16 : 0.08)
        case .midnight: return Color(hex: 0x0A84D8).opacity(0.18)
        case .graphite: return .black.opacity(0.18)
        case .forest: return Color(hex: 0x062B21).opacity(0.18)
        case .amethyst: return Color(hex: 0x6D24B8).opacity(0.2)
        }
    }

    private var shadowRadius: CGFloat {
        if visualTheme == .classic { return role == .panel ? 22 : 12 }
        switch visualTheme {
        case .midnight: return 18
        case .graphite: return 8
        case .forest: return 24
        case .amethyst: return 20
        case .classic: return 12
        }
    }

    private var shadowY: CGFloat {
        visualTheme == .graphite ? 3 : (role == .panel ? 10 : 5)
    }

    private var rimShadowColor: Color {
        switch visualTheme {
        case .midnight, .forest, .amethyst: return visualTheme.accent.opacity(0.08)
        case .classic, .graphite: return .clear
        }
    }

    private var rimShadowRadius: CGFloat {
        visualTheme == .graphite || visualTheme == .classic ? 0 : 8
    }
}

private struct PulseScanlineTexture: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 4
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color.opacity(0.045)), lineWidth: 0.5)
                y += 7
            }
        }
        .allowsHitTesting(false)
    }
}

/// Menu bar / floating panel themed surface.
struct GlassPanelBackground: View {
    var cornerRadius: CGFloat = PulseTheme.radiusPopover
    var prominent: Bool = false

    var body: some View {
        PulseThemedSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            role: .panel,
            prominent: prominent
        )
    }
}

/// Dashboard / bento tile themed surface.
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = PulseTheme.radiusCard

    var body: some View {
        PulseThemedSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            role: .card
        )
    }
}

// MARK: - Signature: liquid progress bar（按「剩余」百分比填充与上色）

struct LiquidProgressBar: View {
    /// 剩余百分比 0…100
    let remainingPercent: Double
    var height: CGFloat = 8
    var animated: Bool = true

    /// 兼容旧参数名
    init(percent: Double, height: CGFloat = 8, animated: Bool = true) {
        self.remainingPercent = percent
        self.height = height
        self.animated = animated
    }

    init(remainingPercent: Double, height: CGFloat = 8, animated: Bool = true) {
        self.remainingPercent = remainingPercent
        self.height = height
        self.animated = animated
    }

    private var clamped: Double { min(100, max(0, remainingPercent)) }
    private var tint: Color { PulseTheme.usage(clamped) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * CGFloat(clamped / 100)))
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .allowsHitTesting(false)
                    }
                    .shadow(color: tint.opacity(0.45), radius: 6, y: 0)
            }
        }
        .frame(height: height)
        .animation(animated ? .easeOut(duration: 0.55) : nil, value: clamped)
    }
}

// MARK: - Status orb

struct StatusOrb: View {
    let color: PulseStatusColor
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(PulseTheme.status(color))
            .frame(width: size, height: size)
            .shadow(color: PulseTheme.status(color).opacity(0.65), radius: 5)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            }
    }
}

// MARK: - Color hex (shared)

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
