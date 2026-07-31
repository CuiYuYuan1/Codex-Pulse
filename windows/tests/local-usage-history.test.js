const assert = require("assert");
const fs = require("fs");
const Module = require("module");
const path = require("path");
const vm = require("vm");

function loadUsageFunctions() {
  const mainPath = path.join(__dirname, "..", "src", "main.js");
  const mainRequire = Module.createRequire(mainPath);
  const source = fs.readFileSync(mainPath, "utf8");
  const lifecycle = source.indexOf("app.whenReady().then(");
  assert(lifecycle > 0, "main lifecycle marker is missing");
  const testExports = `
    module.exports = {
      dayKey,
      calculateLocalUsageStreak,
      mergeLocalDailyUsage,
      mergeLocalTodayUsage,
      mergeLocalTotalUsage,
      mergeLocalSessionFallback,
      deviceLocalUsageSnapshot,
      millisecondsUntilNextLocalDay,
      parseSessionDailyTokenText,
      parseSessionTodayTokenText,
      parseSessionAllTimeTokenText,
      estimatedAPICost,
      tokenPriceForModel,
      estimateTextTokens,
      unionShapeBounds,
      clampWindowPositionToVisibleShape,
      shouldPromoteLocalDailyUsage,
      shouldPromoteLocalTodayUsage,
      normalizedVersion,
      isVersionNewer,
      preferredWindowsReleaseAsset,
      preferredWindowsReleaseURL,
      normalizedSHA256Digest,
      isPathInsideDirectory,
      safeReleaseURL,
      mediaSourceIdForWindowHandle,
      setAccount(auth, email = null) { state.account = { auth, email }; },
      setProvider(modelProvider) { state.modelProvider = modelProvider; }
    };
  `;
  const electron = {
    app: { getPath: () => process.cwd(), isPackaged: false },
    BrowserWindow: function BrowserWindow() {},
    Tray: function Tray() {},
    Menu: { buildFromTemplate: () => ({}) },
    ipcMain: { handle: () => {}, on: () => {} },
    dialog: {},
    nativeImage: {},
    screen: {},
    shell: {}
  };
  const originalLoad = Module._load;
  Module._load = (request, parent, isMain) => request === "electron"
    ? electron
    : originalLoad(request, parent, isMain);
  try {
    const context = {
      module: { exports: {} },
      exports: {},
      require: mainRequire,
      __dirname: path.dirname(mainPath),
      process,
      Buffer,
      URL,
      URLSearchParams,
      AbortController,
      setTimeout,
      clearTimeout,
      setInterval,
      clearInterval,
      console
    };
    vm.runInNewContext(source.slice(0, lifecycle) + testExports, context, { filename: mainPath });
    return context.module.exports;
  } finally {
    Module._load = originalLoad;
  }
}

function localTime(year, month, day, hour = 0, minute = 0, second = 0) {
  return new Date(year, month - 1, day, hour, minute, second, 0);
}

function tokenEvent(date, tokens, lastTokens = null, components = null) {
  const info = { total_token_usage: { total_tokens: tokens } };
  if (lastTokens !== null) {
    info.last_token_usage = {
      total_tokens: lastTokens,
      ...(components ? {
        input_tokens: components.input,
        cached_input_tokens: components.cached,
        output_tokens: components.output
      } : {})
    };
  }
  return JSON.stringify({
    timestamp: date.toISOString(),
    type: "event_msg",
    payload: {
      type: "token_count",
      info
    }
  });
}

function turnContext(date, model) {
  return JSON.stringify({
    timestamp: date.toISOString(),
    type: "turn_context",
    payload: { model }
  });
}

function subagentSessionMeta(date, id = "child-session") {
  return JSON.stringify({
    timestamp: date.toISOString(),
    type: "session_meta",
    payload: {
      id,
      source: {
        subagent: {
          thread_spawn: {
            parent_thread_id: "parent-session",
            depth: 1
          }
        }
      }
    }
  });
}

