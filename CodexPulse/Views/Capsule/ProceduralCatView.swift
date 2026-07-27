import AppKit
import SwiftUI

/// A continuously evaluated cat rig. Unlike the legacy GIFs, every visible part
/// has its own motion channel and state changes blend without replacing images.
struct ProceduralCatView: View {
    let animationState: PetAnimationState
    let roamingActivity: CatRoamingActivity
    let facesLeft: Bool
    let showsIdleContent: Bool
    let reduceMotion: Bool

    private var mode: CatRigMode {
        if showsIdleContent {
            switch roamingActivity {
            case .resting: return .idle
            case .strolling: return facesLeft ? .walkLeft : .walkRight
            case .investigating: return .sniffing
            case .pawingDesktopItem, .dockPlay: return .pawing
            case .dockPounce: return .pouncing
            case .waving: return .wave
            case .sleeping: return .sleeping
            case .stretching: return .stretch
            case .grooming: return .grooming
            case .hopping: return .hop
            }
        }
        switch animationState {
        case .idle: return .idle
        case .thinking: return .thinking
        case .running: return .working
        case .waiting: return .waiting
        case .waitingAuthorization: return .waitingAuthorization
        case .success: return .success
        case .error: return .error
        case .sleeping: return .sleeping
        case .stretch: return .stretch
        case .grooming: return .grooming
        case .hop: return .hop
        case .wave: return .wave
        case .curious: return .curious
        }
    }

    var body: some View {
        CatRigTimeline(mode: mode, facesLeft: facesLeft, reduceMotion: reduceMotion)
            .accessibilityHidden(true)
    }
}

private enum CatRigMode: Equatable {
    case idle
    case walkLeft
    case walkRight
    case thinking
    case working
    case waiting
    case waitingAuthorization
    case sniffing
    case pawing
    case pouncing
    case success
    case error
    case sleeping
    case stretch
    case grooming
    case hop
    case wave
    case curious

    var facesLeft: Bool {
        self == .walkLeft
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
            || self == .waiting
            || self == .waitingAuthorization
    }
}

private struct CatRigTimeline: View {
    private static let transitionDuration: TimeInterval = 0.62

    let mode: CatRigMode
    let facesLeft: Bool
    let reduceMotion: Bool

    @State private var currentMode: CatRigMode
    @State private var previousMode: CatRigMode
    @State private var transitionFromPose: CatPose
    @State private var transitionStartedAt: TimeInterval

    init(mode: CatRigMode, facesLeft: Bool, reduceMotion: Bool) {
        self.mode = mode
        self.facesLeft = facesLeft
        self.reduceMotion = reduceMotion
        let now = Date.timeIntervalSinceReferenceDate
        _currentMode = State(initialValue: mode)
        _previousMode = State(initialValue: mode)
        _transitionFromPose = State(initialValue: CatPose.sample(mode, time: 0))
        _transitionStartedAt = State(initialValue: now)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let pose = renderedPose(at: now)
            let visualBlend = transitionBlend(at: now)
            let modeElapsed = max(0, now - transitionStartedAt)

            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                context.scaleBy(x: size.width / 480, y: size.height / 288)
                CatRigPainter.draw(
                    pose,
                    facesLeft: currentMode.facesLeft || facesLeft,
                    mode: currentMode,
                    previousMode: previousMode,
                    transition: visualBlend,
                    animationTime: modeElapsed,
                    in: &context
                )
            }
        }
        .onChange(of: mode) { _, newValue in
            let now = Date.timeIntervalSinceReferenceDate
            transitionFromPose = renderedPose(at: now)
            let visibleMode = previousMode != currentMode && transitionBlend(at: now) < 0.5
                ? previousMode
                : currentMode
            previousMode = visibleMode
            currentMode = newValue
            transitionStartedAt = now
        }
    }

    private func renderedPose(at time: TimeInterval) -> CatPose {
        let blend = transitionBlend(at: time)
        return CatTransitionChoreography.pose(
            from: previousMode,
            to: currentMode,
            fromPose: transitionFromPose,
            elapsed: max(0, time - transitionStartedAt),
            progress: blend
        )
    }

    private func transitionBlend(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - transitionStartedAt)
        return reduceMotion
            ? 1
            : CatMotionMath.smoothstep(min(1, elapsed / Self.transitionDuration))
    }
}

private enum CatTransitionChoreography {
    private static let outgoingEnd = 0.38
    private static let incomingStart = 0.68

    static func visualMode(
        from: CatRigMode,
        to: CatRigMode,
        progress: Double
    ) -> CatRigMode {
        if progress < outgoingEnd { return from }
        if progress < incomingStart { return bridgeMode(from: from, to: to) }
        return to
    }

    static func pose(
        from: CatRigMode,
        to: CatRigMode,
        fromPose: CatPose,
        elapsed: Double,
        progress: Double
    ) -> CatPose {
        let p = max(0, min(1, progress))
        let bridge = bridgePose(from: from, to: to)
        if p < outgoingEnd {
            return CatPose.mix(
                fromPose,
                bridge,
                CatMotionMath.smoothstep(p / outgoingEnd)
            )
        }
        let target = CatPose.sample(
            to,
            time: max(0, elapsed - outgoingEnd * 0.62)
        )
        return CatPose.mix(
            bridge,
            target,
            CatMotionMath.smoothstep((p - outgoingEnd) / (1 - outgoingEnd))
        )
    }

