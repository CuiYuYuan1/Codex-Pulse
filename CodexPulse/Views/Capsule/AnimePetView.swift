import AppKit
import SwiftUI

/// Non-GIF runtime for the four rebuilt anime companions. Each species owns
/// its authored state poses and locomotion cadence; the canvas only supplies
/// restrained breathing, follow-through and one-silhouette state changes.
struct AnimePetView: View {
    let character: PetCharacter
    let animationState: PetAnimationState
    let roamingActivity: CatRoamingActivity
    let facesLeft: Bool
    let showsIdleContent: Bool
    let reduceMotion: Bool

    @State private var currentMode: AnimePetMode
    @State private var previousMode: AnimePetMode
    @State private var modeStartedAt: TimeInterval
    @State private var previousModeElapsed: TimeInterval

    init(
        character: PetCharacter,
        animationState: PetAnimationState,
        roamingActivity: CatRoamingActivity,
        facesLeft: Bool,
        showsIdleContent: Bool,
        reduceMotion: Bool
    ) {
        self.character = character
        self.animationState = animationState
        self.roamingActivity = roamingActivity
        self.facesLeft = facesLeft
        self.showsIdleContent = showsIdleContent
        self.reduceMotion = reduceMotion
        let mode = Self.resolveMode(
            animationState: animationState,
            roamingActivity: roamingActivity,
            facesLeft: facesLeft,
            showsIdleContent: showsIdleContent
        )
        _currentMode = State(initialValue: mode)
        _previousMode = State(initialValue: mode)
        _modeStartedAt = State(initialValue: Date.timeIntervalSinceReferenceDate)
        _previousModeElapsed = State(initialValue: 0)
    }

    private var mode: AnimePetMode {
        Self.resolveMode(
            animationState: animationState,
            roamingActivity: roamingActivity,
            facesLeft: facesLeft,
            showsIdleContent: showsIdleContent
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let elapsed = max(0, now - modeStartedAt)
            let transitionDuration = Self.transitionDuration(
                character: character,
                from: previousMode,
                to: currentMode
            )
            let isTransitioning = previousMode != currentMode
                && elapsed < transitionDuration
                && !reduceMotion
            let transitionProgress = min(1, elapsed / transitionDuration)

            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                context.scaleBy(x: size.width / 480, y: size.height / 288)
                if isTransitioning {
                    AnimePetPainter.drawTransition(
                        character: character,
                        from: previousMode,
                        to: currentMode,
                        progress: transitionProgress,
                        transitionElapsed: elapsed,
                        previousElapsed: previousModeElapsed,
                        facesLeft: facesLeft,
                        in: &context
                    )
                } else {
                    AnimePetPainter.draw(
                        character: character,
                        mode: currentMode,
                        elapsed: reduceMotion ? 0 : elapsed,
                        facesLeft: facesLeft,
                        opacity: 1,
                        in: &context
                    )
                }
            }
        }
        .onChange(of: mode) { _, nextMode in
            let now = Date.timeIntervalSinceReferenceDate
            let elapsed = max(0, now - modeStartedAt)
            let duration = Self.transitionDuration(
                character: character,
                from: previousMode,
                to: currentMode
            )
            let progress = min(1, elapsed / duration)
            let visibleMode = previousMode != currentMode
                ? AnimePetTransitionChoreography.visualMode(
                    from: previousMode,
                    to: currentMode,
                    progress: progress
                )
                : currentMode
            previousModeElapsed = visibleMode == currentMode
                ? elapsed
                : previousModeElapsed + elapsed
            previousMode = visibleMode
            currentMode = nextMode
            modeStartedAt = now
        }
        .accessibilityHidden(true)
    }

    private static func transitionDuration(
        character: PetCharacter,
        from: AnimePetMode,
        to: AnimePetMode
    ) -> TimeInterval {
        let base: TimeInterval
        switch character {
        case .dino: base = 0.58
        case .bunny: base = 0.66
        case .ghost: base = 0.52
        case .robot: base = 0.46
        case .cat: base = 0.60
        case .fox: base = 0.64
        case .orb, .orb2, .orb3, .orb4: base = 0.52
        case .blackHole: base = 0.52
        }
        if from.isResting || to.isResting {
            return base + 0.14
        }
        return base
    }

    private static func resolveMode(
        animationState: PetAnimationState,
        roamingActivity: CatRoamingActivity,
        facesLeft: Bool,
        showsIdleContent: Bool
    ) -> AnimePetMode {
        if showsIdleContent {
            switch roamingActivity {
            case .resting: return .idle
            case .strolling: return facesLeft ? .walkLeft : .walkRight
            case .investigating: return .sniffing
            case .pawingDesktopItem: return .pawing
            case .dockPlay: return .dockPlay
            case .dockPounce: return .pouncing
            case .hopping: return .success
            case .sleeping: return .sleeping
            case .stretching: return .stretch
            case .grooming: return .grooming
            case .waving: return .success
            }
        }
        switch animationState {
        case .idle: return .idle
        case .thinking: return .thinking
        case .running: return .working
        case .waiting, .waitingAuthorization: return .waitingAuthorization
        case .success, .hop, .wave: return .success
        case .error: return .error
        case .sleeping: return .sleeping
        case .stretch: return .stretch
        case .grooming: return .grooming
        case .curious: return .curious
        }
    }
}

