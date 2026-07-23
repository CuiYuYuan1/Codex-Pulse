const { contextBridge, ipcRenderer } = require("electron");

const fixture = process.argv.find((value) => value.startsWith("--fixture="))?.split("=")[1] || "clear";
const isInformationDisabled = fixture.startsWith("off");
const isAPIKey = fixture.startsWith("api-");
const isLargeToken = fixture === "large-token" || fixture === "off-large";
const isFullQuota = fixture === "full";
const isActual = fixture === "actual";
const isInformationRegression = fixture === "api-126k";
const isUpdateAvailable = fixture === "update";
const isAlmostFullQuota = fixture === "almost-full" || isActual;
const isZeroToken = fixture === "zero" || isActual;
const weatherFixtureName = isActual ? "thunder" : isInformationRegression ? "rain" : isAPIKey ? fixture.slice(4) : fixture;
const weatherFixtures = {
  clear: { code: 0, temperature: 27, isDay: true },
  rain: { code: 63, temperature: 21, isDay: true },
  snow: { code: 73, temperature: -3, isDay: true },
  night: { code: 0, temperature: 18, isDay: false },
  thunder: { code: 95, temperature: 32, isDay: true }
};
const weather = weatherFixtures[weatherFixtureName] || weatherFixtures.clear;
const today = Date.now();
const day = 24 * 60 * 60 * 1000;

const state = {
  connection: "connected",
  message: "已连接",
  cliPath: "C:\\Users\\demo\\codex.exe",
  cliVersion: "codex-cli 0.99.0",
  account: { maskedEmail: "de***@example.com", plan: isAPIKey ? "API" : "Plus", auth: isAPIKey ? "API Key" : "ChatGPT" },
  limits: isAPIKey ? [] : [
    { name: "每周用量", remainingPercent: isFullQuota ? 100 : isAlmostFullQuota ? 98 : 78, resetsAt: today / 1000 + 3 * day / 1000 },
    { name: "5 小时用量", remainingPercent: 64, resetsAt: today / 1000 + 2 * 60 * 60 }
  ],
  resetCards: [],
  usage: {
    today: isLargeToken ? 153200000 : isZeroToken ? 0 : isInformationRegression ? 126800 : 184320,
    total: 12345678,
    streakDays: 12,
    daily: Array.from({ length: 7 }, (_, index) => ({
      date: new Date(today - (6 - index) * day).toISOString().slice(0, 10),
      tokens: [72000, 93000, 51000, 137000, 88000, 112000, 184320][index]
    }))
  },
  task: { state: "idle", label: "空闲", title: null, project: null, startedAt: null },
  informationBar: {
    enabled: !isInformationDisabled,
    location: isInformationDisabled ? null : {
      name: isInformationRegression ? "广州" : "衡阳",
      admin1: isInformationRegression ? "广东" : "湖南",
      country: "中国",
      latitude: 26.90,
      longitude: 112.61,
      timezone: "Asia/Shanghai"
    },
    weather: isInformationDisabled ? null : {
      ...weather,
      unit: "°C",
      timezone: "Asia/Shanghai",
      fetchedAt: today
    },
    status: isInformationDisabled ? "disabled" : "ready",
    message: null,
    updatedAt: today
  },
  appUpdate: {
    currentVersion: "0.1.26",
    status: isUpdateAvailable ? "available" : "current",
    message: isUpdateAvailable ? "发现新版本 v0.1.27" : "当前已是最新版 v0.1.26",
    availableVersion: isUpdateAvailable ? "0.1.27" : null,
    releaseTitle: isUpdateAvailable ? "CodexPulse v0.1.27" : null,
    releaseNotes: isUpdateAvailable
      ? "更新内容\n\n- 优化 Windows 胶囊磁吸跟随，响应更及时，快速移动时更接近 macOS 的吸附手感。\n- 解决双击缩小与还原时的重复圆环、残影和闪烁。\n- 保持透明窗口原生表面尺寸稳定，减少展开、收起和缩放过程中的合成卡顿。\n- 补充磁吸快速扫动、缩小/还原和详情展开的视觉回归测试。\n\n安装说明\n\n- Windows：下载 CodexPulse-Windows-Setup-0.1.26-x64.exe。\n- macOS：下载 CodexPulse-macOS-0.1.26-universal.dmg。"
      : null,
    downloadURL: isUpdateAvailable ? "https://github.com/CuiYuYuan1/Codex-Pulse/releases/download/v0.1.27/CodexPulse-Windows-Setup-0.1.27-x64.exe" : null,
    expectedSHA256: isUpdateAvailable ? "a".repeat(64) : null,
    downloadProgress: null,
    downloadedBytes: 0,
    totalBytes: 0,
    releasePageURL: "https://github.com/CuiYuYuan1/Codex-Pulse/releases",
    checkedAt: today
  },
  updatedAt: today
};

const noop = () => {};
const stateListeners = new Set();
contextBridge.exposeInMainWorld("pulse", {
  getState: async () => state,
  onState: (callback) => {
    stateListeners.add(callback);
    return () => stateListeners.delete(callback);
  },
  onCollapse: (callback) => {
    const listener = () => callback();
    ipcRenderer.on("pulse:collapse", listener);
    return () => ipcRenderer.removeListener("pulse:collapse", listener);
  },
  onExpand: (callback) => {
    const listener = () => callback();
    ipcRenderer.on("pulse:expand", listener);
    return () => ipcRenderer.removeListener("pulse:expand", listener);
  },
  resize: (mode) => ipcRenderer.invoke("visual:resize", mode),
  setWindowShape: (rects) => ipcRenderer.invoke("visual:set-shape", rects),
  beginDrag: noop,
  dragTo: noop,
  endDrag: noop,
  refresh: noop,
  checkForUpdates: async () => state.appUpdate,
  performUpdate: async () => {
    if (state.appUpdate.status === "ready") {
      state.appUpdate = {
        ...state.appUpdate,
        status: "installing",
        message: `正在重启并安装 v${state.appUpdate.availableVersion}…`
      };
      stateListeners.forEach((listener) => listener(state));
      return true;
    }
    if (state.appUpdate.status === "downloading" || state.appUpdate.status === "installing") return false;
    state.appUpdate = {
      ...state.appUpdate,
      status: "downloading",
      message: `正在下载 v${state.appUpdate.availableVersion}…`,
      downloadProgress: 0.42,
      downloadedBytes: 42 * 1024 * 1024,
      totalBytes: 100 * 1024 * 1024
    };
    stateListeners.forEach((listener) => listener(state));
    setTimeout(() => {
      state.appUpdate = {
        ...state.appUpdate,
        status: "ready",
        message: `v${state.appUpdate.availableVersion} 下载完成，重启后自动安装`,
        downloadProgress: 1,
        downloadedBytes: 100 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024
      };
      stateListeners.forEach((listener) => listener(state));
    }, 180);
    return true;
  },
  skipUpdate: async (version) => {
    if (state.appUpdate.availableVersion !== version) return state.appUpdate;
    state.appUpdate = {
      ...state.appUpdate,
      status: "skipped",
      message: `已跳过版本 v${version}`,
      availableVersion: null,
      releaseTitle: null,
      releaseNotes: null,
      downloadURL: null
    };
    stateListeners.forEach((listener) => listener(state));
    return state.appUpdate;
  },
  quit: noop,
  clearCodexPath: noop,
  openExternal: async () => true,
  searchLocations: async () => [],
  setInformationBarEnabled: async () => state,
  setInformationBarLocation: async () => state
});