const usage = loadUsageFunctions();
const streak = usage.calculateLocalUsageStreak(
  new Set([
    usage.dayKey(localTime(2026, 7, 2)),
    usage.dayKey(localTime(2026, 7, 3)),
    usage.dayKey(localTime(2026, 7, 8)),
    usage.dayKey(localTime(2026, 7, 9)),
    usage.dayKey(localTime(2026, 7, 10)),
    usage.dayKey(localTime(2026, 7, 11)),
    usage.dayKey(localTime(2026, 7, 12)),
    usage.dayKey(localTime(2026, 7, 13)),
    usage.dayKey(localTime(2026, 7, 14))
  ]),
  localTime(2026, 7, 14, 12)
);
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(streak)),
  { currentDays: 7, longestDays: 7 },
  "device streak must use all local session days rather than the seven-day chart window"
);
const beforeFirstUseToday = usage.calculateLocalUsageStreak(
  new Set([
    usage.dayKey(localTime(2026, 7, 12)),
    usage.dayKey(localTime(2026, 7, 13))
  ]),
  localTime(2026, 7, 14, 0, 1)
);
assert.strictEqual(
  beforeFirstUseToday.currentDays,
  2,
  "the local streak should remain visible after midnight until today's first session"
);
assert.strictEqual(usage.normalizedVersion("v0.1.24"), "0.1.24");
assert.strictEqual(usage.isVersionNewer("0.1.24", "0.1.23"), true);
assert.strictEqual(usage.isVersionNewer("0.1.23", "0.1.23"), false);
assert.strictEqual(usage.isVersionNewer("0.1.23-beta.1", "0.1.23"), false);
assert.strictEqual(
  usage.preferredWindowsReleaseURL([
    { name: "CodexPulse-Windows-Portable-0.1.24.exe", browser_download_url: "https://github.com/CuiYuYuan1/Codex-Pulse/releases/download/v0.1.24/portable.exe" },
    { name: "CodexPulse-Windows-Setup-0.1.24-x64.exe", browser_download_url: "https://github.com/CuiYuYuan1/Codex-Pulse/releases/download/v0.1.24/setup.exe" }
  ]),
  "https://github.com/CuiYuYuan1/Codex-Pulse/releases/download/v0.1.24/setup.exe"
);
assert.strictEqual(usage.safeReleaseURL("https://evil.example/update.exe"), null);
assert(usage.safeReleaseURL("https://github.com/CuiYuYuan1/Codex-Pulse/releases/download/v0.1.24/setup.exe"));
assert.strictEqual(usage.normalizedSHA256Digest(`sha256:${"A".repeat(64)}`), "a".repeat(64));
assert.strictEqual(usage.normalizedSHA256Digest("not-a-digest"), null);
assert.strictEqual(usage.isPathInsideDirectory("/tmp/codexpulse/update.exe", "/tmp/codexpulse"), true);
assert.strictEqual(usage.isPathInsideDirectory("/tmp/escaped.exe", "/tmp/codexpulse"), false);
assert.strictEqual(
  usage.mediaSourceIdForWindowHandle("4660"),
  "window:4660:0",
  "Windows HWND must map to Electron's relative z-order source id without precision loss"
);
const start = localTime(2026, 7, 12);
const end = localTime(2026, 7, 15);
const fixture = [
  tokenEvent(localTime(2026, 7, 11, 23), 100),
  tokenEvent(localTime(2026, 7, 12, 9), 160),
  tokenEvent(localTime(2026, 7, 12, 10), 160),
  "not json",
  tokenEvent(localTime(2026, 7, 12, 18), 220),
  tokenEvent(localTime(2026, 7, 13, 10), 300),
  tokenEvent(localTime(2026, 7, 13, 12), 40),
  tokenEvent(localTime(2026, 7, 14, 11), 90),
  tokenEvent(localTime(2026, 7, 15, 1), 999)
].join("\n");