private enum AnimePetMode: Equatable {
    case idle
    case walkLeft
    case walkRight
    case thinking
    case working
    case waitingAuthorization
    case success
    case error
    case sleeping
    case stretch
    case grooming
    case curious
    case sniffing
    case pawing
    case pouncing
    case dockPlay

    var isDirectionalInteraction: Bool {
        switch self {
        case .sniffing, .pawing, .pouncing, .dockPlay:
            return true
        default:
            return false
        }
    }

    var isLocomotion: Bool {
        self == .walkLeft || self == .walkRight
    }

    var isResting: Bool {
        self == .sleeping || self == .stretch || self == .grooming
    }

    var isFocused: Bool {
        self == .thinking
            || self == .working
            || self == .waitingAuthorization
    }
}

private struct AnimePetTransitionMotion {
    var x = 0.0
    var y = 0.0
    var rotation = 0.0
}

private enum AnimePetTransitionChoreography {
    private static let outgoingEnd = 0.30
    private static let incomingStart = 0.68

    static func visualMode(
        from: AnimePetMode,
        to: AnimePetMode,
        progress: Double
    ) -> AnimePetMode {
        if progress < outgoingEnd { return from }
        if progress < incomingStart { return bridgeMode(from: from, to: to) }
        return to
    }

    static func elapsed(
        from: AnimePetMode,
        to: AnimePetMode,
        progress: Double,
        transitionElapsed: Double,
        previousElapsed: Double
    ) -> Double {
        if progress < outgoingEnd {
            return previousElapsed + transitionElapsed
        }
        if progress < incomingStart {
            return max(0, transitionElapsed * (progress - outgoingEnd))
        }
        return max(0, transitionElapsed * (progress - incomingStart))
    }

