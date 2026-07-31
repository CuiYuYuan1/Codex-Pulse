const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const swift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/FloatingCapsuleView.swift"),
  "utf8"
);
const petSwift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/PetCapsuleView.swift"),
  "utf8"
);
const proceduralCatSwift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/ProceduralCatView.swift"),
  "utf8"
);
const animePetSwift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/AnimePetView.swift"),
  "utf8"
);
const blackHoleSwift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/BlackHolePetView.swift"),
  "utf8"
);
const orbPetSwift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/OrbPetView.swift"),
  "utf8"
);
const blackHoleMetal = fs.readFileSync(
  path.join(root, "CodexPulse/Resources/BlackHolePetShader.metal.txt"),
  "utf8"
);
const capsuleController = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/FloatingCapsuleController.swift"),
  "utf8"
);
const macApp = fs.readFileSync(path.join(root, "CodexPulse/App/CodexPulseApp.swift"), "utf8");
const menuBarPanel = fs.readFileSync(
  path.join(root, "CodexPulse/Views/MenuBar/MenuBarPanelView.swift"),
  "utf8"
);
const dashboard = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Dashboard/DashboardView.swift"),
  "utf8"
);
const settingsStore = fs.readFileSync(path.join(root, "Shared/Storage/SettingsStore.swift"), "utf8");
const petGrowthSwift = fs.readFileSync(path.join(root, "Shared/Utilities/PetGrowth.swift"), "utf8");
const snapshotStore = fs.readFileSync(path.join(root, "Shared/Storage/SnapshotStore.swift"), "utf8");
const css = fs.readFileSync(path.join(root, "windows/src/renderer/styles.css"), "utf8");
const renderer = fs.readFileSync(path.join(root, "windows/src/renderer/renderer.js"), "utf8");
const dockInteraction = fs.readFileSync(
  path.join(root, "windows/src/renderer/dock-interaction.js"),
  "utf8"
);
const catRig = fs.readFileSync(path.join(root, "windows/src/renderer/cat-rig.js"), "utf8");
const blackHoleWebGL = fs.readFileSync(
  path.join(root, "windows/src/renderer/black-hole-pet.js"),
  "utf8"
);
const petGrowthWeb = fs.readFileSync(
  path.join(root, "windows/src/renderer/pet-growth.js"),
  "utf8"
);
const html = fs.readFileSync(path.join(root, "windows/src/renderer/index.html"), "utf8");
const main = fs.readFileSync(path.join(root, "windows/src/main.js"), "utf8");
const preload = fs.readFileSync(path.join(root, "windows/src/preload.js"), "utf8");
const pulseStore = fs.readFileSync(path.join(root, "Shared/Services/PulseStore.swift"), "utf8");
const formatters = fs.readFileSync(path.join(root, "Shared/Utilities/Formatters.swift"), "utf8");
const appServerClient = fs.readFileSync(path.join(root, "Shared/Services/StdioCodexAppServerClient.swift"), "utf8");
const localUsageReader = fs.readFileSync(path.join(root, "Shared/Services/LocalCodexUsageReader.swift"), "utf8");
const artificialAnalysis = fs.readFileSync(path.join(root, "CodexPulse/Services/ArtificialAnalysisService.swift"), "utf8");
const updateService = fs.readFileSync(path.join(root, "CodexPulse/Services/AppUpdateService.swift"), "utf8");
const macUpdateSupport = fs.readFileSync(path.join(root, "CodexPulse/Services/MacUpdateSupport.swift"), "utf8");
const releaseWorkflow = fs
  .readFileSync(path.join(root, ".github/workflows/release.yml"), "utf8")
  .replace(/\r\n/g, "\n");
const macPackageScript = fs
  .readFileSync(path.join(root, "Scripts/package-macos.sh"), "utf8")
  .replace(/\r\n/g, "\n");
const macSignScript = fs
  .readFileSync(path.join(root, "Scripts/sign-macos-app.sh"), "utf8")
  .replace(/\r\n/g, "\n");
const macBuildAndRunScript = fs
  .readFileSync(path.join(root, "script/build_and_run.sh"), "utf8")
  .replace(/\r\n/g, "\n");

function includes(source, fragment, label) {
  const normalizedSource = source.replace(/\r\n/g, "\n");
  const normalizedFragment = fragment.replace(/\r\n/g, "\n");
  assert(
    normalizedSource.includes(normalizedFragment),
    `${label} drifted; missing ${JSON.stringify(fragment)}`
  );
}

// Task polling is allowed to go silent, but quota-backed pets must continue to
// refresh while idle and must bypass the client cache at the reset boundary.
includes(
  pulseStore,
  "private let idleRateLimitPollingInterval: TimeInterval = 8",
  "macOS persistent idle quota interval"
);
includes(
  pulseStore,
  "let forceRemote = self.hasDueRateLimitReset(reference: Date())",
  "macOS reset-boundary force refresh"
);
includes(
  pulseStore,
  "await self.refreshRateLimitsOnly(forceRemote: forceRemote)",
  "macOS lightweight quota-only refresh"
);
includes(
  pulseStore,
  "startRateLimitMonitoring()",
  "macOS quota monitor startup"
);

// Shared collapsed layout contract.
includes(swift, "private let informationCapsuleWidth: CGFloat = 275", "macOS information width");
includes(css, "width: var(--information-capsule-width, 275px);", "Windows information width");
includes(swift, "private let compactCapsuleMinimumWidth: CGFloat = 235", "macOS compact width");
includes(css, "min-width: 235px;", "Windows compact width");
includes(swift, ".frame(height: 64)", "macOS capsule height");
includes(css, "height: 64px;", "Windows capsule height");
includes(swift, ".frame(width: informationBarEnabled ? 62 : 30, height: 64)", "macOS weather slot");
includes(css, "62px 14px auto minmax(8px, 1fr) 1px", "Windows weather and spacer grid");
includes(swift, "HStack(spacing: 5)", "macOS Token/icon gap");
includes(css, ".token-readout { display: flex; align-items: center; gap: 5px;", "Windows Token/icon gap");
includes(swift, ".frame(maxWidth: 66)", "macOS live Token width");
includes(css, ".token-metric strong { max-width: 66px;", "Windows live Token width");
includes(swift, ".frame(width: 1, height: 22)", "macOS divider");
includes(css, ".divider { width: 1px; height: 22px;", "Windows divider");

