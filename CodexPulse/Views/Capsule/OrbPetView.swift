import SwiftUI

enum OrbPetPage: String, CaseIterable, Sendable {
    case quota
    case tokens
    case weather
    case temperature
    case time

    var next: OrbPetPage {
        let pages = Self.allCases
        let index = pages.firstIndex(of: self) ?? 0
        return pages[(index + 1) % pages.count]
    }
}

enum OrbPetStyle: Int, CaseIterable, Sendable {
    case glassRing = 1
    case dashedRing = 2
    case liquid = 3
    case darkDial = 4

    var displayName: String {
        "小圆球\(rawValue)"
    }
}

/// 四款小圆球共享数据轮播、圆形点击区域、固定位置和固定大小。
/// 视觉层全部由 SwiftUI 绘制，不依赖位图，也不参与 Token 成长。
struct OrbPetView: View {
    let style: OrbPetStyle
    let animationState: PetAnimationState
    let page: OrbPetPage
    let value: String
    let progress: Double
    let dataColor: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            orb(at: timeline.date)
        }
        .frame(width: 216, height: 129.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.displayName)，\(pageLabel)，\(value)")
    }

    private func orb(at date: Date) -> some View {
        let elapsed = date.timeIntervalSinceReferenceDate
        let phase = elapsed.truncatingRemainder(dividingBy: breathingDuration)
            / breathingDuration
        let brightness = reduceMotion
            ? 0
            : sin(phase * .pi * 2) * brightnessAmplitude
        let ringRotation = reduceMotion || !rotatesInformationArc
            ? 0
            : elapsed.truncatingRemainder(dividingBy: rotationDuration)
                / rotationDuration * 360
        let wavePhase = reduceMotion ? 0 : elapsed * 1.65

        return ZStack {
            background
            decoration(wavePhase: wavePhase)
        }
        .frame(width: 62, height: 62)
        .rotationEffect(.degrees(ringRotation))
        .overlay {
            centeredValue
                .foregroundStyle(valueColor)
                .frame(width: 49, height: 62, alignment: .center)
                .shadow(
                    color: style == .darkDial
                        ? Color.black.opacity(0.65)
                        : Color.white.opacity(0.65),
                    radius: 0.8,
                    y: 0.4
                )
                .allowsHitTesting(false)
        }
        .brightness(brightness)
        .opacity(animationState == .sleeping ? 0.72 : 1)
        .shadow(color: outerShadowColor, radius: outerShadowRadius, y: 2)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.24),
            value: value
        )
    }

    @ViewBuilder
    private var centeredValue: some View {
        if let tokenParts {
            VStack(spacing: -0.5) {
                Text(tokenParts.number)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if !tokenParts.unit.isEmpty {
                    Text(tokenParts.unit)
                        .font(.system(size: 6.5, weight: .bold, design: .rounded))
                        .opacity(0.72)
                }
            }
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
        } else {
            Text(value)
                .font(valueFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .contentTransition(.numericText(countsDown: false))
        }
    }

    private var tokenParts: (number: String, unit: String)? {
        guard page == .tokens else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suffix = trimmed.last, "KMB".contains(suffix) else {
            return (trimmed, "")
        }
        return (String(trimmed.dropLast()), String(suffix))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .glassRing, .dashedRing:
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.52),
                            Color(red: 0.81, green: 0.90, blue: 0.96).opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            glassHighlight

        case .liquid:
            Circle()
                .fill(Color(red: 0.94, green: 0.97, blue: 0.99).opacity(0.94))
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
            glassHighlight

        case .darkDial:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.13, green: 0.20, blue: 0.31),
                            Color(red: 0.045, green: 0.075, blue: 0.13)
                        ],
                        center: UnitPoint(x: 0.34, y: 0.28),
                        startRadius: 2,
                        endRadius: 40
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .padding(2)
        }
    }

    private var glassHighlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.74),
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.27, y: 0.19),
                    startRadius: 0,
                    endRadius: 34
                )
            )
    }

    @ViewBuilder
    private func decoration(wavePhase: Double) -> some View {
        switch style {
        case .glassRing:
            completeRing(opacity: 0.30, lineWidth: 2.6)
            progressArc(lineWidth: 3.0)

        case .dashedRing:
            Circle()
                .stroke(
                    informationArcColor.opacity(0.78),
                    style: StrokeStyle(
                        lineWidth: 2.8,
                        lineCap: .round,
                        dash: [2.2, 3.6]
                    )
                )
                .padding(1.2)
                .shadow(color: informationArcColor.opacity(0.22), radius: 1.2)

        case .liquid:
            OrbWaveFill(
                level: max(0.12, normalizedProgress * 0.72),
                phase: wavePhase,
                amplitude: 2.4
            )
            .fill(
                LinearGradient(
                    colors: [
                        informationArcColor.opacity(0.42),
                        informationArcColor.opacity(0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(Circle().inset(by: 3))

            OrbWaveFill(
                level: max(0.10, normalizedProgress * 0.68),
                phase: wavePhase + 1.9,
                amplitude: 2
            )
            .fill(informationArcColor.opacity(0.20))
            .clipShape(Circle().inset(by: 3))

            Circle()
                .stroke(informationArcColor.opacity(0.26), lineWidth: 1.4)

        case .darkDial:
            completeRing(opacity: 0.34, lineWidth: 2.2)
                .padding(4)
            progressArc(lineWidth: 2.8)
                .padding(4)
        }
    }

    private func completeRing(opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        informationArcColor.opacity(opacity * 0.72),
                        informationArcColor.opacity(opacity),
                        informationArcColor.opacity(opacity * 0.78),
                        informationArcColor.opacity(opacity)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
    }

    private func progressArc(lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: max(0.035, normalizedProgress))
            .stroke(
                AngularGradient(
                    colors: [
                        informationArcColor.opacity(0.72),
                        informationArcColor,
                        informationArcColor.opacity(0.82),
                        informationArcColor
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: informationArcColor.opacity(0.32), radius: 1.6)
    }

    private var normalizedProgress: Double {
        min(1, max(0, progress))
    }

    private var valueColor: Color {
        style == .darkDial
            ? Color.white.opacity(0.96)
            : Color(red: 0.06, green: 0.09, blue: 0.14).opacity(0.94)
    }

    private var outerShadowColor: Color {
        style == .darkDial
            ? Color.black.opacity(0.38)
            : Color.black.opacity(0.18)
    }

    private var outerShadowRadius: CGFloat {
        style == .darkDial ? 6 : 5
    }

    private var informationArcColor: Color {
        switch animationState {
        case .thinking, .running:
            return PulseTheme.orange
        case .waiting, .waitingAuthorization, .error:
            return PulseTheme.red
        case .success:
            return PulseTheme.green
        case .idle, .sleeping, .stretch, .grooming, .hop, .wave, .curious:
            return dataColor
        }
    }

    private var breathingDuration: Double {
        switch animationState {
        case .thinking, .running: return 1.55
        case .waiting, .waitingAuthorization, .error: return 1.05
        case .success: return 1.3
        case .idle, .sleeping, .stretch, .grooming, .hop, .wave, .curious: return 3.2
        }
    }

    private var brightnessAmplitude: Double {
        switch animationState {
        case .waiting, .waitingAuthorization, .error: return 0.04
        case .thinking, .running: return 0.035
        case .success: return 0.03
        case .idle, .sleeping, .stretch, .grooming, .hop, .wave, .curious: return 0.012
        }
    }

    private var rotationDuration: Double {
        2.1
    }

    private var rotatesInformationArc: Bool {
        switch animationState {
        case .thinking, .running:
            return style != .liquid
        case .waiting, .waitingAuthorization, .error, .success,
             .idle, .sleeping, .stretch, .grooming, .hop, .wave, .curious:
            return false
        }
    }

    private var valueFont: Font {
        switch page {
        case .quota: return .system(size: 14, weight: .bold, design: .rounded)
        case .tokens: return .system(size: 9, weight: .bold, design: .rounded)
        case .weather: return .system(size: 12.5, weight: .bold, design: .rounded)
        case .temperature: return .system(size: 12.5, weight: .bold, design: .rounded)
        case .time: return .system(size: 10.5, weight: .bold, design: .monospaced)
        }
    }

    private var pageLabel: String {
        switch page {
        case .quota: return "剩余额度"
        case .tokens: return "今日 Token"
        case .weather: return "天气"
        case .temperature: return "温度"
        case .time: return "当地时间"
        }
    }
}

private struct OrbWaveFill: Shape {
    let level: Double
    let phase: Double
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedLevel = CGFloat(min(1, max(0, level)))
        let wavePhase = CGFloat(phase)
        let waterline = rect.maxY - rect.height * clampedLevel
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: waterline))
        for x in stride(from: rect.minX, through: rect.maxX, by: 1) {
            let normalizedX = (x - rect.minX) / max(1, rect.width)
            let y = waterline + sin(normalizedX * .pi * 2.1 + wavePhase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