    static func motion(
        character: PetCharacter,
        from: AnimePetMode,
        to: AnimePetMode,
        progress: Double
    ) -> AnimePetTransitionMotion {
        let p = max(0, min(1, progress))
        let weightShift = sin(.pi * p)
        let enteringLocomotion = to.isLocomotion && !from.isLocomotion
        let leavingLocomotion = from.isLocomotion && !to.isLocomotion
        let locomotionChange = enteringLocomotion || leavingLocomotion

        switch character {
        case .fox:
            // Foxes lower the head and forequarters before the first step,
            // then let the tail mass counter the forward weight transfer.
            return AnimePetTransitionMotion(
                x: weightShift * (enteringLocomotion ? 4.2 : 2.8),
                y: weightShift * 2.1,
                rotation: weightShift * (enteringLocomotion ? -1.5 : -0.8)
            )
        case .bunny:
            // A rabbit starts from compressed hind limbs and finishes by
            // receiving weight through the forefeet before settling.
            let compression = sin(.pi * min(1, p * 1.35))
            let landing = leavingLocomotion
                ? sin(.pi * max(0, (p - 0.45) / 0.55))
                : 0
            return AnimePetTransitionMotion(
                x: locomotionChange ? weightShift * 1.8 : 0,
                y: compression * 3.4 + landing * 1.4,
                rotation: weightShift * (enteringLocomotion ? -0.8 : 0.55)
            )
        case .dino:
            // The torso leans into the action while the long tail supplies
            // the counterbalance; avoid the mammal-like vertical squash.
            return AnimePetTransitionMotion(
                x: weightShift * (locomotionChange ? 3.2 : 1.7),
                y: weightShift * 0.8,
                rotation: weightShift * (enteringLocomotion ? -1.25 : 0.55)
            )
        case .ghost, .orb, .orb2, .orb3, .orb4, .blackHole:
            // A floating companion changes state through inertia rather than
            // planted feet: it glides past center and gently returns.
            return AnimePetTransitionMotion(
                x: sin(.pi * p) * 2.2,
                y: -sin(.pi * p) * 2.8,
                rotation: sin(.pi * 2 * p) * 0.9
            )
        case .robot:
            // Two small servo beats: brace, execute, then lock the new pose.
            let servo = sin(.pi * min(1, p * 2))
                - sin(.pi * max(0, (p - 0.5) * 2)) * 0.45
            return AnimePetTransitionMotion(
                x: servo * 1.7,
                y: abs(servo) * 0.65,
                rotation: servo * 0.38
            )
        case .cat:
            return AnimePetTransitionMotion()
        }
    }

    private static func bridgeMode(
        from: AnimePetMode,
        to: AnimePetMode
    ) -> AnimePetMode {
        if to.isLocomotion { return to }
        if from.isLocomotion { return from }
        if to == .sleeping || from == .sleeping { return .stretch }
        if to.isFocused || from.isFocused { return .curious }
        if to == .pawing || to == .dockPlay || to == .pouncing {
            return .sniffing
        }
        if to.isResting || from.isResting { return .stretch }
        return .curious
    }
}

/// A short-lived optical warp rendered around the real paw contact point.
/// It does not invent desktop text and does not read screen pixels. Paired
/// compression/refraction edges bend the viewer's perception of whatever real
/// icon or glyph is already behind the transparent pet surface.
enum PetFootstepPainter {
    private static let lifetime = 1.22
    private static let anticipation: TimeInterval = 0.10
    private static let trailSpeed: CGFloat = 185

    static func draw(
        character: PetCharacter,
        elapsed: Double,
        movesLeft: Bool,
        cycleDuration: Double,
        in context: inout GraphicsContext
    ) {
        guard elapsed >= 0, cycleDuration > 0 else { return }
        let contactInterval = cycleDuration / 2
        let newestStep = Int(floor(elapsed / contactInterval))
        for offset in -1..<2 {
            let step = newestStep - offset
            guard step >= 0 else { continue }
            let age = elapsed - Double(step) * contactInterval
            guard age >= -anticipation, age <= lifetime else { continue }

            let sideX: CGFloat = step.isMultiple(of: 2) ? 111 : 153
            let mirroredX = movesLeft ? 264 - sideX : sideX
            let travel = CGFloat(age) * trailSpeed * (movesLeft ? 1 : -1)
            let center = CGPoint(
                x: mirroredX + travel,
                y: groundY(for: character)
            )
            let life = max(0, 1 - age / lifetime)
            let impact = age < 0 ? 0 : max(0, min(1, 1 - age / 0.14))
            let expansion = 0.72 + min(1, age / 0.20) * 0.28
            var layer = context
            // Keep a readable tail between alternating paw contacts. Squaring
            // `life` made the effect mathematically present but practically
            // invisible on a white editor or browser background.
            layer.opacity *= age < 0 ? 1 : max(0.18, life)

            guard age >= 0 else { continue }

            switch positiveModulo(step, 3) {
            case 0:
                drawDent(
                    character: character,
                    center: center,
                    expansion: expansion,
                    impact: impact,
                    in: &layer
                )
                drawCracks(
                    center: CGPoint(x: center.x, y: center.y - 1),
                    seed: step,
                    expansion: expansion,
                    in: &layer
                )
            case 1:
                drawDent(
                    character: character,
                    center: center,
                    expansion: expansion * 0.94,
                    impact: impact,
                    in: &layer
                )
                drawCracks(
                    center: CGPoint(x: center.x, y: center.y - 1),
                    seed: step + 17,
                    expansion: expansion * 1.08,
                    in: &layer
                )
            default:
                drawDent(
                    character: character,
                    center: center,
                    expansion: expansion * 0.88,
                    impact: impact,
                    in: &layer
                )
                drawFootprint(
                    character: character,
                    center: center,
                    expansion: expansion,
                    in: &layer
                )
                drawCracks(
                    center: CGPoint(x: center.x, y: center.y - 1),
                    seed: step + 31,
                    expansion: expansion * 0.74,
                    in: &layer
                )
                drawPressureArcs(
                    center: center,
                    expansion: expansion,
                    in: &layer
                )
            }
        }
    }

