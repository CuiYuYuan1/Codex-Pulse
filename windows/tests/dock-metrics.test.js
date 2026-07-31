"use strict";

const assert = require("assert");
const dock = require("../src/renderer/dock-metrics");

assert.strictEqual(dock.formatTokens(37_901_000), "37.901M");
assert.strictEqual(dock.formatTokens(2_448_000_000), "2.448B");
assert.strictEqual(dock.formatTokens(12_448_000_000_000), "12.448T");
assert.strictEqual(dock.formatTokens(12_400), "12.400K");
assert.strictEqual(dock.formatTokens(null), "—");
assert.strictEqual(dock.cacheHitRate(1000, 825), 0.825);
assert.strictEqual(dock.cacheHitRate(0, 0), null);
assert.strictEqual(dock.formatPercentRatio(0.825), "82.5%");
assert.strictEqual(dock.formatUSD(12.3456), "$12.35");
assert.strictEqual(dock.formatUSD(0.0042), "$0.0042");

const clock = dock.dateTimeParts(
  { location: { timezone: "Asia/Shanghai" } },
  new Date("2026-07-30T07:29:42Z"),
  true
);
assert.strictEqual(clock.time, "15:29:42");
assert(clock.date.includes("2026"));

assert.deepStrictEqual(dock.changedGlyphIndices("15:29:41", "15:29:42"), [7]);
assert.strictEqual(dock.pointerResult(null), "activate");
assert.strictEqual(dock.pointerResult("reorder"), "reorder");
assert.strictEqual(dock.pointerResult("detach"), "detach");
assert.strictEqual(dock.pointerResult(null, true), "cancel");

console.log("dock metric formatting and interaction: PASS");