// Codex window attachment stays compact and reversible on both desktop
// platforms. The preview appears at 30px, the dock remains 44px tall, and
// crossing the same 30px threshold is required to drag it back out.
includes(capsuleController, "private let codexDockProximity: CGFloat = 30", "macOS Codex dock proximity");
includes(capsuleController, "private let codexDockHorizontalThickness: CGFloat = 44", "macOS horizontal Codex dock thickness");
includes(capsuleController, "private let codexDockVerticalThickness: CGFloat = 54", "macOS compact side dock thickness");
includes(capsuleController, "private let codexDockOverlap: CGFloat = 16", "macOS shoulder overlap");
includes(capsuleController, "distance / codexDockProximity", "macOS Codex dock detachment progress");
includes(
  capsuleController,
  "let distance = edge.isVertical",
  "macOS Codex dock edge-aware detachment"
);
includes(
  capsuleController,
  "if capsuleMouseDownScreenLocation != nil {\n                // 普通胶囊由 AppKit",
  "macOS normal capsule emits live Codex dock drag updates"
);
includes(
  capsuleController,
  "private var cachedCodexWindows: [CodexDesktopWindow] = []",
  "macOS Codex window lookup is cached during live drag"
);
includes(
  capsuleController,
  "CGWindowListCopyWindowInfo([.optionIncludingWindow], id)",
  "macOS attached dock tracks only its bound Codex window"
);
includes(
  capsuleController,
  "try? await Task.sleep(nanoseconds: 8_333_333)",
  "macOS attached dock follows at ProMotion cadence"
);
includes(
  capsuleController,
  "let edge: CodexDockEdge = isFullScreen ? .top : preferredEdge",
  "macOS full-screen Codex always migrates an existing dock to the top"
);
includes(
  capsuleController,
  "windowFrame.width\n                * codexDockFullScreenWidthRatio",
  "macOS full-screen dock width adapts to the Codex window"
);
includes(
  capsuleController,
  "UserDefaults.standard.set(savedEdge.rawValue, forKey: codexDockPreferredEdgeKey)",
  "macOS remembers the pre-full-screen dock edge"
);
includes(
  swift,
  "isCodexDockFullScreen ? .bottom : codexDockEdge",
  "macOS full-screen dock grows downward from the Codex top bar"
);
includes(
  capsuleController,
  "panel.level = .normal",
  "macOS attached dock uses the Codex window level"
);
includes(
  capsuleController,
  "hideCodexDockPreview(immediately: true)",
  "macOS attachment removes its guide before morphing"
);
assert(
  !capsuleController.includes("let landingFrame = NSRect("),
  "macOS attachment must remain one continuous envelope morph"
);
assert(
  !capsuleController.includes("panel.alphaValue = 0"),
  "macOS detachment must not introduce a blank frame"
);
includes(swift, '@AppStorage("pulse.codexDock.order")', "macOS Codex dock order persistence");
includes(swift, "struct CodexDockExtensionShape: Shape", "macOS Codex dock extension shoulder");
includes(swift, "enum CodexDockEdge: String, CaseIterable", "macOS four-edge dock model");
includes(swift, "if vertical {", "macOS side dock hides metric labels");
includes(
  swift,
  "codexDockVerticalFocusedContent(focusedMetric, at: date)",
  "macOS side dock exposes the selected metric detail"
);
includes(
  swift,
  "let primaryInset: CGFloat = codexDockEdge.isVertical ? 10 : 14",
  "macOS dock tap mapping follows both horizontal and vertical content insets"
);
assert(
  !swift.includes("guard isCodexDockAttached, !codexDockEdge.isVertical else { return }"),
  "macOS side dock taps must not be discarded"
);
includes(capsuleController, "panel.order(.below", "macOS dock overlaps behind Codex");
includes(
  capsuleController,
  "onCodexDockInteractionBegan?()",
  "macOS reasserts Codex window ordering before drawing a clicked dock frame"
);
includes(
  capsuleController,
  "x: windowFrame.minX,",
  "macOS Codex dock aligns to the visible window edge"
);
includes(main, "const CODEX_DOCK_PROXIMITY = 30;", "Windows Codex dock proximity");
includes(main, "const CODEX_DOCK_HORIZONTAL_THICKNESS = 44;", "Windows horizontal dock thickness");
includes(main, "const CODEX_DOCK_VERTICAL_THICKNESS = 54;", "Windows compact side dock thickness");
includes(main, "const CODEX_DOCK_OVERLAP = 16;", "Windows shoulder overlap");
includes(main, '["top", "bottom", "left", "right"]', "Windows four-edge dock model");
includes(main, '"  Start-Sleep -Milliseconds 8"', "Windows Codex dock high-refresh tracking cadence");
includes(
  main,
  "normalizeTrackedWindowBounds(trackedWindow, screen)",
  "Windows Codex window tracking normalizes physical pixels into Electron DIPs"
);
includes(
  main,
  "visibleWindowBounds(",
  "Windows Codex proximity follows the visible capsule instead of its transparent surface"
);
includes(
  main,
  "$knownInstall -and $windowTitle -match '(?i)(codex|chatgpt)'",
  "Windows recognizes packaged Codex and ChatGPT desktop window hosts"
);
includes(
  main,
  "handle=$h.ToInt64().ToString()",
  "Windows tracks the Codex HWND without losing precision"
);
includes(
  main,
  "windowRef.moveAbove(codexWindowMediaSourceId);",
  "Windows keeps the normal-level dock visibly above its Codex source window"
);
includes(
  main,
  "if (!windowRef.isVisible()) windowRef.showInactive();",
  "Windows attachment remains visible without stealing Codex focus"
);
includes(main, "windowRef.setAlwaysOnTop(false);", "Windows attached dock uses normal window level");
includes(main, "windowRef.setAlwaysOnTop(true);", "Windows detached capsule restores top level");
includes(main, 'ipcMain.handle("pulse:codex-dock-detach"', "Windows Codex dock reverse transition");
includes(
  main,
  "function applyAttachedCodexDockShape(",
  "Windows main process owns the attached seam-clipped shape policy"
);
includes(
  main,
  'const nextEdge = nextFullscreen ? "top" : codexDockPreferredEdge;',
  "Windows full-screen Codex always migrates an existing dock to the top"
);
includes(
  main,
  "fullscreenTopDockFrame(bounds, {",
  "Windows full-screen dock uses adaptive in-window geometry"
);
includes(
  css,
  'html[data-codex-dock-fullscreen="true"] .codex-dock',
  "Windows full-screen dock grows downward from the Codex top bar"
);
includes(
  main,
  "windowRef.setShape([shape]);",
  "Windows attached dock excludes its transparent overlap from drawing and input"
);
includes(renderer, 'const codexDockOrderKey = "codexPulse.codexDockOrder";', "Windows Codex dock order persistence");
includes(
  renderer,
  "if (codexDockAttached) {\n    return [{ x: 0, y: 0, width: innerWidth, height: innerHeight }];\n  }",
  "Windows renderer keeps attached shape refreshes non-empty for main-process clipping"
);
includes(
  renderer,
  "if (expanded || miniMode || miniTransitioning || codexDockAttached) return;",
  "Windows attached dock skips floating capsule width recalculation"
);
includes(
  renderer,
  "if (didMove) window.pulse.dragTo(event.screenX, event.screenY);",
  "Windows flushes the final drag position before deciding attachment"
);
includes(
  dockInteraction,
  "const DETACH_DISTANCE = 18;",
  "Windows detachment completes before the pointer leaves the native dock surface"
);
includes(
  dockInteraction,
  "Math.abs(normalDistance(edge, dx, dy))",
  "Windows dock detaches in either perpendicular direction"
);
includes(html, '<script src="dock-interaction.js"></script>', "Windows loads the tested dock interaction policy");
includes(
  renderer,
  "void window.pulse.detachCodexDock(event.screenX, event.screenY);",
  "Windows starts detachment immediately at the threshold without waiting for an out-of-window pointerup"
);
includes(
  main,
  "1 - Math.exp(-elapsed / 7)",
  "Windows Codex dock follows host movement with low-latency interpolation"
);
includes(
  main,
  "codexDockPreviewSuppressUntil = Date.now() + 450;",
  "Windows detached surfaces have a short anti-reattachment cooldown"
);
includes(
  renderer,
  "setTimeout(scheduleWindowShapeSync, 80);",
  "Windows restores the floating capsule shape after detachment"
);
includes(css, "height: 100%;\n  padding-top: 16px;", "Windows Codex dock overlap frame");
includes(css, "inset: 16px 0 0;", "Windows dock glass begins outside Codex");
includes(css, "top: 16px;\n  left: 12px;", "Windows aurora line follows the bottom seam");
includes(
  capsuleController,
  "private struct CodexDockSeamOverlayView: View",
  "macOS Codex dock uses an independent aurora seam"
);
includes(
  capsuleController,
  "seam.level = .normal",
  "macOS aurora seam shares the Codex normal window level"
);
includes(
  capsuleController,
  "seam.order(.above, relativeTo: Int(window.id))",
  "macOS aurora seam remains visible above Codex without becoming globally topmost"
);
includes(
  capsuleController,
  "y: windowFrame.minY - half,",
  "macOS bottom aurora is centered on the exact Codex seam"
);
assert(
  !swift.includes("CodexDockAuroraSeam"),
  "macOS dock surface must not offset the aurora into its content"
);
includes(css, '.codex-dock-metric small {\n  display: none;', "Windows side dock hides metric labels");
includes(
  renderer,
  "const next = codexDockMetricIds.includes(metric)",
  "Windows side dock accepts metric focus clicks"
);
includes(
  swift,
  'case trend',
  "macOS Codex dock includes the seven-day Token trend metric"
);
includes(
  html,
  'data-metric="trend"',
  "Windows Codex dock includes the seven-day Token trend metric"
);
includes(
  swift,
  'Text("编程 IQ")',
  "macOS Token focus exposes the model programming index"
);
includes(
  html,
  '编程 IQ <strong id="codexDockTokenProgrammingIQ"',
  "Windows Token focus exposes the model programming index"
);
includes(
  renderer,
  "codexDockProgrammingIndex(state.task?.model, state.task?.reasoningEffort)",
  "Windows programming IQ resolves a model variant instead of displaying effort"
);
includes(
  css,
  'html[data-codex-dock-edge="left"] .codex-dock-focus-panel',
  "Windows side dock has a compact focused layout"
);
assert(
  !css.includes(
    'html[data-codex-dock-edge="left"] .codex-dock-focus,\n'
      + 'html[data-codex-dock-edge="right"] .codex-dock-focus {\n'
      + '  display: none !important;'
  ),
  "Windows side dock focus must remain visible"
);
includes(preload, "onCodexDockTransition", "Windows Codex dock transition bridge");
includes(
  capsuleController,
  "NSWorkspace.didLaunchApplicationNotification",
  "macOS Codex launch follower"
);
includes(
  settingsStore,
  "var resolvedFollowCodexLaunch: Bool",
  "shared Codex launch follower setting"
);
includes(
  macApp,
  "store.settings.resolvedFollowCodexLaunch",
  "macOS Codex launch follower startup"
);
includes(
  main,
  'ipcMain.handle("pulse:set-follow-codex-launch"',
  "Windows Codex launch follower setting"
);
includes(
  renderer,
  "window.pulse.setFollowCodexLaunch",
  "Windows Codex launch follower control"
);

