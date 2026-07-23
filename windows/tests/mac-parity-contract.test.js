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
const capsuleController = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/FloatingCapsuleController.swift"),
  "utf8"
);
const settingsStore = fs.readFileSync(path.join(root, "Shared/Storage/SettingsStore.swift"), "utf8");
const css = fs.readFileSync(path.join(root, "windows/src/renderer/styles.css"), "utf8");
const renderer = fs.readFileSync(path.join(root, "windows/src/renderer/renderer.js"), "utf8");
const html = fs.readFileSync(path.join(root, "windows/src/renderer/index.html"), "utf8");
const main = fs.readFileSync(path.join(root, "windows/src/main.js"), "utf8");
const pulseStore = fs.readFileSync(path.join(root, "Shared/Services/PulseStore.swift"), "utf8");
const formatters = fs.readFileSync(path.join(root, "Shared/Utilities/Formatters.swift"), "utf8");
const appServerClient = fs.readFileSync(path.join(root, "Shared/Services/StdioCodexAppServerClient.swift"), "utf8");
const localUsageReader = fs.readFileSync(path.join(root, "Shared/Services/LocalCodexUsageReader.swift"), "utf8");
const artificialAnalysis = fs.readFileSync(path.join(root, "CodexPulse/Services/ArtificialAnalysisService.swift"), "utf8");
const updateService = fs.readFileSync(path.join(root, "CodexPulse/Services/AppUpdateService.swift"), "utf8");
const releaseWorkflow = fs
  .readFileSync(path.join(root, ".github/workflows/release.yml"), "utf8")
  .replace(/\r\n/g, "\n");

function includes(source, fragment, label) {
  assert(source.includes(fragment), `${label} drifted; missing ${JSON.stringify(fragment)}`);
}

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

// Rich pet mini mode: generated opaque sprites stay readable on every desktop;
// the programmatic monitor remains stable while the pet changes actions.
includes(swift, ".frame(width: 216, height: 129.6)", "macOS compact pet scene size");
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
includes(petSwift, '"codex_\\(character.rawValue)_v2_\\(animationState.richResourceSuffix)"', "macOS generated rich pet assets");
includes(petSwift, "case scratch", "macOS thinking pause action");
includes(swift, "(9...11).contains(phase) ? .scratch : .thinking", "macOS typing and head-scratch choreography");
includes(renderer, 'petState === "scratch" ? "想一下" : "思考中"', "Windows monitor-aware thinking choreography");
includes(capsuleController, "case .leftMouseDragged:", "macOS compact pet has native drag tracking");
includes(capsuleController, "clampedCompactOrigin", "macOS compact pet drag stays inside the visible desktop");
includes(css, '--pet-display-left: 126px;', "Windows dino terminal x");
includes(css, '.capsule[data-pet="cat"]', "Windows cat speech bubble");
includes(css, '.capsule[data-pet="bunny"]', "Windows bunny tag");
includes(css, '.capsule[data-pet="ghost"]', "Windows ghost bubble");
includes(css, '.capsule[data-pet="robot"]', "Windows robot HUD");
includes(main, "const MINI_SIZE = { width: 240, height: 154 };", "Windows compact native pet size");
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
includes(petSwift, "case authorization = \"auth\"", "macOS pet authorization mapping");
for (const pet of ["dino", "cat", "bunny", "ghost", "robot"]) {
  for (const action of ["idle", "typing", "scratch", "auth"]) {
    assert(fs.existsSync(path.join(root, `CodexPulse/Resources/PetsV2/codex_${pet}_v2_${action}.gif`)), `missing macOS rich ${pet}/${action}`);
    assert(fs.existsSync(path.join(root, `windows/src/renderer/assets/pets-v2/codex_${pet}_v2_${action}.gif`)), `missing Windows rich ${pet}/${action}`);
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
includes(pulseStore, "try await Task.sleep(nanoseconds: 120_000_000)", "macOS local token debounce");
includes(pulseStore, "for delay in [0.75, 2.5]", "macOS post-turn profile refresh");
includes(appServerClient, "private let rateLimitsCacheTTL: TimeInterval = 4", "macOS quota cache cadence");
includes(appServerClient, "private let usageCacheTTL: TimeInterval = 10", "macOS usage cache cadence");
includes(appServerClient, "promoteToDisplayedUsage: true", "macOS remote Token failure promotes local session usage");
includes(formatters, 'return "刚刚"', "macOS immediate sync wording");
includes(formatters, "static func liveTokens", "macOS live Token precision");
includes(formatters, 'return String(format: "%.1fM"', "macOS compact live Token precision");
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
includes(renderer, "function setMiniMonitorText(value, animated)", "Windows pet monitor upward page roll");
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
includes(css, "var(--conversation-origin-scale-x", "Windows conversation starts at the collapsed island width");
includes(renderer, "collapsedRect.width / 342", "Windows measures the collapsed information island before expansion");
includes(renderer, "elements.conversationDetail.getBoundingClientRect();", "Windows commits the collapsed morph frame before opening");
includes(css, "html.conversation-expanded .information-strip", "Windows information island header expansion");
includes(css, ".information-stream-dots", "Windows continuous processing feedback");
includes(css, "margin-top: -24px;", "Windows conversation grows from information strip");
includes(css, "html.mini-mode.mini-conversation-expanded .conversation-detail", "Windows pet-preserving conversation layout");
includes(appServerClient, "cachedCLIPath", "macOS cached CLI discovery");
includes(appServerClient, "proc.currentDirectoryURL = Self.safeCodexWorkingDirectory()", "macOS safe Codex working directory");
assert(!appServerClient.includes('["-lc", "command -v codex"]'), "macOS startup must not launch a login shell");
includes(artificialAnalysis, "private var cachedAPIKey: String?", "macOS one-time Keychain read");
includes(artificialAnalysis, "static func containsCredential() -> Bool", "macOS metadata-only startup Keychain check");
includes(artificialAnalysis, "guard let apiKey = loadAPIKeyIfNeeded()", "macOS lazy Keychain data access");
includes(updateService, "releases/latest", "macOS GitHub latest release check");
includes(updateService, 'hasSuffix(".dmg")', "macOS DMG release selection");
includes(main, "GITHUB_LATEST_RELEASE_API", "Windows GitHub latest release check");
includes(main, "preferredWindowsReleaseURL", "Windows installer release selection");
includes(main, "const UPDATE_CHECK_INTERVAL_MS = 5 * 60 * 1000", "Windows live update polling cadence");
includes(main, 'powerMonitor.on("resume"', "Windows wake update check");
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
