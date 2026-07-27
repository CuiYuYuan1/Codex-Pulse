import AppKit
import CoreMedia
import CoreVideo
import MetalKit
import ScreenCaptureKit
import SwiftUI
import simd

extension Notification.Name {
    static let pulseBlackHoleDrop = Notification.Name("com.codexpulse.black-hole.drop")
}

enum BlackHoleDropPhase: String, Sendable {
    case idle
    case targeting
    case absorbed
    case failed
}

struct BlackHoleDropEvent: Sendable {
    let phase: BlackHoleDropPhase
    let fileCount: Int
}

/// A procedural pet rather than a flat sprite. The captured desktop becomes the
/// shader's sky texture, so windows moving behind this view are genuinely
/// resampled by the gravitational lens instead of being covered by an overlay.
struct BlackHolePetView: View {
    let animationState: PetAnimationState
    let reduceMotion: Bool
    let sceneSize: CGSize
    let roamingActivity: CatRoamingActivity
    let facesLeft: Bool

    @State private var dropPhase: BlackHoleDropPhase = .idle
    @State private var absorbedFileCount = 0
    @State private var dropResetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            BlackHoleMetalSurface(
                animationState: animationState,
                reduceMotion: reduceMotion,
                dropPhase: dropPhase,
                roamingActivity: roamingActivity,
                facesLeft: facesLeft
            )