const parsed = usage.parseSessionDailyTokenText(fixture, start.getTime(), end.getTime());
assert(parsed && typeof parsed.get === "function", "daily parser should return a Map-like result");
assert.strictEqual(parsed.get(usage.dayKey(localTime(2026, 7, 12))), 120);
assert.strictEqual(parsed.get(usage.dayKey(localTime(2026, 7, 13))), 120);
assert.strictEqual(parsed.get(usage.dayKey(localTime(2026, 7, 14))), 50);
assert.strictEqual(parsed.has(usage.dayKey(localTime(2026, 7, 15))), false, "end is exclusive");
assert.strictEqual(
  usage.parseSessionTodayTokenText(fixture, localTime(2026, 7, 14).getTime(), end.getTime()),
  50,
  "today parser should subtract the latest pre-day counter"
);
assert.strictEqual(parsed.estimated, false, "native token_count must remain exact");
const allTime = usage.parseSessionAllTimeTokenText([
  tokenEvent(localTime(2026, 7, 12, 9), 100),
  tokenEvent(localTime(2026, 7, 12, 10), 160),
  tokenEvent(localTime(2026, 7, 13, 9), 10),
  tokenEvent(localTime(2026, 7, 13, 10), 40)
].join("\n"));
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(allTime)),
  { tokens: 200, estimated: false },
  "lifetime parser must sum positive deltas and restart after counter resets"
);
const interleavedFixture = [
  tokenEvent(localTime(2026, 7, 14, 9), 100, 100),
  tokenEvent(localTime(2026, 7, 14, 10), 160, 60),
  tokenEvent(localTime(2026, 7, 14, 11), 20, 20),
  tokenEvent(localTime(2026, 7, 14, 12), 220, 60),
  tokenEvent(localTime(2026, 7, 14, 12), 220, 60)
].join("\n");
const interleavedDaily = usage.parseSessionDailyTokenText(
  interleavedFixture,
  localTime(2026, 7, 14).getTime(),
  end.getTime()
);
assert.strictEqual(
  interleavedDaily.get(usage.dayKey(localTime(2026, 7, 14))),
  240,
  "interleaved cumulative streams must use per-event last usage and ignore duplicates"
);
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(usage.parseSessionAllTimeTokenText(interleavedFixture))),
  { tokens: 240, estimated: false },
  "lifetime aggregation must not count cumulative stream switches as Token usage"
);

const cacheFixture = [
  turnContext(localTime(2026, 7, 14, 8, 59), "gpt-5.6-terra"),
  tokenEvent(
    localTime(2026, 7, 14, 9),
    110_000,
    110_000,
    { input: 100_000, cached: 80_000, output: 10_000 }
  )
].join("\n");
const cacheDaily = usage.parseSessionDailyTokenText(
  cacheFixture,
  localTime(2026, 7, 14).getTime(),
  end.getTime()
);
assert.strictEqual(cacheDaily.breakdown.inputTokens, 100_000);
assert.strictEqual(cacheDaily.breakdown.cachedInputTokens, 80_000);
assert.strictEqual(cacheDaily.breakdown.outputTokens, 10_000);
assert(Math.abs(cacheDaily.breakdown.estimatedCostUSD - 0.22) < 0.000001);
assert(Math.abs(cacheDaily.breakdown.uncachedInputCostUSD - 0.05) < 0.000001);
assert(Math.abs(cacheDaily.breakdown.cachedInputCostUSD - 0.02) < 0.000001);
assert(Math.abs(cacheDaily.breakdown.outputCostUSD - 0.15) < 0.000001);
const cacheLifetime = usage.parseSessionAllTimeTokenText(cacheFixture);
assert.strictEqual(cacheLifetime.tokens, 110_000);
assert(
  Math.abs(cacheLifetime.estimatedCostUSD - 0.22) < 0.000001,
  "lifetime parser must accumulate model-aware API-equivalent cost"
);

