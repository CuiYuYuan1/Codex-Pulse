"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { app, BrowserWindow, ipcMain } = require("electron");

const outputDirectory = path.resolve(__dirname, "../../output/windows-dock");

ipcMain.handle("visual:resize", () => ({ width: 1050, height: 60 }));
ipcMain.handle("visual:set-shape", () => true);

app.whenReady().then(async () => {
  fs.mkdirSync(outputDirectory, { recursive: true });
  const window = new BrowserWindow({
    width: 1050,
    height: 60,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    webPreferences: {
      preload: path.join(__dirname, "visual-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      additionalArguments: ["--fixture=actual"]
    }
  });

  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await new Promise((resolve) => setTimeout(resolve, 350));
  await window.webContents.executeJavaScript(`(() => {
    codexDockAttached = true;
    codexDockEdge = "bottom";
    document.documentElement.dataset.codexDockEdge = "bottom";
    document.documentElement.classList.add("codex-dock-attached");
    elements.codexDock.hidden = false;
    currentState = {
      ...currentState,
      limits: [{
        id: "codex:primary:10080",
        headline: true,
        role: "primary",
        name: "每周用量",
        windowDurationMins: 10080,
        remainingPercent: 4,
        usedPercent: 96,
        resetsAt: Date.now() / 1000 + 86400
      }],
      resetCards: Array.from({ length: 8 }, (_, index) => ({
        id: "card-" + index,
        title: "Full reset",
        available: true,
        expiresAt: Date.now() / 1000 + (index + 1) * 86400
      })),
      usage: {
        ...currentState.usage,
        today: 112345678,
        total: 2448123456,
        tokenVelocityPerMinute: 12400,
        localTodayInputTokens: 100000000,
        localTodayCachedInputTokens: 80000000,
        localTodayOutputTokens: 12345678,
        localTodayEstimatedCostUSD: 0.25518517,
        localTodayUncachedInputCostUSD: 0.05,
        localTodayCachedInputCostUSD: 0.02,
        localTodayOutputCostUSD: 0.18518517
      },
      task: {
        ...currentState.task,
        state: "working",
        activeCount: 3,
        model: "GPT-5.6 Sol",
        reasoningEffort: "max"
      },
      informationBar: {
        ...currentState.informationBar,
        weather: {
          ...currentState.informationBar.weather,
          apparentTemperature: 32,
          maximumTemperature: 31,
          minimumTemperature: 26,
          humidity: 82,
          windSpeed: 12,
          windUnit: "km/h"
        }
      }
    };
    render(currentState);
    return true;
  })()`, true);
  await new Promise((resolve) => setTimeout(resolve, 650));
  const normal = await window.webContents.executeJavaScript(`(() => {
    const dock = elements.codexDock.getBoundingClientRect();
    return {
      width: dock.width,
      height: dock.height,
      value: elements.codexDockTokens.textContent,
      order: [...elements.codexDock.querySelectorAll(".codex-dock-metric")]
        .map((item) => item.dataset.metric),
      trendTotal: elements.codexDockTrendTotal.textContent,
      trendLine: elements.codexDockTrendLine.getAttribute("points")
    };
  })()`, true);

  assert.strictEqual(normal.height, 60);
  assert.strictEqual(normal.value, "112.346M");
  assert.strictEqual(normal.order.at(-1), "trend");
  assert.strictEqual(normal.trendTotal, "737.320K");
  assert.strictEqual(normal.trendLine.split(" ").length, 7);
  fs.writeFileSync(
    path.join(outputDirectory, "normal.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`(() => {
    setCodexDockFocus("quota");
    return true;
  })()`, true);
  await new Promise((resolve) => setTimeout(resolve, 240));
  const focused = await window.webContents.executeJavaScript(`(() => {
    const focus = elements.codexDockFocus.getBoundingClientRect();
    const visiblePanel = elements.codexDockFocus.querySelector(
      '[data-focus-panel="quota"]'
    ).getBoundingClientRect();
    return {
      focusHeight: focus.height,
      panelHeight: visiblePanel.height,
      quota: elements.codexDockFocusQuota.textContent,
      tasks: elements.codexDockFocusTaskCount.textContent,
      page: elements.codexDockCardPage.textContent
    };
  })()`, true);

  assert.strictEqual(focused.focusHeight, 44);
  assert.strictEqual(focused.panelHeight, 44);
  assert.strictEqual(focused.quota, "4%");
  assert.strictEqual(focused.tasks, "● 3 个任务执行中");
  assert.strictEqual(focused.page, "1/8");
  fs.writeFileSync(
    path.join(outputDirectory, "quota-focus.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`setCodexDockFocus("tokens")`, true);
  await new Promise((resolve) => setTimeout(resolve, 240));
  const tokenFocus = await window.webContents.executeJavaScript(`(() => {
    const panel = elements.codexDockFocus.querySelector('[data-focus-panel="tokens"]');
    const cells = [...panel.querySelectorAll('.codex-dock-focus-cell')].map((cell) => {
      const rect = cell.getBoundingClientRect();
      return { left: rect.left, right: rect.right, width: rect.width };
    });
    return {
      cells,
      cacheHit: elements.codexDockTokenCacheHit.textContent,
      cost: elements.codexDockTokenCost.textContent,
      programmingIQ: elements.codexDockTokenProgrammingIQ.textContent,
      total: elements.codexDockTokenTotal.textContent,
      copy: panel.textContent
    };
  })()`, true);
  assert.strictEqual(tokenFocus.cells.length, 5);
  assert(tokenFocus.cells[0].left < 20, "token focus must begin at the leading edge");
  assert(tokenFocus.cells[4].right > 1030, "token focus must fill the trailing edge");
  assert.strictEqual(tokenFocus.cacheHit, "80.0%");
  assert.strictEqual(tokenFocus.cost, "$0.255");
  assert.strictEqual(tokenFocus.programmingIQ, "77.4");
  assert.strictEqual(tokenFocus.total, "2.448B");
  assert(tokenFocus.copy.includes("编程 IQ"));
  fs.writeFileSync(
    path.join(outputDirectory, "token-focus.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`setCodexDockFocus("cacheHit")`, true);
  await new Promise((resolve) => setTimeout(resolve, 240));
  const cacheFocus = await window.webContents.executeJavaScript(`(() => ({
    hitRate: elements.codexDockFocusCacheHit.textContent,
    cached: elements.codexDockCacheTokens.textContent,
    uncached: elements.codexDockUncachedTokens.textContent,
    input: elements.codexDockInputTokens.textContent,
    cells: elements.codexDockFocus.querySelectorAll('[data-focus-panel="cacheHit"] .codex-dock-focus-cell').length
  }))()`, true);
  assert.strictEqual(cacheFocus.cells, 5);
  assert.strictEqual(cacheFocus.hitRate, "80.0%");
  assert.strictEqual(cacheFocus.cached, "80.000M");
  assert.strictEqual(cacheFocus.uncached, "20.000M");
  assert.strictEqual(cacheFocus.input, "100.000M");
  fs.writeFileSync(
    path.join(outputDirectory, "cache-focus.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`setCodexDockFocus("cost")`, true);
  await new Promise((resolve) => setTimeout(resolve, 240));
  const costFocus = await window.webContents.executeJavaScript(`(() => ({
    total: elements.codexDockFocusCost.textContent,
    uncached: elements.codexDockUncachedCost.textContent,
    cached: elements.codexDockCachedCost.textContent,
    output: elements.codexDockOutputCost.textContent,
    cells: elements.codexDockFocus.querySelectorAll('[data-focus-panel="cost"] .codex-dock-focus-cell').length
  }))()`, true);
  assert.strictEqual(costFocus.cells, 5);
  assert.strictEqual(costFocus.total, "$0.255");
  assert.strictEqual(costFocus.uncached, "$0.050");
  assert.strictEqual(costFocus.cached, "$0.020");
  assert.strictEqual(costFocus.output, "$0.185");
  fs.writeFileSync(
    path.join(outputDirectory, "cost-focus.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`setCodexDockFocus("trend")`, true);
  await new Promise((resolve) => setTimeout(resolve, 240));
  const trendFocus = await window.webContents.executeJavaScript(`(() => ({
    total: elements.codexDockFocusTrendTotal.textContent,
    today: elements.codexDockFocusTrendToday.textContent,
    peak: elements.codexDockFocusTrendPeak.textContent,
    line: elements.codexDockFocusTrendLine.getAttribute("points"),
    cells: elements.codexDockFocus.querySelectorAll('[data-focus-panel="trend"] .codex-dock-focus-cell').length
  }))()`, true);
  assert.strictEqual(trendFocus.cells, 4);
  assert.strictEqual(trendFocus.total, "737.320K");
  assert.strictEqual(trendFocus.today, "184.320K");
  assert.strictEqual(trendFocus.peak, "184.320K");
  assert(trendFocus.line.split(" ").length === 7);
  fs.writeFileSync(
    path.join(outputDirectory, "trend-focus.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  window.destroy();
  console.log("Windows dock visual smoke: PASS");
  app.quit();
}).catch((error) => {
  console.error(error);
  app.exit(1);
});