    private static func bridgeMode(
        from: CatRigMode,
        to: CatRigMode
    ) -> CatRigMode {
        if to.isLocomotion { return to }
        if from.isLocomotion { return from }
        if to == .sleeping || from == .sleeping { return .stretch }
        if to.isFocused || from.isFocused { return .curious }
        if to == .pawing || to == .pouncing { return .sniffing }
        if to.isResting || from.isResting { return .stretch }
        return .curious
    }

    private static func bridgePose(
        from: CatRigMode,
        to: CatRigMode
    ) -> CatPose {
        if to == .sleeping || from == .sleeping || to.isResting {
            // Cats lower the shoulders, extend the forelegs and only then
            // fold into rest; waking uses the same stretch in reverse.
            return CatPose.sample(.stretch, time: 1.2)
        }

        var pose = CatPose.sample(.idle, time: 0)
        if to.isLocomotion {
            // Tripodal support before the first step: shift weight toward the
            // planted side, unload one forepaw and counter with the tail.
            pose.bodyX -= 3.2
            pose.bodyY += 1.8
            pose.bodyRotation = -1.8
            pose.headX += 2.4
            pose.frontNearAngle = -13
            pose.frontNearLift = 5.5
            pose.hindFarAngle = 4
            pose.tailLift = 7
            pose.tailSway = 8
            return pose
        }
        if from.isLocomotion {
            // Finish on a planted stance before the head and tail relax.
            pose.bodyX += 1.4
            pose.bodyY += 1.2
            pose.frontNearAngle = -4
            pose.frontFarAngle = 3
            pose.tailLift = 4
            pose.tailSway = -5
            return pose
        }
        if to.isFocused {
            // Attention starts at the ears and head, followed by a small
            // weight shift that frees the near forepaw for thinking/typing.
            pose.bodyX += 2.2
            pose.bodyY += 1.4
            pose.headX += 4.8
            pose.headY += 3.8
            pose.headRotation = -4.5
            pose.earLeft -= 5
            pose.earRight += 3
            pose.frontNearAngle = -20
            pose.frontNearLift = 8
            pose.tailSway = 3
            pose.workSurface = to == .working ? 0.28 : 0
            return pose
        }
        if from.isFocused {
            pose.headRotation = 3
            pose.headX += 2
            pose.frontNearAngle = -8
            pose.frontNearLift = 3
            pose.tailSway = 5
            return pose
        }

        pose.headRotation = 4
        pose.headX += 2.5
        pose.pupilX = 1.4
        pose.earLeft -= 3
        pose.tailSway = 6
        return pose
    }
}

private enum CatMotionMath {
    static let tau = Double.pi * 2

    static func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    static func pulse(_ phase: Double, center: Double, width: Double) -> Double {
        let distance = abs(phase - center)
        let wrapped = min(distance, 1 - distance)
        guard wrapped < width else { return 0 }
        return 0.5 + 0.5 * cos(Double.pi * wrapped / width)
    }

    static func hash(_ value: Int) -> Double {
        let x = sin(Double(value) * 12.9898 + 78.233) * 43_758.5453
        return x - floor(x)
    }

    static func blink(at time: Double) -> Double {
        let bucket = Int(floor(time / 5))
        let local = time - Double(bucket * 5)
        let start = 0.45 + hash(bucket) * 3.75
        let first = max(0, 1 - abs(local - start) / 0.105)
        let doubleBlink = hash(bucket + 91) > 0.78
            ? max(0, 1 - abs(local - start - 0.24) / 0.09)
            : 0
        return 1 - min(1, max(first, doubleBlink))
    }

    static func earFlick(at time: Double) -> Double {
        let bucket = Int(floor(time / 7))
        let local = time - Double(bucket * 7)
        let start = 0.8 + hash(bucket + 44) * 5.1
        return sin(min(1, max(0, (local - start) / 0.34)) * Double.pi) * (local >= start && local <= start + 0.34 ? 1 : 0)
    }
}

private struct CatPose {
    var bodyX = 142.0
    var bodyY = 174.0
    var bodyRotation = 0.0
    var bodyScaleX = 1.0
    var bodyScaleY = 1.0
    var headX = 181.0
    var headY = 130.0
    var headRotation = 0.0
    var headScale = 1.0
    var eyeOpen = 1.0
    var pupilX = 0.0
    var pupilY = 0.0
    var earLeft = 0.0
    var earRight = 0.0
    var tailSway = 0.0
    var tailLift = 0.0
    var frontFarAngle = 0.0
    var frontNearAngle = 0.0
    var hindFarAngle = 0.0
    var hindNearAngle = 0.0
    var frontFarLift = 0.0
    var frontNearLift = 0.0
    var hindFarLift = 0.0
    var hindNearLift = 0.0
    var pawReach = 0.0
    var mouthOpen = 0.0
    var workSurface = 0.0
    var keyPulse = 0.0
    var walkPhase = 0.0
    var walkBlend = 0.0
    var opacity = 1.0