const replayStart = localTime(2026, 7, 14, 14);
const replayedSubagentFixture = [
  subagentSessionMeta(replayStart),
  ...Array.from({ length: 8 }, (_, index) => tokenEvent(
    new Date(replayStart.getTime() + index + 1),
    (index + 1) * 100,
    100
  )),
  tokenEvent(new Date(replayStart.getTime() + 10_000), 900, 100)
].join("\n");
const replayedSubagentDaily = usage.parseSessionDailyTokenText(
  replayedSubagentFixture,
  localTime(2026, 7, 14).getTime(),
  end.getTime()
);
assert.strictEqual(
  replayedSubagentDaily.get(usage.dayKey(replayStart)),
  100,
  "forked subagent history replay must not be counted again as today's usage"
);
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(usage.parseSessionAllTimeTokenText(replayedSubagentFixture))),
  { tokens: 100, estimated: false },
  "forked subagent history replay must not inflate lifetime usage"
);

const quickSubagentFixture = [
  subagentSessionMeta(replayStart, "quick-child-session"),
  tokenEvent(new Date(replayStart.getTime() + 100), 100, 100),
  tokenEvent(new Date(replayStart.getTime() + 200), 200, 100)
].join("\n");
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(usage.parseSessionAllTimeTokenText(quickSubagentFixture))),
  { tokens: 200, estimated: false },
  "a normal fast subagent response must not be mistaken for inherited replay"
);

const providerUsageFixture = [
  JSON.stringify({
    timestamp: localTime(2026, 7, 14, 9).toISOString(),
    type: "response_item",
    payload: {
      type: "message",
      role: "assistant",
      content: [{ type: "output_text", text: "done" }],
      usage: { prompt_tokens: 120, completion_tokens: 30 }
    }
  }),
  JSON.stringify({
    timestamp: localTime(2026, 7, 14, 10).toISOString(),
    type: "response_item",
    payload: {
      type: "message",
      role: "assistant",
      content: [{ type: "output_text", text: "done again" }],
      usage: { inputTokens: 200, outputTokens: 50 }
    }
  })
].join("\n");
const providerUsage = usage.parseSessionDailyTokenText(
  providerUsageFixture,
  localTime(2026, 7, 14).getTime(),
  end.getTime()
);
assert.strictEqual(providerUsage.get(usage.dayKey(localTime(2026, 7, 14))), 400);
assert.strictEqual(providerUsage.estimated, false, "provider-reported usage must remain exact");

const deepSeekWithoutUsageFixture = [
  tokenEvent(localTime(2026, 7, 14, 8), 0),
  JSON.stringify({
    timestamp: localTime(2026, 7, 14, 9).toISOString(),
    type: "response_item",
    payload: {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: "请帮我设计一个本地知识库" }]
    }
  }),
  JSON.stringify({
    timestamp: localTime(2026, 7, 14, 9, 1).toISOString(),
    type: "response_item",
    payload: {
      type: "message",
      role: "assistant",
      content: [{ type: "output_text", text: "可以，先从 Markdown 文件和向量搜索开始。" }]
    }
  })
].join("\n");
const deepSeekEstimated = usage.parseSessionDailyTokenText(
  deepSeekWithoutUsageFixture,
  localTime(2026, 7, 14).getTime(),
  end.getTime()
);
assert(deepSeekEstimated.get(usage.dayKey(localTime(2026, 7, 14))) > 0, "custom provider without usage must not stay at zero");
assert.strictEqual(deepSeekEstimated.estimated, true, "fallback must be explicitly marked as estimated");
assert(usage.estimateTextTokens("中文 and English") > 0);

