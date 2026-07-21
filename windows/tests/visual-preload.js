const { contextBridge, ipcRenderer } = require("electron");

const fixture = process.argv.find((value) => value.startsWith("--fixture="))?.split("=")[1] || "clear";
const isInformationDisabled = fixture.startsWith("off");
const isAPIKey = fixture.startsWith("api-");
const isLargeToken = fixture === "large-token" || fixture === "off-large";
const isFullQuota = fixture === "full";
const isActual = fixture === "actual";
const isInformationRegression = fixture === "api-126k";
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
  updatedAt: today
};

const noop = () => {};
contextBridge.exposeInMainWorld("pulse", {
  getState: async () => state,
  onState: noop,
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
  quit: noop,
  clearCodexPath: noop,
  openExternal: async () => true,
  searchLocations: async () => [],
  setInformationBarEnabled: async () => state,
  setInformationBarLocation: async () => state
});