// Rich pet mini mode: generated opaque sprites stay readable on every desktop;
// the programmatic monitor remains stable while the pet changes actions.
includes(petSwift, "CGSize(width: 216, height: 129.6)", "macOS compact pet scene size");
includes(swift, ".padding(12)", "macOS mini safe area");
includes(css, "html.mini-mode .stage { padding: 12px; align-items: flex-end; }", "Windows mini safe area and anchor");
includes(css, "width: 216px;", "Windows compact pet scene width");
includes(css, "height: 129.6px;", "Windows compact pet scene height");
includes(petSwift, "case .dino: return CGRect(x: 126, y: 23, width: 76, height: 34)", "macOS dino terminal geometry");
includes(petSwift, "case .cat: return CGRect(x: 123, y: 17, width: 81, height: 36)", "macOS cat speech bubble geometry");
includes(petSwift, "case .bunny: return CGRect(x: 122, y: 21, width: 82, height: 34)", "macOS bunny tag geometry");
includes(petSwift, "case .ghost: return CGRect(x: 125, y: 17, width: 79, height: 36)", "macOS ghost bubble geometry");
includes(petSwift, "case .robot: return CGRect(x: 122, y: 21, width: 82, height: 34)", "macOS robot HUD geometry");
includes(petSwift, "NSView.noIntrinsicMetric", "macOS compact pet scales the complete GIF instead of clipping its intrinsic canvas");
assert(!petSwift.includes("Color.white.opacity(0.72)"), "macOS pet must not restore the ugly glow outline");
assert(!css.includes("drop-shadow(0 0 1.15px rgba(255, 255, 255, .72))"), "Windows pet must not restore the ugly glow outline");
includes(swift, "(8...11).contains(phase) ? .thinking : .running", "macOS cat work and thinking choreography");
includes(renderer, 'phase >= 8 && phase <= 11 ? "thinking" : "running"', "Windows cat work and thinking choreography");
includes(petSwift, "ProceduralCatView(", "macOS procedural cat renderer");
includes(petSwift, "AnimePetView(", "macOS anime renderer for the other four companions");
includes(settingsStore, 'case blackHole = "black_hole"', "shared Event Horizon pet identity");
includes(petSwift, "BlackHolePetView(", "macOS procedural Event Horizon pet renderer");
includes(settingsStore, "case orb", "shared small-orb pet identity");
includes(settingsStore, 'case orb2 = "orb_2"', "shared small-orb 2 identity");
includes(settingsStore, 'case orb3 = "orb_3"', "shared small-orb 3 identity");
includes(settingsStore, 'case orb4 = "orb_4"', "shared small-orb 4 identity");
includes(settingsStore, 'case .orb: return "小圆球1"', "shared small-orb 1 label");
includes(settingsStore, 'case .orb4: return "小圆球4"', "shared small-orb 4 label");
includes(settingsStore, "var isOrb: Bool", "shared small-orb family behavior");
includes(petSwift, "OrbPetView(", "macOS procedural small-orb pet renderer");
includes(orbPetSwift, ".frame(width: 62, height: 62)", "macOS small-orb visual size");
includes(orbPetSwift, ".fill(.ultraThinMaterial)", "macOS small-orb frosted glass center");
includes(orbPetSwift, ".environment(\\.colorScheme, .light)", "macOS small-orb light frosted material");
includes(orbPetSwift, "case glassRing = 1", "macOS small-orb continuous-ring style");
includes(orbPetSwift, "case dashedRing = 2", "macOS small-orb dashed-ring style");
includes(orbPetSwift, "case liquid = 3", "macOS small-orb liquid style");
includes(orbPetSwift, "case darkDial = 4", "macOS small-orb dark-dial style");
includes(orbPetSwift, "completeRing(opacity:", "macOS partial progress keeps a complete colored base ring");
includes(orbPetSwift, "OrbWaveFill(", "macOS liquid small-orb renderer");
includes(orbPetSwift, ".frame(width: 49, height: 62, alignment: .center)", "macOS small-orb centered content");
includes(orbPetSwift, "if let tokenParts", "macOS small-orb splits Token number and unit");
assert(!orbPetSwift.includes("rotationEffect(.degrees(-ringRotation))"), "macOS small-orb value must remain stationary while its ring rotates");
assert(!css.includes("top: calc(var(--pet-display-top) + 19.5px)"), "Windows small-orb content must use the full circle flex center");
assert(!orbPetSwift.includes("statusDotSize"), "macOS small-orb must not restore the redundant status dot");
includes(swift, "if remaining >= 80 { return PulseTheme.green }", "macOS small-orb green quota threshold");
includes(swift, "if remaining >= 50 { return PulseTheme.blue }", "macOS small-orb blue quota threshold");
includes(swift, "if remaining >= 20 { return PulseTheme.orange }", "macOS small-orb orange quota threshold");
includes(renderer, "if (remaining >= 80) return \"#30d158\";", "Windows small-orb green quota threshold");
includes(renderer, "if (remaining >= 50) return \"#0a84ff\";", "Windows small-orb blue quota threshold");
includes(renderer, "if (remaining >= 20) return \"#ff9f0a\";", "Windows small-orb orange quota threshold");
includes(swift, "guard !isOrbPet else { return 1 }", "macOS small-orb ignores Token growth");
includes(swift, "isMini\n            && !isOrbPet", "macOS small-orb stays where the user moves it");
includes(swift, "if isOrbPet {\n            cycleOrbPage()", "macOS small-orb click cycles its own data");
includes(capsuleController, "usesOrbCircularHitRegion", "macOS small-orb circular hit region");
includes(capsuleController, "hypot(point.x - center.x, point.y - center.y) <= 31", "macOS small-orb exact circular hit test");
includes(renderer, 'const orbPetCharacters = new Set(["orb", "orb_2", "orb_3", "orb_4"])', "Windows small-orb family identities");
includes(renderer, "const nextScale = isOrbCharacter()", "Windows small-orb family ignores Token growth");
includes(renderer, "if (isOrbCharacter()) return false;", "Windows small-orb family stays where the user moves it");
includes(renderer, "if (isOrbCharacter()) {\n    cycleMiniDisplay();", "Windows small-orb family click cycles its own data");
includes(renderer, "function isMiniOrbPointerHit(event)", "Windows small-orb circular hit region");
includes(renderer, "Math.hypot(dx, dy) <= radius", "Windows small-orb exact circular hit test");
includes(renderer, "splitCompactTokenUnit(monitorValue)", "Windows small-orb splits Token number and unit");
includes(css, ".capsule[data-orb-style] .pet-orb", "Windows procedural small-orb renderer");
includes(css, "content: attr(data-unit)", "Windows small-orb renders Token unit below its number");
includes(css, '.capsule[data-orb-style="2"] .pet-orb::after', "Windows dashed small-orb renderer");
includes(css, '.capsule[data-orb-style="3"] .pet-orb-liquid', "Windows liquid small-orb renderer");
includes(css, '.capsule[data-orb-style="4"] .pet-orb', "Windows dark small-orb renderer");
assert(!html.includes("petOrbStatus"), "Windows small-orb must not restore the redundant status dot");
assert(!html.includes("petOrbLabel"), "Windows small-orb center must stay title-free");
assert(!orbPetSwift.includes("shortPageLabel"), "macOS small-orb center must stay title-free");
includes(html, 'data-value="orb"', "Windows small-orb pet picker option");
includes(html, 'data-value="orb_2"', "Windows small-orb 2 picker option");
includes(html, 'data-value="orb_3"', "Windows small-orb 3 picker option");
includes(html, 'data-value="orb_4"', "Windows small-orb 4 picker option");
includes(petGrowthSwift, "static let baseInterval: Int64 = 10_000_000", "macOS 10M pet-growth base interval");
includes(petGrowthSwift, "static let maximumScale = 10.0", "macOS pet-growth 10x cap");
includes(petGrowthWeb, "const BASE_INTERVAL = 10_000_000", "Windows 10M pet-growth base interval");
includes(petGrowthWeb, "const MAXIMUM_SCALE = 10", "Windows pet-growth 10x cap");
includes(renderer, "--pet-growth-scale", "Windows live pet-growth CSS state");
includes(main, "Math.ceil(216 * petScale + 24)", "Windows grown pet native envelope");
includes(main, 'mode.petCharacter === "black_hole"', "Windows selects the taller black-hole envelope");
includes(main, "? 184", "Windows black-hole scene has vertical disk clearance");
includes(swift, "PetGrowth.scale(forTodayTokens: todayTokens)", "macOS live pet-growth state");
includes(petSwift, "growthScale: CGFloat", "macOS grown pet scene");
includes(petSwift, "CGSize(width: 216, height: 184)", "macOS black-hole scene has vertical disk clearance");
includes(blackHoleSwift, "SCShareableContent.excludingDesktopWindows", "macOS ScreenCaptureKit desktop source");
includes(blackHoleSwift, "Privacy_ScreenCapture", "macOS screen-capture permission settings guidance");
includes(blackHoleSwift, "retryCaptureAfterPermissionChange()", "macOS screen-capture permission retry");
includes(macPackageScript, "sign-macos-app.sh", "macOS release bundle signing");
includes(macSignScript, "--identifier com.codexpulse.app", "macOS release bundle signing identity");
includes(macSignScript, "CodexPulse/Resources/CodexPulse.entitlements", "macOS main-app entitlements");
includes(macSignScript, "CodexPulseWidget/CodexPulseWidget.entitlements", "macOS widget entitlements");
includes(macSignScript, "codesign --verify --deep --strict", "macOS release signature verification");
includes(macBuildAndRunScript, "sign-macos-app.sh", "macOS local-run bundle signing");
includes(blackHoleSwift, "excludingWindows: excludedWindow.map", "macOS capture excludes its own transparent pet window");
includes(blackHoleSwift, "NSWorkspace.didWakeNotification", "macOS black-hole wake recovery observer");
includes(blackHoleSwift, "captureGeneration &+= 1", "macOS invalidates stale pre-sleep capture tasks");
includes(blackHoleSwift, "synchronizeDrawableGeometry()", "macOS rebuilds Metal drawable geometry after wake");
includes(blackHoleSwift, "enforceTransparentComposition()", "macOS restores transparent Metal composition after wake");
includes(capsuleController, "restorePanelGeometryAfterSystemWake()", "macOS restores the stable pet panel size after wake");
includes(petSwift, "NSWorkspace.shared.recycle(files)", "macOS Finder drops move recoverably to Trash");
includes(blackHoleSwift, "private let glyphStream = Array(", "macOS Codex thinking infall is a single-glyph stream");
includes(blackHoleSwift, "for emissionOffset in 0..<3", "macOS limits the visible stream to three independent glyphs");
includes(blackHoleSwift, "let entryAngle = randomUnit(emissionIndex, salt: 1.0) * .pi * 2", "macOS code glyphs spawn around the full black-hole perimeter");
includes(blackHoleSwift, "private func randomUnit(_ seed: Int, salt: Double)", "macOS glyph positions are deterministically randomized");
includes(preload, "webUtils.getPathForFile", "Windows File drop paths use Electron's supported bridge");
includes(main, 'ipcMain.handle("pulse:black-hole-trash-files"', "Windows black-hole Recycle Bin IPC");
includes(main, "await shell.trashItem(resolved)", "Windows drops move recoverably to Recycle Bin");
includes(main, "setDisplayMediaRequestHandler", "Windows desktop capture broker");
includes(main, 'windowRef.webContents.send("pulse:black-hole-capture-geometry"', "Windows pushes black-hole geometry while the pet moves");
includes(main, 'windowRef.webContents.send("pulse:system-resume")', "Windows forwards system resume to the renderer");
includes(preload, "onSystemResume", "Windows exposes a bounded resume event bridge");
includes(preload, "onBlackHoleCaptureGeometry", "Windows exposes live black-hole window geometry");
includes(renderer, 'petCharacterPreference === "black_hole"', "Windows Event Horizon pet activation");
includes(blackHoleWebGL, "navigator.mediaDevices.getDisplayMedia", "Windows desktop capture stream");
includes(blackHoleWebGL, "async resetAfterSystemResume()", "Windows restarts the black-hole capture after resume");
includes(blackHoleWebGL, 'track.contentHint = "motion"', "Windows capture favors low-latency motion frames");
includes(blackHoleWebGL, "this.applyCaptureGeometry(geometry)", "Windows consumes pushed geometry without a polling delay");
includes(blackHoleWebGL, "}, 80);", "Windows changes capture display without a long stale-frame pause");
includes(blackHoleWebGL, "classicCodeGlyphs", "Windows Codex thinking infall is a single-glyph stream");
includes(blackHoleWebGL, "function fragmentRandom(seed, salt)", "Windows glyph positions are deterministically randomized");
includes(blackHoleWebGL, 'code.style.setProperty("--spawn-x"', "Windows code glyphs receive independent spawn positions");
includes(blackHoleWebGL, "code.textContent = glyph", "Windows emits one glyph per animated element");
includes(css, "@keyframes black-hole-code-glyph-infall", "Windows glyphs visibly collapse into the event horizon");
includes(blackHoleMetal, "blackHoleDemoPreset(time)", "macOS tours the reference demo looks");
includes(blackHoleWebGL, "demoDiskLook(time)", "Windows tours the reference demo looks");
includes(blackHoleMetal, "fmod(time, 42.0)", "macOS uses the reference 42-second showcase loop");
includes(blackHoleWebGL, "mod(time, 42.0)", "Windows uses the reference 42-second showcase loop");
includes(blackHoleMetal, "preset.diskOuter = 8.0", "macOS shape presets share one visual envelope");
includes(blackHoleWebGL, "look.outer = 8.0", "Windows shape presets share one visual envelope");
includes(blackHoleMetal, "float radius = aspect * 0.0926", "macOS fixed width-relative black-hole size");
includes(blackHoleWebGL, "float holeRadius = aspect * 0.0926", "Windows fixed width-relative black-hole size");
includes(blackHoleMetal, "captureReady ? mask : min(mask, fallbackAlpha)", "macOS capture fallback stays transparent");
includes(blackHoleWebGL, "captureReady ? mask : min(mask, fallbackAlpha)", "Windows capture fallback stays transparent");
includes(blackHoleWebGL, "vec4(color * mask, mask)", "Windows captured desktop edge uses premultiplied alpha");
includes(blackHoleWebGL, "vec4(color * outputAlpha, outputAlpha)", "Windows fallback edge uses premultiplied alpha");
assert(!blackHoleMetal.includes("mix(minimumRadius, maximumRadius, growth)"), "macOS showcase must not change pet size");
assert(!blackHoleWebGL.includes("mix(minimumRadius, maximumRadius, growth)"), "Windows showcase must not change pet size");
includes(blackHoleMetal, "0.055 * sin(time * 1.25)", "macOS black-hole breathing");
includes(blackHoleWebGL, "0.055 * sin(time * 1.25)", "Windows black-hole breathing");
includes(blackHoleMetal, "preset.diskRoll + 0.12 * sin(time * 0.31)", "macOS animated disk rotation");
includes(blackHoleWebGL, "look.roll + 0.12 * sin(time * 0.31)", "Windows animated disk rotation");
includes(blackHoleMetal, "brightnessPulse", "macOS animated disk brightness");
includes(blackHoleWebGL, "brightnessPulse", "Windows animated disk brightness");
includes(blackHoleMetal, "float2 center = float2(0.48, 0.53)", "macOS shader aligns with the code/file infall target");
includes(blackHoleWebGL, "vec2 center = vec2(0.48, 0.53)", "Windows shader aligns with the code/file infall target");
assert(!css.includes("black-hole-absorb-pulse"), "Windows must not stack a CSS scale pulse over the shader choreography");
includes(blackHoleMetal, "background * transmittance", "macOS Ghostty black-hole physical disk compositing");
includes(blackHoleWebGL, "background * transmittance", "Windows Ghostty black-hole physical disk compositing");
includes(blackHoleMetal, "blackHoleNoiseWrapY", "macOS Ghostty seamless accretion streaks");
includes(blackHoleWebGL, "noiseWrapY", "Windows Ghostty seamless accretion streaks");
assert(!blackHoleMetal.includes("float diskAlpha"), "macOS must not overlay a painted analytic disk");
assert(!blackHoleWebGL.includes("float diskAlpha"), "Windows must not overlay a painted analytic disk");
for (const [label, metalValue, webGLValue] of [
  ["disk temperature", "5500.0", "5500.0"],
  ["disk inclination", "1.50", "1.50"],
  ["disk inner radius", "1.8", "1.8"],
  ["disk outer radius", "8.0", "8.0"],
  ["disk opacity", "0.90", "0.90"],
  ["disk gain", "2.2", "2.2"],
  ["disk contrast", "1.6", "1.6"],
  ["disk exposure", "1.40", "1.40"],
]) {
  includes(blackHoleMetal, metalValue, `macOS reference black-hole ${label}`);
  includes(blackHoleWebGL, webGLValue, `Windows reference black-hole ${label}`);
}
includes(blackHoleMetal, "for (uint step = 0; step < 48; step++)", "macOS reference ray-step count");
includes(blackHoleWebGL, "for (int step = 0; step < 48; step++)", "Windows reference ray-step count");
includes(animePetSwift, "TimelineView(.animation(minimumInterval: 1.0 / 60.0", "macOS 60fps anime pet renderer");
includes(animePetSwift, "case .dino: return 1.06", "macOS dinosaur quadruped cadence");
includes(animePetSwift, "case .bunny: return 1.38", "macOS rabbit hop cadence");
includes(animePetSwift, "case .ghost: return 1.24", "macOS ghost hover cadence");
includes(animePetSwift, "case .robot: return 0.94", "macOS robot servo cadence");
includes(animePetSwift, "private static func foxIdleSample", "macOS fox idle sequence exposes continuous frame sampling");
includes(animePetSwift, "return FoxIdleSample(frame: frame)", "macOS fox tail loop renders one clean frame");
includes(animePetSwift, "case .fox: base = 0.64", "macOS fox transition allows natural weight transfer");
includes(animePetSwift, "private enum AnimePetTransitionChoreography", "macOS anime pets use species transition choreography");
includes(animePetSwift, "if to.isLocomotion { return to }", "macOS transitions include a planted locomotion bridge");
includes(animePetSwift, "character == .fox ? \"walk-left-0\"", "macOS fox interaction pose has complete tails");
assert(!animePetSwift.includes(".plusLighter"), "macOS pet frames must not create bright double-image trails");
includes(petSwift, "let frameBlend: Double", "macOS working pose sequence carries interpolation");
includes(proceduralCatSwift, "TimelineView(.animation(minimumInterval: 1.0 / 60.0", "macOS 60fps cat rig");
includes(proceduralCatSwift, "Canvas(opaque: false, rendersAsynchronously: true)", "macOS vector cat canvas");
includes(proceduralCatSwift, "let counterStride = -stride", "macOS diagonal-pair quadruped gait");
includes(proceduralCatSwift, "private static let transitionDuration: TimeInterval = 0.62", "macOS cat transition allows a real weight-shift bridge");
includes(proceduralCatSwift, "private enum CatTransitionChoreography", "macOS cat transitions use authored movement stages");
includes(proceduralCatSwift, "transitionFromPose = renderedPose(at: now)", "macOS interruption-safe state blending");
includes(proceduralCatSwift, "case .sniffing:", "macOS desktop item inspection motion");
includes(proceduralCatSwift, "case .pawing:", "macOS desktop item paw motion");
includes(proceduralCatSwift, "case .pouncing:", "macOS Dock icon pounce motion");
includes(proceduralCatSwift, 'AnimeCatAssets.image("anime-cat-state-working-\\($0)")', "macOS multi-pose paw working cycle");
includes(petSwift, "leftKeyStrength: frame == 2 ? contact : 0", "macOS key light follows actual left-paw contact");
includes(petSwift, "rightKeyStrength: frame == 5 ? contact : 0", "macOS key light follows actual right-paw contact");
includes(proceduralCatSwift, "pose.workSurface = 1", "macOS working state reveals its keyboard");
includes(proceduralCatSwift, "AnimeCatPainter.draw(", "macOS anime artwork rig renderer");
includes(proceduralCatSwift, 'AnimeCatAssets.image("anime-cat-whole")', "macOS identity-locked anime master");
includes(proceduralCatSwift, "if !facesLeft", "macOS native-left artwork mirrors only for rightward travel");
includes(proceduralCatSwift, 'AnimeCatAssets.image("anime-cat-walk-right-\\($0)")', "macOS complete-pose rightward walk cycle");
includes(proceduralCatSwift, "pose.walkPhase = cycle.truncatingRemainder", "macOS walk cycle advances with gait phase");
includes(proceduralCatSwift, "let cycle = time * 1.12", "macOS natural 896ms gait cycle");
includes(html, 'id="petCatCanvas"', "Windows procedural cat canvas");
includes(renderer, "proceduralCat.setState(petState)", "Windows procedural cat state control");
includes(renderer, "proceduralCat.setCharacter(petCharacterPreference)", "Windows shared anime companion renderer");
includes(catRig, "requestAnimationFrame(tick)", "Windows 60fps cat rig");
includes(catRig, "renderFrameForQA(nextState, elapsedSeconds)", "Windows visual QA owns an exact animation clock");
includes(catRig, "renderFootstepImpactForQA(ageSeconds)", "Windows QA measures the grounded contact decal");
includes(catRig, "function samplePose(mode, time)", "Windows continuous cat pose evaluation");
includes(catRig, "fromPose = sampleCurrent(now)", "Windows interruption-safe state blending");
includes(catRig, '`state-working-${index}`', "Windows multi-pose paw working cycle");
includes(catRig, "left: frame === 2 ? contact : 0", "Windows key light follows actual left-paw contact");
includes(catRig, "right: frame === 5 ? contact : 0", "Windows key light follows actual right-paw contact");
includes(catRig, "pose.workSurface = 1", "Windows working state reveals its keyboard");
includes(catRig, "function drawAnimeCat(ctx, pose, facesLeft, state", "Windows anime artwork rig renderer");
includes(catRig, "anime-cat-${name}.png", "Windows anime puppet layers");
includes(catRig, '"whole",', "Windows identity-locked anime master");
includes(catRig, '`walk-right-${index}`', "Windows complete-pose rightward walk cycle");
includes(catRig, "const cycle = time * 1.12", "Windows natural 896ms gait cycle");
includes(catRig, "function drawAnimePet(", "Windows anime renderer for all companions");
includes(catRig, "dino: 1.06, bunny: 1.38, ghost: 1.24, robot: .94", "Windows species-specific locomotion cadence");
includes(catRig, "const foxIdleSample = (animationTime)", "Windows fox idle sequence exposes continuous frame sampling");
includes(catRig, "function transitionBridgeState(from, to)", "Windows pet transitions use authored movement stages");
includes(catRig, "function animeTransitionMotion(character, from, to, progress)", "Windows species own their transition mechanics");
includes(catRig, "fox: 640", "Windows fox transition matches macOS weight-transfer timing");
includes(catRig, 'character === "fox" ? "walk-left-0"', "Windows fox interaction pose has complete tails");
assert(!catRig.includes('globalCompositeOperation = "lighter"'), "Windows pet frames must not create bright double-image trails");
includes(catRig, "nextFrame: (frame + 1) % WORKING_FRAME_DURATIONS.length", "Windows working pose sequence carries interpolation");
includes(renderer, "function petLocomotionCycleDuration(character)", "Windows pet locomotion cycle contract");
includes(renderer, 'petRoamingState = plan.direction === "left" ? "walk_left" : "walk_right"', "Windows authored directional pet gait");
includes(renderer, "const fullCycles = Math.max(2, Math.round(requestedDuration / cycle))", "Windows movement ends on a full gait cycle");
includes(main, "const eased = 0.5 - Math.cos(Math.PI * progress) / 2", "Windows pet roaming has planted ease-in and ease-out");
includes(main, 'direction: plan.direction < 0 ? "left" : "right"', "Windows native roaming direction contract");
includes(main, "right.horizontalDistance - left.horizontalDistance", "Windows idle roaming prioritizes horizontal walking room");
includes(main, "const arc = Math.sin(Math.PI * progress) * arcHeight", "Windows idle roaming uses a shallow travel arc");
includes(renderer, "function petRoamingArcHeight(character)", "Windows pet species own distinct roaming arcs");
includes(main, "const kind = forceInteraction", "Windows first idle roam must choose a desktop or taskbar interaction");
includes(main, 'kind: "wander"', "Windows ordinary idle roaming remains available");
includes(renderer, '["pawing", totalDuration * 0.64]', "Windows desktop interaction holds a visible pawing action");
includes(renderer, '["pouncing", totalDuration * 0.50]', "Windows taskbar interaction holds a visible pounce");
includes(renderer, '["dock_play", totalDuration * 0.32]', "Windows taskbar interaction holds a visible play action");
includes(renderer, "proceduralCat.setFacesLeft?.", "Windows interaction pose faces the real target");
includes(catRig, "setFacesLeft(nextFacesLeft)", "Windows pet renderer accepts target-facing updates");
includes(catRig, "function drawWorkingKeyPulse", "Windows working pets have synchronized keyboard lights");
includes(catRig, "y = breathe * .35", "Windows authored paw cycle keeps the working root stable");
includes(animePetSwift, "y = breath * 0.35", "macOS authored paw cycle keeps the working root stable");
includes(capsuleController, "catRoamingMinimumHorizontalDistance", "macOS idle roaming enforces horizontal travel");
includes(capsuleController, "let arc = sin(progress * .pi) * catRoamingArcHeight", "macOS idle roaming uses a shallow travel arc");
assert(!petSwift.includes("codex_cat_v3_"), "macOS cat must not use GIF state assets");
assert(!renderer.includes("codex_cat_v3_"), "Windows cat must not use GIF state assets");
for (const directory of [
  "CodexPulse/Resources/PetsV2",
  "windows/src/renderer/assets/pets-v2",
]) {
  const absoluteDirectory = path.join(root, directory);
  const legacyGIFs = fs.existsSync(absoluteDirectory)
    ? fs.readdirSync(absoluteDirectory).filter((name) => /\.gif$/i.test(name))
    : [];
  assert.deepStrictEqual(legacyGIFs, [], `${directory} must not package legacy pet GIF assets`);
}
for (const part of ["whole"]) {
  assert(
    fs.existsSync(path.join(root, `CodexPulse/Resources/AnimeCat/anime-cat-${part}.png`)),
    `missing macOS anime cat ${part} layer`
  );
  assert(
    fs.existsSync(path.join(root, `windows/src/renderer/assets/anime-cat/anime-cat-${part}.png`)),
    `missing Windows anime cat ${part} layer`
  );
}
for (const direction of ["left", "right"]) {
  for (let frame = 0; frame < 8; frame += 1) {
    for (const platformRoot of [
      "CodexPulse/Resources/AnimeCat",
      "windows/src/renderer/assets/anime-cat",
    ]) {
      assert(
        fs.existsSync(path.join(root, platformRoot, `anime-cat-walk-${direction}-${frame}.png`)),
        `missing ${platformRoot} ${direction} walk frame ${frame}`
      );
    }
  }
}
for (const state of [
  "idle", "working", "waiting-auth",
  "sleeping", "stretch", "grooming", "wave",
]) {
  for (const platformRoot of [
    "CodexPulse/Resources/AnimeCat",
    "windows/src/renderer/assets/anime-cat",
  ]) {
    assert(
      fs.existsSync(path.join(root, platformRoot, `anime-cat-state-${state}.png`)),
      `missing ${platformRoot} ${state} state pose`
    );
  }
}
for (let frame = 0; frame < 8; frame += 1) {
  for (const platformRoot of [
    "CodexPulse/Resources/AnimeCat",
    "windows/src/renderer/assets/anime-cat",
  ]) {
    assert(
      fs.existsSync(path.join(root, platformRoot, `anime-cat-state-thinking-${frame}.png`)),
      `missing ${platformRoot} thinking pose ${frame}`
    );
  }
}
includes(capsuleController, "case .leftMouseDragged:", "macOS compact pet has native drag tracking");
includes(capsuleController, "clampedCompactOrigin", "macOS compact pet drag stays inside the visible desktop");
includes(capsuleController, "let screens = NSScreen.screens", "macOS compact pet drag evaluates every display");
includes(capsuleController, "$0.frame.contains(pointer)", "macOS compact pet follows the pointer onto a secondary display");
includes(capsuleController, "var owesFirstInteraction = true", "macOS first idle trip demonstrates an interaction");
includes(capsuleController, "case .desktopItem:", "macOS desktop icon-grid interaction target");
includes(capsuleController, "case .dockIcon:", "macOS Dock interaction target");
includes(capsuleController, "publishCatRoaming(.pawingDesktopItem", "macOS desktop item interaction choreography");
includes(capsuleController, "publishCatRoaming(.dockPounce", "macOS Dock interaction choreography");
includes(capsuleController, "onManualDragEnded", "macOS manual pet drag reports its desktop drop");
includes(capsuleController, "onManualDragMoved", "macOS remembers targets crossed during a manual drag");
includes(capsuleController, "handleManualPetDrop(at:", "macOS manual desktop drop starts a pet interaction");
includes(capsuleController, "return isDockDrop ? .dockIcon : .desktopItem", "macOS manual drop distinguishes Dock and desktop");
includes(capsuleController, "Double.random(in: 5...10)", "macOS encounter play lasts a natural 5–10 seconds");
includes(capsuleController, "Double.random(in: 15...30)", "macOS repeated encounters cool down for 15–30 seconds");
includes(capsuleController, "guard await waitForCat(seconds: Double.random(in: 2.2...2.9))", "macOS sleep cycle holds its stretch for 2–3 seconds");
includes(capsuleController, "wakeSleepingPetFromClick()", "macOS sleeping pet wakes through a click stretch");
includes(capsuleController, "guard await self.waitForCat(seconds: 2.5)", "macOS click wake stretch remains readable");
includes(capsuleController, 'Menu("切换宠物", systemImage: "pawprint")', "macOS capsule pet switch menu");
includes(capsuleController, "ForEach(PetCharacter.allCases)", "macOS pet switch menu covers every companion");
includes(capsuleController, "store.settings.resolvedPetCharacter = character", "macOS pet switch applies in place");
includes(capsuleController, "store.saveSettings()", "macOS pet switch persists");
includes(preload, "showPetSwitchMenu", "Windows preload exposes the native pet switch menu");
includes(main, 'ipcMain.handle("pulse:show-pet-switch-menu"', "Windows native pet switch menu IPC");
includes(main, "type: \"radio\"", "Windows pet switch menu marks the active companion");
includes(renderer, 'elements.capsule.addEventListener("contextmenu"', "Windows compact pet supports right-click switching");
includes(renderer, "function selectPetCharacter(value)", "Windows pet selection reuses one persistence path");
includes(animePetSwift, "case .investigating: return .sniffing", "macOS anime pets visibly inspect desktop and Dock targets");
includes(animePetSwift, "case .pawingDesktopItem: return .pawing", "macOS anime pets visibly paw desktop targets");
includes(animePetSwift, "case .dockPlay: return .dockPlay", "macOS anime pets visibly play with Dock targets");
includes(animePetSwift, "case .dockPounce: return .pouncing", "macOS anime pets visibly pounce on Dock targets");
includes(capsuleController, "let leftInset = max(0, visible.minX - frame.minX)", "macOS Dock edge detection");
includes(capsuleController, "let movementFacesLeft = abs(horizontalDelta) > 2", "macOS walking direction follows actual destination delta");
includes(capsuleController, "let completeCycles = max(2", "macOS movement ends on a complete gait cycle");
includes(proceduralCatSwift, "CatTransitionChoreography.visualMode(", "macOS transitions keep one staged silhouette");
includes(animePetSwift, "enum PetFootstepPainter", "macOS walking pets render contact decals under their feet");
includes(animePetSwift, "Double(step) * contactInterval", "macOS footfalls stay synchronized to the locomotion cycle");
includes(animePetSwift, "for offset in -1..<2", "macOS footstep warp follows the grounded locomotion trail");
assert(!animePetSwift.includes("crushedTokens"), "macOS footstep effect must not draw fixed fake desktop words");
assert(!animePetSwift.includes("drawGlyphHalf"), "macOS footstep effect must not fracture invented glyphs");
assert(!animePetSwift.includes("drawScreenWarp"), "macOS must not fake desktop displacement with detached refraction stripes");
includes(animePetSwift, "drawCracks(", "macOS footfalls include restrained impact fissures");
includes(catRig, "transitionVisualState(previousState, state, transition)", "Windows transitions keep one staged silhouette");
includes(catRig, "function drawFootstepTrail(", "Windows walking pets render contact decals under their feet");
includes(catRig, "step * contactInterval", "Windows footfalls stay synchronized to the locomotion cycle");
includes(catRig, "for (let offset = -1; offset < 2; offset += 1)", "Windows footstep warp follows the grounded locomotion trail");
assert(!catRig.includes("CRUSHED_TEXT_TOKENS"), "Windows footstep effect must not draw fixed fake desktop words");
assert(!catRig.includes('ctx.strokeText('), "Windows footstep effect must not fracture invented glyphs");
assert(!catRig.includes("drawScreenWarp"), "Windows must not fake desktop displacement with detached refraction stripes");
includes(swift, "@State private var isCatMonitorVisible = false", "macOS idle cat and fox monitors cannot start permanently visible");
includes(swift, `catMonitorHideTask = nil
            guard isMini`, "macOS monitor timer always releases ownership before its idle-state guard");
