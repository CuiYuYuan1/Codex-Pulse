"use strict";

const assert = require("assert");
const dock = require("../src/renderer/dock-interaction");

assert.strictEqual(dock.DETACH_DISTANCE, 18);
assert.strictEqual(dock.dragAxis("bottom", 1, 8), "detach");
assert.strictEqual(dock.dragAxis("bottom", 1, -12), "detach");
assert.strictEqual(dock.dragAxis("top", 1, -8), "detach");
assert.strictEqual(dock.dragAxis("top", 1, 8), "detach");
assert.strictEqual(dock.dragAxis("left", -8, 1), "detach");
assert.strictEqual(dock.dragAxis("left", 8, 1), "detach");
assert.strictEqual(dock.dragAxis("right", 8, 1), "detach");
assert.strictEqual(dock.dragAxis("right", -12, 1), "detach");
assert.strictEqual(dock.dragAxis("bottom", 12, 1), "reorder");
assert.strictEqual(dock.dragAxis("left", 1, 12), "reorder");
assert.strictEqual(dock.detachProgress("bottom", 0, 17), 17 / 18);
assert.strictEqual(dock.detachProgress("bottom", 0, 18), 1);
assert.strictEqual(dock.detachProgress("bottom", 0, 40), 1);
assert.strictEqual(dock.detachProgress("bottom", 0, -40), 1);
assert.strictEqual(dock.detachDirection("bottom", 0, 12), 1);
assert.strictEqual(dock.detachDirection("bottom", 0, -12), -1);
assert.strictEqual(dock.detachDirection("left", -12, 0), 1);
assert.strictEqual(dock.detachDirection("left", 12, 0), -1);
assert.deepStrictEqual(dock.detachmentOffset("bottom", -1, 4), { x: 0, y: -4 });
assert.deepStrictEqual(dock.detachmentOffset("top", -1, 4), { x: 0, y: 4 });
assert.deepStrictEqual(dock.detachmentOffset("left", -1, 4), { x: 4, y: 0 });
assert.deepStrictEqual(dock.detachmentOffset("right", -1, 4), { x: -4, y: 0 });

console.log("Codex dock interactions: PASS");