    static func mix(_ a: CatPose, _ b: CatPose, _ t: Double) -> CatPose {
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return CatPose(
            bodyX: lerp(a.bodyX, b.bodyX),
            bodyY: lerp(a.bodyY, b.bodyY),
            bodyRotation: lerp(a.bodyRotation, b.bodyRotation),
            bodyScaleX: lerp(a.bodyScaleX, b.bodyScaleX),
            bodyScaleY: lerp(a.bodyScaleY, b.bodyScaleY),
            headX: lerp(a.headX, b.headX),
            headY: lerp(a.headY, b.headY),
            headRotation: lerp(a.headRotation, b.headRotation),
            headScale: lerp(a.headScale, b.headScale),
            eyeOpen: lerp(a.eyeOpen, b.eyeOpen),
            pupilX: lerp(a.pupilX, b.pupilX),
            pupilY: lerp(a.pupilY, b.pupilY),
            earLeft: lerp(a.earLeft, b.earLeft),
            earRight: lerp(a.earRight, b.earRight),
            tailSway: lerp(a.tailSway, b.tailSway),
            tailLift: lerp(a.tailLift, b.tailLift),
            frontFarAngle: lerp(a.frontFarAngle, b.frontFarAngle),
            frontNearAngle: lerp(a.frontNearAngle, b.frontNearAngle),
            hindFarAngle: lerp(a.hindFarAngle, b.hindFarAngle),
            hindNearAngle: lerp(a.hindNearAngle, b.hindNearAngle),
            frontFarLift: lerp(a.frontFarLift, b.frontFarLift),
            frontNearLift: lerp(a.frontNearLift, b.frontNearLift),
            hindFarLift: lerp(a.hindFarLift, b.hindFarLift),
            hindNearLift: lerp(a.hindNearLift, b.hindNearLift),
            pawReach: lerp(a.pawReach, b.pawReach),
            mouthOpen: lerp(a.mouthOpen, b.mouthOpen),
            workSurface: lerp(a.workSurface, b.workSurface),
            keyPulse: lerp(a.keyPulse, b.keyPulse),
            walkPhase: lerp(a.walkPhase, b.walkPhase),
            walkBlend: lerp(a.walkBlend, b.walkBlend),
            opacity: lerp(a.opacity, b.opacity)
        )
    }