includes(catRig, "drawFootstepCracks(", "Windows footfalls include restrained impact fissures");
includes(main, "function classifyManualPetDrop(point)", "Windows manual pet drag classifies desktop and taskbar drops");
includes(main, "encounterKind", "Windows remembers targets crossed before mouse-up");
includes(preload, "onPetDrop: (callback)", "Windows renderer receives native manual pet drops");
includes(renderer, "async function runManualPetDropInteraction(drop)", "Windows manual drop starts a pet interaction");
includes(renderer, "5000 + Math.random() * 5000", "Windows encounter play lasts 5–10 seconds");
includes(renderer, "15000 + Math.random() * 15000", "Windows repeated encounters cool down for 15–30 seconds");
includes(renderer, "let catIdleSequence = []", "Windows pet sleep uses a staged state sequence");
includes(renderer, "wakeSleepingPetFromClick()", "Windows sleeping pet wakes through a click stretch");
includes(renderer, 'holdPetRoamingState("stretch", 2500', "Windows wake stretch remains visible for 2.5 seconds");
assert(!swift.includes("withAnimation(.easeInOut(duration: 0.22)) {\n                catRoamingActivity"), "macOS roaming state must not stack an outer canvas animation");
includes(capsuleController, 'Button("退出 CodexPulse", role: .destructive)', "macOS capsule context quit action");
includes(macApp, "CommandGroup(replacing: .appTermination)", "macOS standard quit command");
includes(macApp, "CodexPulseLifecycle.quit(store: store)", "macOS centralized graceful termination");
includes(macApp, "runningApplications(withBundleIdentifier: AppConstants.bundleID)", "macOS single-instance guard");
includes(macApp, "guard !isSecondaryInstance else { return }", "macOS duplicate instance does not start services");
includes(menuBarPanel, '"随 Codex 启动"', "macOS menu panel exposes Codex launch follower");
includes(
  menuBarPanel,
  "FloatingCapsuleController.shared.setFollowCodexLaunch(",
  "macOS menu panel applies Codex launch follower immediately"
);
includes(
  menuBarPanel,
  ".frame(width: 332, height: menuPanelHeight)",
  "macOS menu panel keeps a stable reset-card shell"
);
includes(
  menuBarPanel,
  'toolbarTextLabel("刷新", systemImage: "arrow.clockwise")',
  "macOS menu panel keeps refresh on one compact toolbar row"
);
includes(
  menuBarPanel,
  ".frame(width: 52, height: 30)",
  "macOS menu toolbar text actions reserve a non-wrapping hit target"
);
includes(
  menuBarPanel,
  ".frame(width: 30, height: 30)",
  "macOS menu toolbar icon actions share one compact hit target"
);
includes(
  menuBarPanel,
  ".menuIndicator(.hidden)",
  "macOS menu toolbar avoids a second overflow chevron"
);
assert(
  !menuBarPanel.includes("withAnimation(.spring(response: 0.3, dampingFraction: 0.85))"),
  "macOS reset-card collapse must not animate the MenuBarExtra window height"
);
includes(snapshotStore, "SecTaskCopyValueForEntitlement", "macOS App Group entitlement verification");
includes(snapshotStore, "static let appGroupURL: URL?", "macOS App Group lookup is cached");
includes(css, '--pet-display-left: 126px;', "Windows dino terminal x");
includes(css, '.capsule[data-pet="cat"]', "Windows cat speech bubble");
includes(css, '.capsule[data-pet="bunny"]', "Windows bunny tag");
includes(css, '.capsule[data-pet="ghost"]', "Windows ghost bubble");
includes(css, '.capsule[data-pet="robot"]', "Windows robot HUD");
includes(main, "const MINI_SIZE = { width: 240, height: 154 };", "Windows compact native pet size");
includes(main, "const miniConversationSize = {", "Windows pet conversation has an expanded native envelope");
includes(preload, "conversationExpanded: mode.conversationExpanded === true", "Windows pet conversation state crosses the IPC boundary");
includes(renderer, "if (miniMode) {", "Windows compact pet hit shape branch");
includes(renderer, "rects.push(paddedShapeRect(elements.conversationDetail, 14, 18))", "Windows mini conversation hit shape");
includes(settingsStore, "case dino", "shared dino pet option");
includes(settingsStore, "get { petCharacter ?? .dino }", "shared default dino pet");
includes(settingsStore, "allCases.filter(\\.isAvailableInAPIKeyMode)", "shared API mini style filtering");
includes(settingsStore, "let style = apiMiniCapsuleStyle ?? .time", "macOS API mini default time");
includes(swift, "? store.settings.resolvedAPIMiniCapsuleStyle", "macOS active API mini preference");
includes(renderer, 'const apiMiniStyles = new Set(["tokens", "status", "weather", "time"]);', "Windows API mini choices");
includes(renderer, 'return apiMiniStyles.has(saved) ? saved : "time";', "Windows API mini default time");
includes(renderer, "if (quotaOption) quotaOption.hidden = apiMode;", "Windows API quota option filtering");
includes(renderer, 'const interactionPhase = Math.floor(now.getTime() / 1000) % 13;', "Windows rich pet action cadence");
for (const pet of ["dino", "bunny", "ghost", "robot", "fox"]) {
  for (const state of [
    "idle-0", "idle-1", "idle-2", "idle-3",
    "thinking-0", "thinking-1", "thinking-2", "thinking-3",
    "working", "waiting-auth", "success", "error",
    "sleeping", "stretch", "grooming", "curious",
  ]) {
    for (const platformRoot of [
      "CodexPulse/Resources/AnimePets",
      "windows/src/renderer/assets/anime-pets",
    ]) {
      assert(
        fs.existsSync(path.join(root, platformRoot, `anime-${pet}-state-${state}.png`)),
        `missing ${platformRoot} ${pet}/${state}`
      );
    }
  }
  for (const direction of ["left", "right"]) {
    for (let frame = 0; frame < 8; frame += 1) {
      for (const platformRoot of [
        "CodexPulse/Resources/AnimePets",
        "windows/src/renderer/assets/anime-pets",
      ]) {
        assert(
          fs.existsSync(path.join(root, platformRoot, `anime-${pet}-walk-${direction}-${frame}.png`)),
          `missing ${platformRoot} ${pet}/${direction}/${frame}`
        );
      }
    }
  }
}