    private static func groundY(for character: PetCharacter) -> CGFloat {
        switch character {
        case .ghost, .orb, .orb2, .orb3, .orb4, .blackHole: return 244
        case .cat: return 249
        case .dino, .bunny, .robot, .fox: return 251
        }
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static func drawDent(
        character: PetCharacter,
        center: CGPoint,
        expansion: Double,
        impact: Double,
        in context: inout GraphicsContext
    ) {
        let width = CGFloat(character == .robot ? 52 : character == .dino ? 58 : 47)
            * CGFloat(expansion)
        let height = CGFloat(character == .ghost ? 7 : 11) * CGFloat(expansion)
        let dent = Path(ellipseIn: CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        ))
        context.fill(
            dent,
            with: .color(Color(red: 0.015, green: 0.025, blue: 0.065).opacity(0.36 + impact * 0.18))
        )
        context.stroke(
            dent,
            with: .color(Color.white.opacity(0.62)),
            lineWidth: 1.15
        )
    }

    private static func drawCracks(
        center: CGPoint,
        seed: Int,
        expansion: Double,
        in context: inout GraphicsContext
    ) {
        var cracks = Path()
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
                + Double((seed + index * 7) % 5 - 2) * 0.055
            let length = CGFloat(13 + ((seed * 5 + index * 7) % 14))
                * CGFloat(expansion)
            let kink = length * 0.56
            let mid = CGPoint(
                x: center.x + CGFloat(cos(angle)) * kink,
                y: center.y + CGFloat(sin(angle)) * kink * 0.42
            )
            let end = CGPoint(
                x: center.x
                    + CGFloat(cos(angle + (index.isMultiple(of: 2) ? 0.10 : -0.08))) * length,
                y: center.y + CGFloat(sin(angle)) * length * 0.46
            )
            cracks.move(to: center)
            cracks.addLine(to: mid)
            cracks.addLine(to: end)
        }
        context.stroke(
            cracks,
            with: .color(Color(red: 0.008, green: 0.015, blue: 0.045).opacity(0.94)),
            lineWidth: 3.4
        )
        context.stroke(
            cracks,
            with: .color(Color(red: 0.62, green: 0.90, blue: 1).opacity(0.82)),
            lineWidth: 1.15
        )
    }

    private static func drawFootprint(
        character: PetCharacter,
        center: CGPoint,
        expansion: Double,
        in context: inout GraphicsContext
    ) {
        let scale = CGFloat(expansion) * 1.22
        let fill = Color(red: 0.015, green: 0.025, blue: 0.07).opacity(0.42)
        let rim = Color(red: 0.58, green: 0.84, blue: 1).opacity(0.48)
        switch character {
        case .robot:
            let plate = Path(roundedRect: CGRect(
                x: center.x - 14 * scale,
                y: center.y - 5 * scale,
                width: 28 * scale,
                height: 9 * scale
            ), cornerRadius: 2.2)
            context.fill(plate, with: .color(fill))
            context.stroke(plate, with: .color(rim), lineWidth: 0.8)
        case .bunny:
            for offset: CGFloat in [-6, 6] {
                let print = Path(ellipseIn: CGRect(
                    x: center.x + offset - 4 * scale,
                    y: center.y - 8 * scale,
                    width: 8 * scale,
                    height: 14 * scale
                ))
                context.fill(print, with: .color(fill))
                context.stroke(print, with: .color(rim), lineWidth: 0.65)
            }
        case .dino:
            var toes = Path()
            for offset: CGFloat in [-9, 0, 9] {
                toes.move(to: CGPoint(x: center.x + offset, y: center.y + 2))
                toes.addLine(to: CGPoint(x: center.x + offset - 3 * scale, y: center.y - 7 * scale))
                toes.addLine(to: CGPoint(x: center.x + offset + 3 * scale, y: center.y - 7 * scale))
                toes.closeSubpath()
            }
            context.fill(toes, with: .color(fill))
            context.stroke(toes, with: .color(rim), lineWidth: 0.7)
        case .ghost, .orb, .orb2, .orb3, .orb4, .blackHole:
            let ripple = Path(ellipseIn: CGRect(
                x: center.x - 18 * scale,
                y: center.y - 3 * scale,
                width: 36 * scale,
                height: 6 * scale
            ))
            context.stroke(ripple, with: .color(rim), lineWidth: 1.15)
        case .cat, .fox:
            let pad = Path(ellipseIn: CGRect(
                x: center.x - 7 * scale,
                y: center.y - 4 * scale,
                width: 14 * scale,
                height: 9 * scale
            ))
            context.fill(pad, with: .color(fill))
            for offset: CGFloat in [-6, 0, 6] {
                let toe = Path(ellipseIn: CGRect(
                    x: center.x + offset - 2.2 * scale,
                    y: center.y - 8 * scale,
                    width: 4.4 * scale,
                    height: 4.6 * scale
                ))
                context.fill(toe, with: .color(fill))
            }
            context.stroke(pad, with: .color(rim), lineWidth: 0.7)
        }
    }

    private static func drawPressureArcs(
        center: CGPoint,
        expansion: Double,
        in context: inout GraphicsContext
    ) {
        let scale = CGFloat(expansion)
        for width: CGFloat in [48, 66] {
            let arc = Path(ellipseIn: CGRect(
                x: center.x - width * scale / 2,
                y: center.y - 4 * scale,
                width: width * scale,
                height: 8 * scale
            ))
            context.stroke(
                arc,
                with: .color(Color.white.opacity(width < 40 ? 0.26 : 0.16)),
                lineWidth: 0.65
            )
        }
    }
}

