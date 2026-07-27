import SwiftUI

struct ProceduralFoxView: View {
    let animationState: PetAnimationState
    let roamingActivity: CatRoamingActivity?
    let facesLeft: Bool
    let showsIdleContent: Bool
    let reduceMotion: Bool

    private var mode: FoxRigMode {
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
            case .none: return .idle
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
        FoxRigTimeline(mode: mode, facesLeft: facesLeft, reduceMotion: reduceMotion)
            .accessibilityHidden(true)
    }
}

private enum FoxRigMode: Equatable {
    case idle, walkLeft, walkRight, thinking, working, waiting, waitingAuthorization
    case sniffing, pawing, pouncing, success, error, sleeping, stretch, grooming, hop, wave, curious

    var facesLeft: Bool { self == .walkLeft }
}

private struct FoxRigTimeline: View {
    let mode: FoxRigMode
    let facesLeft: Bool
    let reduceMotion: Bool

    @State private var currentMode: FoxRigMode
    @State private var previousMode: FoxRigMode
    @State private var transitionFromPose: FoxPose
    @State private var transitionStartedAt: TimeInterval

    init(mode: FoxRigMode, facesLeft: Bool, reduceMotion: Bool) {
        self.mode = mode
        self.facesLeft = facesLeft
        self.reduceMotion = reduceMotion
        let now = Date.timeIntervalSinceReferenceDate
        _currentMode = State(initialValue: mode)
        _previousMode = State(initialValue: mode)
        _transitionFromPose = State(initialValue: FoxPose.sample(mode, time: now))
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
                FoxRigPainter.draw(
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
            previousMode = currentMode
            currentMode = newValue
            transitionStartedAt = now
        }
    }

    private func renderedPose(at time: TimeInterval) -> FoxPose {
        let blend = transitionBlend(at: time)
        return FoxPose.mix(
            transitionFromPose,
            FoxPose.sample(currentMode, time: time),
            blend
        )
    }

    private func transitionBlend(at time: TimeInterval) -> Double {
        let elapsed = max(0, time - transitionStartedAt)
        return reduceMotion ? 1 : FoxMotionMath.smoothstep(min(1, elapsed / 0.34))
    }
}

private enum FoxMotionMath {
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

private struct FoxPose {
    var bodyX = 150.0, bodyY = 170.0
    var bodyRotation = 0.0
    var bodyScaleX = 1.0, bodyScaleY = 1.0
    var headX = 185.0, headY = 125.0
    var headRotation = 0.0
    var headScale = 1.0
    var eyeOpen = 1.0
    var pupilX = 0.0, pupilY = 0.0
    var mouthOpen = 0.0
    var earLeftAngle = 0.0, earRightAngle = 0.0
    var earLeftFlatten = 0.0, earRightFlatten = 0.0
    var foreheadRuneGlow = 0.6
    var energyBurst = 0.0
    var tailBaseAngle = 0.0
    var tailSpread = 0.7
    var tailSway = 0.0
    var tailLift = 0.0
    var tailEnergy = 0.5
    var frontFarAngle = 0.0, frontNearAngle = 0.0
    var hindFarAngle = 0.0, hindNearAngle = 0.0
    var frontFarLift = 0.0, frontNearLift = 0.0
    var hindFarLift = 0.0, hindNearLift = 0.0
    var pawReach = 0.0
    var workSurface = 0.0
    var keyPulse = 0.0
    var walkPhase = 0.0, walkBlend = 0.0
    var opacity = 1.0