            if isCodexThinking {
                BlackHoleCodeInfall(reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if dropPhase == .targeting || dropPhase == .absorbed {
                BlackHoleFileInfall(
                    fileCount: max(1, absorbedFileCount),
                    absorbed: dropPhase == .absorbed,
                    reduceMotion: reduceMotion
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
        .onReceive(NotificationCenter.default.publisher(for: .pulseBlackHoleDrop)) { note in
            guard let event = note.object as? BlackHoleDropEvent else { return }
            dropResetTask?.cancel()
            absorbedFileCount = event.fileCount
            withAnimation(.easeOut(duration: 0.18)) {
                dropPhase = event.phase
            }
            guard event.phase == .absorbed || event.phase == .failed else { return }
            dropResetTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: event.phase == .absorbed
                        ? 1_550_000_000
                        : 700_000_000)
                } catch {
                    return
                }
                withAnimation(.easeOut(duration: 0.3)) {
                    dropPhase = .idle
                }
            }
        }
        .onDisappear {
            dropResetTask?.cancel()
            dropResetTask = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var isCodexThinking: Bool {
        animationState == .thinking || animationState == .running
    }

    private var accessibilityDescription: String {
        switch dropPhase {
        case .targeting:
            return "事件视界，松开文件后移入废纸篓"
        case .absorbed:
            return "事件视界，已将 \(absorbedFileCount) 个项目移入废纸篓"
        case .failed:
            return "事件视界，文件吸入失败"
        case .idle:
            return isCodexThinking
                ? "事件视界，Codex 正在思考，代码正在坠入黑洞"
                : "事件视界桌面宠物"
        }
    }
}

private struct BlackHoleCodeInfall: View {
    let reduceMotion: Bool

    /// A deterministic stream keeps the classic-code feel without ever
    /// presenting a complete line. Every emission is one independently
    /// positioned glyph that falls directly into the event horizon.
    private let glyphStream = Array(
        "constanswer=42;absorb(token);returninsight;"
    )

    var body: some View {
        TimelineView(.animation(
            minimumInterval: reduceMotion ? 0.12 : 1.0 / 30.0,
            paused: false
        )) { context in
            Canvas { canvas, size in
                let center = CGPoint(x: size.width * 0.48, y: size.height * 0.53)
                let now = context.date.timeIntervalSinceReferenceDate
                let emissionInterval = reduceMotion ? 0.72 : 0.36
                let lifetime = reduceMotion ? 1.70 : 1.15
                let latestEmission = Int(floor(now / emissionInterval))

                // A maximum of three live glyphs reads as a sequence of
                // individual arrivals instead of a line or an orbiting cloud.
                for emissionOffset in 0..<3 {
                    let emissionIndex = latestEmission - emissionOffset
                    let emittedAt = Double(emissionIndex) * emissionInterval
                    let age = now - emittedAt
                    guard age >= 0, age < lifetime else { continue }

                    drawGlyph(
                        emissionIndex: emissionIndex,
                        progress: age / lifetime,
                        center: center,
                        canvas: canvas
                    )
                }
            }
        }
    }

    private func drawGlyph(
        emissionIndex: Int,
        progress: Double,
        center: CGPoint,
        canvas: GraphicsContext
    ) {
        let glyphIndex = positiveModulo(emissionIndex, glyphStream.count)
        let glyph = glyphStream[glyphIndex]
        let entryAngle = randomUnit(emissionIndex, salt: 1.0) * .pi * 2
        let entryRadius = 82
            + randomUnit(emissionIndex, salt: 2.0) * 30
        let curve = (
            randomUnit(emissionIndex, salt: 3.0) - 0.5
        ) * (reduceMotion ? 8 : 22)
        let eased = smoothStep(0, 1, progress)
        let radius = (1 - eased) * entryRadius
        let tangent = sin(progress * .pi) * curve
        let point = CGPoint(
            x: center.x
                + cos(entryAngle) * radius
                - sin(entryAngle) * tangent,
            y: center.y
                + sin(entryAngle) * radius * 0.62
                + cos(entryAngle) * tangent * 0.62
        )
        let opacity = min(1, progress * 12)
            * min(1, max(0, (1 - progress) * 8))
        let collapse = smoothStep(0.58, 1, progress)
        let scale = max(0.05, 1 - collapse * 0.95)
        let glyphColor = emissionIndex.isMultiple(of: 3)
            ? Color(red: 0.30, green: 0.88, blue: 1.0)
            : Color(red: 1.0, green: 0.78, blue: 0.24)
        let text = Text(String(glyph))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(glyphColor)

        var glyphContext = canvas
        glyphContext.addFilter(.shadow(
            color: .black.opacity(0.92),
            radius: 1
        ))
        glyphContext.addFilter(.shadow(
            color: glyphColor.opacity(0.98),
            radius: 3.5
        ))
        glyphContext.translateBy(x: point.x, y: point.y)
        glyphContext.rotate(by: .radians(
            (randomUnit(emissionIndex, salt: 4.0) - 0.5)
                * 0.48
                * sin(progress * .pi)
        ))
        glyphContext.scaleBy(
            x: scale * (1 + collapse * 0.18),
            y: scale * (1 - collapse * 0.30)
        )
        glyphContext.opacity = opacity
        glyphContext.draw(
            glyphContext.resolve(text),
            at: .zero,
            anchor: .center
        )
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private func randomUnit(_ seed: Int, salt: Double) -> Double {
        let value = sin(Double(seed) * 12.9898 + salt * 78.233)
            * 43_758.5453
        return value - floor(value)
    }

    private func smoothStep(
        _ lower: Double,
        _ upper: Double,
        _ value: Double
    ) -> Double {
        let normalized = min(1, max(0, (value - lower) / (upper - lower)))
        return normalized * normalized * (3 - 2 * normalized)
    }
}

private struct BlackHoleFileInfall: View {
    let fileCount: Int
    let absorbed: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0,
            paused: false
        )) { context in
            Canvas { canvas, size in
                let center = CGPoint(x: size.width * 0.48, y: size.height * 0.53)
                let now = context.date.timeIntervalSinceReferenceDate
                let count = min(7, max(1, fileCount))
                for index in 0..<count {
                    let base = absorbed
                        ? min(1, (now * 1.8 + Double(index) * 0.08)
                            .truncatingRemainder(dividingBy: 1))
                        : 0.18
                    let progress = reduceMotion ? (absorbed ? 0.82 : 0.18) : base
                    let radius = (1 - progress * progress) * (56 + Double(index) * 5)
                    let angle = Double(index) * 2.1 + progress * 4.2
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius * 0.46
                    )
                    var contextCopy = canvas
                    contextCopy.translateBy(x: point.x, y: point.y)
                    contextCopy.rotate(by: .radians(angle))
                    contextCopy.scaleBy(
                        x: max(0.12, 0.78 - progress * 0.66),
                        y: max(0.12, 0.78 - progress * 0.66)
                    )
                    contextCopy.opacity = absorbed ? max(0, 1 - progress) : 0.92
                    let icon = Text(Image(systemName: "doc.fill"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.86, green: 0.94, blue: 1.0))
                    contextCopy.draw(
                        contextCopy.resolve(icon),
                        at: .zero,
                        anchor: .center
                    )
                }
            }
        }
    }
}

private struct BlackHoleMetalSurface: NSViewRepresentable {
    let animationState: PetAnimationState
    let reduceMotion: Bool
    let dropPhase: BlackHoleDropPhase
    let roamingActivity: CatRoamingActivity
    let facesLeft: Bool

    func makeNSView(context: Context) -> BlackHoleMetalRendererView {
        let view = BlackHoleMetalRendererView(frame: .zero)
        view.update(
            animationState: animationState,
            reduceMotion: reduceMotion,
            dropPhase: dropPhase,
            roamingActivity: roamingActivity,
            facesLeft: facesLeft
        )
        return view
    }