private enum AnimePetPainter {
    static func drawTransition(
        character: PetCharacter,
        from: AnimePetMode,
        to: AnimePetMode,
        progress: Double,
        transitionElapsed: Double,
        previousElapsed: Double,
        facesLeft: Bool,
        in context: inout GraphicsContext
    ) {
        let mode = AnimePetTransitionChoreography.visualMode(
            from: from,
            to: to,
            progress: progress
        )
        draw(
            character: character,
            mode: mode,
            elapsed: AnimePetTransitionChoreography.elapsed(
                from: from,
                to: to,
                progress: progress,
                transitionElapsed: transitionElapsed,
                previousElapsed: previousElapsed
            ),
            facesLeft: facesLeft,
            opacity: 1,
            transitionMotion: AnimePetTransitionChoreography.motion(
                character: character,
                from: from,
                to: to,
                progress: progress
            ),
            in: &context
        )
    }

    static func draw(
        character: PetCharacter,
        mode: AnimePetMode,
        elapsed: Double,
        facesLeft: Bool,
        opacity: Double,
        transitionMotion: AnimePetTransitionMotion = AnimePetTransitionMotion(),
        in context: inout GraphicsContext
    ) {
        let workingSample = mode == .working
            ? PetWorkingCadence.sample(at: elapsed)
            : nil
        let asset: Image
        switch mode {
        case .walkLeft, .walkRight:
            let cycleDuration = locomotionDuration(for: character)
            let phase = (elapsed / cycleDuration).truncatingRemainder(dividingBy: 1)
            let framePosition = max(0, phase) * 8
            let frame = min(7, max(0, Int(floor(framePosition))))
            let direction = mode == .walkLeft ? "left" : "right"
            asset = AnimePetAssets.image(
                character,
                "walk-\(direction)-\(frame)"
            )
        case .thinking:
            let hold = thinkingHold(for: character)
            let framePosition = elapsed / hold
            let frame = Int(floor(framePosition)) % 4
            asset = AnimePetAssets.image(character, "state-thinking-\(frame)")
        case .working:
            asset = AnimePetAssets.image(
                character,
                "state-working-\(workingSample?.frame ?? 0)"
            )
        case .waitingAuthorization:
            asset = AnimePetAssets.image(character, "state-waiting-auth")
        case .success:
            asset = AnimePetAssets.image(character, "state-success")
        case .error:
            asset = AnimePetAssets.image(character, "state-error")
        case .sleeping:
            asset = AnimePetAssets.image(character, "state-sleeping")
        case .stretch:
            asset = AnimePetAssets.image(character, "state-stretch")
        case .grooming:
            asset = AnimePetAssets.image(
                character,
                character == .fox ? "state-idle-loop-5" : "state-grooming"
            )
        case .curious:
            asset = AnimePetAssets.image(
                character,
                character == .fox ? "state-idle-loop-3" : "state-curious"
            )
        case .sniffing, .pawing, .dockPlay:
            asset = AnimePetAssets.image(
                character,
                character == .fox ? "walk-left-0" : "state-curious"
            )
        case .pouncing:
            asset = AnimePetAssets.image(character, "state-success")
        case .idle:
            if character == .fox {
                let sample = foxIdleSample(at: elapsed)
                asset = AnimePetAssets.image(
                    character,
                    "state-idle-loop-\(sample.frame)"
                )
            } else {
                asset = AnimePetAssets.image(character, "state-idle-0")
            }
        }

        if mode == .walkLeft || mode == .walkRight {
            PetFootstepPainter.draw(
                character: character,
                elapsed: elapsed,
                movesLeft: mode == .walkLeft,
                cycleDuration: locomotionDuration(for: character),
                in: &context
            )
        }

        var layer = context
        layer.opacity *= opacity
        let motion = motionTransform(character: character, mode: mode, elapsed: elapsed)
        layer.translateBy(
            x: 132 + motion.x + transitionMotion.x,
            y: 154 + motion.y + transitionMotion.y
        )
        layer.rotate(by: .degrees(motion.rotation + transitionMotion.rotation))
        let directionalScaleX = mode.isDirectionalInteraction && !facesLeft
            ? -motion.scaleX
            : motion.scaleX
        layer.scaleBy(
            x: directionalScaleX,
            y: motion.scaleY
        )
        layer.draw(
            layer.resolve(asset),
            in: CGRect(x: -92, y: -99.5, width: 184, height: 199)
        )
        if let workingSample {
            drawWorkingKeyPulse(
                character: character,
                sample: workingSample,
                in: &layer
            )
        }
    }