    static func mix(_ a: FoxPose, _ b: FoxPose, _ t: Double) -> FoxPose {
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return FoxPose(
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
            mouthOpen: lerp(a.mouthOpen, b.mouthOpen),
            earLeftAngle: lerp(a.earLeftAngle, b.earLeftAngle),
            earRightAngle: lerp(a.earRightAngle, b.earRightAngle),
            earLeftFlatten: lerp(a.earLeftFlatten, b.earLeftFlatten),
            earRightFlatten: lerp(a.earRightFlatten, b.earRightFlatten),
            foreheadRuneGlow: lerp(a.foreheadRuneGlow, b.foreheadRuneGlow),
            energyBurst: lerp(a.energyBurst, b.energyBurst),
            tailBaseAngle: lerp(a.tailBaseAngle, b.tailBaseAngle),
            tailSpread: lerp(a.tailSpread, b.tailSpread),
            tailSway: lerp(a.tailSway, b.tailSway),
            tailLift: lerp(a.tailLift, b.tailLift),
            tailEnergy: lerp(a.tailEnergy, b.tailEnergy),
            frontFarAngle: lerp(a.frontFarAngle, b.frontFarAngle),
            frontNearAngle: lerp(a.frontNearAngle, b.frontNearAngle),
            hindFarAngle: lerp(a.hindFarAngle, b.hindFarAngle),
            hindNearAngle: lerp(a.hindNearAngle, b.hindNearAngle),
            frontFarLift: lerp(a.frontFarLift, b.frontFarLift),
            frontNearLift: lerp(a.frontNearLift, b.frontNearLift),
            hindFarLift: lerp(a.hindFarLift, b.hindFarLift),
            hindNearLift: lerp(a.hindNearLift, b.hindNearLift),
            pawReach: lerp(a.pawReach, b.pawReach),
            workSurface: lerp(a.workSurface, b.workSurface),
            keyPulse: lerp(a.keyPulse, b.keyPulse),
            walkPhase: lerp(a.walkPhase, b.walkPhase),
            walkBlend: lerp(a.walkBlend, b.walkBlend),
            opacity: lerp(a.opacity, b.opacity)
        )
    }