    func updateNSView(_ nsView: BlackHoleMetalRendererView, context: Context) {
        nsView.update(
            animationState: animationState,
            reduceMotion: reduceMotion,
            dropPhase: dropPhase,
            roamingActivity: roamingActivity,
            facesLeft: facesLeft
        )
    }

    static func dismantleNSView(
        _ nsView: BlackHoleMetalRendererView,
        coordinator: Void
    ) {
        nsView.stopCapture()
    }
}

private struct BlackHolePetRenderParams {
    var resolution: SIMD2<Float>
    var captureOrigin: SIMD2<Float>
    var captureSize: SIMD2<Float>
    var time: Float
}

private final class BlackHoleMetalRendererView:
    NSView,
    MTKViewDelegate,
    SCStreamOutput,
    SCStreamDelegate
{
    private let metalView: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let captureQueue = DispatchQueue(
        label: "com.codexpulse.black-hole.capture",
        qos: .userInteractive
    )
    private let textureLock = NSLock()
    private var textureCache: CVMetalTextureCache?
    private var capturedTexture: MTLTexture?
    private var retainedCVTexture: CVMetalTexture?
    private var fallbackTexture: MTLTexture
    private var stream: SCStream?
    private var capturedDisplayID: CGDirectDisplayID?
    private var captureStarting = false
    private var captureDenied = false
    private var captureGeneration = 0
    private var startTime = CACurrentMediaTime()
    private var reduceMotion = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let shaderURL = Bundle.main.url(
                forResource: "BlackHolePetShader.metal",
                withExtension: "txt"
              ),
              let shaderSource = try? String(
                contentsOf: shaderURL,
                encoding: .utf8
              ),
              let library = try? device.makeLibrary(
                source: shaderSource,
                options: nil
              ),
              let vertex = library.makeFunction(name: "blackHolePetVertex"),
              let fragment = library.makeFunction(name: "blackHolePetFragment") else {
            fatalError("Event Horizon requires a Metal-capable Mac")
        }
        self.device = device
        self.commandQueue = commandQueue

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Unable to create Event Horizon Metal pipeline: \(error)")
        }

        let fallbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        guard let fallback = device.makeTexture(descriptor: fallbackDescriptor) else {
            fatalError("Unable to create Event Horizon fallback texture")
        }
        fallbackTexture = fallback
        var fallbackPixel: UInt32 = 0xFF020100
        fallbackTexture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &fallbackPixel,
            bytesPerRow: MemoryLayout<UInt32>.size
        )

        metalView = MTKView(frame: frameRect, device: device)
        super.init(frame: frameRect)

        wantsLayer = true
        metalView.autoresizingMask = [.width, .height]
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.preferredFramesPerSecond = 30
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.delegate = self
        addSubview(metalView)
        enforceTransparentComposition()

        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        installSystemObservers()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in applicationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func layout() {
        super.layout()
        synchronizeDrawableGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopCapture()
            return
        }
        configureCaptureIfNeeded()
    }

    func update(
        animationState: PetAnimationState,
        reduceMotion: Bool,
        dropPhase: BlackHoleDropPhase,
        roamingActivity: CatRoamingActivity,
        facesLeft: Bool
    ) {
        self.reduceMotion = reduceMotion
        metalView.preferredFramesPerSecond = reduceMotion ? 12 : 30
    }

    func stopCapture() {
        captureGeneration &+= 1
        let activeStream = stream
        self.stream = nil
        capturedDisplayID = nil
        captureStarting = false
        textureLock.lock()
        capturedTexture = nil
        retainedCVTexture = nil
        textureLock.unlock()
        guard let activeStream else { return }
        activeStream.stopCapture { error in
            if let error {
                PulseLog.write("black-hole capture stop warning: \(error.localizedDescription)")
            }
        }
    }

    private func configureCaptureIfNeeded() {
        guard !captureStarting,
              !captureDenied,
              let window,
              let screen = window.screen else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber)?.uint32Value ?? 0
        guard displayID != 0 else { return }
        if capturedDisplayID == displayID, stream != nil { return }

        stopCapture()
        captureStarting = true
        let generation = captureGeneration
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            captureDenied = true
            captureStarting = false
            PulseLog.write("black-hole capture permission denied; renderer is using local fallback")
            return
        }

        let excludedWindowNumber = CGWindowID(window.windowNumber)
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let display = content.displays.first(where: {
                    $0.displayID == displayID
                }) else {
                    throw BlackHoleCaptureError.displayUnavailable
                }
                let excludedWindow = content.windows.first(where: {
                    $0.windowID == excludedWindowNumber
                })
                let filter = SCContentFilter(
                    display: display,
                    excludingWindows: excludedWindow.map { [$0] } ?? []
                )
                let configuration = SCStreamConfiguration()
                let longestEdge = max(display.width, display.height)
                let captureScale = longestEdge > 3_840
                    ? 3_840.0 / Double(longestEdge)
                    : 1.0
                configuration.width = max(1, Int(Double(display.width) * captureScale))
                configuration.height = max(1, Int(Double(display.height) * captureScale))
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.queueDepth = 3
                configuration.showsCursor = false

                let stream = SCStream(
                    filter: filter,
                    configuration: configuration,
                    delegate: self
                )
                try stream.addStreamOutput(
                    self,
                    type: .screen,
                    sampleHandlerQueue: captureQueue
                )
                try await stream.startCapture()
                await MainActor.run {
                    guard self.captureGeneration == generation,
                          self.window != nil else {
                        stream.stopCapture { _ in }
                        return
                    }
                    self.stream = stream
                    self.capturedDisplayID = displayID
                    self.captureStarting = false
                    PulseLog.write("black-hole desktop lens capture started")
                }
            } catch {
                await MainActor.run {
                    guard self.captureGeneration == generation else { return }
                    self.captureStarting = false
                    PulseLog.write(
                        "black-hole capture unavailable: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        textureLock.lock()
        retainedCVTexture = cvTexture
        capturedTexture = texture
        textureLock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.capturedDisplayID = nil
            self.captureStarting = false
            PulseLog.write("black-hole capture stopped: \(error.localizedDescription)")
        }
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: descriptor
              ) else { return }

        if let screen = window?.screen {
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value
            if displayID != capturedDisplayID, !captureStarting {
                DispatchQueue.main.async { [weak self] in
                    self?.configureCaptureIfNeeded()
                }
            }
        }

        textureLock.lock()
        let desktopTexture = capturedTexture ?? fallbackTexture
        let hasCapturedDesktop = capturedTexture != nil
        textureLock.unlock()

        let captureRect = normalizedCaptureRect()
        var params = BlackHolePetRenderParams(
            resolution: SIMD2(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            captureOrigin: SIMD2(
                Float(captureRect.origin.x),
                Float(captureRect.origin.y)
            ),
            captureSize: hasCapturedDesktop
                ? SIMD2(Float(captureRect.width), Float(captureRect.height))
                : .zero,
            time: Float(CACurrentMediaTime() - startTime)
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(desktopTexture, index: 0)
        encoder.setFragmentBytes(
            &params,
            length: MemoryLayout<BlackHolePetRenderParams>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func installSystemObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        })
        applicationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartAfterDisplayTopologyChange()
        })
    }

    private func handleSystemWillSleep() {
        metalView.isPaused = true
        stopCapture()
    }

    private func handleSystemDidWake() {
        startTime = CACurrentMediaTime()
        enforceTransparentComposition()
        synchronizeDrawableGeometry()
        if let textureCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.window != nil else { return }
            self.enforceTransparentComposition()
            self.synchronizeDrawableGeometry()
            self.metalView.isPaused = false
            self.configureCaptureIfNeeded()
        }
    }

    private func restartAfterDisplayTopologyChange() {
        guard window != nil else { return }
        stopCapture()
        synchronizeDrawableGeometry()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.configureCaptureIfNeeded()
        }
    }

    private func synchronizeDrawableGeometry() {
        metalView.frame = bounds
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        let expected = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        if abs(metalView.drawableSize.width - expected.width) > 0.5
            || abs(metalView.drawableSize.height - expected.height) > 0.5 {
            metalView.drawableSize = expected
        }
    }

    private func enforceTransparentComposition() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
    }

    private func normalizedCaptureRect() -> CGRect {
        guard let window,
              let screen = window.screen else { return .zero }
        let viewInWindow = convert(bounds, to: nil)
        let globalRect = window.convertToScreen(viewInWindow)
        let screenFrame = screen.frame
        guard screenFrame.width > 0, screenFrame.height > 0 else { return .zero }
        return CGRect(
            x: (globalRect.minX - screenFrame.minX) / screenFrame.width,
            y: (screenFrame.maxY - globalRect.maxY) / screenFrame.height,
            width: globalRect.width / screenFrame.width,
            height: globalRect.height / screenFrame.height
        )
    }
}

private enum BlackHoleCaptureError: LocalizedError {
    case displayUnavailable

    var errorDescription: String? {
        "当前显示器不可捕获"
    }
}