    static func sample(_ mode: CatRigMode, time: Double) -> CatPose {
        var pose = CatPose()
        let breathe = sin(time * CatMotionMath.tau / 3.6)
        pose.bodyY += breathe * 1.25
        pose.bodyScaleY += breathe * 0.012
        pose.headY += breathe * 0.45
        pose.eyeOpen = CatMotionMath.blink(at: time)
        let ear = CatMotionMath.earFlick(at: time)
        pose.earLeft -= ear * 7
        pose.earRight += ear * 3
        pose.tailSway = sin(time * 1.32) * 7 + sin(time * 0.47) * 3

        switch mode {
        case .idle:
            let curiousBeat = CatMotionMath.pulse(
                (time / 9.5).truncatingRemainder(dividingBy: 1),
                center: 0.72,
                width: 0.11
            )
            pose.headRotation += curiousBeat * 4
            pose.pupilX += curiousBeat * 1.2

        case .walkLeft, .walkRight:
            let cycle = time * 1.12
            pose.walkPhase = cycle.truncatingRemainder(dividingBy: 1)
            pose.walkBlend = 1
            let stride = sin(cycle * CatMotionMath.tau)
            let counterStride = -stride
            pose.bodyY += abs(stride) * 1.55
            pose.bodyRotation = stride * 0.75
            pose.headY -= abs(stride) * 0.45
            pose.headRotation = -pose.bodyRotation * 0.42
            // A diagonal-pair feline gait. Positive rotation moves the paw
            // toward the cat's native screen-left facing direction, and the
            // paw lifts during that forward swing instead of on the backstroke.
            pose.frontNearAngle = stride * 10
            pose.hindFarAngle = stride * 8
            pose.frontFarAngle = counterStride * 10
            pose.hindNearAngle = counterStride * 8
            pose.frontNearLift = max(0, stride) * 6
            pose.hindFarLift = max(0, stride) * 5
            pose.frontFarLift = max(0, counterStride) * 6
            pose.hindNearLift = max(0, counterStride) * 5
            pose.tailSway = -sin(cycle * CatMotionMath.tau - 0.65) * 10
            pose.tailLift = 5

        case .thinking:
            pose.headRotation = -8 + sin(time * 0.8) * 1.5
            pose.headY += 1
            pose.pupilX = 2.1
            pose.pupilY = 1.4
            pose.earLeft -= 7
            pose.earRight += 5
            pose.frontNearAngle = -34
            pose.frontNearLift = 18
            pose.pawReach = -2
            pose.workSurface = 0.88
            pose.tailSway = sin(time * 2.8) * 3

        case .working:
            let cycle = time * 3.4
            let nearTap = max(0, sin(cycle * CatMotionMath.tau))
            let farTap = max(0, -sin(cycle * CatMotionMath.tau))
            pose.bodyX += 3
            pose.bodyY += 2
            pose.bodyRotation = sin(cycle * 0.62) * 1.1
            pose.headX += 3
            pose.headY += 7 + sin(cycle * 0.5) * 1.3
            pose.headRotation = 4 + sin(cycle * 0.42) * 2.2
            pose.frontNearAngle = -28 + nearTap * 17
            pose.frontFarAngle = -28 + farTap * 17
            pose.frontNearLift = 13 - nearTap * 4
            pose.frontFarLift = 13 - farTap * 4
            pose.pawReach = 2 + nearTap * 4
            pose.pupilX = sin(cycle * 0.7) * 1.8
            pose.pupilY = 1.3
            pose.tailSway = sin(cycle * 0.55) * 6
            pose.workSurface = 1
            pose.keyPulse = max(nearTap, farTap)

        case .waiting:
            pose.bodyX += 3
            pose.headX += 4
            pose.headY -= 2
            pose.headRotation = sin(time * 1.3) * 2
            pose.earLeft += 4
            pose.earRight -= 4
            pose.tailLift = 7
            pose.tailSway = sin(time * 1.8) * 5

        case .waitingAuthorization:
            let hesitant = CatMotionMath.pulse(
                (time / 4.6).truncatingRemainder(dividingBy: 1),
                center: 0.62,
                width: 0.18
            )
            pose.bodyY += 2
            pose.headRotation = 4
            pose.earLeft -= 7
            pose.earRight -= 3
            pose.frontNearAngle = -hesitant * 26
            pose.frontNearLift = hesitant * 13
            pose.pawReach = hesitant * 4
            pose.tailSway = sin(time * 1.2) * 3

        case .sniffing:
            let sniff = sin(time * 5.2)
            pose.bodyX += 5
            pose.bodyY += 2
            pose.headX += 14 + sniff * 1.2
            pose.headY += 19 + abs(sniff) * 2
            pose.headRotation = 13 + sniff * 2.5
            pose.pupilX = 2.2
            pose.pupilY = 2.1
            pose.earLeft -= 3
            pose.earRight += 5
            pose.frontNearAngle = -18
            pose.frontNearLift = 5
            pose.tailLift = 6
            pose.tailSway = sin(time * 2.4) * 5

        case .pawing:
            let cycle = (time / 1.25).truncatingRemainder(dividingBy: 1)
            let prepare = CatMotionMath.pulse(cycle, center: 0.18, width: 0.18)
            let tap = CatMotionMath.pulse(cycle, center: 0.48, width: 0.22)
            pose.bodyX += 6 + tap * 2
            pose.bodyY += prepare * 2
            pose.bodyRotation = -3 - tap * 2
            pose.headX += 10 + tap * 3
            pose.headY += 8
            pose.headRotation = 8 + tap * 4
            pose.pupilX = 2.4
            pose.pupilY = 1.2
            pose.frontNearAngle = -47 + tap * 24
            pose.frontNearLift = 23 - tap * 5
            pose.pawReach = 6 + tap * 14
            pose.tailLift = 10
            pose.tailSway = -sin(cycle * CatMotionMath.tau - 0.4) * 9

        case .pouncing:
            let cycle = (time / 2.25).truncatingRemainder(dividingBy: 1)
            let crouch = CatMotionMath.pulse(cycle, center: 0.16, width: 0.15)
            let leap = CatMotionMath.pulse(cycle, center: 0.48, width: 0.29)
            let land = CatMotionMath.pulse(cycle, center: 0.78, width: 0.1)
            pose.bodyX += leap * 14
            pose.bodyY += crouch * 7 - leap * 17 + land * 4
            pose.headX += leap * 18
            pose.headY += crouch * 5 - leap * 19 + land * 2
            pose.bodyScaleX += crouch * 0.06 - leap * 0.025
            pose.bodyScaleY -= crouch * 0.08 - leap * 0.04
            pose.headRotation = -leap * 4
            pose.frontFarLift = leap * 12
            pose.frontNearLift = leap * 15
            pose.hindFarLift = leap * 8
            pose.hindNearLift = leap * 8
            pose.frontNearAngle = -leap * 27
            pose.frontFarAngle = -leap * 20
            pose.tailLift = 7 + leap * 12
            pose.tailSway = -sin(cycle * CatMotionMath.tau) * 11

        case .success:
            let phase = (time / 1.65).truncatingRemainder(dividingBy: 1)
            let jump = sin(min(1, phase / 0.72) * Double.pi)
            pose.bodyY -= max(0, jump) * 17
            pose.headY -= max(0, jump) * 20
            pose.bodyRotation = sin(phase * CatMotionMath.tau) * 3
            pose.bodyScaleY += (1 - jump) * 0.035
            pose.tailLift = 14
            pose.tailSway = sin(phase * CatMotionMath.tau) * 12
            pose.mouthOpen = 1

        case .error:
            pose.bodyY += 6
            pose.bodyScaleY = 0.93
            pose.headY += 7
            pose.headRotation = 5
            pose.earLeft -= 16
            pose.earRight += 16
            pose.eyeOpen = min(pose.eyeOpen, 0.72)
            pose.pupilY = 1.8
            pose.tailLift = -8
            pose.tailSway = sin(time * 0.8) * 2

        case .sleeping:
            pose.bodyX = 145
            pose.bodyY = 184 + breathe * 1.6
            pose.bodyScaleX = 1.1
            pose.bodyScaleY = 0.78 + breathe * 0.016
            pose.headX = 185
            pose.headY = 170 + breathe * 1.1
            pose.headRotation = 7
            pose.headScale = 0.9
            pose.eyeOpen = 0.03
            pose.earLeft -= 7
            pose.earRight += 5
            pose.tailSway = -28
            pose.tailLift = -9
            pose.frontFarLift = 12
            pose.frontNearLift = 12

        case .stretch:
            let phase = (time / 4.8).truncatingRemainder(dividingBy: 1)
            let hold = CatMotionMath.smoothstep(min(1, phase / 0.25))
                * (1 - CatMotionMath.smoothstep(max(0, (phase - 0.78) / 0.22)))
            pose.bodyX -= hold * 7
            pose.bodyY -= hold * 9
            pose.bodyRotation = -hold * 7
            pose.bodyScaleX += hold * 0.1
            pose.headX += hold * 17
            pose.headY += hold * 28
            pose.headRotation = hold * 8
            pose.frontFarAngle = -hold * 31
            pose.frontNearAngle = -hold * 35
            pose.pawReach = hold * 15
            pose.tailLift = hold * 16
            pose.eyeOpen = min(pose.eyeOpen, 1 - hold * 0.5)

        case .grooming:
            let cycle = time * 1.2
            let lift = 0.5 + 0.5 * sin(cycle)
            pose.frontNearAngle = -34 - lift * 18
            pose.frontNearLift = 18 + lift * 8
            pose.pawReach = -4
            pose.headX -= lift * 10
            pose.headY += lift * 11
            pose.headRotation = -10 - lift * 10
            pose.eyeOpen = min(pose.eyeOpen, 0.62)
            pose.mouthOpen = CatMotionMath.pulse(
                (cycle / CatMotionMath.tau).truncatingRemainder(dividingBy: 1),
                center: 0.56,
                width: 0.18
            )

        case .hop:
            let phase = (time / 2.3).truncatingRemainder(dividingBy: 1)
            let crouch = CatMotionMath.pulse(phase, center: 0.14, width: 0.14)
            let air = CatMotionMath.pulse(phase, center: 0.48, width: 0.3)
            let land = CatMotionMath.pulse(phase, center: 0.79, width: 0.1)
            pose.bodyY += crouch * 7 - air * 24 + land * 5
            pose.headY += crouch * 5 - air * 27 + land * 3
            pose.bodyScaleY += crouch * -0.08 + air * 0.05 + land * -0.07
            pose.bodyScaleX += crouch * 0.05 + air * -0.03 + land * 0.05
            pose.frontFarLift = air * 13
            pose.frontNearLift = air * 13
            pose.hindFarLift = air * 9
            pose.hindNearLift = air * 9
            pose.tailLift = air * 12

        case .wave:
            let cycle = time * 2.1
            let wave = 0.5 + 0.5 * sin(cycle * CatMotionMath.tau)
            pose.bodyRotation = -3
            pose.headRotation = 3
            pose.frontNearAngle = -47 + wave * 19
            pose.frontNearLift = 25
            pose.pawReach = -5
            pose.tailSway = sin(cycle * 1.1) * 8

        case .curious:
            let cycle = time * 0.72
            pose.headRotation = sin(cycle) * 7
            pose.headX += sin(cycle * 0.55) * 3
            pose.headY -= abs(sin(cycle)) * 2
            pose.pupilX = sin(cycle * 1.4) * 2
            pose.pupilY = cos(cycle * 0.8) * 1.2
            pose.earLeft += sin(cycle * 1.15) * 4
            pose.earRight -= sin(cycle * 0.92) * 4
            pose.tailSway = sin(cycle * 1.6 - 0.7) * 9
        }
        return pose
    }
}

