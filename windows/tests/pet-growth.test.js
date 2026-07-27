const assert = require("assert");
const {
  scaleForTodayTokens
} = require("../src/renderer/pet-growth.js");

assert.strictEqual(scaleForTodayTokens(undefined), 1);
assert.strictEqual(scaleForTodayTokens(0), 1);
assert.strictEqual(scaleForTodayTokens(-1), 1);
assert.strictEqual(scaleForTodayTokens(9_999_999), 1);
assert.strictEqual(scaleForTodayTokens(10_000_000), 1.1);
assert.strictEqual(scaleForTodayTokens(100_000_000), 2);
assert.strictEqual(scaleForTodayTokens(145_000_000), 2.4);
assert.strictEqual(scaleForTodayTokens(899_999_999), 9.9);
assert.strictEqual(scaleForTodayTokens(900_000_000), 10);
assert.strictEqual(scaleForTodayTokens(9_000_000_000), 10);

// The next day's zero-valued today bucket always restores the original size.
assert.strictEqual(scaleForTodayTokens(0), 1);

console.log("pet growth thresholds: PASS");