    static func sample(_ mode: FoxRigMode, time: Double) -> FoxPose {
        var pose = FoxPose()
        let breathe = sin(time * FoxMotionMath.tau / 3.6)
        pose.bodyY += breathe * 1.1
        pose.bodyScaleY += breathe * 0.012
        pose.headY += breathe * 0.4
        pose.eyeOpen = FoxMotionMath.blink(at: time)
        let ear = FoxMotionMath.earFlick(at: time)
        pose.earLeftAngle -= ear * 6
        pose.earRightAngle += ear * 4
        pose.tailSway = sin(time * 1.15) * 10 + sin(time * 0.41) * 4

        switch mode {
        case .idle:
            pose.tailSpread = 0.75
            pose.tailBaseAngle = 5
            pose.tailLift = 3
            pose.tailEnergy = 0.5
            let curiousBeat = FoxMotionMath.pulse(
                (time / 9.5).truncatingRemainder(dividingBy: 1),
                center: 0.72, width: 0.11
            )
            pose.headRotation += curiousBeat * 5
            pose.pupilX += curiousBeat * 1.2

        case .walkLeft, .walkRight:
            let cycle = time * 1.12
            pose.walkPhase = cycle.truncatingRemainder(dividingBy: 1)
            pose.walkBlend = 1
            let stride = sin(cycle * FoxMotionMath.tau)
            let counterStride = -stride
            pose.bodyY += abs(stride) * 1.4
            pose.bodyRotation = stride * 0.8
            pose.headY -= abs(stride) * 0.4
            pose.headRotation = -pose.bodyRotation * 0.4
            pose.frontNearAngle = stride * 10
            pose.hindFarAngle = stride * 8
            pose.frontFarAngle = counterStride * 10
            pose.hindNearAngle = counterStride * 8
            pose.frontNearLift = max(0, stride) * 6
            pose.hindFarLift = max(0, stride) * 5
            pose.frontFarLift = max(0, counterStride) * 6
            pose.hindNearLift = max(0, counterStride) * 5
            pose.tailSpread = 0.5
            pose.tailBaseAngle = 2
            pose.tailSway = -sin(cycle * FoxMotionMath.tau - 0.65) * 10

        case .thinking:
            pose.headRotation = -10 + sin(time * 0.8) * 1.5
            pose.headY += 1
            pose.pupilX = 2.0
            pose.pupilY = 1.2
            pose.earLeftAngle -= 10
            pose.earRightAngle += 4
            pose.frontNearAngle = -32
            pose.frontNearLift = 16
            pose.pawReach = -2
            pose.tailSpread = 0.4
            pose.tailBaseAngle = -8
            pose.tailLift = 5
            pose.workSurface = 0.88

        case .working:
            let cycle = time * 3.4
            let nearTap = max(0, sin(cycle * FoxMotionMath.tau))
            let farTap = max(0, -sin(cycle * FoxMotionMath.tau))
            pose.bodyX += 3
            pose.bodyY += 2
            pose.bodyRotation = sin(cycle * 0.62) * 1.1
            pose.headX += 3
            pose.headY += 7 + sin(cycle * 0.5) * 1.3
            pose.headRotation = 4 + sin(cycle * 0.42) * 2.2
            pose.earLeftFlatten = 0.55
            pose.earRightFlatten = 0.55
            pose.frontNearAngle = -26 + nearTap * 15
            pose.frontFarAngle = -26 + farTap * 15
            pose.frontNearLift = 12 - nearTap * 4
            pose.frontFarLift = 12 - farTap * 4
            pose.pawReach = 2 + nearTap * 4
            pose.pupilX = sin(cycle * 0.7) * 1.8
            pose.pupilY = 1.2
            pose.tailSpread = 0.3
            pose.tailBaseAngle = 0
            pose.tailLift = 2
            pose.tailEnergy = 0.8
            pose.workSurface = 1
            pose.keyPulse = max(nearTap, farTap)

        case .waiting:
            pose.bodyX += 3
            pose.headX += 4
            pose.headY -= 2
            pose.headRotation = sin(time * 1.3) * 2
            pose.earLeftAngle += 4
            pose.earRightAngle -= 4
            pose.tailSpread = 0.6
            pose.tailBaseAngle = 8
            pose.tailLift = 6
            pose.tailSway = sin(time * 1.8) * 6

        case .waitingAuthorization:
            let hesitant = FoxMotionMath.pulse(
                (time / 4.6).truncatingRemainder(dividingBy: 1),
                center: 0.62, width: 0.18
            )
            pose.bodyY += 2
            pose.headRotation = 4
            pose.earLeftAngle -= 6
            pose.earRightAngle -= 3
            pose.frontNearAngle = -hesitant * 24
            pose.frontNearLift = hesitant * 12
            pose.pawReach = hesitant * 4
            pose.tailSpread = 0.5
            pose.tailBaseAngle = -5
            pose.tailLift = 3

        case .sniffing:
            let sniff = sin(time * 5.2)
            pose.bodyX += 5
            pose.bodyY += 2
            pose.headX += 12 + sniff * 1.2
            pose.headY += 18 + abs(sniff) * 2
            pose.headRotation = 12 + sniff * 2.5
            pose.pupilX = 2.0
            pose.pupilY = 2.0
            pose.earLeftAngle -= 3
            pose.earRightAngle += 5
            pose.frontNearAngle = -16
            pose.frontNearLift = 4
            pose.tailSpread = 0.35
            pose.tailBaseAngle = 0
            pose.tailLift = 8
            pose.tailSway = sin(time * 2.4) * 4

        case .pawing:
            let cycle = (time / 1.25).truncatingRemainder(dividingBy: 1)
            let prepare = FoxMotionMath.pulse(cycle, center: 0.18, width: 0.18)
            let tap = FoxMotionMath.pulse(cycle, center: 0.48, width: 0.22)
            pose.bodyX += 6 + tap * 2
            pose.bodyY += prepare * 2
            pose.bodyRotation = -3 - tap * 2
            pose.headX += 10 + tap * 3
            pose.headY += 8
            pose.headRotation = 8 + tap * 4
            pose.pupilX = 2.2
            pose.pupilY = 1.0
            pose.frontNearAngle = -44 + tap * 22
            pose.frontNearLift = 22 - tap * 5
            pose.pawReach = 6 + tap * 12
            pose.tailSpread = 0.6
            pose.tailBaseAngle = -10
            pose.tailLift = 8

        case .pouncing:
            let cycle = (time / 2.25).truncatingRemainder(dividingBy: 1)
            let crouch = FoxMotionMath.pulse(cycle, center: 0.16, width: 0.15)
            let leap = FoxMotionMath.pulse(cycle, center: 0.48, width: 0.29)
            let land = FoxMotionMath.pulse(cycle, center: 0.78, width: 0.1)
            pose.bodyX += leap * 14
            pose.bodyY += crouch * 7 - leap * 17 + land * 4
            pose.headX += leap * 16
            pose.headY += crouch * 5 - leap * 18 + land * 2
            pose.bodyScaleX += crouch * 0.06 - leap * 0.025
            pose.bodyScaleY -= crouch * 0.08 - leap * 0.04
            pose.headRotation = -leap * 4
            pose.frontFarLift = leap * 12
            pose.frontNearLift = leap * 15
            pose.hindFarLift = leap * 8
            pose.hindNearLift = leap * 8
            pose.frontNearAngle = -leap * 25
            pose.frontFarAngle = -leap * 18
            pose.tailSpread = 0.4
            pose.tailBaseAngle = leap * 15
            pose.tailLift = 5 + leap * 10

        case .success:
            let phase = (time / 1.65).truncatingRemainder(dividingBy: 1)
            let jump = sin(min(1, phase / 0.72) * Double.pi)
            pose.bodyY -= max(0, jump) * 18
            pose.headY -= max(0, jump) * 21
            pose.bodyRotation = sin(phase * FoxMotionMath.tau) * 3
            pose.bodyScaleY += (1 - jump) * 0.035
            pose.tailSpread = 1.0
            pose.tailBaseAngle = -35
            pose.tailLift = 15
            pose.tailEnergy = 1.0
            pose.energyBurst = 1.0
            pose.foreheadRuneGlow = 1.0
            pose.mouthOpen = 1
            pose.earLeftAngle -= 8
            pose.earRightAngle += 8

        case .error:
            pose.bodyY += 7
            pose.bodyScaleY = 0.92
            pose.headY += 7
            pose.headRotation = 5
            pose.earLeftFlatten = 1.0
            pose.earRightFlatten = 1.0
            pose.eyeOpen = min(pose.eyeOpen, 0.65)
            pose.pupilY = 1.8
            pose.tailSpread = 0.25
            pose.tailBaseAngle = 50
            pose.tailLift = -5
            pose.tailEnergy = 0.15
            pose.foreheadRuneGlow = 0.15
            pose.energyBurst = 0

        case .sleeping:
            pose.bodyX = 148
            pose.bodyY = 182 + breathe * 1.6
            pose.bodyScaleX = 1.08
            pose.bodyScaleY = 0.76 + breathe * 0.016
            pose.headX = 183
            pose.headY = 168 + breathe * 1.1
            pose.headRotation = 7
            pose.headScale = 0.9
            pose.eyeOpen = 0.02
            pose.earLeftAngle -= 6
            pose.earRightAngle += 4
            pose.tailSpread = 0.3
            pose.tailBaseAngle = 15
            pose.tailLift = -4
            pose.tailEnergy = 0.2 + breathe * 0.1
            pose.foreheadRuneGlow = 0.25 + breathe * 0.15

        case .stretch:
            let phase = (time / 4.8).truncatingRemainder(dividingBy: 1)
            let hold = FoxMotionMath.smoothstep(min(1, phase / 0.25))
                * (1 - FoxMotionMath.smoothstep(max(0, (phase - 0.78) / 0.22)))
            pose.bodyX -= hold * 7
            pose.bodyY -= hold * 9
            pose.bodyRotation = -hold * 7
            pose.bodyScaleX += hold * 0.1
            pose.headX += hold * 16
            pose.headY += hold * 27
            pose.headRotation = hold * 8
            pose.frontFarAngle = -hold * 30
            pose.frontNearAngle = -hold * 34
            pose.pawReach = hold * 14
            pose.tailSpread = 0.5 + hold * 0.3
            pose.tailBaseAngle = -hold * 10
            pose.tailLift = hold * 14

        case .grooming:
            let cycle = time * 1.2
            let lift = 0.5 + 0.5 * sin(cycle)
            pose.frontNearAngle = -34 - lift * 18
            pose.frontNearLift = 18 + lift * 8
            pose.pawReach = -4
            pose.headX -= lift * 10
            pose.headY += lift * 11
            pose.headRotation = -10 - lift * 10
            pose.eyeOpen = min(pose.eyeOpen, 0.6)
            pose.mouthOpen = FoxMotionMath.pulse(
                (cycle / FoxMotionMath.tau).truncatingRemainder(dividingBy: 1),
                center: 0.56, width: 0.18
            )

        case .hop:
            let phase = (time / 2.3).truncatingRemainder(dividingBy: 1)
            let crouch = FoxMotionMath.pulse(phase, center: 0.14, width: 0.14)
            let air = FoxMotionMath.pulse(phase, center: 0.48, width: 0.3)
            let land = FoxMotionMath.pulse(phase, center: 0.79, width: 0.1)
            pose.bodyY += crouch * 7 - air * 22 + land * 5
            pose.headY += crouch * 5 - air * 25 + land * 3
            pose.bodyScaleY += crouch * -0.08 + air * 0.05 + land * -0.07
            pose.bodyScaleX += crouch * 0.05 + air * -0.03 + land * 0.05
            pose.frontFarLift = air * 13
            pose.frontNearLift = air * 13
            pose.hindFarLift = air * 9
            pose.hindNearLift = air * 9
            pose.tailSpread = 0.5
            pose.tailBaseAngle = air * -10
            pose.tailLift = air * 12

        case .wave:
            let cycle = time * 2.1
            let wave = 0.5 + 0.5 * sin(cycle * FoxMotionMath.tau)
            pose.bodyRotation = -3
            pose.headRotation = 3
            pose.frontNearAngle = -45 + wave * 18
            pose.frontNearLift = 24
            pose.pawReach = -5
            pose.tailSpread = 0.6
            pose.tailBaseAngle = -5
            pose.tailSway = sin(cycle * 1.1) * 8

        case .curious:
            let cycle = time * 0.72
            pose.headRotation = sin(cycle) * 7
            pose.headX += sin(cycle * 0.55) * 3
            pose.headY -= abs(sin(cycle)) * 2
            pose.pupilX = sin(cycle * 1.4) * 2
            pose.pupilY = cos(cycle * 0.8) * 1.2
            pose.earLeftAngle += sin(cycle * 1.15) * 4
            pose.earRightAngle -= sin(cycle * 0.92) * 4
            pose.tailSpread = 0.65
            pose.tailBaseAngle = -8
            pose.tailSway = sin(cycle * 1.6 - 0.7) * 9
        }
        return pose
    }
}

private enum FoxRigPainter {
    private static let white = Color(red: 0.97, green: 0.98, blue: 0.99)
    private static let cream = Color(red: 0.94, green: 0.96, blue: 0.98)
    private static let outline = Color(red: 0.14, green: 0.17, blue: 0.26)
    private static let earPink = Color(red: 1.0, green: 0.75, blue: 0.82)
    private static let iceBlue = Color(red: 0.42, green: 0.80, blue: 0.96)
    private static let iceGlow = Color(red: 0.55, green: 0.88, blue: 1.0)
    private static let eyeBlue = Color(red: 0.22, green: 0.58, blue: 0.88)
    private static let runeCyan = Color(red: 0.30, green: 0.82, blue: 1.0)
    private static let noseDark = Color(red: 0.18, green: 0.14, blue: 0.22)