private enum CatRigPainter {
    private static let outline = Color(red: 0.035, green: 0.055, blue: 0.16)
    private static let white = Color(red: 0.98, green: 0.985, blue: 0.99)
    private static let shade = Color(red: 0.73, green: 0.87, blue: 0.96)
    private static let cyan = Color(red: 0.31, green: 0.75, blue: 0.94)

    static func draw(
        _ pose: CatPose,
        facesLeft: Bool,
        mode: CatRigMode,
        previousMode: CatRigMode,
        transition: Double,
        animationTime: Double,
        in context: inout GraphicsContext
    ) {
        AnimeCatPainter.draw(
            pose,
            facesLeft: facesLeft,
            mode: mode,
            previousMode: previousMode,
            transition: transition,
            animationTime: animationTime,
            in: &context
        )
    }

    private static func drawKeyboard(_ pose: CatPose, in context: inout GraphicsContext) {
        guard pose.workSurface > 0.01 else { return }
        var layer = context
        layer.opacity = pose.workSurface

        let deck = Path(
            roundedRect: CGRect(x: 151, y: 220, width: 104, height: 27),
            cornerRadius: 8
        )
        layer.fill(deck, with: .color(outline.opacity(0.96)))
        layer.stroke(deck, with: .color(cyan.opacity(0.84)), lineWidth: 2.4)

        for row in 0..<2 {
            for column in 0..<7 {
                let isActive = (column + row * 2) % 4 == Int(pose.keyPulse * 3.9)
                let key = Path(
                    roundedRect: CGRect(
                        x: 159 + CGFloat(column) * 12.5,
                        y: 225 + CGFloat(row) * 8.2,
                        width: 8.5,
                        height: 5.2
                    ),
                    cornerRadius: 1.8
                )
                layer.fill(
                    key,
                    with: .color(
                        isActive
                            ? cyan
                            : shade.opacity(0.62)
                    )
                )
            }
        }
    }