// Magnetic motion and click timing contract.
includes(swift, "magneticOffset = CGSize(width: normalizedX * 12, height: normalizedY * 8)", "macOS magnet travel");
includes(renderer, "magnet.targetX = normalizedX * 12;", "Windows horizontal magnet travel");
includes(renderer, "magnet.targetY = normalizedY * 8;", "Windows vertical magnet travel");
includes(renderer, "function springStep", "Windows SwiftUI-matched magnetic return");
includes(renderer, "deltaSeconds / 0.020", "Windows fast eased magnetic follow");
includes(renderer, "timestamp - lastGlowPaintAt < 32", "Windows decorative glow throttle");
includes(renderer, "magnet.renderX = magnet.x;", "Windows subpixel magnetic motion");
includes(renderer, "elements.capsule.style.translate = `${magnet.renderX.toFixed(3)}px", "Windows isolated magnetic translate channel");
includes(renderer, "rect.left - magnet.renderX", "Windows stable pointer mapping during magnetic motion");
includes(main, "if (signature === windowShapeSignature) return true;", "Windows native shape deduplication");
includes(main, "windowRef.setShape(fullTargetShape);", "Windows atomic mini/full native shape reset");
includes(main, "const target = USE_STABLE_DESKTOP_SURFACE", "Windows stable native surface in mini mode");
includes(main, "const limitsInterval = active ? 3_000 : 8_000;", "Windows live quota refresh cadence");
includes(main, "const usageInterval = active ? 5_000 : 12_000;", "Windows live usage refresh cadence");
includes(main, "function mergeLocalSessionFallback", "Windows remote Token failure local session fallback");
includes(main, "if (remoteUsageFailed) {", "Windows remote failure enters local session fallback path");
includes(main, "if (!rpc) {", "Windows unavailable RPC still reads local session usage");
includes(pulseStore, "private let activePollingInterval: TimeInterval = 5", "macOS live quota polling cadence");
includes(pulseStore, "try await Task.sleep(nanoseconds: 90_000_000)", "macOS local token debounce");
includes(
  pulseStore,
  "readRealtimeLocalUsage(merging: previous.usage)",
  "macOS live cache/cost refresh avoids history aggregation"
);
includes(pulseStore, "for delay in [0.75, 2.5]", "macOS post-turn profile refresh");
includes(appServerClient, "private let rateLimitsCacheTTL: TimeInterval = 4", "macOS quota cache cadence");
includes(appServerClient, "private let usageCacheTTL: TimeInterval = 10", "macOS usage cache cadence");
includes(appServerClient, "return await mergingLocalUsage(into: fallback)", "macOS fallback refreshes all device-local Token aggregates");
includes(appServerClient, "LocalCodexUsageReader.shared.allTimeSummary", "macOS scans all local sessions for lifetime Token and streak");
includes(appServerClient, "merged.mergeLocalStreak(", "macOS promotes the device-local session streak");
includes(pulseStore, "private func promoteDeviceLocalUsage", "macOS promotes device-local Token for every account type");
includes(pulseStore, "result.localCurrentStreakDays = usage.localCurrentStreakDays", "macOS account switches preserve the local streak");
includes(pulseStore, "next.usage = deviceLocalUsage(from: snapshot.usage)", "macOS account switches preserve device Token totals");
includes(formatters, 'return "刚刚"', "macOS immediate sync wording");
includes(formatters, "static func liveTokens", "macOS live Token precision");
includes(formatters, 'return String(format: "%.1fM"', "macOS compact live Token precision");
includes(formatters, 'return String(format: "%.1fB"', "macOS dashboard Token units switch to billions");
includes(formatters, 'return String(format: "%.1fT"', "macOS dashboard Token units switch to trillions");
includes(dashboard, 'Text("缓存命中率")', "macOS usage overview displays cache hit rate");
includes(dashboard, '"缓存"', "macOS usage overview displays cached Token volume");
includes(dashboard, '"未缓存"', "macOS usage overview displays uncached Token volume");
includes(dashboard, '"今日成本"', "macOS usage overview displays today's estimated cost");
includes(dashboard, '"累计成本"', "macOS usage overview displays lifetime estimated cost");
assert(
  !swift.includes("accountDetails(snapshot.account)"),
  "macOS expanded capsule must not repeat account and plan details below its header"
);
includes(swift, 'metric("缓存命中率", cacheHitRate)', "macOS detail displays cache hit rate");
includes(swift, 'metric("缓存 Token"', "macOS detail displays cached Token volume");
includes(swift, 'metric("未缓存 Token"', "macOS detail displays uncached Token volume");
includes(swift, 'metric("成本"', "macOS detail displays today's estimated cost");
includes(swift, 'metric("累计成本"', "macOS detail displays lifetime estimated cost");
includes(html, 'id="cacheHitDetail"', "Windows detail displays cache hit rate");
includes(html, 'id="cachedTokensDetail"', "Windows detail displays cached Token volume");
includes(html, 'id="uncachedTokensDetail"', "Windows detail displays uncached Token volume");
includes(html, 'id="todayCostDetail"', "Windows detail displays today's estimated cost");
includes(html, 'id="totalCostDetail"', "Windows detail displays lifetime estimated cost");
includes(
  localUsageReader,
  "estimatedCostUSD: hasPricedUsage ? estimatedCostUSD : nil",
  "macOS lifetime session aggregation preserves model-aware estimated cost"
);
includes(localUsageReader, "lastTokenUsage", "macOS Token aggregation uses per-event usage");
includes(
  capsuleController,
  "stabilizeAttachedWindowLevel",
  "macOS keeps the attached panel below Codex after click-driven state updates"
);
includes(swift, ".numericText(countsDown: false)", "macOS upward live Token roll");
includes(swift, "showsIdleContent: mode == .idle || mode == .offline", "macOS offline API time remains an idle presentation");
includes(swift, "store.snapshot.account.authMode != .apiKey", "macOS active pet quota excludes API Key sessions");
includes(swift, "elapsed.truncatingRemainder(dividingBy: 8) >= 5", "macOS active pet quota carousel cadence");
includes(renderer, "function setLiveTokenText(value, animated)", "Windows upward live Token roll");
includes(renderer, 'translateY(-110%)', "Windows outgoing Token layers do not overlap");
includes(renderer, 'translateY(110%)', "Windows incoming Token layers do not overlap");
includes(renderer, 'localStorage.getItem(lastUsageModePreferenceKey) === "api"', "Windows preserves API mini style while reconnecting");
includes(renderer, "function formatLiveUsageTokens(value)", "Windows live Token precision");
includes(renderer, 'state.account?.auth !== "API Key"', "Windows active pet quota excludes API Key sessions");
includes(renderer, "activeElapsed % 8 >= 5", "Windows active pet quota carousel cadence");
includes(renderer, 'function setMiniMonitorText(value, animated, unit = "")', "Windows pet monitor upward page roll");
includes(html, 'id="todayTokensPrevious"', "Windows compositor Token roll layer");
includes(html, 'id="miniValuePrevious"', "Windows pet monitor compositor roll layer");
includes(pulseStore, "mergeRealtimeThreadTokenTotal", "macOS real-time Token delta merge");
includes(localUsageReader, "var totalTokens: Int64?", "macOS session-tail Token total");
includes(appServerClient, 'case "item/agentMessage/delta":', "macOS visible response delta subscription");
includes(pulseStore, "case .agentMessageDelta", "macOS response delta state merge");
includes(localUsageReader, '"agent_message_content_delta"', "macOS session delta compatibility fallback");
includes(swift, "private var taskStreamStrip", "macOS task information strip");
includes(swift, "private var taskInformationIsland", "macOS persistent task information island");
includes(swift, "showsSurface: false", "macOS expanded conversation reuses the information island surface");
assert(!capsuleController.includes("isConversationIslandMorph"), "macOS native panel must not compete with the SwiftUI conversation morph");
includes(capsuleController, "!isPetConversationMorph", "macOS pet conversation bypasses native panel interpolation");
includes(swift, "private struct StreamingTaskSummary", "macOS live task summary transition");
includes(swift, "private struct StreamingActivityDots", "macOS continuous processing feedback");
assert(!swift.includes("ScrollView(.horizontal)"), "macOS task strip must not show a horizontal scroll indicator");
includes(swift, "private var isMiniConversationExpanded", "macOS mini pet conversation state");
includes(swift, "private func handleMiniSingleClick()", "macOS mini pet click behavior");
includes(swift, "? [.tokens, .weather, .time]", "macOS API mini click cycle");
includes(capsuleController, "private var isPetConversationLayout", "macOS pet remains interactive above conversation");
includes(main, 'lower === "item/agentmessage/delta"', "Windows visible response delta subscription");
includes(main, 'payloadType === "agent_message_content_delta"', "Windows session delta compatibility fallback");
includes(renderer, "function setConversationExpanded", "Windows task island expansion state");
includes(renderer, "function setMiniConversationExpanded", "Windows mini pet conversation expansion state");
includes(renderer, "function handleMiniSingleClick", "Windows mini pet click behavior");
includes(renderer, '["quota", "tokens", "weather", "time"]', "Windows account mini click cycle");
includes(renderer, "function renderConversationMessages", "Windows live conversation rendering");
includes(renderer, "summaryElement.scrollLeft = summaryElement.scrollWidth", "Windows live task summary tail scrolling");
includes(renderer, "taskSummaryAnimation = elements.informationTaskSummary.animate", "Windows live summary page transition");
includes(html, 'id="conversationDetail"', "Windows task conversation surface");
includes(html, 'class="information-task-copy"', "Windows centered task copy group");
includes(css, ".conversation-detail.open", "Windows outward conversation transition");
includes(css, "transform: translate3d(0, -6px, 0);", "Windows conversation avoids expensive scaled glass layers");
includes(css, "-webkit-backdrop-filter: none;", "Windows conversation avoids DirectComposition blur trails");
includes(renderer, "conversationExpanded: true", "Windows grows the native pet window before revealing conversation");
includes(css, "html.conversation-expanded .information-strip", "Windows information island header expansion");
includes(css, ".information-stream-dots", "Windows continuous processing feedback");
includes(css, "margin-top: 6px;", "Windows conversation no longer overlaps the information strip in layers");
includes(css, "html.mini-mode.mini-conversation-expanded .conversation-detail", "Windows pet-preserving conversation layout");
includes(appServerClient, "cachedCLIPath", "macOS cached CLI discovery");
includes(appServerClient, "proc.currentDirectoryURL = Self.safeCodexWorkingDirectory()", "macOS safe Codex working directory");
assert(!appServerClient.includes('["-lc", "command -v codex"]'), "macOS startup must not launch a login shell");
includes(artificialAnalysis, "private var cachedAPIKey: String?", "macOS one-time Keychain read");
includes(artificialAnalysis, "static func containsCredential() -> Bool", "macOS metadata-only startup Keychain check");
includes(artificialAnalysis, "guard let apiKey = loadAPIKeyIfNeeded()", "macOS lazy Keychain data access");
includes(updateService, "releases/latest", "macOS GitHub latest release check");
includes(updateService, 'hasSuffix(".dmg")', "macOS DMG release selection");
includes(updateService, "downloadAvailableUpdate", "macOS in-app update download");
includes(updateService, 'case .ready: "重启并更新"', "macOS restart-to-install action");
includes(macUpdateSupport, "URLSessionDownloadDelegate", "macOS native download progress");
includes(macUpdateSupport, "SHA256.hash", "macOS downloaded asset verification");
includes(macUpdateSupport, "/usr/bin/hdiutil attach", "macOS DMG replacement helper");
includes(main, "GITHUB_LATEST_RELEASE_API", "Windows GitHub latest release check");
includes(main, "preferredWindowsReleaseURL", "Windows installer release selection");
includes(main, "downloadAvailableUpdate", "Windows in-app update download");
includes(main, "normalizedSHA256Digest", "Windows downloaded asset verification");
includes(main, '["--updated", "/S", "--force-run"]', "Windows silent restart installer");
includes(main, "const UPDATE_CHECK_INTERVAL_MS = 5 * 60 * 1000", "Windows live update polling cadence");
includes(main, 'powerMonitor.on("resume"', "Windows wake update check");
includes(main, "function nativeWindowCoordinate", "Windows pet roam Win32 coordinate normalization");
includes(main, "Object.is(rounded, -0)", "Windows pet roam rejects JavaScript negative zero");
includes(main, "windowRef.setPosition(nextX, nextY, false);", "Windows pet roam native movement");
includes(main, "finish(true);", "Windows pet roam native failure isolation");
includes(renderer, 'window.addEventListener("online"', "Windows network recovery update check");
includes(updateService, "skipAvailableVersion", "macOS skipped release persistence");
includes(updateService, "private let automaticCheckInterval: TimeInterval = 5 * 60", "macOS live update polling cadence");
includes(updateService, "NSWorkspace.didWakeNotification", "macOS wake update check");
includes(updateService, "NWPathMonitor()", "macOS network recovery update check");
includes(swift, "updateDetailCard", "macOS capsule update details");
includes(main, "skippedUpdateVersion", "Windows skipped release persistence");
includes(renderer, "showUpdateDetails", "Windows capsule update details");
includes(renderer, "function releaseNotesForDisplay(markdown)", "Windows release note formatter");
includes(renderer, "完整变更：${from} → ${to}", "Windows compact changelog label");
includes(html, 'id="updateIndicator"', "Windows capsule update indicator");
includes(html, 'id="updateProgress"', "Windows capsule update progress");
includes(renderer, "formatDownloadBytes", "Windows update byte progress formatting");
includes(css, ".detail.update-mode", "Windows update detail layout");
includes(releaseWorkflow, "permissions:\n  contents: write", "GitHub release write permission");
includes(releaseWorkflow, '--notes-file "$RELEASE_NOTES_FILE"', "GitHub curated release notes");
assert(!css.includes("translate3d(0, -4px, 0) scale(.96)"), "Windows details must not scale glyphs during reveal");
includes(renderer, "}, 300);", "Windows single-click delay");
includes(renderer, "duration: 150", "Windows outgoing mini transition phase");
includes(renderer, "duration: 190", "Windows incoming mini transition phase");
includes(renderer, "scale(.72)", "Windows macOS-matched independent view scale");
includes(renderer, "runCapsuleMorphTransition", "Windows rigid mini/full transition");
includes(renderer, "await incoming.ready;", "Windows flash-free animation ownership handoff");
includes(renderer, "outgoing.cancel();", "Windows flash-free fallback handoff");
includes(css, "align-items: flex-end;", "Windows right-edge mini transition anchor");
assert(!renderer.includes("width: `${firstRect.width}px`"), "Windows mini transition must not squeeze capsule width");
includes(swift, ".spring(response: 0.34, dampingFraction: 0.86)", "macOS mini transition");

