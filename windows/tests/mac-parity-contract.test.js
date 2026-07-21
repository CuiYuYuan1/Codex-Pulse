const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const swift = fs.readFileSync(
  path.join(root, "CodexPulse/Views/Capsule/FloatingCapsuleView.swift"),
  "utf8"
);
const css = fs.readFileSync(path.join(root, "windows/src/renderer/styles.css"), "utf8");
const renderer = fs.readFileSync(path.join(root, "windows/src/renderer/renderer.js"), "utf8");
const html = fs.readFileSync(path.join(root, "windows/src/renderer/index.html"), "utf8");
const main = fs.readFileSync(path.join(root, "windows/src/main.js"), "utf8");
const pulseStore = fs.readFileSync(path.join(root, "Shared/Services/PulseStore.swift"), "utf8");
const formatters = fs.readFileSync(path.join(root, "Shared/Utilities/Formatters.swift"), "utf8");
const appServerClient = fs.readFileSync(path.join(root, "Shared/Services/StdioCodexAppServerClient.swift"), "utf8");
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
includes(swift, ".frame(width: 1, height: 22)", "macOS divider");
includes(css, ".divider { width: 1px; height: 22px;", "Windows divider");

// Mini mode contract: 68px visual inside a 10px safe area, 49px value width.
includes(swift, ".frame(width: 68, height: 68)", "macOS mini diameter");
includes(swift, ".padding(10)", "macOS mini safe area");
includes(css, "html.mini-mode .stage { padding: 10px; }", "Windows mini safe area");
includes(css, "width: 49px;", "Windows mini value width");
includes(swift, ".frame(width: 49)", "macOS mini value width");

// Magnetic motion and click timing contract.
includes(swift, "magneticOffset = CGSize(width: normalizedX * 12, height: normalizedY * 8)", "macOS magnet travel");
includes(renderer, "magnet.targetX = normalizedX * 12;", "Windows horizontal magnet travel");
includes(renderer, "magnet.targetY = normalizedY * 8;", "Windows vertical magnet travel");
includes(renderer, "function criticallyDampedStep", "Windows time-based magnetic return");
includes(renderer, "deltaSeconds / 0.055", "Windows refresh-rate independent magnetic follow");
includes(renderer, "Math.round(magnet.x * scale) / scale", "Windows physical-pixel magnetic alignment");
includes(renderer, "elements.capsule.style.transform = `translate3d(${magnet.renderX}px", "Windows rigid-body magnetic motion");
includes(renderer, "rect.left - magnet.renderX", "Windows stable pointer mapping during magnetic motion");
includes(main, "if (signature === windowShapeSignature) return true;", "Windows native shape deduplication");
includes(main, "windowRef.setShape(fullTargetShape);", "Windows atomic mini/full native shape reset");
includes(main, "const limitsInterval = active ? 3_000 : 8_000;", "Windows live quota refresh cadence");
includes(main, "const usageInterval = active ? 5_000 : 12_000;", "Windows live usage refresh cadence");
includes(pulseStore, "private let activePollingInterval: TimeInterval = 5", "macOS live quota polling cadence");
includes(pulseStore, "try await Task.sleep(nanoseconds: 120_000_000)", "macOS local token debounce");
includes(pulseStore, "for delay in [0.75, 2.5]", "macOS post-turn profile refresh");
includes(appServerClient, "private let rateLimitsCacheTTL: TimeInterval = 4", "macOS quota cache cadence");
includes(appServerClient, "private let usageCacheTTL: TimeInterval = 10", "macOS usage cache cadence");
includes(formatters, 'return "刚刚"', "macOS immediate sync wording");
includes(updateService, "releases/latest", "macOS GitHub latest release check");
includes(updateService, 'hasSuffix(".dmg")', "macOS DMG release selection");
includes(main, "GITHUB_LATEST_RELEASE_API", "Windows GitHub latest release check");
includes(main, "preferredWindowsReleaseURL", "Windows installer release selection");
includes(releaseWorkflow, "permissions:\n  contents: write", "GitHub release write permission");
assert(!css.includes("translate3d(0, -4px, 0) scale(.96)"), "Windows details must not scale glyphs during reveal");
includes(renderer, "}, 300);", "Windows single-click delay");
includes(renderer, "duration: 155", "Windows rigid outgoing mini transition phase");
includes(renderer, "duration: 185", "Windows rigid incoming mini transition phase");
includes(renderer, "runCapsuleMorphTransition", "Windows rigid mini/full transition");
includes(renderer, "scale(.72)", "Windows mini/full transition matches macOS scale ratio");
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