    private static func locomotionDuration(for character: PetCharacter) -> Double {
        switch character {
        case .dino: return 1.06
        case .bunny: return 1.38
        case .ghost: return 1.24
        case .robot: return 0.94
        case .cat: return 0.89
        case .fox: return 1.12
        case .orb, .orb2, .orb3, .orb4: return 1.0
        case .blackHole: return 1.28
        }
    }

    private struct FoxIdleSample {
        let frame: Int
    }

    private static func foxIdleSample(at elapsed: Double) -> FoxIdleSample {
        let holds = [0.86, 0.68, 0.75, 1.05, 0.64, 0.82, 0.71, 0.96]
        let total = holds.reduce(0, +)
        var cursor = elapsed.truncatingRemainder(dividingBy: total)
        if cursor < 0 { cursor += total }
        for (frame, hold) in holds.enumerated() {
            if cursor < hold {
                return FoxIdleSample(frame: frame)
            }
            cursor -= hold
        }
        return FoxIdleSample(frame: 0)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let amount = max(0, min(1, value))
        return amount * amount * (3 - 2 * amount)
    }

    private static func pulse(_ phase: Double, center: Double, width: Double) -> Double {
        let distance = abs(phase - center)
        let wrapped = min(distance, 1 - distance)
        guard wrapped < width else { return 0 }
        return 0.5 + 0.5 * cos(.pi * wrapped / width)
    }