// Hover light geometry. Keep the same three masked stroke layers as macOS;
// an unmasked rectangular bloom can escape past a rounded Windows corner.
includes(swift, "lineWidth: 2.35", "macOS conic edge width");
includes(swift, "endRadius: 48", "macOS conic reveal radius");
includes(swift, "lineWidth: 3.2", "macOS bright edge width");
includes(swift, "endRadius: 44", "macOS bright edge radius");
includes(swift, "lineWidth: 4.4", "macOS bloom edge width");
includes(swift, "endRadius: 52", "macOS bloom radius");
includes(swift, ".blur(radius: 5)", "macOS bloom blur");
includes(css, "padding: 2.35px;", "Windows conic edge width");
includes(css, "clip-path: circle(48px", "Windows conic reveal radius");
includes(css, "padding: 3.2px;", "Windows bright edge width");
includes(css, "radial-gradient(circle 44px", "Windows bright edge radius");
includes(css, "padding: 4.4px;", "Windows outer edge width");
includes(css, "radial-gradient(circle 52px", "Windows outer edge radius");
includes(css, "inset: -2px;", "Windows outward hover/activity light offset");
includes(css, "width: 36px;", "Windows curved hover crest width");
includes(css, "height: 5px;", "Windows curved hover crest height");
includes(css, "filter: none;", "Windows grain-free hover crest");
assert(!html.includes("capsule-hover-bloom"), "Windows hover bloom must stay on the rounded edge");

// Compact content is centered as a group; task light is biased outside the
// lower edge; weather tint never passes through a dark intermediate color.
includes(css, ".capsule:not(.information-enabled) { justify-content: center; }", "Windows compact content centering");
includes(css, "--activity-y: 102%;", "Windows outward activity light");
includes(css, "drop-shadow(0 2.5px 2.5px", "Windows outward activity shadow");
assert(!css.includes("var(--weather-end) 82%"), "Windows weather fade reintroduced a dark seam");

process.stdout.write("macOS/Windows capsule parity contract: PASS\n");