    static func draw(
        _ pose: FoxPose,
        facesLeft: Bool,
        mode: FoxRigMode,
        previousMode: FoxRigMode,
        transition: Double,
        animationTime: Double,
        in context: inout GraphicsContext
    ) {
        var layer = context
        if facesLeft {
            layer.translateBy(x: 480, y: 0)
            layer.scaleBy(x: -1, y: 1)
        }

        if pose.energyBurst > 0.01 {
            drawEnergyBurst(pose, in: &layer)
        }

        drawNineTails(pose, in: &layer)

        drawLeg(x: pose.bodyX - 32, pose.hindFarAngle, pose.hindFarLift, far: true, pose: pose, in: &layer)
        drawLeg(x: pose.bodyX + 12, pose.hindNearAngle, pose.hindNearLift, far: false, pose: pose, in: &layer)

        drawBody(pose, in: &layer)

        drawLeg(x: pose.bodyX - 22, pose.frontFarAngle, pose.frontFarLift, far: true, pose: pose, in: &layer)
        drawLeg(x: pose.bodyX + 22, pose.frontNearAngle, pose.frontNearLift, far: false, pose: pose, in: &layer)

        drawKeyboard(pose, in: &layer)

        drawHead(pose, in: &layer)
    }

    private static func drawEnergyBurst(_ pose: FoxPose, in context: inout GraphicsContext) {
        let burst = pose.energyBurst
        let center = CGPoint(x: pose.bodyX, y: pose.bodyY - 20)
        for i in 0..<12 {
            let angle = Double(i) * FoxMotionMath.tau / 12
            let len = 30 + burst * 40
            var ray = Path()
            ray.move(to: center)
            ray.addLine(to: CGPoint(
                x: center.x + cos(angle) * len,
                y: center.y + sin(angle) * len
            ))
            context.stroke(ray, with: .color(iceGlow.opacity(burst * 0.3)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private static func drawNineTails(_ pose: FoxPose, in context: inout GraphicsContext) {
        let baseX = pose.bodyX - 42
        let baseY = pose.bodyY - 5
        let spreadRange = pose.tailSpread * 50
        let halfSpread = spreadRange / 2

        for i in 0..<9 {
            let t = Double(i) / 8.0
            let angle = pose.tailBaseAngle - halfSpread + spreadRange * t + pose.tailSway * (t - 0.5) * 0.5
            let energy = pose.tailEnergy * (0.7 + 0.3 * sin(Double(i) * 1.3 + pose.tailSway * 0.2))
            drawSingleTail(
                baseX: baseX, baseY: baseY,
                angle: angle, lift: pose.tailLift,
                energy: energy, index: i,
                in: &context
            )
        }
    }

    private static func drawSingleTail(
        baseX: Double, baseY: Double,
        angle: Double, lift: Double,
        energy: Double, index: Int,
        in context: inout GraphicsContext
    ) {
        let rad = angle * Double.pi / 180
        let len: Double = 55
        let midX = baseX + cos(rad) * len * 0.5 - sin(rad) * lift * 0.3
        let midY = baseY + sin(rad) * len * 0.5 + cos(rad) * lift * 0.3 - lift
        let tipX = baseX + cos(rad) * len - sin(rad) * lift * 0.6
        let tipY = baseY + sin(rad) * len + cos(rad) * lift * 0.6 - lift * 1.5

        var tail = Path()
        tail.move(to: CGPoint(x: baseX, y: baseY))
        tail.addQuadCurve(
            to: CGPoint(x: midX, y: midY),
            control: CGPoint(x: baseX + cos(rad - 0.15) * len * 0.25, y: baseY + sin(rad - 0.15) * len * 0.25 - lift * 0.2)
        )
        tail.addQuadCurve(
            to: CGPoint(x: tipX, y: tipY),
            control: CGPoint(x: midX + cos(rad + 0.1) * len * 0.3, y: midY + sin(rad + 0.1) * len * 0.3 - lift * 0.3)
        )

        context.stroke(tail, with: .color(outline), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        context.stroke(tail, with: .color(white), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.stroke(tail, with: .color(cream.opacity(0.7)), style: StrokeStyle(lineWidth: 6, lineCap: .round))

        if energy > 0.05 {
            let glowSize = 4 + energy * 6
            let tipGlow = Path(ellipseIn: CGRect(
                x: tipX - glowSize / 2, y: tipY - glowSize / 2,
                width: glowSize, height: glowSize
            ))
            context.fill(tipGlow, with: .color(iceGlow.opacity(energy * 0.8)))
            context.fill(tipGlow, with: .color(iceBlue.opacity(energy)))
        }
    }

    private static func drawBody(_ pose: FoxPose, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: pose.bodyX, y: pose.bodyY)
        layer.rotate(by: .degrees(pose.bodyRotation))
        layer.scaleBy(x: pose.bodyScaleX, y: pose.bodyScaleY)

        let body = Path(ellipseIn: CGRect(x: -48, y: -34, width: 96, height: 68))
        layer.fill(body, with: .color(white))
        layer.stroke(body, with: .color(outline), lineWidth: 5)

        let chest = Path(ellipseIn: CGRect(x: 16, y: -22, width: 22, height: 40))
        layer.fill(chest, with: .color(cream.opacity(0.65)))
    }

    private static func drawLeg(
        x: Double, _ angle: Double, _ lift: Double,
        far: Bool, pose: FoxPose,
        in context: inout GraphicsContext
    ) {
        var layer = context
        layer.translateBy(x: x, y: pose.bodyY + 16 - lift)
        layer.rotate(by: .degrees(angle))
        let leg = Path(roundedRect: CGRect(x: -9, y: -4, width: 18, height: 40), cornerRadius: 9)
        layer.fill(leg, with: .color(far ? cream.opacity(0.85) : white))
        layer.stroke(leg, with: .color(outline), lineWidth: far ? 4 : 5)
        let paw = Path(ellipseIn: CGRect(x: -12, y: 26, width: 24, height: 13))
        layer.fill(paw, with: .color(far ? cream.opacity(0.85) : white))
        layer.stroke(paw, with: .color(outline), lineWidth: far ? 4 : 5)
    }

    private static func drawHead(_ pose: FoxPose, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: pose.headX, y: pose.headY)
        layer.rotate(by: .degrees(pose.headRotation))
        layer.scaleBy(x: pose.headScale, y: pose.headScale)

        drawEar(x: -24, rotation: -8 + pose.earLeftAngle, flatten: pose.earLeftFlatten, mirror: false, in: &layer)
        drawEar(x: 25, rotation: 8 + pose.earRightAngle, flatten: pose.earRightFlatten, mirror: true, in: &layer)

        let headBase = Path(roundedRect: CGRect(x: -42, y: -34, width: 84, height: 70), cornerRadius: 28)
        layer.fill(headBase, with: .color(white))
        layer.stroke(headBase, with: .color(outline), lineWidth: 5)

        var muzzle = Path()
        muzzle.move(to: CGPoint(x: 38, y: -5))
        muzzle.addLine(to: CGPoint(x: 62, y: 2))
        muzzle.addLine(to: CGPoint(x: 38, y: 10))
        muzzle.closeSubpath()
        layer.fill(muzzle, with: .color(white))
        layer.stroke(muzzle, with: .color(outline), lineWidth: 4)

        let nose = Path(ellipseIn: CGRect(x: 58, y: -2, width: 7, height: 5))
        layer.fill(nose, with: .color(noseDark))

        drawEye(x: -16, pose: pose, in: &layer)
        drawEye(x: 16, pose: pose, in: &layer)

        if pose.foreheadRuneGlow > 0.05 {
            drawForeheadRune(glow: pose.foreheadRuneGlow, in: &layer)
        }

        var mouth = Path()
        mouth.move(to: CGPoint(x: 48, y: 6))
        mouth.addCurve(
            to: CGPoint(x: 58, y: 6 + pose.mouthOpen * 3),
            control1: CGPoint(x: 52, y: 10 + pose.mouthOpen * 3),
            control2: CGPoint(x: 55, y: 10 + pose.mouthOpen * 3)
        )
        layer.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        for side in [-1.0, 1.0] {
            for offset in [-4.0, 2.0, 8.0] {
                var whisker = Path()
                whisker.move(to: CGPoint(x: 38 + side * 6, y: 2 + offset * 0.3))
                whisker.addLine(to: CGPoint(x: 38 + side * 22, y: offset))
                layer.stroke(whisker, with: .color(outline.opacity(0.6)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
    }

    private static func drawEar(
        x: Double, rotation: Double, flatten: Double, mirror: Bool,
        in context: inout GraphicsContext
    ) {
        var layer = context
        layer.translateBy(x: x, y: -30)
        layer.rotate(by: .degrees(rotation))
        if mirror { layer.scaleBy(x: -1, y: 1) }

        let flattenScale = 1.0 - flatten * 0.55
        layer.scaleBy(x: 1, y: flattenScale)

        var ear = Path()
        ear.move(to: CGPoint(x: -14, y: 5))
        ear.addLine(to: CGPoint(x: -5, y: -34))
        ear.addLine(to: CGPoint(x: 15, y: 2))
        ear.closeSubpath()
        layer.fill(ear, with: .color(white))
        layer.stroke(ear, with: .color(outline), style: StrokeStyle(lineWidth: 5, lineJoin: .round))

        var inner = Path()
        inner.move(to: CGPoint(x: -7, y: 0))
        inner.addLine(to: CGPoint(x: -3, y: -22))
        inner.addLine(to: CGPoint(x: 8, y: 0))
        inner.closeSubpath()
        layer.fill(inner, with: .color(earPink))
    }

    private static func drawEye(x: Double, pose: FoxPose, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: x + pose.pupilX, y: -2 + pose.pupilY)
        layer.scaleBy(x: 1, y: max(0.04, pose.eyeOpen))

        let eyeFrame = Path(ellipseIn: CGRect(x: -10, y: -12, width: 20, height: 24))
        layer.fill(eyeFrame, with: .color(outline))

        let iris = Path(ellipseIn: CGRect(x: -7, y: -9, width: 14, height: 18))
        layer.fill(iris, with: .color(eyeBlue))

        let pupil = Path(ellipseIn: CGRect(x: -4, y: -5, width: 8, height: 10))
        layer.fill(pupil, with: .color(outline.opacity(0.85)))

        let glint1 = Path(ellipseIn: CGRect(x: -2, y: -7, width: 4, height: 4))
        layer.fill(glint1, with: .color(.white))
        let glint2 = Path(ellipseIn: CGRect(x: 2, y: -3, width: 2, height: 2))
        layer.fill(glint2, with: .color(.white.opacity(0.8)))
    }

    private static func drawForeheadRune(glow: Double, in context: inout GraphicsContext) {
        var glowRune = Path()
        glowRune.move(to: CGPoint(x: 0, y: -32))
        glowRune.addLine(to: CGPoint(x: 8, y: -23))
        glowRune.addLine(to: CGPoint(x: 0, y: -14))
        glowRune.addLine(to: CGPoint(x: -8, y: -23))
        glowRune.closeSubpath()
        context.fill(glowRune, with: .color(runeCyan.opacity(glow * 0.25)))

        var rune = Path()
        rune.move(to: CGPoint(x: 0, y: -28))
        rune.addLine(to: CGPoint(x: 5, y: -23))
        rune.addLine(to: CGPoint(x: 0, y: -18))
        rune.addLine(to: CGPoint(x: -5, y: -23))
        rune.closeSubpath()
        context.fill(rune, with: .color(runeCyan.opacity(glow)))
        context.stroke(rune, with: .color(.white.opacity(glow * 0.8)), lineWidth: 1)
    }

    private static func drawKeyboard(_ pose: FoxPose, in context: inout GraphicsContext) {
        guard pose.workSurface > 0.01 else { return }
        var layer = context
        layer.opacity = pose.workSurface

        let deck = Path(roundedRect: CGRect(x: 148, y: 218, width: 100, height: 24), cornerRadius: 7)
        layer.fill(deck, with: .color(outline.opacity(0.92)))
        layer.stroke(deck, with: .color(iceBlue.opacity(0.78)), lineWidth: 2)

        for row in 0..<2 {
            for column in 0..<6 {
                let isActive = (column + row * 2) % 4 == Int(pose.keyPulse * 3.9)
                let key = Path(roundedRect: CGRect(
                    x: 155 + CGFloat(column) * 14,
                    y: 223 + CGFloat(row) * 7.5,
                    width: 8, height: 4.5
                ), cornerRadius: 1.5)
                layer.fill(key, with: .color(isActive ? iceGlow : cream.opacity(0.55)))
            }
        }
    }
}