    private static func drawTail(_ pose: CatPose, in context: inout GraphicsContext) {
        let sway = pose.tailSway
        let lift = pose.tailLift
        var tail = Path()
        tail.move(to: CGPoint(x: pose.bodyX - 45, y: pose.bodyY - 2))
        tail.addCurve(
            to: CGPoint(x: pose.bodyX - 88 + sway * 0.45, y: pose.bodyY - 28 - lift),
            control1: CGPoint(x: pose.bodyX - 69, y: pose.bodyY + 4),
            control2: CGPoint(x: pose.bodyX - 94 + sway, y: pose.bodyY - 2 - lift * 0.7)
        )
        context.stroke(tail, with: .color(outline), style: StrokeStyle(lineWidth: 19, lineCap: .round))
        context.stroke(tail, with: .color(white), style: StrokeStyle(lineWidth: 12, lineCap: .round))
    }

    private static func drawBody(_ pose: CatPose, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: pose.bodyX, y: pose.bodyY)
        layer.rotate(by: .degrees(pose.bodyRotation))
        layer.scaleBy(x: pose.bodyScaleX, y: pose.bodyScaleY)
        let body = Path(ellipseIn: CGRect(x: -53, y: -36, width: 106, height: 72))
        layer.fill(body, with: .color(white))
        layer.stroke(body, with: .color(outline), lineWidth: 5)
        let chest = Path(ellipseIn: CGRect(x: 18, y: -23, width: 23, height: 43))
        layer.fill(chest, with: .color(shade.opacity(0.58)))
    }

    private static func drawLeg(
        x: Double,
        _ angle: Double,
        _ lift: Double,
        far: Bool,
        pose: CatPose,
        in context: inout GraphicsContext
    ) {
        var layer = context
        layer.translateBy(x: x, y: pose.bodyY + 18 - lift)
        layer.rotate(by: .degrees(angle))
        let leg = Path(roundedRect: CGRect(x: -10, y: -5, width: 20, height: 43), cornerRadius: 10)
        layer.fill(leg, with: .color(far ? shade.opacity(0.9) : white))
        layer.stroke(leg, with: .color(outline), lineWidth: far ? 4 : 5)
        let paw = Path(ellipseIn: CGRect(x: -14, y: 28, width: 28, height: 15))
        layer.fill(paw, with: .color(far ? shade.opacity(0.9) : white))
        layer.stroke(paw, with: .color(outline), lineWidth: far ? 4 : 5)
    }

    private static func drawHead(_ pose: CatPose, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: pose.headX, y: pose.headY)
        layer.rotate(by: .degrees(pose.headRotation))
        layer.scaleBy(x: pose.headScale, y: pose.headScale)

        drawEar(x: -26, rotation: -7 + pose.earLeft, mirror: false, in: &layer)
        drawEar(x: 27, rotation: 7 + pose.earRight, mirror: true, in: &layer)

        let head = Path(roundedRect: CGRect(x: -46, y: -36, width: 92, height: 77), cornerRadius: 31)
        layer.fill(head, with: .color(white))
        layer.stroke(head, with: .color(outline), lineWidth: 5)

        drawEye(x: -20, pose: pose, in: &layer)
        drawEye(x: 20, pose: pose, in: &layer)

        let nose = Path(roundedRect: CGRect(x: -5, y: 11, width: 10, height: 7), cornerRadius: 3)
        layer.fill(nose, with: .color(outline))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 0, y: 18))
        mouth.addCurve(
            to: CGPoint(x: 12, y: 18 + pose.mouthOpen * 3),
            control1: CGPoint(x: 4, y: 23 + pose.mouthOpen * 3),
            control2: CGPoint(x: 9, y: 23 + pose.mouthOpen * 3)
        )
        layer.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        for side in [-1.0, 1.0] {
            for offset in [-5.0, 2.0, 9.0] {
                var whisker = Path()
                whisker.move(to: CGPoint(x: side * 31, y: 16 + offset * 0.35))
                whisker.addLine(to: CGPoint(x: side * 53, y: 14 + offset))
                layer.stroke(whisker, with: .color(outline), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }
    }

    private static func drawEar(
        x: Double,
        rotation: Double,
        mirror: Bool,
        in context: inout GraphicsContext
    ) {
        var layer = context
        layer.translateBy(x: x, y: -28)
        layer.rotate(by: .degrees(rotation))
        if mirror { layer.scaleBy(x: -1, y: 1) }
        var ear = Path()
        ear.move(to: CGPoint(x: -16, y: 6))
        ear.addLine(to: CGPoint(x: -7, y: -31))
        ear.addLine(to: CGPoint(x: 17, y: 3))
        ear.closeSubpath()
        layer.fill(ear, with: .color(white))
        layer.stroke(ear, with: .color(outline), style: StrokeStyle(lineWidth: 5, lineJoin: .round))

        var inner = Path()
        inner.move(to: CGPoint(x: -8, y: 0))
        inner.addLine(to: CGPoint(x: -5, y: -19))
        inner.addLine(to: CGPoint(x: 8, y: 0))
        inner.closeSubpath()
        layer.fill(inner, with: .color(cyan))
    }

    private static func drawEye(x: Double, pose: CatPose, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: x + pose.pupilX, y: -1 + pose.pupilY)
        layer.scaleBy(x: 1, y: max(0.045, pose.eyeOpen))
        let eye = Path(ellipseIn: CGRect(x: -8, y: -10, width: 16, height: 21))
        layer.fill(eye, with: .color(outline))
        let glint = Path(ellipseIn: CGRect(x: -3.5, y: -6.5, width: 4.2, height: 4.2))
        layer.fill(glint, with: .color(.white))
    }
}