const legacyDeepSeekFixture = JSON.stringify({
  timestamp: localTime(2026, 7, 14, 11).toISOString(),
  type: "event_msg",
  payload: { type: "agent_message", message: "这是旧版会话事件，也必须能够估算 Token。" }
});
const legacyDeepSeekEstimated = usage.parseSessionDailyTokenText(
  legacyDeepSeekFixture,
  localTime(2026, 7, 14).getTime(),
  end.getTime()
);
assert(legacyDeepSeekEstimated.get(usage.dayKey(localTime(2026, 7, 14))) > 0);
assert.strictEqual(legacyDeepSeekEstimated.estimated, true);

const localDaily = [
  { date: usage.dayKey(localTime(2026, 7, 12)), tokens: 120 },
  { date: usage.dayKey(localTime(2026, 7, 13)), tokens: 120 },
  { date: usage.dayKey(localTime(2026, 7, 14)), tokens: 50 }
];
const remote = {
  today: 20,
  total: 999,
  daily: [
    { date: usage.dayKey(localTime(2026, 7, 12)), tokens: 150 },
    { date: usage.dayKey(localTime(2026, 7, 13)), tokens: 0 },
    { date: usage.dayKey(localTime(2026, 7, 14)), tokens: 10 }
  ]
};
const merged = usage.mergeLocalDailyUsage(remote, localDaily, localTime(2026, 7, 14, 12));
const mergedByDate = new Map(merged.daily.map((bucket) => [bucket.date, bucket.tokens]));
assert.strictEqual(mergedByDate.get(usage.dayKey(localTime(2026, 7, 12))), 120, "device bucket must replace account history");
assert.strictEqual(mergedByDate.get(usage.dayKey(localTime(2026, 7, 13))), 120);
assert.strictEqual(mergedByDate.get(usage.dayKey(localTime(2026, 7, 14))), 50);
assert.strictEqual(merged.today, 50);
assert.strictEqual(merged.total, 999, "local 7-day total must not overwrite lifetime total");
assert.strictEqual(merged.localSevenDayTokens, 290);
const mergedTotal = usage.mergeLocalTotalUsage(merged, {
  tokens: 12_345,
  estimated: false,
  estimatedCostUSD: 286.42,
  streakDays: 7,
  longestStreakDays: 12
});
assert.strictEqual(mergedTotal.total, 12_345, "all local sessions must replace the account lifetime summary");
assert.strictEqual(mergedTotal.localTotal, 12_345);
assert.strictEqual(mergedTotal.localTotalEstimatedCostUSD, 286.42);
assert.strictEqual(mergedTotal.streakDays, 7, "the displayed streak must come from local sessions");
assert.strictEqual(mergedTotal.localLongestStreakDays, 12);

const correctedInflatedToday = usage.mergeLocalTodayUsage(
  {
    today: 2_400_000_000,
    localToday: 2_400_000_000,
    daily: [{ date: usage.dayKey(localTime(2026, 7, 14)), tokens: 2_400_000_000 }]
  },
  { tokens: 210_000_000, estimated: false },
  localTime(2026, 7, 14, 12)
);
assert.strictEqual(
  correctedInflatedToday.today,
  210_000_000,
  "an authoritative rescan must be able to correct an inflated persisted today value"
);
const correctedInflatedTotal = usage.mergeLocalTotalUsage(
  { total: 24_000_000_000, localTotal: 24_000_000_000 },
  { tokens: 7_500_000_000, estimated: false }
);
assert.strictEqual(
  correctedInflatedTotal.total,
  7_500_000_000,
  "an authoritative rescan must be able to correct an inflated persisted lifetime value"
);