    private static func thinkingHold(for character: PetCharacter) -> Double {
        switch character {
        case .dino: return 1.75
        case .bunny: return 1.55
        case .ghost: return 1.85
        case .robot: return 1.35
        case .cat: return 1.45
        case .fox: return 1.45
        case .orb, .orb2, .orb3, .orb4: return 1.45
        case .blackHole: return 1.45
        }
    }

    private static func motionTransform(
        character: PetCharacter,
        mode: AnimePetMode,
        elapsed: Double
    ) -> (x: Double, y: Double, rotation: Double, scaleX: Double, scaleY: Double) {
        let breath = sin(elapsed * .pi * 2 / breathingDuration(for: character))
        var x = 0.0
        var y = breath * 0.75
        var rotation = 0.0
        let baseScale = character == .fox ? 1.14 : 1.0
        var scaleX = baseScale
        var scaleY = baseScale + breath * 0.006

        switch mode {
        case .walkLeft, .walkRight:
            // Full-pose frames own the gait. Only species-specific whole-body
            // follow-through is added here; never slide limbs independently.
            let duration = locomotionDuration(for: character)
            let phase = elapsed / duration * .pi * 2
            switch character {
            case .dino:
                y = abs(sin(phase)) * 0.9
                rotation = sin(phase) * 0.35
            case .bunny:
                y = -max(0, sin(phase)) * 3.4 + max(0, -sin(phase)) * 0.8
                rotation = sin(phase - 0.35) * 0.55
            case .ghost, .orb, .orb2, .orb3, .orb4, .blackHole:
                y = sin(phase) * 2.4
                rotation = sin(phase - 0.55) * 1.1
                scaleX = 1 + cos(phase) * 0.012
                scaleY = 1 - cos(phase) * 0.016
            case .robot:
                y = abs(sin(phase)) * 0.65
                rotation = sin(phase) * 0.24
            case .fox:
                y = abs(sin(phase)) * 0.8
                rotation = sin(phase - 0.2) * 0.32
            case .cat:
                break
            }
        case .thinking:
            rotation = sin(elapsed * 0.72) * thinkingRotation(for: character)
            y += sin(elapsed * 1.15) * 0.5
        case .working:
            // Authored frames own the paw and shoulder mechanics. Keeping the
            // root stable prevents the old "whole pet trembling" illusion.
            y = breath * 0.35
            rotation = 0
        case .waitingAuthorization:
            y += sin(elapsed * 1.35) * 0.65
        case .success:
            y -= max(0, sin(elapsed * 2.4)) * (character == .ghost ? 3.2 : 1.8)
        case .sniffing:
            let sniff = sin(elapsed * 5.2)
            x = 4.5 + sniff * 1.2
            y += 3.2 + abs(sniff) * 1.3
            rotation = 1.8 + sniff * 0.7
            scaleX *= 1.015
            scaleY *= 0.985
        case .pawing:
            let phase = (elapsed / 1.25).truncatingRemainder(dividingBy: 1)
            let prepare = pulse(phase, center: 0.18, width: 0.18)
            let tap = pulse(phase, center: 0.48, width: 0.22)
            x = 3.5 + tap * 7.5
            y += prepare * 1.8 - tap * 1.2
            rotation = -1.5 - tap * 2.2
            scaleX *= 1 + tap * 0.018
            scaleY *= 1 - tap * 0.014
        case .pouncing:
            let phase = (elapsed / 2.25).truncatingRemainder(dividingBy: 1)
            let crouch = pulse(phase, center: 0.16, width: 0.15)
            let leap = pulse(phase, center: 0.48, width: 0.29)
            let land = pulse(phase, center: 0.78, width: 0.10)
            x = leap * 10
            y += crouch * 4.5 - leap * 11 + land * 3
            rotation = -leap * 2.5
            scaleX *= 1 + crouch * 0.045 - leap * 0.018
            scaleY *= 1 - crouch * 0.055 + leap * 0.026
        case .dockPlay:
            let phase = (elapsed / 1.9).truncatingRemainder(dividingBy: 1)
            let reach = pulse(phase, center: 0.28, width: 0.22)
            let recoil = pulse(phase, center: 0.66, width: 0.20)
            x = reach * 6 - recoil * 2
            y += -reach * 3 + recoil * 1.5
            rotation = reach * 2.2 - recoil * 1.2
        case .sleeping:
            scaleX += breath * 0.009
            scaleY += breath * 0.011
        case .stretch, .grooming, .curious, .error, .idle:
            break
        }
        return (x, y, rotation, scaleX, scaleY)
    }