/// High-fidelity anime artwork stays rasterized, while every piece is moved by
/// the same continuously sampled rig. This preserves illustration quality
/// without returning to frame-by-frame animation.
private enum AnimeCatPainter {
    private static let wholeCat = AnimeCatAssets.image("anime-cat-whole")
    private static let walkRight = (0..<8).map {
        AnimeCatAssets.image("anime-cat-walk-right-\($0)")
    }
    private static let walkLeft = (0..<8).map {
        AnimeCatAssets.image("anime-cat-walk-left-\($0)")
    }
    private static let thinking = (0..<8).map {
        AnimeCatAssets.image("anime-cat-state-thinking-\($0)")
    }
    private static let working = (0..<8).map {
        AnimeCatAssets.image("anime-cat-state-working-\($0)")
    }
    private static let waitingAuth = AnimeCatAssets.image("anime-cat-state-waiting-auth")
    private static let sleeping = AnimeCatAssets.image("anime-cat-state-sleeping")
    private static let stretching = AnimeCatAssets.image("anime-cat-state-stretch")
    private static let grooming = AnimeCatAssets.image("anime-cat-state-grooming")
    private static let waving = AnimeCatAssets.image("anime-cat-state-wave")

    static func draw(
        _ pose: CatPose,
        facesLeft: Bool,
        mode: CatRigMode,
        previousMode: CatRigMode,
        transition: Double,
        animationTime: Double,
        in context: inout GraphicsContext
    ) {
        let blend = max(0, min(1, transition))
        var layer = context
        layer.opacity = pose.opacity
        let visualMode = previousMode != mode
            ? CatTransitionChoreography.visualMode(
                from: previousMode,
                to: mode,
                progress: blend
            )
            : mode
        let visualFacesLeft = visualMode.facesLeft || facesLeft
        let visualTime = visualMode == mode
            ? animationTime
            : 0
        if visualMode == .walkLeft || visualMode == .walkRight {
            PetFootstepPainter.draw(
                character: .cat,
                elapsed: visualTime,
                movesLeft: visualMode == .walkLeft,
                cycleDuration: 1.0 / 1.12,
                in: &layer
            )
        }
        drawMode(
            visualMode,
            pose: pose,
            facesLeft: visualFacesLeft,
            animationTime: visualTime,
            in: &layer
        )
    }

    private static func drawMode(
        _ mode: CatRigMode,
        pose: CatPose,
        facesLeft: Bool,
        animationTime: Double,
        in context: inout GraphicsContext
    ) {
        switch mode {
        case .walkLeft:
            drawWalkCat(animationTime: animationTime, facesLeft: true, in: &context)
        case .walkRight:
            drawWalkCat(animationTime: animationTime, facesLeft: false, in: &context)
        case .thinking:
            let frame = min(7, max(0, Int(floor(animationTime / 1.18)) % 8))
            drawStateCat(thinking[frame], pose: pose, in: &context)
        case .working:
            let sample = PetWorkingCadence.sample(at: animationTime)
            drawStateCat(
                working[sample.frame],
                pose: pose,
                workingSample: sample,
                in: &context
            )
        case .waiting, .waitingAuthorization:
            drawStateCat(waitingAuth, pose: pose, in: &context)
        case .sleeping:
            drawStateCat(sleeping, pose: pose, in: &context)
        case .stretch:
            drawStateCat(stretching, pose: pose, in: &context)
        case .grooming:
            drawStateCat(grooming, pose: pose, in: &context)
        case .wave, .success:
            drawStateCat(waving, pose: pose, in: &context)
        case .idle, .sniffing, .pawing, .pouncing, .error, .hop, .curious:
            drawWholeCat(
                pose,
                facesLeft: facesLeft,
                in: &context
            )
        }
    }

