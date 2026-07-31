"use strict";

const assert = require("assert");
const {
  attachedDockShape,
  detachedWindowBounds,
  fullscreenTopDockFrame,
  isFullscreenWindowBounds,
  mediaSourceIdForWindowHandle,
  normalizeTrackedWindowBounds,
  visibleWindowBounds,
  rectangleDistance
} = require("../src/codex-dock-geometry");

assert.deepStrictEqual(
  attachedDockShape(900, 60, "bottom", 16),
  { x: 0, y: 16, width: 900, height: 44 },
  "bottom dock must draw and receive input only below the Codex seam"
);

assert.deepStrictEqual(
  attachedDockShape(900, 60, "top", 16),
  { x: 0, y: 0, width: 900, height: 44 },
  "top dock must exclude the native overlap strip"
);

assert.strictEqual(
  isFullscreenWindowBounds(
    { x: 0, y: 0, width: 1920, height: 1080 },
    { x: 0, y: 0, width: 1920, height: 1080 }
  ),
  true,
  "a display-filling Codex window must enter the dedicated full-screen dock mode"
);

assert.strictEqual(
  isFullscreenWindowBounds(
    { x: 120, y: 80, width: 1500, height: 900 },
    { x: 0, y: 0, width: 1920, height: 1080 }
  ),
  false,
  "ordinary maximized or floating Codex windows must keep their chosen dock edge"
);

assert.deepStrictEqual(
  fullscreenTopDockFrame(
    { x: 0, y: 0, width: 1920, height: 1080 }
  ),
  { x: 519, y: 24, width: 883, height: 60 },
  "full-screen dock must be centered below the title bar at the approved 46% ratio"
);

assert.deepStrictEqual(
  fullscreenTopDockFrame(
    { x: 50, y: 20, width: 1366, height: 768 }
  ),
  { x: 419, y: 44, width: 628, height: 60 },
  "full-screen dock width must adapt proportionally to the Codex window"
);

assert.deepStrictEqual(
  attachedDockShape(70, 720, "left", 16),
  { x: 0, y: 0, width: 54, height: 720 },
  "left dock must end at the Codex seam"
);

assert.deepStrictEqual(
  attachedDockShape(70, 720, "right", 16),
  { x: 16, y: 0, width: 54, height: 720 },
  "right dock must start outside the Codex seam"
);

const scaledScreen = {
  screenToDipPoint(point) {
    return { x: point.x / 1.5, y: point.y / 1.5 };
  }
};

assert.deepStrictEqual(
  normalizeTrackedWindowBounds({
    left: 150,
    top: 90,
    right: 1650,
    bottom: 990,
    physical: true
  }, scaledScreen),
  { x: 100, y: 60, width: 1000, height: 600 },
  "DWM physical pixels must be converted to Electron DIP coordinates"
);

assert.deepStrictEqual(
  normalizeTrackedWindowBounds({
    left: 100,
    top: 60,
    right: 1100,
    bottom: 660,
    physical: false
  }, scaledScreen),
  { x: 100, y: 60, width: 1000, height: 600 },
  "GetWindowRect logical coordinates must not be scaled twice"
);

assert.strictEqual(
  normalizeTrackedWindowBounds({
    left: 100,
    top: 60,
    right: 400,
    bottom: 260,
    physical: true
  }, { screenToDipPoint: (point) => point }),
  null,
  "utility windows that are too small must not be treated as Codex"
);

assert.deepStrictEqual(
  visibleWindowBounds(
    { x: 300, y: 200, width: 390, height: 810 },
    { x: 53, y: 6, width: 283, height: 96 },
    true
  ),
  { x: 353, y: 206, width: 283, height: 96 },
  "dock proximity must use the visible capsule shape, not the transparent 390x810 surface"
);

assert.strictEqual(
  rectangleDistance(
    { x: 353, y: 206, width: 283, height: 96 },
    { x: 350, y: 330, width: 900, height: 60 }
  ),
  28,
  "visible capsule reaches the 30px dock preview threshold"
);

assert.strictEqual(
  mediaSourceIdForWindowHandle("123456789"),
  "window:123456789:0",
  "the tracked Codex HWND must map to Electron's external-window media source id"
);

assert.strictEqual(
  mediaSourceIdForWindowHandle("0"),
  null,
  "an empty native window handle must never become a z-order target"
);

assert.deepStrictEqual(
  detachedWindowBounds(
    { x: 40, y: 500 },
    { x: 0, y: 0, width: 390, height: 810 },
    { x: 53, y: 6, width: 283, height: 96 }
  ),
  { x: -154, y: 446, width: 390, height: 810 },
  "side detachment must center the visible capsule under the pointer, not the transparent surface"
);

console.log("Codex dock geometry: PASS");