    private static func drawWorkingKeyPulse(
        character: PetCharacter,
        sample: PetWorkingAnimationSample,
        in context: inout GraphicsContext
    ) {
        let keyX: (Double, Double)
        let keyY: Double
        switch character {
        case .dino:
            keyX = (-10, 35)
            keyY = 68
        case .bunny:
            keyX = (-22, 26)
            keyY = 65
        case .ghost:
            keyX = (-33, 30)
            keyY = 68
        case .robot:
            keyX = (-33, 34)
            keyY = 70
        case .cat:
            keyX = (-25, 16)
            keyY = 66
        case .fox:
            keyX = (-39, 12)
            keyY = 74
        case .orb, .orb2, .orb3, .orb4:
            keyX = (-24, 24)
            keyY = 66
        case .blackHole:
            keyX = (-24, 24)
            keyY = 66
        }
        let cyan = Color(red: 0.16, green: 0.82, blue: 1)
        for (x, strength) in [
            (keyX.0, sample.leftKeyStrength),
            (keyX.1, sample.rightKeyStrength),
        ] where strength > 0.015 {
            let glow = Path(roundedRect: CGRect(
                x: x - 4.2,
                y: keyY - 2.2,
                width: 8.4,
                height: 4.4
            ), cornerRadius: 1.6)
            context.fill(glow, with: .color(cyan.opacity(0.10 + strength * 0.22)))
            let key = Path(
                roundedRect: CGRect(x: x - 3.0, y: keyY - 1.35, width: 6, height: 2.7),
                cornerRadius: 1.1
            )
            context.fill(
                key,
                with: .color(cyan.opacity(0.40 + strength * 0.60))
            )
        }
    }

    private static func breathingDuration(for character: PetCharacter) -> Double {
        switch character {
        case .dino: return 3.8
        case .bunny: return 3.2
        case .ghost: return 4.6
        case .robot: return 2.8
        case .cat: return 3.6
        case .fox: return 3.6
        case .orb, .orb2, .orb3, .orb4: return 3.2
        case .blackHole: return 4.2
        }
    }

    private static func thinkingRotation(for character: PetCharacter) -> Double {
        switch character {
        case .dino: return 0.7
        case .bunny: return 0.9
        case .ghost: return 1.3
        case .robot: return 0.35
        case .cat: return 0.8
        case .fox: return 0.8
        case .orb, .orb2, .orb3, .orb4: return 1.0
        case .blackHole: return 1.0
        }
    }
}

private enum AnimePetAssets {
    private static var cache: [String: Image] = [:]

    static func image(_ character: PetCharacter, _ suffix: String) -> Image {
        let name = "anime-\(character.rawValue)-\(suffix)"
        if let cached = cache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            NSLog("[CodexPulse] Missing anime pet resource: %@.png", name)
            let fallbackName = "anime-dino-state-idle-0"
            if let fallbackURL = Bundle.main.url(forResource: fallbackName, withExtension: "png"),
               let fallbackImage = NSImage(contentsOf: fallbackURL) {
                let result = Image(nsImage: fallbackImage)
                cache[name] = result
                return result
            }
            let result = Image(nsImage: NSImage(size: NSSize(width: 1, height: 1)))
            cache[name] = result
            return result
        }
        let result = Image(nsImage: image)
        cache[name] = result
        return result
    }
}
