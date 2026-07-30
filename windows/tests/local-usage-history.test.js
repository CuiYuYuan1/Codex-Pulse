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
      mergeLocalDailyUsage,
      mergeLocalTodayUsage,
      mergeLocalSessionFallback,
      millisecondsUntilNextLocalDay,
      parseSessionDailyTokenText,
      parseSessionTodayTokenText,
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

function tokenEvent(date, tokens) {
  return JSON.stringify({
    timestamp: date.toISOString(),
    type: "event_msg",
    payload: {
      type: "token_count",
      info: { total_token_usage: { total_tokens: tokens } }
    }
  });
}

const usage = loadUsageFunctions();
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
assert.strictEqual(mergedByDate.get(usage.dayKey(localTime(2026, 7, 12))), 150, "remote bucket must not be double-counted");
assert.strictEqual(mergedByDate.get(usage.dayKey(localTime(2026, 7, 13))), 120);
assert.strictEqual(mergedByDate.get(usage.dayKey(localTime(2026, 7, 14))), 50);
assert.strictEqual(merged.today, 50);
assert.strictEqual(merged.total, 999, "local 7-day total must not overwrite lifetime total");
assert.strictEqual(merged.localSevenDayTokens, 290);

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
const remoteFailureFallback = usage.mergeLocalSessionFallback(
  { today: 0, total: 0, daily: [] },
  { tokens: 4321, estimated: false },
  [{ date: usage.dayKey(remoteFailureDate), tokens: 4321, estimated: false }],
  remoteFailureDate
);
assert.strictEqual(remoteFailureFallback.today, 4321, "remote failure must promote local session today usage");
assert.strictEqual(remoteFailureFallback.localSessionFallback, true, "remote failure must mark local fallback source");
assert(
  remoteFailureFallback.sourceNote.includes("本机 Codex session"),
  "remote failure must explain the local session source"
);

usage.setAccount("API Key");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true);
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), true);
usage.setAccount("ChatGPT", "first@example.com");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true);
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), false, "ChatGPT history must remain server-scoped");
usage.setAccount("ChatGPT", "second@example.com");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true, "account switch must keep device-wide today usage live");
usage.setProvider("deepseek");
assert.strictEqual(usage.shouldPromoteLocalTodayUsage(), true, "custom providers must enable local today usage");
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), true, "custom providers must enable local history even with ChatGPT login");
usage.setProvider("openai");
assert.strictEqual(usage.shouldPromoteLocalDailyUsage(), false, "native OpenAI ChatGPT history remains server-scoped");

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