    /// Keep the approved illustration intact. Generated puppet pieces drifted
    /// from the master face and their independent joints visibly tore apart.
    /// Motion is therefore applied to the complete character as a restrained
    /// rigid transform until a future pose family passes identity QA.
    private static func drawWholeCat(
        _ pose: CatPose,
        facesLeft: Bool,
        in context: inout GraphicsContext
    ) {
        var layer = context
        // The approved master naturally faces screen-left. Mirror the intact
        // image only for rightward attention or travel.
        if !facesLeft {
            layer.translateBy(x: 285, y: 0)
            layer.scaleBy(x: -1, y: 1)
        }
        let motionX = clamped(
            (pose.bodyX - 142) * 0.34 + (pose.headX - 181) * 0.10,
            -6,
            8
        )
        let motionY = clamped(
            (pose.bodyY - 174) * 0.52 + (pose.headY - 130) * 0.12,
            -15,
            14
        )
        let rotation = clamped(
            pose.bodyRotation * 0.38 + pose.headRotation * 0.06,
            -2.4,
            2.4
        )
        let uniformScale = clamped(
            1 + (pose.bodyScaleX + pose.bodyScaleY - 2) * 0.10,
            0.975,
            1.035
        )
        layer.translateBy(
            x: 132 + motionX,
            y: 156 + motionY
        )
        layer.rotate(by: .degrees(rotation))
        layer.scaleBy(x: uniformScale, y: uniformScale)
        layer.draw(
            layer.resolve(wholeCat),
            in: CGRect(x: -93, y: -96, width: 186, height: 192)
        )
    }

    private static func drawStateCat(
        _ image: Image,
        pose: CatPose,
        workingSample: PetWorkingAnimationSample? = nil,
        in context: inout GraphicsContext
    ) {
        var layer = context
        // The eight authored typing frames contain the real paw mechanics.
        // Do not re-apply the procedural root motion that previously made the
        // complete cat shake while its paws stayed frozen.
        let motionX = workingSample == nil
            ? clamped((pose.bodyX - 142) * 0.28 + (pose.headX - 181) * 0.06, -5, 6)
            : 0
        let motionY = workingSample == nil
            ? clamped((pose.bodyY - 174) * 0.48 + (pose.headY - 130) * 0.08, -15, 14)
            : 0
        let rotation = workingSample == nil
            ? clamped(pose.bodyRotation * 0.26 + pose.headRotation * 0.035, -1.8, 1.8)
            : 0
        layer.translateBy(x: 132 + motionX, y: 154 + motionY)
        layer.rotate(by: .degrees(rotation))
        layer.draw(
            layer.resolve(image),
            in: CGRect(x: -92, y: -99.5, width: 184, height: 199)
        )
        if let workingSample {
            drawWorkingKeyPulse(sample: workingSample, in: &layer)
        }
    }

    private static func drawWorkingKeyPulse(
        sample: PetWorkingAnimationSample,
        in context: inout GraphicsContext
    ) {
        let cyan = Color(red: 0.16, green: 0.82, blue: 1)
        for (x, strength) in [
            (-25.0, sample.leftKeyStrength),
            (16.0, sample.rightKeyStrength),
        ] where strength > 0.015 {
            let glow = Path(
                roundedRect: CGRect(x: x - 4.2, y: 63.8, width: 8.4, height: 4.4),
                cornerRadius: 1.6
            )
            context.fill(glow, with: .color(cyan.opacity(0.10 + strength * 0.22)))
            let key = Path(
                roundedRect: CGRect(x: x - 3, y: 64.7, width: 6, height: 2.7),
                cornerRadius: 1.1
            )
            context.fill(
                key,
                with: .color(cyan.opacity(0.40 + strength * 0.60))
            )
        }
    }

    private static func drawWalkCat(
        animationTime: Double,
        facesLeft: Bool,
        in context: inout GraphicsContext
    ) {
        let phase = (animationTime * 1.12).truncatingRemainder(dividingBy: 1)
        let frameIndex = min(7, max(0, Int(floor(phase * 8))))
        let frame = facesLeft ? walkLeft[frameIndex] : walkRight[frameIndex]

        let layer = context
        // Generated frames already contain the correct travel direction, so
        // never mirror them again. Keeping all eight full poses on one stable
        // baseline provides real paw lift/contact instead of window sliding.
        layer.draw(
            layer.resolve(frame),
            in: CGRect(x: 40, y: 54, width: 184, height: 199)
        )
    }

    private static func clamped(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

private enum AnimeCatAssets {
    static func image(_ name: String) -> Image {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            NSLog("[CodexPulse] Missing anime cat resource: %@.png", name)
            return Image(nsImage: NSImage(size: NSSize(width: 1, height: 1)))
        }
        return Image(nsImage: image)
    }
}