const newDay = localTime(2026, 7, 15, 0, 0);
const stalePreviousDay = {
  today: 999,
  daily: [{ date: usage.dayKey(localTime(2026, 7, 14)), tokens: 999 }]
};
const crossedDayToday = usage.mergeLocalTodayUsage(
  stalePreviousDay,
  { tokens: 12, estimated: false },
  newDay
);
assert.strictEqual(crossedDayToday.today, 12, "yesterday's remote today value must not return after midnight");
assert.strictEqual(
  crossedDayToday.daily[crossedDayToday.daily.length - 1].tokens,
  12,
  "the new local-day bucket must be authoritative"
);
const crossedDayDaily = usage.mergeLocalDailyUsage(
  stalePreviousDay,
  [{ date: usage.dayKey(newDay), tokens: 8 }],
  newDay
);
assert.strictEqual(crossedDayDaily.today, 8, "daily merge must ignore an undated stale today summary");
const boundaryDelay = usage.millisecondsUntilNextLocalDay(localTime(2026, 7, 14, 23, 59, 59));
assert(boundaryDelay >= 1_000 && boundaryDelay <= 1_500, "midnight timer must target the next local day");
assert.strictEqual(merged.localDailyAvailable, true);

const remoteFailureDate = localTime(2026, 7, 14, 12);
usage.setAccount("ChatGPT", "account@example.com");
const remoteFailureFallback = usage.mergeLocalSessionFallback(
  { today: 0, total: 0, daily: [] },
  { tokens: 4321, estimated: false },
  [{ date: usage.dayKey(remoteFailureDate), tokens: 4321, estimated: false }],
  { tokens: 98_765, estimated: false },
  remoteFailureDate
);
assert.strictEqual(remoteFailureFallback.today, 4321, "ChatGPT must use the device-wide today value");
assert.strictEqual(remoteFailureFallback.localToday, 4321);
assert.strictEqual(remoteFailureFallback.total, 98_765, "ChatGPT must use the device-wide lifetime value");
assert.strictEqual(remoteFailureFallback.localSessionFallback, true, "remote failure must mark local fallback source");
assert(
  remoteFailureFallback.sourceNote.includes("所有账号"),
  "the source note must explain the cross-account device scope"
);

usage.setAccount("API Key");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true);
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), true);
const apiFailureFallback = usage.mergeLocalSessionFallback(
  { today: 0, total: 0, daily: [] },
  { tokens: 4321, estimated: false },
  [{ date: usage.dayKey(remoteFailureDate), tokens: 4321, estimated: false }],
  { tokens: 98_765, estimated: false },
  remoteFailureDate
);
assert.strictEqual(apiFailureFallback.today, 4321, "API Key fallback must promote local session usage");
usage.setAccount("ChatGPT", "first@example.com");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true);
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), true, "ChatGPT history must use device sessions");
const beforeSwitch = usage.deviceLocalUsageSnapshot(remoteFailureFallback, remoteFailureDate);
usage.setAccount("ChatGPT", "second@example.com");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true);
assert.strictEqual(beforeSwitch.today, 4321, "account switch must preserve device-wide today");
assert.strictEqual(beforeSwitch.total, 98_765, "account switch must preserve device-wide lifetime");
usage.setProvider("deepseek");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true, "custom providers must enable local today usage");
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), true, "custom providers must enable local history even with ChatGPT login");
usage.setProvider("openai");
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), true, "native OpenAI ChatGPT history remains device-scoped");

const visibleShape = usage.unionShapeBounds([
  { x: 72, y: 6, width: 246, height: 86 },
  { x: 118, y: 88, width: 154, height: 38 }
]);
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(visibleShape)),
  { x: 72, y: 6, width: 246, height: 120 },
  "shape union should represent only visible/interactive content"
);
const draggedToBottom = usage.clampWindowPositionToVisibleShape(
  9999,
  9999,
  { x: 0, y: 0, width: 1920, height: 1040 },
  { width: 390, height: 790 },
  visibleShape
);
assert.strictEqual(draggedToBottom.x, 1602, "visible capsule right edge should reach the work-area edge");
assert.strictEqual(draggedToBottom.y, 914, "visible information strip bottom should reach the work-area edge");

console.log("local usage history fixtures: PASS");
