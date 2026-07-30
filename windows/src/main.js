const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  ipcMain,
  dialog,
  nativeImage,
  screen,
  shell,
  powerMonitor,
  desktopCapturer,
  session
} = require("electron");
const { spawn, execFile } = require("child_process");
const fs = require("fs");
const path = require("path");
const readline = require("readline");
const crypto = require("crypto");
const { isDeepStrictEqual } = require("util");
const {
  attachedDockShape,
  detachedWindowBounds,
  mediaSourceIdForWindowHandle,
  normalizeTrackedWindowBounds,
  visibleWindowBounds,
  rectangleDistance
} = require("./codex-dock-geometry");
const APP_VERSION = require("../package.json").version;
const processStartedAt = process.hrtime.bigint();

const GITHUB_REPOSITORY = "CuiYuYuan1/Codex-Pulse";
const GITHUB_RELEASES_URL = `https://github.com/${GITHUB_REPOSITORY}/releases`;
const GITHUB_LATEST_RELEASE_API = `https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/latest`;

const COLLAPSED_SIZE = { width: 283, height: 116 };
const COLLAPSED_MIN_WIDTH = 283;
const COLLAPSED_MAX_WIDTH = 471;
const INFORMATION_COLLAPSED_SIZE = { width: 323, height: 128 };
const INFORMATION_MIN_WIDTH = 323;
const INFORMATION_MAX_WIDTH = 471;
const EXPANDED_SIZE = { width: 390, height: 810 };
// 普通宠物为 216×130；黑洞使用 216×184，为竖向吸积盘留出透明空间。
const MINI_SIZE = { width: 240, height: 154 };
const CODEX_DOCK_HORIZONTAL_THICKNESS = 44;
const CODEX_DOCK_VERTICAL_THICKNESS = 54;
const CODEX_DOCK_OVERLAP = 16;
const CODEX_DOCK_PROXIMITY = 30;
const CODEX_DOCK_PREVIEW_RELEASE_DISTANCE = 42;
const USE_STABLE_DESKTOP_SURFACE = process.platform === "win32";
const SETTINGS_FILE = () => path.join(app.getPath("userData"), "settings.json");
const WEATHER_CACHE_TTL_MS = 10 * 60 * 1000;
const WEATHER_REFRESH_MS = 15 * 60 * 1000;
const WEATHER_REQUEST_TIMEOUT_MS = 9000;
const GEOCODING_CACHE_TTL_MS = 30 * 60 * 1000;
const UPDATE_CHECK_INTERVAL_MS = 5 * 60 * 1000;
const PET_SWITCH_ITEMS = Object.freeze([
  { id: "dino", label: "小恐龙" },
  { id: "cat", label: "猫咪" },
  { id: "bunny", label: "兔子" },
  { id: "ghost", label: "幽灵" },
  { id: "robot", label: "机器人" },
  { id: "fox", label: "九尾狐" },
  { id: "orb", label: "小圆球1" },
  { id: "orb_2", label: "小圆球2" },
  { id: "orb_3", label: "小圆球3" },
  { id: "orb_4", label: "小圆球4" },
  { id: "black_hole", label: "事件视界" }
]);

let windowRef;
let currentWindowLayoutMode = "collapsed";
let startupCapsuleShown = false;
let backgroundStartupScheduled = false;
let collapsedWidth = COLLAPSED_SIZE.width;
let informationCollapsedWidth = INFORMATION_COLLAPSED_SIZE.width;
let tray;
let rpc;
let refreshTimer;
let limitsRefreshInFlight = false;
let usageRefreshInFlight = false;
let lastLimitsRefreshAt = 0;
let lastUsageRefreshAt = 0;
let sessionWatcher;
let sessionPollTimer;
let sessionRescanTimer;
let sessionRefreshTimer;
let sessionCandidates = new Map();
let localSessionSnapshot = null;
let pendingSessionPaths = new Set();
let authWatcher;
let authPollTimer;
let authChangeTimer;
let accountTransitionTimer;
let authIdentity = null;
let accountReloadInFlight = false;
let pendingAccountRestart = false;
let accountGeneration = 0;
// “今日 Token”采用本机当天全部 Codex session 的汇总。session 日志没有账号
// 标识，因此账号切换后也要立即重新读取，不能等应用重启才恢复显示。
let localUsageDayKey = null;
const localUsageCache = new Map();
let localUsageRefreshPromise = null;
let localUsageGeneration = 0;
let localUsageLastReadAt = 0;
let localUsageLastValue = null;
const LOCAL_USAGE_MIN_REFRESH_MS = 750;
let localHistoryRefreshPromise = null;
let localHistoryLastReadAt = 0;
let localHistoryLastValue = null;
let localUsageDayTimer;
const LOCAL_HISTORY_MIN_REFRESH_MS = 1500;
const localHistoryCache = new Map();
let weatherRefreshTimer;
let updateRefreshTimer;
let updateCheckInFlight = false;
let updateDownloadPromise;
let updateDownloadAbortController;
let stagedUpdate;
let lastAutomaticUpdateCheckAt = 0;
let weatherRequestGeneration = 0;
const weatherCache = new Map();
const geocodingCache = new Map();
let dragState;
let codexWindowWatcher;
let codexWindowBounds = null;
let codexWindowMediaSourceId = null;
let codexWindowWasPresent = false;
let codexDockPreviewRef;
let codexDockPreviewEdge = null;
let codexDockCandidate = null;
let codexDockCandidateEdge = null;
let codexDockAttached = false;
let codexDockEdge = "bottom";
let codexDockRestorePending = false;
let codexDockPreviousLayout = null;
let codexDockLastZOrderAt = 0;
let codexDockTransition = "idle";
let codexDockTransitionTimer;
let codexDockFollowTarget = null;
let codexDockFollowTimer;
let codexDockFollowLastAt = 0;
let codexDockPreviewSuppressUntil = 0;
let petRoamGeneration = 0;
let petRoamTimer;
let petRoamResolve;
let windowShapeBounds = null;
let windowShapeSignature = null;
let blackHoleCaptureEnabled = false;
let connectionAttempt = 0;
let state = {
  connection: "discovering",
  message: "正在自动获取 Codex 路径…",
  cliPath: null,
  cliVersion: null,
  modelProvider: null,
  account: { email: null, maskedEmail: "—", plan: "—", auth: "—" },
  limits: [],
  resetCards: [],
  usage: { today: 0, total: 0, daily: [] },
  task: { state: "idle", label: "空闲", title: null, project: null, startedAt: null, threadID: null, conversation: [] },
  informationBar: {
    enabled: false,
    location: null,
    weather: null,
    status: "disabled",
    message: null,
    updatedAt: null
  },
  followCodexLaunch: false,
  appUpdate: {
    currentVersion: APP_VERSION,
    status: "idle",
    message: "启动后及每 5 分钟自动检查 GitHub Releases",
    availableVersion: null,
    releaseTitle: null,
    releaseNotes: null,
    downloadURL: null,
    expectedSHA256: null,
    downloadProgress: null,
    downloadedBytes: 0,
    totalBytes: 0,
    releasePageURL: GITHUB_RELEASES_URL,
    checkedAt: null
  },
  updatedAt: null
};

function readSettings() {
  try { return JSON.parse(fs.readFileSync(SETTINGS_FILE(), "utf8")); }
  catch { return {}; }
}

function writeSettings(patch) {
  const next = { ...readSettings(), ...patch };
  fs.mkdirSync(path.dirname(SETTINGS_FILE()), { recursive: true });
  fs.writeFileSync(SETTINGS_FILE(), JSON.stringify(next, null, 2), "utf8");
}

function normalizeWeatherLocation(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = Number(value.latitude);
  const longitude = Number(value.longitude);
  const name = String(value.name || "").trim();
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
      || !Number.isFinite(longitude) || longitude < -180 || longitude > 180
      || !name) return null;
  const clean = (part, fallback = "") => String(part || fallback).trim().slice(0, 120);
  return {
    id: Number.isFinite(Number(value.id)) ? Number(value.id) : null,
    name: clean(name),
    admin1: clean(value.admin1),
    country: clean(value.country),
    countryCode: clean(value.countryCode || value.country_code, "").toUpperCase().slice(0, 8),
    latitude: Math.round(latitude * 1e5) / 1e5,
    longitude: Math.round(longitude * 1e5) / 1e5,
    timezone: clean(value.timezone, "auto") || "auto"
  };
}

function weatherLocationKey(location) {
  return location ? `${location.latitude.toFixed(5)},${location.longitude.toFixed(5)}` : "";
}

function normalizeWeatherSnapshot(value, location) {
  if (!value || typeof value !== "object" || !location) return null;
  const key = weatherLocationKey(location);
  if (value.locationKey && String(value.locationKey) !== key) return null;
  const source = value.weather && typeof value.weather === "object" ? value.weather : value;
  const temperature = Number(source.temperature);
  const code = Number(source.code);
  const isDayValue = source.isDay === true || source.isDay === false
    ? source.isDay
    : Number(source.isDay) === 1 ? true : Number(source.isDay) === 0 ? false : null;
  if (!Number.isFinite(temperature) || !Number.isInteger(code) || code < 0 || code > 99 || isDayValue === null) return null;
  const fetchedAt = Number(value.cachedAt || source.fetchedAt);
  if (!Number.isFinite(fetchedAt) || fetchedAt <= 0) return null;
  return {
    temperature: Number.isFinite(temperature) ? temperature : null,
    unit: String(source.unit || "°C").slice(0, 12),
    code: Number.isFinite(code) ? code : null,
    isDay: isDayValue,
    timezone: String(source.timezone || location.timezone || "auto").slice(0, 80),
    fetchedAt
  };
}

function informationBarSnapshot(patch = {}) {
  return { ...state.informationBar, ...patch };
}

function updateInformationBar(patch) {
  publish({ informationBar: informationBarSnapshot(patch) });
}

function initializeInformationBar() {
  const settings = readSettings();
  const location = normalizeWeatherLocation(settings.weatherLocation);
  const enabled = settings.informationBarEnabled === true && Boolean(location);
  const restoredWeather = normalizeWeatherSnapshot(settings.weatherSnapshot, location);
  if (location && restoredWeather) {
    weatherCache.set(weatherLocationKey(location), { at: restoredWeather.fetchedAt, value: restoredWeather });
  }
  state.informationBar = {
    enabled,
    location,
    weather: restoredWeather,
    status: enabled ? "loading" : "disabled",
    message: null,
    updatedAt: null
  };
  if (!enabled) clearTimeout(weatherRefreshTimer);
}

async function requestJSON(url, timeout = WEATHER_REQUEST_TIMEOUT_MS) {
  if (typeof fetch !== "function") throw new Error("当前运行环境不支持网络请求");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: controller.signal
    });
    if (!response.ok) throw new Error(`网络请求失败（${response.status}）`);
    return await response.json();
  } catch (error) {
    if (error?.name === "AbortError") throw new Error("网络请求超时");
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function normalizedVersion(value) {
  return String(value || "").trim().replace(/^v/i, "");
}

function parsedVersion(value) {
  const [core, prerelease] = normalizedVersion(value).split("-", 2);
  return {
    numbers: String(core || "0").split(".").map((part) => Number.parseInt(part, 10) || 0),
    prerelease: Boolean(prerelease)
  };
}

function isVersionNewer(candidate, current) {
  const left = parsedVersion(candidate);
  const right = parsedVersion(current);
  const count = Math.max(left.numbers.length, right.numbers.length);
  for (let index = 0; index < count; index += 1) {
    const l = left.numbers[index] || 0;
    const r = right.numbers[index] || 0;
    if (l !== r) return l > r;
  }
  if (left.prerelease !== right.prerelease) return !left.prerelease;
  return false;
}

function preferredWindowsReleaseAsset(assets) {
  const candidates = (Array.isArray(assets) ? assets : []).filter((asset) => {
    const name = String(asset?.name || "").toLowerCase();
    return name.endsWith(".exe") && /^https:\/\/github\.com\//i.test(String(asset?.browser_download_url || ""));
  });
  const setup = candidates.find((asset) => /setup|installer/.test(String(asset.name).toLowerCase()));
  return setup || candidates[0] || null;
}

function preferredWindowsReleaseURL(assets, fallbackURL) {
  return String(preferredWindowsReleaseAsset(assets)?.browser_download_url || fallbackURL || GITHUB_RELEASES_URL);
}

function normalizedSHA256Digest(value) {
  const normalized = String(value || "").trim().toLowerCase().replace(/^sha256:/, "");
  return /^[a-f0-9]{64}$/.test(normalized) ? normalized : null;
}

function isPathInsideDirectory(candidate, directory) {
  const relative = path.relative(path.resolve(directory), path.resolve(String(candidate || "")));
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}

function updateDownloadDirectory() {
  return path.join(app.getPath("userData"), "updates");
}

function restoreStagedUpdate(version, expectedSHA256) {
  const saved = readSettings().stagedUpdate;
  const directory = updateDownloadDirectory();
  const installerPath = String(saved?.path || "");
  const savedVersion = normalizedVersion(saved?.version);
  const savedDigest = normalizedSHA256Digest(saved?.sha256);
  if (savedVersion !== normalizedVersion(version)
      || (expectedSHA256 && savedDigest !== expectedSHA256)
      || !isPathInsideDirectory(installerPath, directory)
      || path.extname(installerPath).toLowerCase() !== ".exe") return null;
  try {
    const stats = fs.statSync(installerPath);
    if (!stats.isFile() || stats.size <= 1_000_000) return null;
    return { version: savedVersion, path: installerPath, sha256: savedDigest, size: stats.size };
  } catch {
    return null;
  }
}

function safeReleaseURL(rawURL) {
  try {
    const url = new URL(String(rawURL || ""));
    if (url.protocol !== "https:" || url.hostname.toLowerCase() !== "github.com") return null;
    const pathPrefix = `/${GITHUB_REPOSITORY.toLowerCase()}/releases`;
    if (!url.pathname.toLowerCase().startsWith(pathPrefix)) return null;
    return url.toString();
  } catch {
    return null;
  }
}

function updateAppUpdateState(patch) {
  publish({ appUpdate: { ...state.appUpdate, ...patch } });
}

async function checkForUpdates(userInitiated = false, force = false) {
  const now = Date.now();
  if (updateCheckInFlight || updateDownloadPromise) return state.appUpdate;
  if (!userInitiated && !force && now - lastAutomaticUpdateCheckAt < UPDATE_CHECK_INTERVAL_MS) {
    return state.appUpdate;
  }
  if (!userInitiated) lastAutomaticUpdateCheckAt = now;
  updateCheckInFlight = true;
  if (userInitiated || state.appUpdate.status === "idle" || state.appUpdate.status === "error") {
    updateAppUpdateState({ status: "checking", message: "正在检查 GitHub Releases…" });
  }
  try {
    const response = await fetch(GITHUB_LATEST_RELEASE_API, {
      method: "GET",
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": `CodexPulse/${APP_VERSION}`
      },
      signal: AbortSignal.timeout(12_000)
    });
    if (response.status === 404) {
      stagedUpdate = null;
      updateAppUpdateState({
        status: "current",
        message: "GitHub 暂无已发布版本",
        availableVersion: null,
        releaseTitle: null,
        releaseNotes: null,
        downloadURL: null,
        expectedSHA256: null,
        downloadProgress: null,
        downloadedBytes: 0,
        totalBytes: 0,
        checkedAt: Date.now()
      });
      if (userInitiated) await dialog.showMessageBox({
        type: "info", title: "CodexPulse 更新", message: "GitHub 暂无已发布版本", buttons: ["好"]
      });
      return state.appUpdate;
    }
    if (!response.ok) throw new Error(`GitHub 请求失败（HTTP ${response.status}）`);
    const release = await response.json();
    const remoteVersion = normalizedVersion(release?.tag_name);
    const releasePageURL = safeReleaseURL(release?.html_url) || GITHUB_RELEASES_URL;
    const preferredAsset = preferredWindowsReleaseAsset(release?.assets);
    const downloadURL = safeReleaseURL(preferredWindowsReleaseURL(release?.assets, releasePageURL));
    const expectedSHA256 = normalizedSHA256Digest(preferredAsset?.digest);
    const releaseTitle = String(release?.name || `CodexPulse v${remoteVersion}`).trim().slice(0, 180);
    const releaseNotes = String(release?.body || "新版本已发布，可前往 GitHub 下载并安装。")
      .trim().slice(0, 6_000);
    if (remoteVersion && isVersionNewer(remoteVersion, APP_VERSION)) {
      const skippedVersion = normalizedVersion(readSettings().skippedUpdateVersion);
      if (skippedVersion === remoteVersion) {
        stagedUpdate = null;
        updateAppUpdateState({
          status: "skipped",
          message: `已跳过版本 v${remoteVersion}`,
          availableVersion: null,
          releaseTitle: null,
          releaseNotes: null,
          downloadURL: null,
          expectedSHA256: null,
          downloadProgress: null,
          downloadedBytes: 0,
          totalBytes: 0,
          releasePageURL,
          checkedAt: Date.now()
        });
      } else {
        const restoredUpdate = restoreStagedUpdate(remoteVersion, expectedSHA256);
        stagedUpdate = restoredUpdate;
        updateAppUpdateState({
          status: restoredUpdate ? "ready" : "available",
          message: restoredUpdate
            ? `v${remoteVersion} 已下载，重启后自动安装`
            : `发现新版本 v${remoteVersion}`,
          availableVersion: remoteVersion,
          releaseTitle,
          releaseNotes,
          downloadURL,
          expectedSHA256,
          downloadProgress: restoredUpdate ? 1 : null,
          downloadedBytes: restoredUpdate?.size || 0,
          totalBytes: restoredUpdate?.size || 0,
          releasePageURL,
          checkedAt: Date.now()
        });
      }
    } else {
      stagedUpdate = null;
      updateAppUpdateState({
        status: "current",
        message: `当前已是最新版 v${APP_VERSION}`,
        availableVersion: null,
        releaseTitle: null,
        releaseNotes: null,
        downloadURL: null,
        expectedSHA256: null,
        downloadProgress: null,
        downloadedBytes: 0,
        totalBytes: 0,
        releasePageURL,
        checkedAt: Date.now()
      });
      if (userInitiated) await dialog.showMessageBox({
        type: "info", title: "CodexPulse 更新", message: `当前已是最新版 v${APP_VERSION}`, buttons: ["好"]
      });
    }
  } catch (error) {
    if (!userInitiated && ["available", "ready", "download-error"].includes(state.appUpdate.status)) {
      updateAppUpdateState({ checkedAt: Date.now() });
    } else {
      updateAppUpdateState({ status: "error", message: `检查更新失败：${error.message}`, checkedAt: Date.now() });
    }
    if (userInitiated) await dialog.showMessageBox({
      type: "warning", title: "CodexPulse 更新", message: "检查更新失败", detail: error.message, buttons: ["好"]
    });
  } finally {
    updateCheckInFlight = false;
  }
  return state.appUpdate;
}

function armAutomaticUpdateCheck(delay = UPDATE_CHECK_INTERVAL_MS) {
  clearTimeout(updateRefreshTimer);
  updateRefreshTimer = setTimeout(() => {
    void checkForUpdates(false).finally(() => armAutomaticUpdateCheck());
  }, Math.max(1_000, delay));
}

function triggerAutomaticUpdateCheck(force = false) {
  void checkForUpdates(false, force).finally(() => armAutomaticUpdateCheck());
}

function skipAvailableUpdate(version) {
  const availableVersion = normalizedVersion(state.appUpdate?.availableVersion);
  const requestedVersion = normalizedVersion(version);
  if (!availableVersion || requestedVersion !== availableVersion) return state.appUpdate;
  if (stagedUpdate?.path && isPathInsideDirectory(stagedUpdate.path, updateDownloadDirectory())) {
    try { fs.rmSync(stagedUpdate.path, { force: true }); } catch {}
  }
  stagedUpdate = null;
  writeSettings({ skippedUpdateVersion: availableVersion, stagedUpdate: null });
  updateAppUpdateState({
    status: "skipped",
    message: `已跳过版本 v${availableVersion}`,
    availableVersion: null,
    releaseTitle: null,
    releaseNotes: null,
    downloadURL: null,
    expectedSHA256: null,
    downloadProgress: null,
    downloadedBytes: 0,
    totalBytes: 0,
    checkedAt: Date.now()
  });
  return state.appUpdate;
}

async function downloadAvailableUpdate() {
  if (updateDownloadPromise) return updateDownloadPromise;
  const version = normalizedVersion(state.appUpdate?.availableVersion);
  const downloadURL = safeReleaseURL(state.appUpdate?.downloadURL);
  const expectedSHA256 = normalizedSHA256Digest(state.appUpdate?.expectedSHA256);
  if (!version || !downloadURL) return false;

  const directory = updateDownloadDirectory();
  const destination = path.join(directory, `CodexPulse-Windows-Setup-${version}-x64.exe`);
  const partial = `${destination}.partial`;
  updateDownloadAbortController = new AbortController();
  updateAppUpdateState({
    status: "downloading",
    message: `正在下载 v${version}…`,
    downloadProgress: 0,
    downloadedBytes: 0,
    totalBytes: 0
  });

  updateDownloadPromise = (async () => {
    fs.mkdirSync(directory, { recursive: true });
    await fs.promises.rm(partial, { force: true });
    const response = await fetch(downloadURL, {
      method: "GET",
      headers: { "User-Agent": `CodexPulse/${APP_VERSION}` },
      signal: updateDownloadAbortController.signal
    });
    if (!response.ok || !response.body) {
      throw new Error(`安装包下载失败（HTTP ${response.status}）`);
    }

    const totalBytes = Math.max(0, Number(response.headers.get("content-length")) || 0);
    const handle = await fs.promises.open(partial, "w");
    const digest = crypto.createHash("sha256");
    const reader = response.body.getReader();
    let downloadedBytes = 0;
    let lastPublishedAt = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = Buffer.from(value);
        await handle.write(chunk);
        digest.update(chunk);
        downloadedBytes += chunk.length;
        const now = Date.now();
        if (now - lastPublishedAt >= 100 || (totalBytes > 0 && downloadedBytes >= totalBytes)) {
          lastPublishedAt = now;
          updateAppUpdateState({
            status: "downloading",
            message: `正在下载 v${version}…`,
            downloadProgress: totalBytes > 0 ? Math.min(1, downloadedBytes / totalBytes) : null,
            downloadedBytes,
            totalBytes
          });
        }
      }
    } finally {
      await handle.close();
    }

    if (downloadedBytes <= 1_000_000) throw new Error("下载的安装包不完整");
    const actualSHA256 = digest.digest("hex");
    if (expectedSHA256 && actualSHA256 !== expectedSHA256) {
      throw new Error("安装包 SHA-256 校验不一致");
    }
    await fs.promises.rm(destination, { force: true });
    await fs.promises.rename(partial, destination);
    stagedUpdate = { version, path: destination, sha256: actualSHA256, size: downloadedBytes };
    writeSettings({ stagedUpdate });
    updateAppUpdateState({
      status: "ready",
      message: `v${version} 下载完成，重启后自动安装`,
      downloadProgress: 1,
      downloadedBytes,
      totalBytes: totalBytes || downloadedBytes
    });
    return true;
  })().catch(async (error) => {
    await fs.promises.rm(partial, { force: true }).catch(() => {});
    updateAppUpdateState({
      status: "download-error",
      message: `下载失败：${String(error?.message || error)}`,
      downloadProgress: null,
      downloadedBytes: 0,
      totalBytes: 0
    });
    return false;
  }).finally(() => {
    updateDownloadPromise = null;
    updateDownloadAbortController = null;
  });
  return updateDownloadPromise;
}

function installDownloadedUpdateAndRestart() {
  const version = normalizedVersion(state.appUpdate?.availableVersion);
  const restored = stagedUpdate || restoreStagedUpdate(version, normalizedSHA256Digest(state.appUpdate?.expectedSHA256));
  if (!restored) {
    updateAppUpdateState({ status: "download-error", message: "已下载的安装包不存在，请重新下载" });
    return false;
  }
  stagedUpdate = restored;
  try {
    updateAppUpdateState({ status: "installing", message: `正在重启并安装 v${version}…` });
    const installer = spawn(restored.path, ["--updated", "/S", "--force-run"], {
      detached: true,
      stdio: "ignore",
      windowsHide: true
    });
    installer.once("error", (error) => {
      writeSettings({ stagedUpdate: restored });
      updateAppUpdateState({ status: "download-error", message: `无法启动安装程序：${error.message}` });
    });
    installer.once("spawn", () => {
      writeSettings({ stagedUpdate: null });
      installer.unref();
      app.isQuitting = true;
      setTimeout(() => app.quit(), 250);
    });
    return true;
  } catch (error) {
    writeSettings({ stagedUpdate: restored });
    updateAppUpdateState({ status: "download-error", message: `无法启动安装程序：${error.message}` });
    return false;
  }
}

async function performPrimaryUpdateAction() {
  if (state.appUpdate?.status === "ready") return installDownloadedUpdateAndRestart();
  if (state.appUpdate?.status === "installing" || state.appUpdate?.status === "downloading") return false;
  return downloadAvailableUpdate();
}

async function searchWeatherLocations(query) {
  const text = String(query || "").trim().slice(0, 80);
  if (text.length < 2) return [];
  const cacheKey = text.toLocaleLowerCase();
  const cached = geocodingCache.get(cacheKey);
  if (cached && Date.now() - cached.at < GEOCODING_CACHE_TTL_MS) return cached.results;
  const params = new URLSearchParams({
    name: text,
    count: "8",
    language: "zh",
    format: "json"
  });
  const payload = await requestJSON(`https://geocoding-api.open-meteo.com/v1/search?${params.toString()}`);
  const results = (Array.isArray(payload?.results) ? payload.results : [])
    .map((item) => normalizeWeatherLocation({
      id: item.id,
      name: item.name,
      admin1: item.admin1,
      country: item.country,
      countryCode: item.country_code,
      latitude: item.latitude,
      longitude: item.longitude,
      timezone: item.timezone
    }))
    .filter(Boolean);
  geocodingCache.set(cacheKey, { at: Date.now(), results });
  return results;
}

async function fetchWeather(location, force = false) {
  const key = weatherLocationKey(location);
  const cached = weatherCache.get(key);
  if (!force && cached && Date.now() - cached.at < WEATHER_CACHE_TTL_MS) return cached.value;
  const params = new URLSearchParams({
    latitude: String(location.latitude),
    longitude: String(location.longitude),
    current: "temperature_2m,weather_code,is_day",
    timezone: location.timezone && location.timezone !== "auto" ? location.timezone : "auto",
    forecast_days: "1"
  });
  const payload = await requestJSON(`https://api.open-meteo.com/v1/forecast?${params.toString()}`);
  const current = payload?.current || {};
  const temperature = Number(current.temperature_2m);
  const code = Number(current.weather_code);
  const isDayValue = Number(current.is_day);
  if (!Number.isFinite(temperature)
      || !Number.isInteger(code) || code < 0 || code > 99
      || (isDayValue !== 0 && isDayValue !== 1)) {
    throw new Error("天气数据格式无效");
  }
  const weather = {
    temperature: Number.isFinite(temperature) ? temperature : null,
    unit: payload?.current_units?.temperature_2m || "°C",
    code,
    isDay: isDayValue === 1,
    timezone: String(payload?.timezone || location.timezone || "auto"),
    fetchedAt: Date.now()
  };
  weatherCache.set(key, { at: Date.now(), value: weather });
  return weather;
}

function armWeatherRefresh() {
  clearTimeout(weatherRefreshTimer);
  const info = state.informationBar;
  if (!info?.enabled || !info.location) return;
  weatherRefreshTimer = setTimeout(() => { void refreshWeather(false); }, WEATHER_REFRESH_MS);
}

async function refreshWeather(force = false) {
  const info = state.informationBar;
  if (!info?.enabled || !info.location) {
    clearTimeout(weatherRefreshTimer);
    return state;
  }
  const generation = ++weatherRequestGeneration;
  const key = weatherLocationKey(info.location);
  updateInformationBar({ status: "loading", message: null });
  try {
    const weather = await fetchWeather(info.location, force);
    if (generation !== weatherRequestGeneration
        || !state.informationBar.enabled
        || weatherLocationKey(state.informationBar.location) !== key) return state;
    updateInformationBar({ weather, status: "ready", message: null, updatedAt: Date.now() });
    writeSettings({ weatherSnapshot: { locationKey: key, cachedAt: Date.now(), weather } });
  } catch (error) {
    if (generation !== weatherRequestGeneration) return state;
    updateInformationBar({
      status: "error",
      message: String(error?.message || "天气暂不可用"),
      updatedAt: Date.now()
    });
  }
  armWeatherRefresh();
  return state;
}

function setInformationBarEnabled(enabled) {
  const nextEnabled = Boolean(enabled);
  const location = normalizeWeatherLocation(state.informationBar.location)
    || normalizeWeatherLocation(readSettings().weatherLocation);
  // 首次打开没有地区时不落盘，renderer 会立即展示搜索器；取消后仍保持关闭。
  if (nextEnabled && !location) return state;
  writeSettings({ informationBarEnabled: nextEnabled });
  ++weatherRequestGeneration;
  if (!nextEnabled) {
    clearTimeout(weatherRefreshTimer);
    updateInformationBar({ enabled: false, status: "disabled", message: null });
    return state;
  }
  updateInformationBar({ enabled: true, location, status: "loading", message: null });
  void refreshWeather(true);
  return state;
}

function setInformationBarLocation(value) {
  const location = normalizeWeatherLocation(value);
  if (!location) throw new Error("地区信息无效，请重新选择");
  writeSettings({ weatherLocation: location, informationBarEnabled: true });
  ++weatherRequestGeneration;
  updateInformationBar({
    enabled: true,
    location,
    weather: null,
    status: "loading",
    message: null,
    updatedAt: null
  });
  void refreshWeather(true);
  return state;
}

function iconPath() {
  return app.isPackaged
    ? path.join(process.resourcesPath, "icon.png")
    : path.join(__dirname, "../../CodexPulse/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png");
}

function publish(patch = {}) {
  const changedPatch = {};
  for (const [key, value] of Object.entries(patch)) {
    if (!isDeepStrictEqual(state[key], value)) changedPatch[key] = value;
  }
  if (!Object.keys(changedPatch).length) return false;
  state = { ...state, ...changedPatch, updatedAt: Date.now() };
  if (windowRef && !windowRef.isDestroyed()) windowRef.webContents.send("pulse:state", state);
  updateTray();
  return true;
}

function maskEmail(email) {
  if (!email || !email.includes("@")) return email || "—";
  const [name, domain] = email.split("@");
  const visible = name.length <= 4 ? 1 : 2;
  return `${name.slice(0, visible)}${"*".repeat(Math.max(4, name.length - visible))}@${domain}`;
}

function exists(candidate) {
  if (!candidate) return false;
  try { return fs.statSync(candidate).isFile(); }
  catch { return false; }
}

function execFileText(command, args, timeout = 4000) {
  return new Promise((resolve) => {
    execFile(command, args, { windowsHide: true, timeout }, (error, stdout, stderr) => {
      const output = String(stdout || "").trim();
      const fallback = String(stderr || "").trim();
      resolve(error ? "" : (output || fallback));
    });
  });
}

function windowsCodexCommand(candidate, args) {
  const safePath = String(candidate || "").replace(/"/g, "");
  return `""${safePath}" ${args.join(" ")}"`;
}

function execCodexText(candidate, args, timeout = 4000) {
  if (process.platform === "win32" && /\.(cmd|bat)$/i.test(candidate)) {
    return execFileText(
      process.env.ComSpec || "C:\\Windows\\System32\\cmd.exe",
      ["/d", "/s", "/c", windowsCodexCommand(candidate, args)],
      timeout
    );
  }
  return execFileText(candidate, args, timeout);
}

async function findDesktopCodexCandidates() {
  if (process.platform !== "win32") return [];
  // Codex/ChatGPT 桌面版会自行启动 app-server。优先读取这个正在工作的
  // 子进程路径；如果进程信息不可见，再扫描当前用户可访问的应用安装目录。
  const script = [
    "$ErrorActionPreference = 'SilentlyContinue'",
    "$paths = New-Object System.Collections.Generic.List[string]",
    "Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.CommandLine -match '(?i)app-server' } | ForEach-Object { $paths.Add($_.ExecutablePath) }",
    "$roots = New-Object System.Collections.Generic.List[string]",
    "Get-AppxPackage | Where-Object { $_.Name -match '(?i)(openai|codex|chatgpt)' } | ForEach-Object { if ($_.InstallLocation) { $roots.Add($_.InstallLocation) } }",
    "$localRoots = New-Object System.Collections.Generic.List[string]",
    "$localRoots.Add((Join-Path $env:LOCALAPPDATA 'Programs\\Codex'))",
    "$localRoots.Add((Join-Path $env:LOCALAPPDATA 'Programs\\ChatGPT'))",
    "$localRoots.Add((Join-Path $env:LOCALAPPDATA 'OpenAI'))",
    "$localRoots | Where-Object { Test-Path $_ } | ForEach-Object { $roots.Add($_) }",
    "foreach ($root in ($roots | Select-Object -Unique)) { Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*codex*.exe' | Where-Object { $_.DirectoryName -ne $root } | ForEach-Object { $paths.Add($_.FullName) } }",
    "$paths | Where-Object { $_ } | Select-Object -Unique"
  ].join("; ");
  const output = await execFileText("powershell.exe", [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-Command", script
  ], 9000);
  return output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

async function probeCodexCLI(candidate) {
  if (!exists(candidate)) return false;
  const version = await execCodexText(candidate, ["--version"], 2500);
  if (!/codex/i.test(version)) return false;
  const appServerHelp = await execCodexText(candidate, ["app-server", "--help"], 3500);
  return /codex app-server|run the app server|stdio:\/\//i.test(appServerHelp);
}

async function firstUsableCodex(candidates) {
  for (const candidate of candidates.filter(Boolean)) {
    if (await probeCodexCLI(candidate)) return candidate;
  }
  return null;
}

function copyExecutable(source, destination) {
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  if (exists(destination)) return;
  fs.copyFileSync(source, destination);
}

async function stageDesktopCodex(candidate) {
  if (!candidate || process.platform !== "win32" || !/\.exe$/i.test(candidate)) return candidate;
  const engineRoot = path.join(app.getPath("userData"), "engine");
  const normalizedCandidate = path.resolve(candidate).toLowerCase();
  if (normalizedCandidate.startsWith(`${path.resolve(engineRoot).toLowerCase()}${path.sep}`)) {
    return candidate;
  }
  const sourceStat = fs.statSync(candidate);
  const fingerprint = `${sourceStat.size}-${Math.floor(sourceStat.mtimeMs)}`;
  const engineDirectory = path.join(engineRoot, fingerprint);
  const stagedExecutable = path.join(engineDirectory, "codex.exe");
  copyExecutable(candidate, stagedExecutable);

  // Codex 的 Windows 引擎可能把沙箱和 Responses API 代理作为同目录辅助程序发布。
  // Pulse 目前只读取状态，但一起暂存可避免不同桌面版构建的启动依赖差异。
  const sourceDirectory = path.dirname(candidate);
  for (const companion of ["codex-windows-sandbox.exe", "codex-responses-api-proxy.exe"]) {
    const source = path.join(sourceDirectory, companion);
    if (exists(source)) copyExecutable(source, path.join(engineDirectory, companion));
  }
  return stagedExecutable;
}

async function firstUsableDesktopCodex(candidates) {
  for (const candidate of candidates.filter(Boolean)) {
    try {
      const staged = await stageDesktopCodex(candidate);
      if (await probeCodexCLI(staged)) return staged;
    } catch (error) {
      console.warn(`[CodexPulse] 无法暂存桌面版 Codex 引擎 ${candidate}: ${error.message}`);
    }
  }
  return null;
}

async function findCodexCLI() {
  const settings = readSettings();
  const explicit = process.platform === "win32"
    ? await firstUsableDesktopCodex([settings.codexPath, process.env.CODEX_PULSE_CODEX_PATH])
    : await firstUsableCodex([settings.codexPath, process.env.CODEX_PULSE_CODEX_PATH]);
  if (explicit) return explicit;

  const home = process.env.USERPROFILE || process.env.HOME || "";
  const appData = process.env.APPDATA || path.join(home, "AppData", "Roaming");
  const localAppData = process.env.LOCALAPPDATA || path.join(home, "AppData", "Local");
  const programData = process.env.ProgramData || "C:\\ProgramData";
  const programFiles = process.env.ProgramFiles || "C:\\Program Files";

  if (process.platform === "win32") {
    const desktopEngine = await firstUsableDesktopCodex(await findDesktopCodexCandidates());
    if (desktopEngine) return desktopEngine;

    const known = await firstUsableCodex([
      path.join(appData, "npm", "codex.cmd"),
      path.join(appData, "npm", "codex.exe"),
      path.join(localAppData, "Microsoft", "WinGet", "Links", "codex.exe"),
      path.join(localAppData, "pnpm", "codex.exe"),
      path.join(localAppData, "pnpm", "codex.cmd"),
      path.join(localAppData, "Yarn", "bin", "codex.cmd"),
      path.join(home, ".bun", "bin", "codex.exe"),
      path.join(home, "scoop", "shims", "codex.exe"),
      path.join(home, "scoop", "shims", "codex.cmd"),
      path.join(programData, "chocolatey", "bin", "codex.exe"),
      path.join(home, ".local", "bin", "codex.exe"),
      path.join(programFiles, "nodejs", "codex.cmd")
    ]);
    if (known) return known;

    const found = await execFileText(process.env.ComSpec || "C:\\Windows\\System32\\cmd.exe", ["/d", "/s", "/c", "where codex"], 2500);
    const pathCandidates = found
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((candidate) => candidate && !candidate.toLowerCase().includes("\\windowsapps\\"));
    const fromPath = await firstUsableCodex(pathCandidates);
    if (fromPath) return fromPath;

    const commandSources = await execFileText("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "@(Get-Command codex -All -ErrorAction SilentlyContinue | ForEach-Object Source) -join \"`n\""
    ], 2500);
    const fromPowerShell = await firstUsableCodex(commandSources.split(/\r?\n/).map((line) => line.trim()));
    if (fromPowerShell) return fromPowerShell;

    const npmPrefix = await execFileText("npm.cmd", ["config", "get", "prefix"], 2500);
    return firstUsableCodex([
      npmPrefix && path.join(npmPrefix, "codex.cmd"),
      npmPrefix && path.join(npmPrefix, "codex.exe")
    ]);
  }

  const found = await execFileText("/usr/bin/which", ["codex"], 2500);
  return await probeCodexCLI(found) ? found : null;
}

function withTimeout(promise, milliseconds, message) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(message)), milliseconds);
    })
  ]).finally(() => clearTimeout(timer));
}

function spawnCodex(cliPath) {
  if (process.platform === "win32" && /\.(cmd|bat)$/i.test(cliPath)) {
    return spawn(process.env.ComSpec || "C:\\Windows\\System32\\cmd.exe", [
      "/d", "/s", "/c", windowsCodexCommand(cliPath, ["app-server"])
    ], { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
  }
  return spawn(cliPath, ["app-server"], { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
}

class CodexRPC {
  constructor(cliPath) {
    this.cliPath = cliPath;
    this.process = null;
    this.nextID = 1;
    this.pending = new Map();
  }

  async connect() {
    this.process = spawnCodex(this.cliPath);
    this.process.once("error", (error) => this.failAll(error));
    this.process.once("exit", (code) => {
      this.failAll(new Error(`Codex App Server 已退出 (${code ?? "unknown"})`));
      if (rpc === this) publish({ connection: "error", message: "Codex 连接已断开" });
    });
    this.process.stderr.on("data", (chunk) => console.warn(`[codex] ${String(chunk).trim()}`));

    const lines = readline.createInterface({ input: this.process.stdout, crlfDelay: Infinity });
    lines.on("line", (line) => this.handleLine(line));

    await this.request("initialize", {
      clientInfo: { name: "codex_pulse_windows", title: "Codex-Pulse", version: APP_VERSION },
      capabilities: { experimentalApi: false }
    }, 12000);
    this.notify("initialized", {});
  }

  request(method, params = {}, timeout = 12000) {
    if (!this.process || this.process.killed) return Promise.reject(new Error("Codex 未连接"));
    const id = this.nextID++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} 请求超时`));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer, method });
      this.process.stdin.write(`${JSON.stringify({ id, method, params })}\n`);
    });
  }

  notify(method, params = {}) {
    if (this.process && !this.process.killed) {
      this.process.stdin.write(`${JSON.stringify({ method, params })}\n`);
    }
  }

  handleLine(line) {
    if (!line.trim()) return;
    let message;
    try { message = JSON.parse(line); }
    catch { return; }
    if (message.id !== undefined && this.pending.has(message.id)) {
      const pending = this.pending.get(message.id);
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message || `RPC ${message.error.code}`));
      else pending.resolve(message.result ?? {});
      return;
    }
    if (message.method) handleNotification(message.method, message.params || {});
  }

  failAll(error) {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
  }

  close() {
    this.failAll(new Error("连接已关闭"));
    if (this.process && !this.process.killed) this.process.kill();
    this.process = null;
  }
}

function notificationStatus(params) {
  const values = [];
  const visit = (value, depth = 0) => {
    if (depth > 4 || value === null || value === undefined) return;
    if (typeof value === "string") {
      values.push(value.toLowerCase());
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((item) => visit(item, depth + 1));
      return;
    }
    if (typeof value === "object") {
      for (const key of ["status", "type", "state", "activeFlags", "active_flags"]) {
        if (key in value) visit(value[key], depth + 1);
      }
      for (const key of ["thread", "turn", "item"]) {
        if (key in value) visit(value[key], depth + 1);
      }
    }
  };
  visit(params);
  const text = values.join(" ");
  if (/approval|permission|waitingonapproval|waiting_on_approval|userinput|user_input/.test(text)) return "attention";
  if (/\b(active|running|inprogress|in_progress|working|started|thinking)\b/.test(text)) return "working";
  if (/\b(idle|completed|complete|failed|aborted|notloaded|not_loaded)\b/.test(text)) return "idle";
  return null;
}

function handleNotification(method, params = {}) {
  const lower = method.toLowerCase();
  if (lower === "item/agentmessage/delta") {
    const delta = typeof params.delta === "string" ? params.delta : "";
    if (!delta) return;
    const threadID = String(params.threadId || state.task.threadID || "unknown");
    const itemID = String(params.itemId || `assistant-${threadID}`);
    const conversation = Array.isArray(state.task.conversation)
      ? state.task.conversation.map((message) => ({ ...message }))
      : [];
    const existing = conversation.findIndex((message) => message.id === itemID);
    if (existing >= 0) {
      conversation[existing].text += delta;
      conversation[existing].isStreaming = true;
    } else {
      conversation.push({
        id: itemID,
        role: "assistant",
        text: delta,
        timestamp: Date.now(),
        isStreaming: true
      });
    }
    if (conversation.length > 32) conversation.splice(0, conversation.length - 32);
    publish({ task: {
      ...state.task,
      state: "working",
      label: "思考中",
      title: "正在输出回复",
      threadID,
      conversation,
      startedAt: state.task.startedAt || Date.now()
    } });
  } else if (lower.includes("turn/started") || lower.includes("item/started")) {
    const isTurnStart = lower.includes("turn/started");
    publish({ task: {
      ...state.task,
      state: "working",
      label: "思考中",
      conversation: isTurnStart ? [] : (state.task.conversation || []),
      startedAt: state.task.startedAt || Date.now()
    } });
  } else if (lower.includes("approval") || lower.includes("request/userinput")) {
    publish({ task: { ...state.task, state: "attention", label: "等待授权" } });
  } else if (lower.includes("turn/completed") || lower.includes("turn/aborted") || lower.includes("turn/failed")) {
    publish({ task: { state: "idle", label: "空闲", title: null, project: null, startedAt: null, threadID: null, conversation: [] } });
    setTimeout(() => refreshAll(true), 120);
  } else if (lower.includes("account/updated")) {
    scheduleAccountTransition(false);
  } else if (lower.includes("ratelimits")) {
    setTimeout(() => refreshLimits(), 100);
  } else if (lower.includes("thread") && lower.includes("status")) {
    const next = notificationStatus(params);
    if (next === "working" || next === "attention") {
      publish({ task: { ...state.task, state: next, label: next === "attention" ? "等待授权" : "思考中", startedAt: state.task.startedAt || Date.now() } });
    }
    // 独立 app-server 会把桌面端正在执行的线程标成 notLoaded；idle/notLoaded
    // 不能直接覆盖本机会话文件的实时状态，只作为触发本地复核的信号。
    scheduleSessionRefresh();
    setTimeout(() => refreshThreads(), 50);
  }
}

function numberValue(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === "object" && "value" in value) return numberValue(value.value);
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function normalizeAccount(result) {
  const account = result.account || {};
  const type = account.type || "none";
  return {
    email: account.email || null,
    maskedEmail: maskEmail(account.email),
    plan: account.planType || "—",
    auth: type === "chatgpt"
      ? "ChatGPT"
      : type === "apiKey" || type === "amazonBedrock" ? "API Key" : type
  };
}

function normalizeLimits(result) {
  const snapshots = [];
  if (result.rateLimits) snapshots.push(result.rateLimits);
  if (result.rateLimitsByLimitId) snapshots.push(...Object.values(result.rateLimitsByLimitId));
  const seen = new Set();
  const limits = [];
  for (const snapshot of snapshots) {
    for (const [kind, fallbackName] of [["primary", "每周用量"], ["secondary", "5 小时用量"]]) {
      const item = snapshot?.[kind];
      if (!item) continue;
      const duration = numberValue(item.windowDurationMins);
      const key = `${kind}-${Math.round(duration || 0)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const used = Math.min(100, Math.max(0, numberValue(item.usedPercent) || 0));
      limits.push({
        id: key,
        name: duration && duration <= 360 ? "5 小时用量" : (snapshot.limitName || fallbackName),
        usedPercent: used,
        remainingPercent: 100 - used,
        resetsAt: numberValue(item.resetsAt)
      });
    }
  }
  limits.sort((a, b) => (b.resetsAt || 0) - (a.resetsAt || 0));
  const creditSummary = result.rateLimitResetCredits || {};
  const cards = Array.isArray(creditSummary.credits)
    ? creditSummary.credits.map((card, index) => {
        const rawTypes = card.applicableLimitTypes || card.applicable_limit_types
          || card.resetType || card.reset_type || "codex_rate_limits";
        return {
          id: card.id || `card-${index}`,
          available: String(card.status || "available").toLowerCase() === "available",
          expiresAt: numberValue(card.expiresAt || card.expires_at),
          applicableLimitTypes: Array.isArray(rawTypes) ? rawTypes.map(String) : [String(rawTypes)]
        };
      })
    : Array.from({ length: numberValue(creditSummary.availableCount) || 0 }, (_, index) => ({
        id: `card-${index}`, available: true, expiresAt: null, applicableLimitTypes: []
      }));
  return { limits, cards };
}

function dayKey(date) {
  const year = date.getFullYear();
  return `${year}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function normalizeUsage(result) {
  const root = result && typeof result === "object" ? result : {};
  const payload = root.usage && typeof root.usage === "object" ? root.usage : root;
  const nested = payload.data && typeof payload.data === "object" ? payload.data
    : payload.result && typeof payload.result === "object" ? payload.result : payload;
  const summary = nested.summary || payload.summary || root.summary || {};
  const rawDaily = nested.dailyUsageBuckets || nested.dailyBuckets || nested.days
    || payload.dailyUsageBuckets || payload.dailyBuckets || root.dailyUsageBuckets || [];
  const byDay = new Map();
  for (const bucket of Array.isArray(rawDaily) ? rawDaily : []) {
    const date = String(bucket?.startDate || bucket?.start_date || bucket?.date || bucket?.day || "").slice(0, 10);
    if (!date) continue;
    const direct = numberValue(bucket?.tokens ?? bucket?.tokenCount ?? bucket?.token_count ?? bucket?.total);
    const input = numberValue(bucket?.inputTokens ?? bucket?.input_tokens) || 0;
    const output = numberValue(bucket?.outputTokens ?? bucket?.output_tokens) || 0;
    const tokens = direct ?? (input + output);
    byDay.set(date, (byDay.get(date) || 0) + (tokens || 0));
  }
  const daily = [];
  for (let offset = 6; offset >= 0; offset -= 1) {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() - offset);
    const dateString = dayKey(date);
    daily.push({ date: dateString, tokens: byDay.get(dateString) || 0 });
  }
  const today = numberValue(summary.todayTokens ?? summary.today_tokens) ?? daily[daily.length - 1].tokens;
  const total = numberValue(summary.lifetimeTokens ?? summary.lifetime_tokens)
    ?? numberValue(summary.totalTokens ?? summary.total_tokens)
    ?? numberValue(summary.totalTokensUsed ?? summary.total_tokens_used)
    ?? 0;
  const streakDays = numberValue(summary.currentStreakDays ?? summary.current_streak_days)
    ?? numberValue(summary.current_streak_days);
  return { today, total, daily, streakDays };
}

function filledLocalDailyBuckets(existing, reference = new Date()) {
  const map = new Map();
  for (const bucket of Array.isArray(existing) ? existing : []) {
    const date = String(bucket?.date || bucket?.startDate || "").slice(0, 10);
    if (!date) continue;
    map.set(date, (map.get(date) || 0) + Math.max(0, numberValue(bucket?.tokens) || 0));
  }
  const result = [];
  for (let offset = 6; offset >= 0; offset -= 1) {
    const date = new Date(reference);
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() - offset);
    const dateString = dayKey(date);
    result.push({ date: dateString, tokens: map.get(dateString) || 0 });
  }
  return result;
}

// Merge the local session aggregate without pretending today's value is a
// lifetime total. `account/usage/read` is commonly empty for API Key auth.
function mergeLocalTodayUsage(usage, localToday, reference = new Date()) {
  const localRecord = localToday && typeof localToday === "object"
    ? localToday
    : { tokens: localToday, estimated: false };
  const local = numberValue(localRecord.tokens);
  if (local === null || local < 0) return usage;
  const today = new Date(reference);
  today.setHours(12, 0, 0, 0);
  const todayString = dayKey(today);
  const daily = filledLocalDailyBuckets(usage?.daily, today);
  const todayBucket = daily[daily.length - 1];
  const remoteToday = numberValue(todayBucket.tokens) || 0;
  todayBucket.tokens = Math.max(remoteToday, local);
  const localWins = local > remoteToday;
  return {
    ...usage,
    today: Math.max(remoteToday, local),
    todayEstimated: localWins ? localRecord.estimated === true : usage?.todayEstimated === true,
    daily
  };
}

// Local session files expose cumulative counters rather than server-style day
// buckets. Merge the per-day local values by taking the larger value for each
// day so a server bucket and a local bucket cannot be double-counted.
function mergeLocalDailyUsage(usage, localDaily, reference = new Date()) {
  if (!Array.isArray(localDaily) || !localDaily.length) return usage;
  const daily = filledLocalDailyBuckets(usage?.daily, reference);
  const byDate = new Map(localDaily.map((bucket) => [
    String(bucket?.date || "").slice(0, 10),
    {
      tokens: Math.max(0, numberValue(bucket?.tokens) || 0),
      estimated: bucket?.estimated === true
    }
  ]));
  let localSevenDayTokens = 0;
  let localHistoryEstimated = false;
  for (const bucket of byDate.values()) {
    localSevenDayTokens = Math.min(Number.MAX_SAFE_INTEGER, localSevenDayTokens + bucket.tokens);
    localHistoryEstimated ||= bucket.estimated;
  }
  const remoteToday = numberValue(daily[daily.length - 1]?.tokens) || 0;
  for (const bucket of daily) {
    if (!byDate.has(bucket.date)) continue;
    bucket.tokens = Math.max(bucket.tokens, byDate.get(bucket.date).tokens);
  }
  const today = daily[daily.length - 1]?.tokens || 0;
  const localToday = byDate.get(daily[daily.length - 1]?.date);
  return {
    ...usage,
    today,
    todayEstimated: localToday && localToday.tokens > remoteToday
      ? localToday.estimated
      : usage?.todayEstimated === true,
    daily,
    localDailyAvailable: true,
    localSevenDayTokens,
    localHistoryEstimated
  };
}

// A failed or unavailable remote profile must never leave the headline at a
// stale zero when Codex has already written usage into local session JSONL.
// In this path both today's value and the local seven-day buckets become the
// displayed fallback regardless of authentication mode.
function mergeLocalSessionFallback(usage, localToday, localDaily, reference = new Date()) {
  let fallback = usage && typeof usage === "object" ? usage : normalizeUsage({});
  if (localToday !== null && localToday !== undefined) {
    fallback = mergeLocalTodayUsage(fallback, localToday, reference);
  }
  if (Array.isArray(localDaily) && localDaily.length) {
    fallback = mergeLocalDailyUsage(fallback, localDaily, reference);
  }
  return {
    ...fallback,
    localSessionFallback: true,
    sourceNote: "Token 远端统计失败，当前使用本机 Codex session 汇总"
  };
}

const SESSION_STALE_MS = 3 * 60 * 60 * 1000;
const SESSION_TAIL_BYTES = 512 * 1024;
const SESSION_USAGE_LOOKBACK_MS = 24 * 60 * 60 * 1000;
const SESSION_HISTORY_LOOKBACK_MS = 8 * 24 * 60 * 60 * 1000;

function codexHomeRoot() {
  return process.env.CODEX_HOME
    || path.join(process.env.USERPROFILE || process.env.HOME || app.getPath("home"), ".codex");
}

function codexSessionsRoot() {
  return path.join(codexHomeRoot(), "sessions");
}

function localUsageBounds(reference = new Date()) {
  const start = new Date(reference);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { startMs: start.getTime(), endMs: end.getTime(), day: dayKey(start) };
}

function resetLocalUsageDay(reference = new Date()) {
  const { day } = localUsageBounds(reference);
  if (localUsageDayKey === day) return day;
  const previousDay = localUsageDayKey;
  localUsageDayKey = day;
  localUsageCache.clear();
  localHistoryCache.clear();
  localUsageLastReadAt = 0;
  localUsageLastValue = null;
  localHistoryLastReadAt = 0;
  localHistoryLastValue = null;
  if (previousDay !== null) {
    const daily = filledLocalDailyBuckets(state.usage?.daily, reference);
    daily[daily.length - 1].tokens = 0;
    const localSevenDayTokens = state.usage?.localDailyAvailable
      ? daily.reduce((sum, bucket) => Math.min(Number.MAX_SAFE_INTEGER, sum + Math.max(0, numberValue(bucket.tokens) || 0)), 0)
      : state.usage?.localSevenDayTokens;
    publish({
      usage: {
        ...state.usage,
        today: 0,
        daily,
        localSevenDayTokens
      }
    });
  }
  return day;
}

function millisecondsUntilNextLocalDay(reference = new Date()) {
  const next = new Date(reference);
  next.setHours(0, 0, 0, 0);
  next.setDate(next.getDate() + 1);
  return Math.max(250, next.getTime() - reference.getTime() + 250);
}

async function handleLocalUsageDayBoundary(reference = new Date()) {
  const previousDay = localUsageDayKey;
  const day = resetLocalUsageDay(reference);
  if (previousDay === null || previousDay === day) return false;

  // The reset above is published synchronously. Refill only from files whose
  // events belong to the new local day; a stale remote `today` value is never
  // allowed to win this boundary refresh.
  await publishLocalTodayUsage(true);
  if (shouldPromoteLocalDailyUsage()) {
    const localDaily = await refreshLocalDailyUsage(true);
    if (localDaily !== null && localUsageDayKey === day) {
      publish({ usage: mergeLocalDailyUsage(state.usage, localDaily, reference) });
    }
  }
  return true;
}

function armLocalUsageDayTimer(reference = new Date()) {
  clearTimeout(localUsageDayTimer);
  resetLocalUsageDay(reference);
  localUsageDayTimer = setTimeout(async () => {
    try { await handleLocalUsageDayBoundary(new Date()); }
    finally { armLocalUsageDayTimer(new Date()); }
  }, millisecondsUntilNextLocalDay(reference));
}

function usageTokenTotal(usage) {
  if (!usage || typeof usage !== "object") return null;
  const direct = numberValue(usage.total_tokens ?? usage.totalTokens);
  const input = numberValue(usage.input_tokens ?? usage.inputTokens
    ?? usage.prompt_tokens ?? usage.promptTokens);
  const output = numberValue(usage.output_tokens ?? usage.outputTokens
    ?? usage.completion_tokens ?? usage.completionTokens);
  const parts = Math.max(0, input || 0) + Math.max(0, output || 0);
  if (direct !== null && direct > 0) return direct;
  if (parts > 0) return parts;
  return direct === 0 ? 0 : null;
}

function responseUsageTotal(object) {
  const payload = object?.payload && typeof object.payload === "object" ? object.payload : {};
  const candidates = [
    payload.usage,
    payload.response?.usage,
    payload.result?.usage,
    object?.usage,
    object?.response?.usage,
    object?.result?.usage
  ];
  for (const candidate of candidates) {
    const tokens = usageTokenTotal(candidate);
    if (tokens !== null) return tokens;
  }
  return null;
}

function responseMessageText(object) {
  if (String(object?.type || "") !== "response_item") return "";
  const payload = object?.payload;
  if (!payload || String(payload.type || "") !== "message") return "";
  const role = String(payload.role || "").toLowerCase();
  if (role !== "user" && role !== "assistant") return "";
  if (typeof payload.content === "string") return payload.content;
  if (!Array.isArray(payload.content)) return "";
  return payload.content.map((item) => {
    if (typeof item === "string") return item;
    if (!item || typeof item !== "object") return "";
    return typeof item.text === "string" ? item.text
      : typeof item.input_text === "string" ? item.input_text
        : typeof item.output_text === "string" ? item.output_text : "";
  }).filter(Boolean).join("\n");
}

function legacyEventMessageText(object) {
  if (String(object?.type || "") !== "event_msg") return "";
  const payload = object?.payload;
  const type = String(payload?.type || "").toLowerCase();
  if (type !== "user_message" && type !== "agent_message") return "";
  if (typeof payload.message === "string") return payload.message;
  if (typeof payload.text === "string") return payload.text;
  if (typeof payload.content === "string") return payload.content;
  return "";
}

function estimateTextTokens(value) {
  const characters = [...String(value || "")].filter((character) => !/\s/u.test(character));
  if (!characters.length) return 0;
  let cjk = 0;
  let other = 0;
  for (const character of characters) {
    if (/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(character)) cjk += 1;
    else other += 1;
  }
  return Math.max(1, cjk + Math.ceil(other / 4));
}

/**
 * Prefer Codex cumulative token_count events, then provider response usage.
 * Some custom providers (including OpenAI-compatible DeepSeek gateways) leave
 * both sources at zero; in that case estimate only recorded user/assistant
 * message text and mark the result so the UI never presents it as billing data.
 */
function parseSessionDailyTokenText(text, startMs, endMs) {
  const cumulativeEvents = [];
  const deltaEvents = [];
  const estimatedEvents = [];
  const legacyEstimatedEvents = [];
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!line) continue;
    let object;
    try { object = JSON.parse(line); }
    catch { continue; }
    const timestamp = Date.parse(object.timestamp || "");
    if (!Number.isFinite(timestamp) || timestamp >= endMs) continue;
    const payload = object?.payload;
    const tokenCountEvent = String(object?.type || "") === "event_msg"
      && payload && String(payload.type || "") === "token_count";
    if (tokenCountEvent) {
      const info = payload.info || payload.usage || {};
      const totalUsage = info.total_token_usage || info.totalTokenUsage || info;
      const tokens = usageTokenTotal(totalUsage);
      if (tokens !== null && tokens >= 0) cumulativeEvents.push({ timestamp, tokens });
      continue;
    }
    const responseTokens = responseUsageTotal(object);
    if (responseTokens !== null && responseTokens > 0) {
      deltaEvents.push({ timestamp, tokens: responseTokens });
    }
    const message = responseMessageText(object);
    const estimatedTokens = estimateTextTokens(message);
    if (estimatedTokens > 0) estimatedEvents.push({ timestamp, tokens: estimatedTokens });
    const legacyMessage = legacyEventMessageText(object);
    const legacyEstimatedTokens = estimateTextTokens(legacyMessage);
    if (legacyEstimatedTokens > 0) {
      legacyEstimatedEvents.push({ timestamp, tokens: legacyEstimatedTokens });
    }
  }

  const byDay = new Map();
  if (cumulativeEvents.some((event) => event.tokens > 0)) {
    cumulativeEvents.sort((left, right) => left.timestamp - right.timestamp);
    let previous = null;
    for (const event of cumulativeEvents) {
      if (event.timestamp < startMs) {
        // Keep the latest pre-window counter as the baseline. Unlike a max()
        // baseline this remains correct when a session counter was reset.
        previous = event.tokens;
        continue;
      }
      const delta = previous === null
        ? event.tokens
        : event.tokens >= previous ? event.tokens - previous : event.tokens;
      const date = dayKey(new Date(event.timestamp));
      byDay.set(date, Math.min(Number.MAX_SAFE_INTEGER, (byDay.get(date) || 0) + Math.max(0, delta)));
      previous = event.tokens;
    }
    byDay.estimated = false;
    return byDay;
  }

  // response_item and event_msg often contain the same visible message. Prefer
  // response_item and use legacy event messages only when it is absent.
  const messageEvents = estimatedEvents.length ? estimatedEvents : legacyEstimatedEvents;
  const events = deltaEvents.length ? deltaEvents : messageEvents;
  if (!events.length) return null;
  for (const event of events) {
    if (event.timestamp < startMs) continue;
    const date = dayKey(new Date(event.timestamp));
    byDay.set(date, Math.min(Number.MAX_SAFE_INTEGER, (byDay.get(date) || 0) + event.tokens));
  }
  byDay.estimated = deltaEvents.length === 0;
  return byDay;
}

function parseSessionTodayTokenText(text, startMs, endMs) {
  const byDay = parseSessionDailyTokenText(text, startMs, endMs);
  if (!byDay) return null;
  let total = 0;
  for (const tokens of byDay.values()) total = Math.min(Number.MAX_SAFE_INTEGER, total + tokens);
  return total;
}

async function discoverLocalUsageFiles(root, startMs, lookbackMs = SESSION_USAGE_LOOKBACK_MS) {
  const files = [];
  const visit = async (directory) => {
    let entries;
    try { entries = await fs.promises.readdir(directory, { withFileTypes: true }); }
    catch { return; }
    await Promise.all(entries.map(async (entry) => {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        await visit(file);
        return;
      }
      if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".jsonl") return;
      try {
        const stat = await fs.promises.stat(file);
        // A resumed thread can live in an older date directory; mtime is the
        // reliable way to include it while avoiding reads of old log contents.
        if (stat.mtimeMs >= startMs - lookbackMs) {
          files.push({ file, size: stat.size, modifiedAt: stat.mtimeMs });
        }
      } catch { /* 文件可能在扫描期间被轮换。 */ }
    }));
  };
  await visit(root);
  return files;
}

async function readLocalTodayTokens() {
  const { startMs, endMs } = localUsageBounds();
  const day = resetLocalUsageDay();
  const files = await discoverLocalUsageFiles(codexSessionsRoot(), startMs, SESSION_USAGE_LOOKBACK_MS);
  let total = 0;
  let found = false;
  let estimated = false;
  for (const candidate of files) {
    const cached = localUsageCache.get(candidate.file);
    let usage;
    if (cached
      && cached.day === day
      && cached.size === candidate.size
      && cached.modifiedAt === candidate.modifiedAt) {
      usage = cached.usage;
    } else {
      let text;
      try { text = await fs.promises.readFile(candidate.file, "utf8"); }
      catch { continue; }
      const parsed = parseSessionDailyTokenText(text, startMs, endMs);
      let tokens = null;
      if (parsed) {
        tokens = 0;
        for (const value of parsed.values()) tokens = Math.min(Number.MAX_SAFE_INTEGER, tokens + value);
      }
      usage = tokens === null ? null : { tokens, estimated: parsed.estimated === true };
      localUsageCache.set(candidate.file, {
        day,
        size: candidate.size,
        modifiedAt: candidate.modifiedAt,
        usage
      });
    }
    if (!usage || usage.tokens === null || usage.tokens === undefined) continue;
    found = true;
    total = Math.min(Number.MAX_SAFE_INTEGER, total + Math.max(0, usage.tokens));
    estimated ||= usage.estimated === true;
  }
  // Drop entries for files no longer in the current scan to keep long-running
  // tray processes bounded when sessions are rotated or deleted.
  const currentPaths = new Set(files.map((candidate) => candidate.file));
  for (const file of localUsageCache.keys()) {
    if (!currentPaths.has(file)) localUsageCache.delete(file);
  }
  return found ? { tokens: total, estimated } : null;
}

function localHistoryBounds(reference = new Date()) {
  const end = new Date(reference);
  end.setHours(0, 0, 0, 0);
  end.setDate(end.getDate() + 1);
  const start = new Date(end);
  start.setDate(start.getDate() - 7);
  return { startMs: start.getTime(), endMs: end.getTime(), range: dayKey(start) };
}

async function readLocalDailyTokens(reference = new Date()) {
  const { startMs, endMs, range } = localHistoryBounds(reference);
  const files = await discoverLocalUsageFiles(codexSessionsRoot(), startMs, SESSION_HISTORY_LOOKBACK_MS);
  const byDay = new Map();
  let found = false;
  for (const candidate of files) {
    const cached = localHistoryCache.get(candidate.file);
    let daily;
    if (cached
      && cached.range === range
      && cached.size === candidate.size
      && cached.modifiedAt === candidate.modifiedAt) {
      daily = cached.daily;
    } else {
      let text;
      try { text = await fs.promises.readFile(candidate.file, "utf8"); }
      catch { continue; }
      const parsed = parseSessionDailyTokenText(text, startMs, endMs);
      daily = parsed
        ? [...parsed.entries()].map(([date, tokens]) => ({
            date,
            tokens,
            estimated: parsed.estimated === true
          }))
        : null;
      localHistoryCache.set(candidate.file, {
        range,
        size: candidate.size,
        modifiedAt: candidate.modifiedAt,
        daily
      });
    }
    if (!Array.isArray(daily) || !daily.length) continue;
    found = true;
    for (const bucket of daily) {
      const date = String(bucket?.date || "").slice(0, 10);
      const tokens = Math.max(0, numberValue(bucket?.tokens) || 0);
      if (!date) continue;
      const current = byDay.get(date) || { tokens: 0, estimated: false };
      byDay.set(date, {
        tokens: Math.min(Number.MAX_SAFE_INTEGER, current.tokens + tokens),
        estimated: current.estimated || bucket?.estimated === true
      });
    }
  }
  const currentPaths = new Set(files.map((candidate) => candidate.file));
  for (const file of localHistoryCache.keys()) {
    if (!currentPaths.has(file)) localHistoryCache.delete(file);
  }
  if (!found) return null;
  const result = [];
  for (let offset = 6; offset >= 0; offset -= 1) {
    const date = new Date(reference);
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() - offset);
    const dateString = dayKey(date);
    const bucket = byDay.get(dateString);
    result.push({
      date: dateString,
      tokens: bucket?.tokens || 0,
      estimated: bucket?.estimated === true
    });
  }
  return result;
}

function isCustomModelProvider() {
  const provider = String(state.modelProvider || localSessionSnapshot?.modelProvider || "").trim().toLowerCase();
  return Boolean(provider) && provider !== "openai";
}

function shouldPromoteLocalTodayUsage() {
  const auth = String(state.account?.auth || "");
  return isCustomModelProvider() || (Boolean(auth) && auth !== "—");
}

function shouldPromoteLocalDailyUsage() {
  // Session JSONL does not identify the ChatGPT account. Keep historical local
  // buckets server-scoped for the native OpenAI+ChatGPT combination. API Key
  // and custom providers use the complete local seven-day session history.
  return isCustomModelProvider() || state.account?.auth !== "ChatGPT";
}

function currentAccountIdentity() {
  return `${state.account?.auth || ""}:${state.account?.email || ""}`;
}

async function refreshLocalTodayUsage(force = false) {
  if (localUsageRefreshPromise) return localUsageRefreshPromise;
  if (!force
      && localUsageLastReadAt > 0
      && Date.now() - localUsageLastReadAt < LOCAL_USAGE_MIN_REFRESH_MS) {
    return localUsageLastValue;
  }
  const generation = localUsageGeneration;
  localUsageRefreshPromise = readLocalTodayTokens()
    .then((value) => {
      if (generation !== localUsageGeneration) return null;
      localUsageLastReadAt = Date.now();
      localUsageLastValue = value;
      return value;
    })
    .catch(() => null)
    .finally(() => {
      if (generation === localUsageGeneration) localUsageRefreshPromise = null;
    });
  return localUsageRefreshPromise;
}

async function refreshLocalDailyUsage(force = false) {
  if (localHistoryRefreshPromise) return localHistoryRefreshPromise;
  if (!force
      && localHistoryLastReadAt > 0
      && Date.now() - localHistoryLastReadAt < LOCAL_HISTORY_MIN_REFRESH_MS) {
    return localHistoryLastValue;
  }
  const generation = localUsageGeneration;
  localHistoryRefreshPromise = readLocalDailyTokens()
    .then((value) => {
      if (generation !== localUsageGeneration) return null;
      localHistoryLastReadAt = Date.now();
      localHistoryLastValue = value;
      return value;
    })
    .catch(() => null)
    .finally(() => {
      if (generation === localUsageGeneration) localHistoryRefreshPromise = null;
    });
  return localHistoryRefreshPromise;
}

async function publishLocalTodayUsage(force = false) {
  if (!shouldPromoteLocalTodayUsage()) return;
  const day = resetLocalUsageDay();
  const accountIdentity = currentAccountIdentity();
  const generation = accountGeneration;
  const localToday = await refreshLocalTodayUsage(force);
  // Authentication can change while the filesystem scan is in flight. Recheck
  // before publishing so a ChatGPT account switch cannot receive old logs.
  if (localToday === null
      || generation !== accountGeneration
      || day !== localUsageDayKey
      || accountIdentity !== currentAccountIdentity()
      || !shouldPromoteLocalTodayUsage()) return;
  publish({ usage: mergeLocalTodayUsage(state.usage, localToday) });
}

function mergeSessionConversation(snapshot) {
  const recorded = Array.isArray(snapshot.conversation)
    ? snapshot.conversation.map((message) => ({ ...message }))
    : [];
  const live = state.task?.threadID === snapshot.threadID && Array.isArray(state.task?.conversation)
    ? state.task.conversation[state.task.conversation.length - 1]
    : null;
  if (live?.isStreaming) {
    const index = recorded.findIndex((message) => message.id === live.id);
    if (index >= 0) recorded[index] = { ...live };
    else if (!recorded.some((message) => message.role === live.role
      && (message.text === live.text || message.text.startsWith(live.text)))) {
      recorded.push({ ...live });
    }
  }
  return recorded.slice(-32);
}

function sessionTask(snapshot) {
  const attention = snapshot.state === "attention";
  return {
    state: attention ? "attention" : "working",
    label: attention ? "等待授权" : "思考中",
    title: "Codex 正在处理",
    project: snapshot.cwd ? path.basename(snapshot.cwd) : null,
    startedAt: snapshot.startedAt || snapshot.modifiedAt || Date.now(),
    threadID: snapshot.threadID,
    conversation: mergeSessionConversation(snapshot)
  };
}

function parseSessionFile(file) {
  let stat;
  let fd;
  try {
    stat = fs.statSync(file);
    if (!stat.isFile() || Date.now() - stat.mtimeMs > SESSION_STALE_MS) return null;
    fd = fs.openSync(file, "r");
    const offset = Math.max(0, stat.size - SESSION_TAIL_BYTES);
    const buffer = Buffer.allocUnsafe(stat.size - offset);
    fs.readSync(fd, buffer, 0, buffer.length, offset);
    let text = buffer.toString("utf8");
    if (offset > 0) {
      const newline = text.indexOf("\n");
      text = newline >= 0 ? text.slice(newline + 1) : "";
    }

    let active = false;
    let recognized = false;
    let startedAt = null;
    let runState = "working";
    let cwd = null;
    let modelProvider = null;
    let threadID = path.basename(file, path.extname(file)).slice(-36);
    let conversation = [];
    let messageSequence = 0;

    const appendConversationMessage = (role, rawText, timestamp, fallbackID) => {
      const textValue = String(rawText || "").trim();
      if (!textValue) return;
      const previous = conversation[conversation.length - 1];
      if (previous?.role === role && previous.text === textValue) {
        previous.isStreaming = false;
        return;
      }
      messageSequence += 1;
      conversation.push({
        id: `${fallbackID}-${messageSequence}`,
        role,
        text: textValue.slice(0, 16_000),
        timestamp,
        isStreaming: false
      });
      if (conversation.length > 32) conversation = conversation.slice(-32);
    };

    for (const line of text.split(/\r?\n/)) {
      if (!line) continue;
      let object;
      try { object = JSON.parse(line); }
      catch { continue; }
      const envelope = String(object.type || "").toLowerCase();
      const payload = object.payload && typeof object.payload === "object" ? object.payload : {};
      const payloadType = String(payload.type || "").toLowerCase();
      const timestamp = Date.parse(object.timestamp || "");
      const eventTime = Number.isFinite(timestamp) ? timestamp : null;

      if (envelope === "session_meta") {
        cwd = payload.cwd || cwd;
        modelProvider = payload.model_provider || payload.modelProvider || modelProvider;
        threadID = payload.id || threadID;
        continue;
      }
      if (envelope === "turn_context" || envelope === "compacted") {
        recognized = true;
        active = true;
        startedAt = startedAt || eventTime;
        cwd = payload.cwd || cwd;
        runState = "working";
        continue;
      }
      if (envelope === "event_msg") {
        if (["task_complete", "turn_complete", "turn_completed", "turn_aborted", "turn_failed"].includes(payloadType)) {
          recognized = true;
          active = false;
          startedAt = null;
          runState = "idle";
        } else if (["user_message", "turn_started", "task_started"].includes(payloadType)) {
          recognized = true;
          active = true;
          startedAt = eventTime || startedAt;
          runState = "working";
          if (payloadType === "turn_started" || payloadType === "task_started") conversation = [];
          if (payloadType === "user_message") {
            appendConversationMessage(
              "user",
              payload.message || payload.text || payload.content,
              eventTime,
              "user"
            );
          }
        } else if (["agent_reasoning", "agent_message", "agent_message_content_delta"].includes(payloadType)) {
          recognized = true;
          active = true;
          startedAt = startedAt || eventTime;
          runState = "working";
          if (payloadType === "agent_message") {
            appendConversationMessage(
              "assistant",
              payload.message || payload.text || payload.content,
              eventTime,
              "assistant"
            );
          } else if (payloadType === "agent_message_content_delta") {
            const delta = typeof payload.delta === "string" ? payload.delta : "";
            const itemID = String(payload.item_id || payload.itemId || "streaming-assistant");
            if (delta) {
              const index = conversation.findIndex((message) => message.id === itemID);
              if (index >= 0) {
                conversation[index].text += delta;
                conversation[index].isStreaming = true;
              } else {
                conversation.push({
                  id: itemID,
                  role: "assistant",
                  text: delta,
                  timestamp: eventTime,
                  isStreaming: true
                });
              }
              if (conversation.length > 32) conversation = conversation.slice(-32);
            }
          }
        }
        continue;
      }
      if (envelope !== "response_item") continue;
      if (payloadType === "message") {
        recognized = true;
        const phase = String(payload.phase || "").toLowerCase();
        active = phase !== "final" && phase !== "final_answer";
        startedAt = active ? (startedAt || eventTime) : null;
        runState = active ? "working" : "idle";
        if (String(payload.role || "").toLowerCase() === "assistant") {
          appendConversationMessage(
            "assistant",
            responseMessageText(object),
            eventTime,
            "response"
          );
        }
        continue;
      }
      if (payloadType === "reasoning") {
        recognized = true;
        active = true;
        startedAt = startedAt || eventTime;
        runState = "working";
        continue;
      }
      if (["function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output", "web_search_call", "computer_tool_call", "computer_tool_call_output"].includes(payloadType)) {
        recognized = true;
        active = true;
        startedAt = startedAt || eventTime;
        const toolName = String(payload.name || payload.tool_name || "").toLowerCase();
        const rawInput = typeof payload.arguments === "string" ? payload.arguments
          : typeof payload.input === "string" ? payload.input
            : JSON.stringify(payload.arguments || payload.input || {});
        const input = rawInput.toLowerCase();
        runState = toolName.includes("request_user_input") || input.includes("require_escalated")
          ? "attention"
          : "working";
      }
    }

    // 刚创建的会话可能只有尚未认识的新版事件；短时间内的写入先按活动处理，
    // 后续 final/task_complete 会给出确定的空闲状态。
    if (!recognized) active = Date.now() - stat.mtimeMs <= 10_000;
    return {
      file,
      threadID,
      cwd,
      modelProvider,
      active,
      state: active ? runState : "idle",
      startedAt,
      modifiedAt: stat.mtimeMs,
      size: stat.size,
      conversation
    };
  } catch {
    return null;
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd); } catch { /* 文件可能在关闭前被桌面端轮换。 */ }
    }
  }
}

function applySessionSnapshot(snapshot) {
  if (!snapshot) return;
  const wasActiveFile = localSessionSnapshot?.active && localSessionSnapshot.file === snapshot.file;
  localSessionSnapshot = snapshot;
  if (snapshot.modelProvider && snapshot.modelProvider !== state.modelProvider) {
    publish({ modelProvider: snapshot.modelProvider });
  }
  if (snapshot.active) {
    publish({ task: sessionTask(snapshot) });
  } else if (wasActiveFile || (state.task.state !== "idle" && Date.now() - snapshot.modifiedAt < 10_000)) {
    publish({ task: { state: "idle", label: "空闲", title: null, project: null, startedAt: null, threadID: null, conversation: [] } });
  }
}

async function discoverSessionCandidates(full = false) {
  const root = codexSessionsRoot();
  const roots = [];
  if (full) {
    roots.push(root);
  } else {
    const now = new Date();
    for (const offset of [0, -1]) {
      const date = new Date(now);
      date.setDate(now.getDate() + offset);
      roots.push(path.join(
        root,
        String(date.getFullYear()).padStart(4, "0"),
        String(date.getMonth() + 1).padStart(2, "0"),
        String(date.getDate()).padStart(2, "0")
      ));
    }
  }

  const visit = async (directory) => {
    let entries;
    try { entries = await fs.promises.readdir(directory, { withFileTypes: true }); }
    catch { return; }
    await Promise.all(entries.map(async (entry) => {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (full) await visit(file);
        return;
      }
      if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".jsonl") return;
      try {
        const stat = await fs.promises.stat(file);
        if (Date.now() - stat.mtimeMs <= SESSION_STALE_MS) {
          const cached = sessionCandidates.get(file);
          const snapshot = cached?.size === stat.size && cached?.modifiedAt === stat.mtimeMs
            ? cached.snapshot
            : null;
          sessionCandidates.set(file, { size: stat.size, modifiedAt: stat.mtimeMs, snapshot });
        }
      } catch { /* 会话文件可能刚好被轮换。 */ }
    }));
  };
  await Promise.all(roots.map(visit));
}

async function refreshLocalSessionState(paths = null) {
  const previousActiveFile = localSessionSnapshot?.active ? localSessionSnapshot.file : null;
  const targets = paths?.length
    ? paths
    : [...sessionCandidates.entries()]
      .sort((a, b) => b[1].modifiedAt - a[1].modifiedAt)
      .slice(0, 32)
      .map(([file]) => file);
  const snapshots = [];
  for (const file of targets) {
    const snapshot = parseSessionFile(file);
    if (!snapshot) {
      sessionCandidates.delete(file);
      continue;
    }
    sessionCandidates.set(file, { size: snapshot.size, modifiedAt: snapshot.modifiedAt, snapshot });
    snapshots.push(snapshot);
  }
  const knownSnapshots = [...sessionCandidates.values()].map((item) => item.snapshot).filter(Boolean);
  const active = knownSnapshots.filter((item) => item.active).sort((a, b) => b.modifiedAt - a.modifiedAt)[0];
  if (active) applySessionSnapshot(active);
  else if (snapshots.length) {
    const completedActive = snapshots.find((item) => item.file === previousActiveFile && !item.active);
    applySessionSnapshot(completedActive || snapshots.sort((a, b) => b.modifiedAt - a.modifiedAt)[0]);
  }
}

function scheduleSessionRefresh(file = null) {
  if (file && path.extname(file).toLowerCase() === ".jsonl") pendingSessionPaths.add(file);
  clearTimeout(sessionRefreshTimer);
  sessionRefreshTimer = setTimeout(async () => {
    const paths = [...pendingSessionPaths];
    pendingSessionPaths.clear();
    if (!paths.length) await discoverSessionCandidates(false);
    await refreshLocalSessionState(paths.length ? paths : null);
    // Session writes are the fastest signal for API-key usage; do not wait for
    // the next remote profile refresh to update today's local aggregate.
    await publishLocalTodayUsage();
  }, 45);
}

async function pollSessionCandidates() {
  const recent = [...sessionCandidates.entries()]
    .sort((a, b) => b[1].modifiedAt - a[1].modifiedAt)
    .slice(0, 16);
  const changed = [];
  await Promise.all(recent.map(async ([file, cached]) => {
    try {
      const stat = await fs.promises.stat(file);
      if (stat.size !== cached.size || stat.mtimeMs !== cached.modifiedAt) changed.push(file);
    } catch { sessionCandidates.delete(file); }
  }));
  if (changed.length) {
    await refreshLocalSessionState(changed);
    await publishLocalTodayUsage();
  }
}

function stopSessionMonitoring() {
  if (sessionWatcher) sessionWatcher.close();
  sessionWatcher = null;
  clearInterval(sessionPollTimer);
  clearInterval(sessionRescanTimer);
  clearTimeout(sessionRefreshTimer);
  sessionPollTimer = null;
  sessionRescanTimer = null;
  sessionRefreshTimer = null;
  pendingSessionPaths.clear();
  sessionCandidates.clear();
  localSessionSnapshot = null;
  // CODEX_HOME or account transitions can replace the session tree; never
  // reuse a cached aggregate from the previous process/account context.
  localUsageCache.clear();
  localHistoryCache.clear();
  localUsageDayKey = null;
  localUsageGeneration += 1;
  localUsageRefreshPromise = null;
  localHistoryRefreshPromise = null;
  localUsageLastReadAt = 0;
  localUsageLastValue = null;
  localHistoryLastReadAt = 0;
  localHistoryLastValue = null;
}

async function startSessionMonitoring() {
  stopSessionMonitoring();
  const root = codexSessionsRoot();
  await discoverSessionCandidates(true);
  await refreshLocalSessionState();
  try {
    sessionWatcher = fs.watch(root, { recursive: true }, (_event, filename) => {
      const relative = filename ? String(filename) : "";
      scheduleSessionRefresh(relative ? path.join(root, relative) : null);
    });
    sessionWatcher.on("error", () => {
      if (sessionWatcher) sessionWatcher.close();
      sessionWatcher = null;
    });
  } catch { sessionWatcher = null; }
  // Windows 偶尔会合并 ReadDirectoryChangesW 事件；只检查少量候选文件作为兜底，
  // 不触发任何 app-server 或额度网络请求。
  const pollInterval = sessionWatcher ? 750 : 350;
  const rescanInterval = sessionWatcher ? 5_000 : 2_000;
  sessionPollTimer = setInterval(() => { void pollSessionCandidates(); }, pollInterval);
  sessionRescanTimer = setInterval(async () => {
    await discoverSessionCandidates(false);
    await pollSessionCandidates();
  }, rescanInterval);
}

function decodeJWTClaims(token) {
  try {
    const part = String(token || "").split(".")[1];
    if (!part) return {};
    return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
  } catch { return {}; }
}

function shortSecretHash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 20);
}

function readAuthIdentity() {
  const authPath = path.join(codexHomeRoot(), "auth.json");
  if (!exists(authPath)) return "none";
  try {
    const root = JSON.parse(fs.readFileSync(authPath, "utf8"));
    const apiKey = root.OPENAI_API_KEY || root.openai_api_key || root.apiKey;
    if (apiKey) return `api:${shortSecretHash(apiKey)}`;
    const tokens = root.tokens && typeof root.tokens === "object" ? root.tokens : {};
    const accessToken = tokens.access_token || tokens.accessToken || "";
    const claims = decodeJWTClaims(accessToken);
    const openAIAuth = claims["https://api.openai.com/auth"] || {};
    const accountID = tokens.account_id || tokens.accountId
      || openAIAuth.chatgpt_account_id || openAIAuth.account_id
      || claims.chatgpt_account_id || claims.account_id;
    const userID = openAIAuth.user_id || claims.user_id || claims.sub;
    const email = claims.email;
    if (accountID || userID || email) return `chatgpt:${accountID || ""}:${userID || ""}:${email || ""}`;
    if (accessToken) return `chatgpt-token:${shortSecretHash(accessToken)}`;
    return `mode:${root.auth_mode || root.authMode || "none"}`;
  } catch {
    // 写入中的临时半文件不应被误判成登出，等待下一次文件事件。
    return null;
  }
}

function checkAuthIdentity() {
  const next = readAuthIdentity();
  if (next === null) return;
  if (authIdentity === null) {
    authIdentity = next;
    return;
  }
  if (next === authIdentity) return;
  authIdentity = next;
  scheduleAccountTransition(true);
}

function scheduleAuthIdentityCheck() {
  clearTimeout(authChangeTimer);
  authChangeTimer = setTimeout(checkAuthIdentity, 140);
}

function stopAuthMonitoring() {
  if (authWatcher) authWatcher.close();
  authWatcher = null;
  clearInterval(authPollTimer);
  clearTimeout(authChangeTimer);
  clearTimeout(accountTransitionTimer);
  authPollTimer = null;
  authChangeTimer = null;
  accountTransitionTimer = null;
  authIdentity = null;
  pendingAccountRestart = false;
}

function startAuthMonitoring() {
  stopAuthMonitoring();
  const home = codexHomeRoot();
  authIdentity = readAuthIdentity();
  try {
    authWatcher = fs.watch(home, (_event, filename) => {
      if (!filename || String(filename).toLowerCase() === "auth.json") scheduleAuthIdentityCheck();
    });
    authWatcher.on("error", () => {
      if (authWatcher) authWatcher.close();
      authWatcher = null;
    });
  } catch { authWatcher = null; }
  // 原子替换 auth.json 时 Windows 可能只报告 rename；低频身份比较作为兜底，
  // 只读取账号标识，不请求网络，也不保存 access token。
  authPollTimer = setInterval(checkAuthIdentity, 800);
}

function scheduleAccountTransition(restartRPC) {
  if (accountReloadInFlight && !restartRPC) return;
  pendingAccountRestart = pendingAccountRestart || restartRPC;
  clearTimeout(accountTransitionTimer);
  accountTransitionTimer = setTimeout(() => {
    const restart = pendingAccountRestart;
    pendingAccountRestart = false;
    void performAccountTransition(restart);
  }, 120);
}

async function performAccountTransition(restartRPC) {
  if (accountReloadInFlight) {
    pendingAccountRestart = pendingAccountRestart || restartRPC;
    return;
  }
  accountReloadInFlight = true;
  accountGeneration += 1;
  clearTimeout(refreshTimer);
  const cliPath = state.cliPath;
  publish({
    account: { email: null, maskedEmail: "—", plan: "—", auth: "—" },
    limits: [],
    resetCards: [],
    usage: normalizeUsage({}),
    message: "检测到 Codex 账号切换，正在同步新账号…"
  });

  try {
    if (restartRPC) {
      ++connectionAttempt;
      if (rpc) rpc.close();
      rpc = new CodexRPC(cliPath);
      await withTimeout(rpc.connect(), 14_000, "切换账号后重新连接 Codex 超时");
    }
    if (!rpc) throw new Error("Codex 未连接");
    // 必须先确认账号身份，再并行读取所有账号专属数据。
    await refreshAccount();
    await Promise.allSettled([refreshLimits(), refreshUsage(), refreshThreads()]);
    publish({ connection: "connected", message: "已连接" });
    armRefreshLoop();
  } catch (error) {
    if (rpc) rpc.close();
    rpc = null;
    publish({ connection: "error", message: `账号切换同步失败：${error.message}` });
    setTimeout(() => { if (!rpc) void connect(); }, 600);
  } finally {
    accountReloadInFlight = false;
    if (pendingAccountRestart) scheduleAccountTransition(true);
  }
}

function threadStatus(thread) {
  const statusObject = typeof thread.status === "object" ? thread.status : {};
  const status = String(statusObject.type || statusObject.status || thread.status || "").toLowerCase();
  const flags = (statusObject.activeFlags || thread.activeFlags || []).map((item) => String(item).toLowerCase());
  if (flags.some((flag) => flag.includes("approval") || flag.includes("input") || flag.includes("permission"))) return "attention";
  if (["active", "running", "inprogress", "in_progress", "working"].some((value) => status.includes(value))) return "working";
  if (flags.length) return "working";
  return "idle";
}

function normalizeTask(result) {
  const threads = result.data || result.threads || [];
  const active = threads.find((thread) => threadStatus(thread) !== "idle");
  if (!active) return { state: "idle", label: "空闲", title: null, project: null, startedAt: null };
  const mode = threadStatus(active);
  const cwd = active.cwd?.value || active.cwd || "";
  return {
    state: mode,
    label: mode === "attention" ? "等待授权" : "思考中",
    title: active.name || active.preview || "Codex 正在处理",
    project: cwd ? path.basename(cwd) : null,
    startedAt: (numberValue(active.createdAt) || numberValue(active.updatedAt) || Date.now() / 1000) * 1000
  };
}

async function refreshAccount() {
  if (!rpc) return;
  try {
    const account = normalizeAccount(await rpc.request("account/read", { refreshToken: false }));
    const previousIdentity = `${state.account?.auth || ""}:${state.account?.email || ""}`;
    const nextIdentity = `${account.auth || ""}:${account.email || ""}`;
    // "—" is the startup placeholder; every other auth value represents a
    // previously observed account state, including an explicit logout.
    const hadKnownAccount = Boolean(state.account?.auth) && state.account.auth !== "—";
    const changed = hadKnownAccount && previousIdentity !== nextIdentity;
    if (changed) accountGeneration += 1;
    publish(changed
      ? { account, limits: [], resetCards: [], usage: normalizeUsage({}) }
      : { account });
  }
  catch (error) { publish({ message: error.message }); }
}

async function refreshLimits() {
  if (!rpc) return;
  try {
    const normalized = normalizeLimits(await rpc.request("account/rateLimits/read", {}, 25000));
    publish({ limits: normalized.limits, resetCards: normalized.cards });
  } catch (error) { publish({ message: `额度刷新失败：${error.message}` }); }
}

async function refreshUsage() {
  const refreshDay = resetLocalUsageDay();
  const accountIdentity = currentAccountIdentity();
  const generation = accountGeneration;
  if (!rpc) {
    const [localToday, localDaily] = await Promise.all([
      refreshLocalTodayUsage(true),
      refreshLocalDailyUsage(false)
    ]);
    if (generation !== accountGeneration
        || refreshDay !== localUsageDayKey
        || accountIdentity !== currentAccountIdentity()) return;
    publish({
      usage: mergeLocalSessionFallback(state.usage, localToday, localDaily)
    });
    return;
  }
  let usage;
  let remoteUsageFailed = false;
  try {
    usage = normalizeUsage(await rpc.request("account/usage/read", {}, 25000));
  } catch (error) {
    remoteUsageFailed = true;
    // Keep the last account-scoped snapshot during a transient RPC failure;
    // account transitions clear it before requesting the new account.
    usage = state.usage && typeof state.usage === "object"
      ? state.usage
      : normalizeUsage({});
    publish({ message: `Token 刷新失败：${error.message}` });
  }

  // API Key accounts usually return no ChatGPT activity buckets. Merge the
  // complete local-session history so the 7-day chart remains useful in that
  // mode. The separate today reader remains the authoritative fast path for
  // the headline while the history reader fills all seven buckets.
  if (remoteUsageFailed) {
    const [localToday, localDaily] = await Promise.all([
      refreshLocalTodayUsage(true),
      refreshLocalDailyUsage(false)
    ]);
    if (generation === accountGeneration
        && accountIdentity === currentAccountIdentity()) {
      usage = mergeLocalSessionFallback(usage, localToday, localDaily);
    }
  } else if (shouldPromoteLocalTodayUsage()) {
    const [localToday, localDaily] = await Promise.all([
      refreshLocalTodayUsage(true),
      shouldPromoteLocalDailyUsage() ? refreshLocalDailyUsage(true) : Promise.resolve(null)
    ]);
    if (generation === accountGeneration
        && accountIdentity === currentAccountIdentity()
        && shouldPromoteLocalTodayUsage()) {
      if (localToday !== null) usage = mergeLocalTodayUsage(usage, localToday);
      if (localDaily !== null && shouldPromoteLocalDailyUsage()) {
        usage = mergeLocalDailyUsage(usage, localDaily);
      }
    }
  }
  if (generation !== accountGeneration
      || refreshDay !== localUsageDayKey
      || accountIdentity !== currentAccountIdentity()) return;
  publish({ usage });
}

async function refreshThreads() {
  if (!rpc) return;
  try {
    const remoteTask = normalizeTask(await rpc.request("thread/list", { limit: 30, archived: false }, 5000));
    let task = remoteTask;
    if (localSessionSnapshot?.active) {
      task = sessionTask(localSessionSnapshot);
    } else if (localSessionSnapshot && Date.now() - localSessionSnapshot.modifiedAt < 10_000) {
      // final_answer/task_complete 比独立 app-server 的 thread/list 更新更及时。
      task = { state: "idle", label: "空闲", title: null, project: null, startedAt: null, threadID: null, conversation: [] };
    }
    publish({ task });
  }
  catch { /* 通知通道仍可维持即时状态，轮询失败不覆盖当前状态。 */ }
}

async function refreshAll(forceUsage = false) {
  if (!rpc) return;
  // Usage promotion depends on the authenticated account mode. Resolve the
  // account before starting the parallel profile requests so an API Key switch
  // cannot race with a stale "—" auth value.
  await refreshAccount();
  await Promise.allSettled([
    refreshLimits(),
    refreshThreads(),
    forceUsage ? refreshUsage() : Promise.resolve()
  ]);
  // 天气与 Codex RPC 无关；手动刷新面板时一并刷新已启用的信息栏。
  if (state.informationBar?.enabled) await refreshWeather(true);
}

function armRefreshLoop() {
  clearTimeout(refreshTimer);
  const tick = async () => {
    // Keep the displayed "today" bucket correct even when no session file is
    // written around midnight.
    resetLocalUsageDay();
    await refreshThreads();
    const active = state.task.state === "working" || state.task.state === "attention";
    const now = Date.now();
    const limitsInterval = active ? 3_000 : 8_000;
    const usageInterval = active ? 5_000 : 12_000;
    if (!limitsRefreshInFlight && now - lastLimitsRefreshAt >= limitsInterval) {
      limitsRefreshInFlight = true;
      lastLimitsRefreshAt = now;
      void refreshLimits().finally(() => { limitsRefreshInFlight = false; });
    }
    if (!usageRefreshInFlight && now - lastUsageRefreshAt >= usageInterval) {
      usageRefreshInFlight = true;
      lastUsageRefreshAt = now;
      void refreshUsage().finally(() => { usageRefreshInFlight = false; });
    }
    // Local session writes remain event-driven (typically < 1s). This loop is
    // the remote quota/usage fallback and task-state safety net.
    refreshTimer = setTimeout(tick, active ? 500 : 1_500);
  };
  refreshTimer = setTimeout(tick, 500);
}

async function connect(customPath) {
  const attempt = ++connectionAttempt;
  clearTimeout(refreshTimer);
  stopAuthMonitoring();
  stopSessionMonitoring();
  if (rpc) rpc.close();
  rpc = null;
  publish({ connection: "discovering", message: "正在自动获取 Codex 路径…" });
  let cliPath;
  try {
    if (customPath) {
      const preparedPath = process.platform === "win32"
        ? await stageDesktopCodex(customPath)
        : customPath;
      const usable = await withTimeout(probeCodexCLI(preparedPath), 7_000, "验证 Codex 路径超时");
      if (!usable) throw new Error("所选文件不是可用的 Codex CLI，或不支持 app-server");
      cliPath = preparedPath;
    } else {
      cliPath = await withTimeout(findCodexCLI(), 20_000, "自动获取 Codex 桌面引擎路径超时");
    }
  } catch (error) {
    if (attempt === connectionAttempt) {
      publish({ connection: "missing", cliPath: null, message: error.message });
    }
    return;
  }
  if (attempt !== connectionAttempt) return;
  if (!cliPath) {
    publish({ connection: "missing", cliPath: null, message: "自动获取失败，请先打开 Codex/ChatGPT 桌面版；也支持已安装的 Codex CLI" });
    return;
  }
  publish({ connection: "connecting", cliPath, message: "已获取路径，正在连接 Codex…" });
  try {
    rpc = new CodexRPC(cliPath);
    await withTimeout(rpc.connect(), 14_000, "连接 Codex 超时");
    if (attempt !== connectionAttempt) {
      rpc.close();
      return;
    }
    // 每个 Windows 用户独立保存自动发现结果；路径变化时“获取路径”会清除并重扫。
    writeSettings({ codexPath: cliPath });
    const version = await execCodexText(cliPath, ["--version"]);
    publish({ connection: "connected", cliPath, cliVersion: version || null, message: "已连接" });
    startAuthMonitoring();
    await startSessionMonitoring();
    await refreshAll(true);
    // Populate local 7-day buckets immediately on startup; do not wait for the
    // next session write/watch event before drawing the API Key history chart.
    await publishLocalTodayUsage();
    lastLimitsRefreshAt = Date.now();
    lastUsageRefreshAt = Date.now();
    armRefreshLoop();
  } catch (error) {
    if (attempt !== connectionAttempt) return;
    if (rpc) rpc.close();
    rpc = null;
    const message = String(error?.message || error);
    const invalidLauncher = /\b(?:EINVAL|ENOENT)\b/i.test(message);
    if (invalidLauncher) writeSettings({ codexPath: null });
    publish({
      connection: "error",
      cliPath: invalidLauncher ? null : cliPath,
      message: invalidLauncher
        ? "发现的 Codex 命令无法启动，已排除该路径，请点击获取路径重新检测"
        : `连接失败：${message}`
    });
  }
}

function resizeWindow(mode) {
  if (!windowRef || windowRef.isDestroyed()) return null;
  if (codexDockAttached
      || codexDockTransition !== "idle"
      || currentWindowLayoutMode === "codex-dock") {
    return windowRef.getBounds();
  }
  const adaptiveRequest = mode && typeof mode === "object";
  const resolvedMode = adaptiveRequest ? mode.mode : mode;
  const informationLayout = adaptiveRequest && resolvedMode === "collapsed"
    ? mode.informationEnabled === true
    : state.informationBar?.enabled === true;
  if (adaptiveRequest && resolvedMode === "collapsed") {
    const requestedWidth = Number(mode.width);
    if (Number.isFinite(requestedWidth)) {
      // Renderer owns the current visual layout. During an information-bar
      // toggle its state can arrive one IPC turn before the published main
      // state, so use the explicit layout flag instead of rejecting the width.
      if (informationLayout) {
        informationCollapsedWidth = Math.max(
          INFORMATION_MIN_WIDTH,
          Math.min(INFORMATION_MAX_WIDTH, Math.round(requestedWidth))
        );
      } else {
        collapsedWidth = Math.max(
          COLLAPSED_MIN_WIDTH,
          Math.min(COLLAPSED_MAX_WIDTH, Math.round(requestedWidth))
        );
      }
    }
  }
  const mini = resolvedMode === "mini";
  const expanded = resolvedMode === true || resolvedMode === "expanded";
  const wasMini = currentWindowLayoutMode === "mini";
  const requestedPetScale = adaptiveRequest ? Number(mode.petScale) : 1;
  const petScale = Number.isFinite(requestedPetScale)
    ? Math.max(1, Math.min(10, requestedPetScale))
    : 1;
  const miniSceneHeight = adaptiveRequest && mode.petCharacter === "black_hole"
    ? 184
    : 129.6;
  const miniSize = {
    width: Math.ceil(216 * petScale + 24),
    height: Math.ceil(miniSceneHeight * petScale + 24)
  };
  const miniConversationExpanded = mini
    && adaptiveRequest
    && mode.conversationExpanded === true;
  const miniConversationSize = {
    width: Math.max(EXPANDED_SIZE.width, miniSize.width),
    // Pet scene + 8px separation + 246px conversation surface + stage inset.
    height: Math.max(
      miniSize.height,
      Math.ceil(miniSceneHeight * petScale + 8 + 246 + 24)
    )
  };
  const informationSize = { ...INFORMATION_COLLAPSED_SIZE, width: informationCollapsedWidth };
  // Full and collapsed modes share the stable DirectComposition surface. Mini
  // mode follows the token-grown pet envelope so a 10x companion is never
  // clipped; setShape still limits interaction to the visible pet.
  const target = mini
    ? (miniConversationExpanded ? miniConversationSize : miniSize)
    : USE_STABLE_DESKTOP_SURFACE
    ? EXPANDED_SIZE
    : expanded
    ? { ...EXPANDED_SIZE, width: state.informationBar?.enabled ? Math.max(INFORMATION_COLLAPSED_SIZE.width, informationCollapsedWidth) : EXPANDED_SIZE.width }
    : informationLayout ? informationSize : { ...COLLAPSED_SIZE, width: collapsedWidth };
  const old = windowRef.getBounds();
  currentWindowLayoutMode = mini ? "mini" : expanded ? "expanded" : "collapsed";
  if (old.width === target.width && old.height === target.height) return old;
  const display = screen.getDisplayMatching(old).workArea;
  const usesLeftEdgeAnchor = adaptiveRequest && resolvedMode === "collapsed";
  const usesRightEdgeAnchor = !usesLeftEdgeAnchor && (
    mini || wasMini || old.width <= 100
  );
  const preferredX = usesLeftEdgeAnchor
    ? old.x
    : usesRightEdgeAnchor
    ? old.x + old.width - target.width
    : Math.round(old.x + old.width / 2 - target.width / 2);
  const x = Math.min(display.x + display.width - target.width, Math.max(display.x, preferredX));
  // 详情只能从胶囊下方展开，不能为了让卡片完全留在屏内而移动胶囊本身。
  const y = old.y;
  // Windows 的透明无边框窗口在系统级尺寸动画期间会重复重绘整张纹理。
  // 立即调整透明窗口边界，展开/收起动效只交给 renderer 的 transform/opacity。
  windowRef.setBounds({ x, y, ...target }, false);
  if (USE_STABLE_DESKTOP_SURFACE && old.width <= MINI_SIZE.width) {
    // One-time migration for a window created by an older build that still
    // used an 88px native mini surface. New transitions never enter this path.
    const fullTargetShape = [{ x: 0, y: 0, width: target.width, height: target.height }];
    windowShapeBounds = unionShapeBounds(fullTargetShape);
    windowShapeSignature = JSON.stringify(fullTargetShape);
    windowRef.setShape(fullTargetShape);
  }
  return windowRef.getBounds();
}

function unionShapeBounds(rects) {
  if (!Array.isArray(rects) || !rects.length) return null;
  const left = Math.min(...rects.map((rect) => rect.x));
  const top = Math.min(...rects.map((rect) => rect.y));
  const right = Math.max(...rects.map((rect) => rect.x + rect.width));
  const bottom = Math.max(...rects.map((rect) => rect.y + rect.height));
  return { x: left, y: top, width: right - left, height: bottom - top };
}

function clampWindowPositionToVisibleShape(wantedX, wantedY, area, windowBounds, shapeBounds) {
  const visible = shapeBounds || { x: 0, y: 0, width: windowBounds.width, height: windowBounds.height };
  const minX = area.x - visible.x;
  const minY = area.y - visible.y;
  const maxX = area.x + area.width - visible.x - visible.width;
  const maxY = area.y + area.height - visible.y - visible.height;
  return {
    x: Math.min(maxX, Math.max(minX, wantedX)),
    y: Math.min(maxY, Math.max(minY, wantedY))
  };
}

function cancelPetRoamAnimation() {
  petRoamGeneration += 1;
  clearTimeout(petRoamTimer);
  petRoamTimer = null;
  if (petRoamResolve) {
    const resolve = petRoamResolve;
    petRoamResolve = null;
    resolve({ cancelled: true });
  }
}

function nativeWindowCoordinate(value, fallback = 0) {
  const numeric = Number(value);
  const fallbackNumeric = Number(fallback);
  const rounded = Math.round(
    Number.isFinite(numeric)
      ? numeric
      : Number.isFinite(fallbackNumeric) ? fallbackNumeric : 0
  );
  // Math.round(-0.4) is JavaScript -0. Electron's Windows native converter
  // rejects that value for BrowserWindow.setPosition even though it prints as
  // zero. Normalize it and keep every coordinate inside the signed Win32 range.
  if (Object.is(rounded, -0)) return 0;
  return Math.max(-2147483648, Math.min(2147483647, rounded));
}

function inferredTaskbarEdge(area, full) {
  const gaps = {
    top: Math.max(0, area.y - full.y),
    bottom: Math.max(0, full.y + full.height - area.y - area.height),
    left: Math.max(0, area.x - full.x),
    right: Math.max(0, full.x + full.width - area.x - area.width)
  };
  const rankedEdges = Object.entries(gaps)
    .sort((left, right) => right[1] - left[1]);
  return Number(rankedEdges[0]?.[1]) > 8
    ? rankedEdges[0][0]
    : "bottom";
}

function planPetRoam(options = {}) {
  if (!windowRef || windowRef.isDestroyed() || dragState) return null;
  const bounds = windowRef.getBounds();
  const visible = USE_STABLE_DESKTOP_SURFACE && windowShapeBounds
    ? windowShapeBounds
    : { x: 0, y: 0, width: bounds.width, height: bounds.height };
  const visibleCenter = {
    x: bounds.x + visible.x + visible.width / 2,
    y: bounds.y + visible.y + visible.height / 2
  };
  const display = screen.getDisplayNearestPoint(visibleCenter);
  const area = display.workArea;
  const full = display.bounds;
  const forceInteraction = options?.forceInteraction === true;
  const roll = Math.random();
  const kind = forceInteraction
    ? (Math.random() < .56 ? "desktop" : "dock")
    : roll < .38
    ? "desktop"
    : roll < .66
    ? "dock"
    : "wander";

  if (kind !== "wander") {
    let targetCenter;
    let clampArea = area;
    if (kind === "desktop") {
      // Windows normally lays desktop icons down the left edge. Position the
      // visible pet just to the right of a grid slot without reading user files
      // or requesting accessibility/screen-capture permissions.
      const slotCount = Math.max(1, Math.min(7, Math.floor((area.height - 96) / 74)));
      const slot = Math.floor(Math.random() * slotCount);
      const iconCenter = {
        x: area.x + 42,
        y: area.y + 50 + slot * 74
      };
      targetCenter = {
        x: iconCenter.x + Math.min(92, visible.width * .42),
        y: iconCenter.y + 8
      };
    } else {
      // Infer the taskbar edge from the display/work-area gap and sit the pet
      // immediately above or beside one of the taskbar icons.
      const taskbarEdge = inferredTaskbarEdge(area, full);
      const slotOffset = (Math.floor(Math.random() * 7) - 3) * 54;
      clampArea = full;
      if (taskbarEdge === "top") {
        targetCenter = {
          x: area.x + area.width / 2 + slotOffset,
          y: area.y + visible.height * .33
        };
      } else if (taskbarEdge === "left") {
        targetCenter = {
          x: area.x + visible.width * .34,
          y: area.y + area.height / 2 + slotOffset
        };
      } else if (taskbarEdge === "right") {
        targetCenter = {
          x: area.x + area.width - visible.width * .34,
          y: area.y + area.height / 2 + slotOffset
        };
      } else {
        targetCenter = {
          x: area.x + area.width / 2 + slotOffset,
          y: area.y + area.height - visible.height * .30
        };
      }
    }
    const target = clampWindowPositionToVisibleShape(
      targetCenter.x - visible.x - visible.width / 2,
      targetCenter.y - visible.y - visible.height / 2,
      clampArea,
      bounds,
      visible
    );
    const horizontalDelta = target.x - bounds.x;
    return {
      x: Math.round(target.x),
      y: Math.round(target.y),
      direction: horizontalDelta < 0 ? "left" : "right",
      distance: Math.round(Math.hypot(horizontalDelta, target.y - bounds.y)),
      kind
    };
  }

  const distance = 150 + Math.random() * 150;
  const preferredDirection = Math.random() < 0.5 ? -1 : 1;
  const candidates = [preferredDirection, -preferredDirection].map((direction) => {
    const desiredX = bounds.x + direction * distance;
    const desiredY = bounds.y + (Math.random() - 0.5) * 56;
    const target = clampWindowPositionToVisibleShape(
      desiredX,
      desiredY,
      area,
      bounds,
      visible
    );
    return {
      x: Math.round(target.x),
      y: Math.round(target.y),
      direction,
      horizontalDistance: Math.abs(target.x - bounds.x),
      distance: Math.hypot(target.x - bounds.x, target.y - bounds.y)
    };
  });
  const plan = candidates.sort(
    (left, right) => right.horizontalDistance - left.horizontalDistance
  )[0];
  if (!plan || plan.horizontalDistance < 100) return null;
  return {
    x: plan.x,
    y: plan.y,
    direction: plan.direction < 0 ? "left" : "right",
    distance: Math.round(plan.distance),
    kind: "wander"
  };
}

function runPetRoam(plan) {
  cancelPetRoamAnimation();
  if (!windowRef || windowRef.isDestroyed() || dragState) {
    return Promise.resolve({ cancelled: true });
  }
  const generation = petRoamGeneration;
  const from = windowRef.getBounds();
  const x = Number(plan?.x);
  const y = Number(plan?.y);
  const duration = Math.max(1.5, Math.min(8.5, Number(plan?.duration) || 2.4));
  const arcHeight = Math.max(0, Math.min(24, Number(plan?.arcHeight) || 0));
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    return Promise.resolve({ cancelled: true });
  }
  const startedAt = performance.now();
  let lastPositionX = from.x;
  let lastPositionY = from.y;
  return new Promise((resolve) => {
    petRoamResolve = resolve;
    const finish = (cancelled) => {
      if (petRoamResolve !== resolve) return;
      petRoamResolve = null;
      if (generation === petRoamGeneration) petRoamTimer = null;
      resolve({ cancelled });
    };
    const step = () => {
      if (generation !== petRoamGeneration
          || dragState
          || !windowRef
          || windowRef.isDestroyed()) {
        finish(true);
        return;
      }
      const progress = Math.min(1, (performance.now() - startedAt) / (duration * 1000));
      // A cosine ease keeps the first and last paw contacts planted without
      // producing the abrupt "window sliding" start/stop seen previously.
      const eased = 0.5 - Math.cos(Math.PI * progress) / 2;
      const nextX = nativeWindowCoordinate(
        from.x + (x - from.x) * eased,
        lastPositionX
      );
      // Windows screen coordinates grow downward, so subtract the shallow
      // species-specific arc to lift the companion between foot contacts.
      const arc = Math.sin(Math.PI * progress) * arcHeight;
      const nextY = nativeWindowCoordinate(
        from.y + (y - from.y) * eased - arc,
        lastPositionY
      );
      if (nextX !== lastPositionX || nextY !== lastPositionY) {
        try {
          windowRef.setPosition(nextX, nextY, false);
          publishBlackHoleCaptureGeometry({
            ...windowRef.getContentBounds(),
            x: nextX,
            y: nextY
          });
        } catch {
          // Roaming is decorative. Display topology can change while a step is
          // in flight, so cancel this walk instead of surfacing a main-process
          // JavaScript error or leaving the renderer waiting indefinitely.
          finish(true);
          return;
        }
        lastPositionX = nextX;
        lastPositionY = nextY;
      }
      if (progress >= 1) {
        finish(false);
        return;
      }
      petRoamTimer = setTimeout(step, 1000 / 60);
    };
    step();
  });
}

function startCodexWindowWatcher() {
  if (process.platform !== "win32"
      || codexWindowWatcher
      || !windowRef
      || windowRef.isDestroyed()) return;
  const script = [
    "$ErrorActionPreference = 'SilentlyContinue';",
    "$packageRoots = @(Get-AppxPackage | Where-Object { $_.Name -match '(?i)(openai|codex|chatgpt)' } | ForEach-Object { $_.InstallLocation } | Where-Object { $_ });",
    "$localRoots = @((Join-Path $env:LOCALAPPDATA 'Programs\\Codex'), (Join-Path $env:LOCALAPPDATA 'Programs\\ChatGPT'), (Join-Path $env:LOCALAPPDATA 'OpenAI')) | Where-Object { Test-Path $_ };",
    "$knownRoots = @($packageRoots + $localRoots) | Select-Object -Unique;",
    "Add-Type -TypeDefinition @'",
    "using System;",
    "using System.Runtime.InteropServices;",
    "public static class PulseWindowRect {",
    "  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }",
    "  [DllImport(\"user32.dll\")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);",
    "  [DllImport(\"user32.dll\")] public static extern bool IsIconic(IntPtr hWnd);",
    "  [DllImport(\"user32.dll\")] public static extern bool IsWindow(IntPtr hWnd);",
    "  [DllImport(\"dwmapi.dll\")] private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out RECT rect, int size);",
    "  public static bool TryGetVisibleRect(IntPtr hWnd, out RECT rect, out bool physical) {",
    "    if (DwmGetWindowAttribute(hWnd, 9, out rect, Marshal.SizeOf(typeof(RECT))) == 0) { physical = true; return true; }",
    "    physical = false;",
    "    return GetWindowRect(hWnd, out rect);",
    "  }",
    "}",
    "'@;",
    "$h = [IntPtr]::Zero;",
    "$r = New-Object PulseWindowRect+RECT;",
    "while ($true) {",
    "  if ($h -eq [IntPtr]::Zero -or -not [PulseWindowRect]::IsWindow($h)) {",
    "    $p = Get-Process -ErrorAction SilentlyContinue | Where-Object {",
    "      if ($_.MainWindowHandle -eq 0 -or $_.ProcessName -eq 'CodexPulse') { return $false }",
    "      $processName = [string]$_.ProcessName;",
    "      $windowTitle = [string]$_.MainWindowTitle;",
    "      $processPath = try { [string]$_.Path } catch { '' };",
    "      $knownProcess = $processName -match '(?i)(^codex$|^codex[._-]|openai.*codex|chatgpt.*codex)';",
    "      $knownInstall = $false;",
    "      foreach ($root in $knownRoots) { if ($processPath -and $processPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { $knownInstall = $true; break } }",
    "      $knownProcess -or ($knownInstall -and $windowTitle -match '(?i)(codex|chatgpt)')",
    "    } | Sort-Object @{ Expression = { if ($_.ProcessName -eq 'Codex') { 0 } else { 1 } } } | Select-Object -First 1;",
    "    $h = if ($null -eq $p) { [IntPtr]::Zero } else { $p.MainWindowHandle };",
    "  }",
    "  if ($h -eq [IntPtr]::Zero) { Write-Output 'null' } else {",
    "    $physical = $false;",
    "    if (-not [PulseWindowRect]::IsIconic($h) -and [PulseWindowRect]::TryGetVisibleRect($h, [ref]$r, [ref]$physical)) {",
    "      @{ handle=$h.ToInt64().ToString(); left=$r.Left; top=$r.Top; right=$r.Right; bottom=$r.Bottom; physical=$physical } | ConvertTo-Json -Compress",
    "    } else { Write-Output 'null' }",
    "  }",
    "  Start-Sleep -Milliseconds 8",
    "}"
  ].join("\n");
  codexWindowWatcher = spawn(
    "powershell.exe",
    ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script],
    {
      windowsHide: true,
      stdio: ["ignore", "pipe", "ignore"]
    }
  );
  const lines = readline.createInterface({ input: codexWindowWatcher.stdout });
  lines.on("line", (line) => {
    try {
      const trackedWindow = JSON.parse(line);
      codexWindowBounds = normalizeTrackedWindowBounds(trackedWindow, screen);
      codexWindowMediaSourceId = codexWindowBounds
        ? mediaSourceIdForWindowHandle(trackedWindow?.handle)
        : null;
    } catch {
      codexWindowBounds = null;
      codexWindowMediaSourceId = null;
    }
    const codexWindowIsPresent = Boolean(codexWindowBounds);
    if (codexWindowIsPresent
        && !codexWindowWasPresent
        && state.followCodexLaunch === true) {
      showStartupCapsule();
    }
    codexWindowWasPresent = codexWindowIsPresent;
    syncAttachedCodexDock();
  });
  codexWindowWatcher.once("exit", () => {
    lines.close();
    codexWindowWatcher = null;
    codexWindowBounds = null;
    codexWindowMediaSourceId = null;
  });
}

function stopCodexWindowWatcher() {
  if (!codexWindowWatcher) return;
  codexWindowWatcher.kill();
  codexWindowWatcher = null;
  codexWindowBounds = null;
  codexWindowMediaSourceId = null;
}

function codexDockFrameForBounds(bounds = codexWindowBounds, edge = codexDockEdge) {
  if (!bounds || !screen) return null;
  const display = screen.getDisplayMatching(bounds);
  const full = display.bounds;
  const work = display.workArea;
  const fillsDisplay = bounds.x <= full.x + 3
    && bounds.y <= full.y + 3
    && bounds.x + bounds.width >= full.x + full.width - 3
    && bounds.y + bounds.height >= full.y + full.height - 3;
  if (fillsDisplay) return null;
  let frame;
  if (edge === "top") {
    frame = {
      x: bounds.x,
      y: bounds.y - CODEX_DOCK_HORIZONTAL_THICKNESS,
      width: bounds.width,
      height: CODEX_DOCK_HORIZONTAL_THICKNESS + CODEX_DOCK_OVERLAP
    };
  } else if (edge === "left") {
    frame = {
      x: bounds.x - CODEX_DOCK_VERTICAL_THICKNESS,
      y: bounds.y,
      width: CODEX_DOCK_VERTICAL_THICKNESS + CODEX_DOCK_OVERLAP,
      height: bounds.height
    };
  } else if (edge === "right") {
    frame = {
      x: bounds.x + bounds.width - CODEX_DOCK_OVERLAP,
      y: bounds.y,
      width: CODEX_DOCK_VERTICAL_THICKNESS + CODEX_DOCK_OVERLAP,
      height: bounds.height
    };
  } else {
    frame = {
      x: bounds.x,
      y: bounds.y + bounds.height - CODEX_DOCK_OVERLAP,
      width: bounds.width,
      height: CODEX_DOCK_HORIZONTAL_THICKNESS + CODEX_DOCK_OVERLAP
    };
  }
  const insideWorkArea = frame.x >= work.x - 1
    && frame.y >= work.y - 1
    && frame.x + frame.width <= work.x + work.width + 1
    && frame.y + frame.height <= work.y + work.height + 1;
  return insideWorkArea ? frame : null;
}

function codexDockTargetsForBounds(bounds = codexWindowBounds) {
  return ["top", "bottom", "left", "right"].flatMap((edge) => {
    const frame = codexDockFrameForBounds(bounds, edge);
    return frame ? [{ edge, frame }] : [];
  });
}

function showCodexDockPreview(frame, edge) {
  codexDockCandidate = frame;
  codexDockCandidateEdge = edge;
  if (!codexDockPreviewRef || codexDockPreviewRef.isDestroyed()) {
    codexDockPreviewRef = new BrowserWindow({
      ...frame,
      frame: false,
      transparent: true,
      resizable: false,
      focusable: false,
      alwaysOnTop: true,
      skipTaskbar: true,
      show: false,
      hasShadow: false,
      backgroundColor: "#00000000",
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true
      }
    });
    codexDockPreviewRef.setIgnoreMouseEvents(true);
    codexDockPreviewEdge = edge;
    codexDockPreviewRef.loadFile(
      path.join(__dirname, "renderer", "dock-preview.html"),
      { query: { edge } }
    );
    codexDockPreviewRef.once("ready-to-show", () => {
      if (codexDockCandidate && codexDockPreviewRef && !codexDockPreviewRef.isDestroyed()) {
        codexDockPreviewRef.showInactive();
      }
    });
  } else {
    if (!isDeepStrictEqual(codexDockPreviewRef.getBounds(), frame)) {
      codexDockPreviewRef.setBounds(frame, false);
    }
    if (codexDockPreviewEdge !== edge) {
      codexDockPreviewEdge = edge;
      codexDockPreviewRef.loadFile(
        path.join(__dirname, "renderer", "dock-preview.html"),
        { query: { edge } }
      );
    }
    if (!codexDockPreviewRef.isVisible()) codexDockPreviewRef.showInactive();
  }
}

function hideCodexDockPreview() {
  codexDockCandidate = null;
  codexDockCandidateEdge = null;
  if (codexDockPreviewRef && !codexDockPreviewRef.isDestroyed()) {
    codexDockPreviewRef.hide();
  }
}

function stopCodexDockFollow() {
  clearTimeout(codexDockFollowTimer);
  codexDockFollowTimer = null;
  codexDockFollowTarget = null;
  codexDockFollowLastAt = 0;
}

function applyAttachedCodexDockShape(width, height, edge = codexDockEdge) {
  const shape = attachedDockShape(width, height, edge, CODEX_DOCK_OVERLAP);
  const signature = JSON.stringify([shape]);
  windowShapeBounds = shape;
  if (windowShapeSignature === signature) return;
  windowShapeSignature = signature;
  // The native frame still overlaps Codex so both windows share one exact
  // seam, but the draw/hit region starts outside the host. This prevents the
  // transparent shoulder from covering Codex controls on Windows.
  windowRef.setShape([shape]);
}

function nextCodexDockCoordinate(current, target, alpha) {
  const delta = target - current;
  if (Math.abs(delta) <= 1) return target;
  const interpolated = Math.round(current + delta * alpha);
  return interpolated === current
    ? current + Math.sign(delta)
    : interpolated;
}

function followCodexDockFrame(target, immediate = false) {
  if (!windowRef || windowRef.isDestroyed() || !target) return;
  codexDockFollowTarget = {
    x: Math.round(target.x),
    y: Math.round(target.y),
    width: Math.round(target.width),
    height: Math.round(target.height)
  };
  if (immediate) {
    clearTimeout(codexDockFollowTimer);
    codexDockFollowTimer = null;
    codexDockFollowLastAt = 0;
    if (!isDeepStrictEqual(windowRef.getBounds(), codexDockFollowTarget)) {
      windowRef.setBounds(codexDockFollowTarget, false);
    }
    return;
  }
  if (codexDockFollowTimer) return;
  const step = () => {
    codexDockFollowTimer = null;
    if (!codexDockAttached
        || !codexDockFollowTarget
        || !windowRef
        || windowRef.isDestroyed()) {
      stopCodexDockFollow();
      return;
    }
    const now = performance.now();
    const elapsed = codexDockFollowLastAt > 0
      ? Math.min(34, Math.max(4, now - codexDockFollowLastAt))
      : 8;
    codexDockFollowLastAt = now;
    // A time-based spring-like low-pass removes the 16ms PowerShell
    // staircase while staying close enough to the native Codex window.
    const alpha = Math.min(0.68, Math.max(0.24, 1 - Math.exp(-elapsed / 22)));
    const current = windowRef.getBounds();
    const next = {
      x: nextCodexDockCoordinate(current.x, codexDockFollowTarget.x, alpha),
      y: nextCodexDockCoordinate(current.y, codexDockFollowTarget.y, alpha),
      width: nextCodexDockCoordinate(current.width, codexDockFollowTarget.width, alpha),
      height: nextCodexDockCoordinate(current.height, codexDockFollowTarget.height, alpha)
    };
    if (!isDeepStrictEqual(current, next)) {
      windowRef.setBounds(next, false);
      if (next.width !== current.width || next.height !== current.height) {
        applyAttachedCodexDockShape(next.width, next.height, codexDockEdge);
      }
    }
    if (isDeepStrictEqual(next, codexDockFollowTarget)) {
      codexDockFollowTarget = null;
      codexDockFollowLastAt = 0;
      return;
    }
    codexDockFollowTimer = setTimeout(step, 8);
  };
  codexDockFollowTimer = setTimeout(step, 0);
}

function keepCodexDockVisible(force = false) {
  if (!codexDockAttached
      || !codexWindowMediaSourceId
      || !windowRef
      || windowRef.isDestroyed()
      || typeof windowRef.moveAbove !== "function") return false;
  const now = Date.now();
  if (!force && now - codexDockLastZOrderAt < 250) return true;
  try {
    // `moveAbove` keeps this normal (non-topmost) window immediately above
    // Codex in the same z-order group. The previous native SetWindowPos loop
    // put the dock behind Codex, where another window could fully occlude it.
    windowRef.moveAbove(codexWindowMediaSourceId);
    codexDockLastZOrderAt = now;
    return true;
  } catch {
    return false;
  }
}

function updateCodexDockCandidate() {
  if (codexDockAttached
      || codexDockTransition !== "idle"
      || Date.now() < codexDockPreviewSuppressUntil
      || !windowRef
      || windowRef.isDestroyed()) {
    hideCodexDockPreview();
    return;
  }
  const current = visibleWindowBounds(
    windowRef.getBounds(),
    windowShapeBounds,
    USE_STABLE_DESKTOP_SURFACE
  );
  if (!current) {
    hideCodexDockPreview();
    return;
  }
  const target = codexDockTargetsForBounds().sort(
    (left, right) => rectangleDistance(current, left.frame)
      - rectangleDistance(current, right.frame)
  )[0];
  const distance = target ? rectangleDistance(current, target.frame) : Infinity;
  const releaseDistance = codexDockCandidate
      && codexDockCandidateEdge === target?.edge
    ? CODEX_DOCK_PREVIEW_RELEASE_DISTANCE
    : CODEX_DOCK_PROXIMITY;
  if (!target || distance > releaseDistance) {
    hideCodexDockPreview();
    return;
  }
  showCodexDockPreview(target.frame, target.edge);
}

function syncAttachedCodexDock(forceNotify = false) {
  if ((!codexDockAttached && !codexDockRestorePending)
      || !windowRef
      || windowRef.isDestroyed()) return;
  const target = codexDockFrameForBounds(codexWindowBounds, codexDockEdge);
  if (!target) {
    stopCodexDockFollow();
    if (currentWindowLayoutMode === "codex-dock") {
      detachCodexDock({ restoreSavedPosition: true });
    }
    return;
  }
  const restoringAttachment = codexDockRestorePending;
  if (codexDockRestorePending) {
    codexDockRestorePending = false;
    codexDockAttached = true;
    windowRef.setAlwaysOnTop(false);
  }
  followCodexDockFrame(
    target,
    restoringAttachment || currentWindowLayoutMode !== "codex-dock" || forceNotify
  );
  const currentBounds = windowRef.getContentBounds();
  applyAttachedCodexDockShape(currentBounds.width, currentBounds.height, codexDockEdge);
  if (currentWindowLayoutMode !== "codex-dock" || forceNotify) {
    currentWindowLayoutMode = "codex-dock";
    windowRef.webContents.send("pulse:codex-dock-transition", {
      phase: "attached",
      width: target.width,
      height: target.height,
      edge: codexDockEdge,
      restored: true
    });
  }
  if (!windowRef.isVisible()) windowRef.showInactive();
  keepCodexDockVisible(forceNotify);
}

function attachCodexDock(frame = codexDockCandidate) {
  if (!frame
      || codexDockAttached
      || codexDockTransition !== "idle"
      || !windowRef
      || windowRef.isDestroyed()) return false;
  const previous = windowRef.getBounds();
  codexDockPreviousLayout = {
    mode: currentWindowLayoutMode,
    bounds: previous,
    shape: windowShapeBounds ? { ...windowShapeBounds } : null
  };
  codexDockTransition = "attaching";
  codexDockRestorePending = false;
  codexDockEdge = codexDockCandidateEdge || "bottom";
  writeSettings({
    codexDockAttached: true,
    codexDockEdge,
    codexDockPreviousLayout
  });
  hideCodexDockPreview();
  cancelPetRoamAnimation();
  windowRef.webContents.send("pulse:codex-dock-transition", {
    phase: "attaching",
    width: frame.width,
    height: frame.height,
    edge: codexDockEdge
  });
  clearTimeout(codexDockTransitionTimer);
  codexDockTransitionTimer = setTimeout(() => {
    codexDockTransitionTimer = null;
    if (codexDockTransition !== "attaching"
        || !windowRef
        || windowRef.isDestroyed()) return;
    codexDockAttached = true;
    codexDockTransition = "idle";
    currentWindowLayoutMode = "codex-dock";
    windowRef.setAlwaysOnTop(false);
    followCodexDockFrame(frame, true);
    applyAttachedCodexDockShape(frame.width, frame.height, codexDockEdge);
    if (!windowRef.isVisible()) windowRef.showInactive();
    keepCodexDockVisible(true);
    windowRef.webContents.send("pulse:codex-dock-transition", {
      phase: "attached",
      width: frame.width,
      height: frame.height,
      edge: codexDockEdge
    });
  }, 220);
  return true;
}

function detachCodexDock({ pointer = null, restoreSavedPosition = false } = {}) {
  if (!codexDockAttached
      || codexDockTransition !== "idle"
      || !windowRef
      || windowRef.isDestroyed()) return false;
  const settings = readSettings();
  const previous = codexDockPreviousLayout || settings.codexDockPreviousLayout;
  const fallback = { x: 40, y: 40, width: COLLAPSED_SIZE.width, height: COLLAPSED_SIZE.height };
  const saved = previous?.bounds && Number(previous.bounds.width) > 80
    ? previous.bounds
    : fallback;
  const savedShape = previous?.shape
      && Number(previous.shape.width) > 0
      && Number(previous.shape.height) > 0
    ? previous.shape
    : {
        x: Math.max(0, (Number(saved.width) - COLLAPSED_SIZE.width) / 2),
        y: 0,
        width: Math.min(Number(saved.width), COLLAPSED_SIZE.width),
        height: Math.min(Number(saved.height), COLLAPSED_SIZE.height)
      };
  const detached = restoreSavedPosition || !pointer
    ? {
        x: Math.round(saved.x),
        y: Math.round(saved.y),
        width: Math.round(saved.width),
        height: Math.round(saved.height)
      }
    : detachedWindowBounds(pointer, saved, savedShape);
  const area = screen.getDisplayNearestPoint(
    pointer || { x: detached.x, y: detached.y }
  ).workArea;
  const clamped = clampWindowPositionToVisibleShape(
    detached.x,
    detached.y,
    area,
    detached,
    savedShape
  );
  const target = {
    ...detached,
    x: Math.round(clamped.x),
    y: Math.round(clamped.y)
  };
  codexDockTransition = "detaching";
  codexDockAttached = false;
  codexDockRestorePending = false;
  codexDockLastZOrderAt = 0;
  codexDockPreviewSuppressUntil = Date.now() + 450;
  stopCodexDockFollow();
  hideCodexDockPreview();
  windowRef.setAlwaysOnTop(true);
  writeSettings({ codexDockAttached: false });
  windowRef.webContents.send("pulse:codex-dock-transition", {
    phase: "detaching",
    mode: previous?.mode || "collapsed",
    edge: codexDockEdge
  });
  currentWindowLayoutMode = previous?.mode || "collapsed";
  windowRef.setBounds(target, false);
  windowShapeBounds = { x: 0, y: 0, width: target.width, height: target.height };
  windowShapeSignature = JSON.stringify([windowShapeBounds]);
  windowRef.setShape([windowShapeBounds]);
  if (!windowRef.isVisible()) windowRef.showInactive();
  clearTimeout(codexDockTransitionTimer);
  codexDockTransitionTimer = setTimeout(() => {
    codexDockTransitionTimer = null;
    if (codexDockTransition !== "detaching"
        || !windowRef
        || windowRef.isDestroyed()) return;
    codexDockTransition = "idle";
    windowRef.webContents.send("pulse:codex-dock-transition", {
      phase: "detached",
      mode: currentWindowLayoutMode
    });
  }, 24);
  return true;
}

function createWindow() {
  windowRef = new BrowserWindow({
    ...(USE_STABLE_DESKTOP_SURFACE
      ? EXPANDED_SIZE
      : state.informationBar?.enabled ? INFORMATION_COLLAPSED_SIZE : COLLAPSED_SIZE),
    frame: false,
    transparent: true,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    // Start as a normal floating Pulse surface even when a saved attachment
    // is pending. The level is lowered only after a live Codex target exists.
    alwaysOnTop: true,
    skipTaskbar: false,
    show: false,
    backgroundColor: "#00000000",
    hasShadow: false,
    icon: iconPath(),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: false
    }
  });
  windowRef.setMenuBarVisibility(false);
  // `ready-to-show` waits for Chromium's full first-paint pipeline. The DOM is
  // already fully styled and scripted at dom-ready, so reveal there and keep
  // ready-to-show only as a fallback. Background services start afterwards.
  windowRef.webContents.once("dom-ready", () => {
    showStartupCapsule();
    syncAttachedCodexDock(true);
    scheduleBackgroundStartup();
  });
  windowRef.once("ready-to-show", () => {
    showStartupCapsule();
    scheduleBackgroundStartup();
  });
  windowRef.webContents.once("did-finish-load", () => {
    showStartupCapsule();
    scheduleBackgroundStartup();
  });
  windowRef.loadFile(path.join(__dirname, "renderer", "index.html"));
  const collapseDetail = () => {
    if (windowRef && !windowRef.isDestroyed()) windowRef.webContents.send("pulse:collapse");
  };
  windowRef.on("blur", collapseDetail);
  windowRef.on("hide", collapseDetail);
  windowRef.on("move", () => publishBlackHoleCaptureGeometry());
  windowRef.on("resize", () => publishBlackHoleCaptureGeometry());
  windowRef.on("close", (event) => {
    if (!app.isQuitting) {
      event.preventDefault();
      windowRef.hide();
    }
  });
}

function showStartupCapsule() {
  if (!windowRef || windowRef.isDestroyed()) return;
  if (startupCapsuleShown && windowRef.isVisible()) return;
  const target = USE_STABLE_DESKTOP_SURFACE
    ? EXPANDED_SIZE
    : state.informationBar?.enabled
    ? { ...INFORMATION_COLLAPSED_SIZE, width: informationCollapsedWidth }
    : { ...COLLAPSED_SIZE, width: collapsedWidth };
  const display = screen.getPrimaryDisplay().workArea;
  const margin = 18;
  const x = Math.max(display.x, display.x + display.width - target.width - margin);
  const y = Math.max(display.y, display.y + margin);
  windowRef.setBounds({ x, y, ...target }, false);
  publishBlackHoleCaptureGeometry({ x, y, ...target });
  windowRef.show();
  windowRef.moveTop();
  startupCapsuleShown = true;
  const elapsedMs = Number(process.hrtime.bigint() - processStartedAt) / 1_000_000;
  process.stdout.write(`CodexPulse first capsule frame: ${elapsedMs.toFixed(1)}ms\n`);
}

function scheduleBackgroundStartup() {
  if (backgroundStartupScheduled) return;
  backgroundStartupScheduled = true;
  // Give Chromium one frame to composite the capsule before spawning Codex or
  // recursively scanning sessions. This changes perceived startup without
  // delaying any user interaction on the already visible capsule.
  setTimeout(() => {
    if (!tray) createTray();
    if (state.informationBar?.enabled) void refreshWeather(false);
    void connect();
    setTimeout(() => { triggerAutomaticUpdateCheck(true); }, 1_800);
  }, 50);
}

function updateTray() {
  if (!tray) return;
  const remaining = state.limits[0]?.remainingPercent;
  tray.setToolTip(`Codex-Pulse · ${state.task.label}${remaining === undefined ? "" : ` · 剩余 ${Math.round(remaining)}%`}`);
}

function showTrayPanel() {
  if (!windowRef || windowRef.isDestroyed() || !tray) return;
  const trayBounds = tray.getBounds();
  const target = {
    ...EXPANDED_SIZE,
    width: state.informationBar?.enabled
      ? Math.max(INFORMATION_COLLAPSED_SIZE.width, informationCollapsedWidth)
      : EXPANDED_SIZE.width
  };
  const display = screen.getDisplayNearestPoint({
    x: Math.round(trayBounds.x + trayBounds.width / 2),
    y: Math.round(trayBounds.y + trayBounds.height / 2)
  }).workArea;
  const centeredX = Math.round(trayBounds.x + trayBounds.width / 2 - target.width / 2);
  const x = Math.min(display.x + display.width - target.width, Math.max(display.x, centeredX));
  const roomAbove = trayBounds.y - display.y;
  const roomBelow = display.y + display.height - trayBounds.y - trayBounds.height;
  const preferredY = roomAbove >= roomBelow
    ? trayBounds.y - target.height - 8
    : trayBounds.y + trayBounds.height + 8;
  const y = Math.min(display.y + display.height - target.height, Math.max(display.y, preferredY));
  windowRef.setBounds({ x, y, ...target }, false);
  windowRef.show();
  windowRef.focus();
  windowRef.webContents.send("pulse:expand");
}

function createTray() {
  let image = nativeImage.createFromPath(iconPath()).resize({ width: 20, height: 20 });
  tray = new Tray(image);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "打开 Codex-Pulse 面板", click: showTrayPanel },
    { label: "刷新", click: () => refreshAll(true) },
    { label: "检查更新", click: () => { void checkForUpdates(true); } },
    { type: "separator" },
    { label: "退出", click: () => { app.isQuitting = true; app.quit(); } }
  ]));
  tray.on("click", () => {
    if (windowRef.isVisible() && windowRef.isFocused()) windowRef.hide();
    else showTrayPanel();
  });
  updateTray();
}

ipcMain.handle("pulse:get-state", () => state);
ipcMain.handle("pulse:refresh", async () => {
  if (!rpc) await connect();
  else await refreshAll(true);
  if (!rpc && state.informationBar?.enabled) await refreshWeather(true);
  return state;
});
ipcMain.handle("pulse:check-update", () => checkForUpdates(true));
ipcMain.on("pulse:network-online", () => triggerAutomaticUpdateCheck(true));
ipcMain.handle("pulse:perform-update", () => performPrimaryUpdateAction());
ipcMain.handle("pulse:skip-update", (_event, version) => skipAvailableUpdate(version));
ipcMain.handle("pulse:search-locations", async (_event, query) => {
  try {
    return { results: await searchWeatherLocations(query), error: null };
  } catch (error) {
    return { results: [], error: String(error?.message || "地区搜索失败") };
  }
});
ipcMain.handle("pulse:set-information-enabled", (_event, enabled) => {
  return setInformationBarEnabled(enabled);
});
ipcMain.handle("pulse:set-follow-codex-launch", (_event, enabled) => {
  const followCodexLaunch = enabled === true;
  writeSettings({ followCodexLaunch });
  publish({ followCodexLaunch });
  if (followCodexLaunch && codexWindowBounds) showStartupCapsule();
  return state;
});
ipcMain.handle("pulse:set-information-location", (_event, location) => {
  try {
    return setInformationBarLocation(location);
  } catch (error) {
    return { ...state, informationError: String(error?.message || "地区信息无效") };
  }
});
ipcMain.handle("pulse:open-external", (_event, rawURL) => {
  try {
    const url = new URL(String(rawURL || ""));
    const allowed = url.protocol === "https:"
      && ["open-meteo.com", "www.open-meteo.com", "geonames.org", "www.geonames.org"].includes(url.hostname.toLowerCase());
    if (!allowed) return false;
    void shell.openExternal(url.toString());
    return true;
  } catch {
    return false;
  }
});
ipcMain.handle("pulse:choose-codex", async () => {
  const result = await dialog.showOpenDialog(windowRef, {
    title: "选择 Codex 命令",
    properties: ["openFile"],
    filters: [
      { name: "Codex", extensions: ["exe", "cmd", "bat"] },
      { name: "所有文件", extensions: ["*"] }
    ]
  });
  if (result.canceled || !result.filePaths[0]) return state;
  writeSettings({ codexPath: result.filePaths[0] });
  await connect(result.filePaths[0]);
  return state;
});
ipcMain.handle("pulse:clear-codex-path", async () => {
  writeSettings({ codexPath: null });
  await connect();
  return state;
});
ipcMain.handle("pulse:resize", (_event, mode) => resizeWindow(mode));
ipcMain.handle("pulse:codex-dock-detach", (event, pointer) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) {
    return false;
  }
  return detachCodexDock({
    pointer: {
      x: Number(pointer?.x) || windowRef.getBounds().x,
      y: Number(pointer?.y) || windowRef.getBounds().y
    }
  });
});
ipcMain.handle("pulse:set-window-shape", (_event, rects) => {
  if (!USE_STABLE_DESKTOP_SURFACE
      || !windowRef
      || windowRef.isDestroyed()
      || typeof windowRef.setShape !== "function") return false;
  const bounds = windowRef.getContentBounds();
  // The renderer can finish a queued floating-capsule shape sync after the
  // attachment transition. Re-apply the edge-aware dock region so a stale
  // request cannot restore either the old capsule or the covered overlap.
  if (codexDockAttached || currentWindowLayoutMode === "codex-dock") {
    applyAttachedCodexDockShape(bounds.width, bounds.height, codexDockEdge);
    return true;
  }
  const normalized = (Array.isArray(rects) ? rects : []).flatMap((rect) => {
    const x = Math.max(0, Math.min(bounds.width, Math.round(Number(rect?.x) || 0)));
    const y = Math.max(0, Math.min(bounds.height, Math.round(Number(rect?.y) || 0)));
    const width = Math.max(0, Math.min(bounds.width - x, Math.round(Number(rect?.width) || 0)));
    const height = Math.max(0, Math.min(bounds.height - y, Math.round(Number(rect?.height) || 0)));
    return width > 0 && height > 0 ? [{ x, y, width, height }] : [];
  });
  const signature = JSON.stringify(normalized);
  if (signature === windowShapeSignature) return true;
  windowShapeSignature = signature;
  windowShapeBounds = unionShapeBounds(normalized);
  windowRef.setShape(normalized);
  return true;
});
ipcMain.handle("pulse:set-black-hole-capture-mode", (event, enabled) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) {
    return false;
  }
  // Electron maps this to SetWindowDisplayAffinity on Windows. Excluding the
  // transparent pet window prevents the desktop stream from feeding the black
  // hole back into itself while normal app windows remain capturable.
  blackHoleCaptureEnabled = enabled === true;
  windowRef.setContentProtection(process.platform === "win32" && blackHoleCaptureEnabled);
  if (blackHoleCaptureEnabled) publishBlackHoleCaptureGeometry();
  return true;
});

function blackHoleCaptureGeometry(windowBounds = null) {
  if (!windowRef || windowRef.isDestroyed()) return null;
  const resolvedBounds = windowBounds || windowRef.getContentBounds();
  const display = screen.getDisplayMatching(resolvedBounds);
  return {
    windowBounds: resolvedBounds,
    displayBounds: display.bounds,
    displayId: String(display.id),
    scaleFactor: display.scaleFactor
  };
}

function publishBlackHoleCaptureGeometry(windowBounds = null) {
  if (!blackHoleCaptureEnabled || !windowRef || windowRef.isDestroyed()) return;
  const geometry = blackHoleCaptureGeometry(windowBounds);
  if (geometry) windowRef.webContents.send("pulse:black-hole-capture-geometry", geometry);
}

ipcMain.handle("pulse:get-black-hole-capture-geometry", (event) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) {
    return null;
  }
  return blackHoleCaptureGeometry();
});
ipcMain.handle("pulse:black-hole-trash-files", async (event, filePaths) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) {
    return { ok: false, trashed: 0, errors: ["unauthorized renderer"] };
  }
  const candidates = Array.isArray(filePaths) ? filePaths.slice(0, 64) : [];
  const errors = [];
  let trashed = 0;
  for (const candidate of candidates) {
    if (typeof candidate !== "string" || !candidate.trim()) continue;
    const resolved = path.resolve(candidate);
    if (resolved === path.parse(resolved).root) {
      errors.push("volume roots cannot be moved to the Recycle Bin");
      continue;
    }
    try {
      await shell.trashItem(resolved);
      trashed += 1;
    } catch (error) {
      errors.push(`${path.basename(resolved)}: ${error?.message || String(error)}`);
    }
  }
  return { ok: errors.length === 0 && trashed > 0, trashed, errors };
});
ipcMain.handle("pulse:show-pet-switch-menu", (event, current) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) {
    return null;
  }
  const selected = PET_SWITCH_ITEMS.some((item) => item.id === current) ? current : "dino";
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    const menu = Menu.buildFromTemplate(PET_SWITCH_ITEMS.map((item) => ({
      label: item.label,
      type: "radio",
      checked: item.id === selected,
      click: () => finish(item.id)
    })));
    menu.popup({
      window: windowRef,
      callback: () => finish(null)
    });
  });
});
ipcMain.handle("pulse:pet-roam-plan", (event, options) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) return null;
  return planPetRoam(options);
});
ipcMain.handle("pulse:pet-roam-run", (event, plan) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) {
    return { cancelled: true };
  }
  return runPetRoam(plan);
});
ipcMain.on("pulse:pet-roam-cancel", (event) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) return;
  cancelPetRoamAnimation();
});
ipcMain.on("pulse:drag-begin", (event, point) => {
  if (!windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) return;
  if (codexDockAttached || codexDockTransition !== "idle") return;
  hideCodexDockPreview();
  if (codexDockRestorePending) {
    codexDockRestorePending = false;
    writeSettings({ codexDockAttached: false });
    windowRef.setAlwaysOnTop(true);
  }
  cancelPetRoamAnimation();
  const bounds = windowRef.getBounds();
  dragState = {
    pointerX: Number(point?.x) || 0,
    pointerY: Number(point?.y) || 0,
    windowX: bounds.x,
    windowY: bounds.y,
    encounterKind: null,
    encounterDirection: null
  };
});
ipcMain.on("pulse:drag-move", (event, point) => {
  if (!dragState || !windowRef || windowRef.isDestroyed() || event.sender !== windowRef.webContents) return;
  const pointer = { x: Number(point?.x) || 0, y: Number(point?.y) || 0 };
  const encounter = classifyManualPetDrop(pointer);
  if (encounter) {
    if (encounter.kind === "dock" || !dragState.encounterKind) {
      dragState.encounterKind = encounter.kind;
      dragState.encounterDirection = encounter.direction;
    }
  }
  const bounds = windowRef.getBounds();
  const area = screen.getDisplayNearestPoint(pointer).workArea;
  const wantedX = Math.round(dragState.windowX + pointer.x - dragState.pointerX);
  const wantedY = Math.round(dragState.windowY + pointer.y - dragState.pointerY);
  const next = clampWindowPositionToVisibleShape(
    wantedX,
    wantedY,
    area,
    bounds,
    USE_STABLE_DESKTOP_SURFACE ? windowShapeBounds : null
  );
  const nextX = Math.round(next.x);
  const nextY = Math.round(next.y);
  if (nextX !== bounds.x || nextY !== bounds.y) {
    windowRef.setPosition(nextX, nextY, false);
    publishBlackHoleCaptureGeometry({
      ...windowRef.getContentBounds(),
      x: nextX,
      y: nextY
    });
  }
  updateCodexDockCandidate();
});
function classifyManualPetDrop(point) {
  if (!windowRef || windowRef.isDestroyed()) return null;
  const pointer = {
    x: Number(point?.x),
    y: Number(point?.y)
  };
  if (!Number.isFinite(pointer.x) || !Number.isFinite(pointer.y)) return null;
  const display = screen.getDisplayNearestPoint(pointer);
  const area = display.workArea;
  const full = display.bounds;
  const taskbarEdge = inferredTaskbarEdge(area, full);
  const threshold = 110;
  const nearTaskbar = taskbarEdge === "top"
    ? pointer.y <= area.y + threshold
    : taskbarEdge === "left"
    ? pointer.x <= area.x + threshold
    : taskbarEdge === "right"
    ? pointer.x >= area.x + area.width - threshold
    : pointer.y >= area.y + area.height - threshold;
  const bounds = windowRef.getBounds();
  const visible = USE_STABLE_DESKTOP_SURFACE && windowShapeBounds
    ? windowShapeBounds
    : { x: 0, y: 0, width: bounds.width, height: bounds.height };
  const visibleCenterX = bounds.x + visible.x + visible.width / 2;
  return {
    kind: nearTaskbar ? "dock" : "desktop",
    direction: pointer.x < visibleCenterX ? "left" : "right"
  };
}

ipcMain.on("pulse:drag-end", (event, point) => {
  const didMove = point?.moved === true;
  const encountered = dragState
    ? {
        kind: dragState.encounterKind,
        direction: dragState.encounterDirection
      }
    : null;
  dragState = null;
  if (!didMove
      || !windowRef
      || windowRef.isDestroyed()
      || event.sender !== windowRef.webContents) {
    hideCodexDockPreview();
    return;
  }
  // Re-evaluate with the final pointer-delivered window position. A pointerup
  // can arrive between animation frames, so relying only on the last preview
  // calculation makes quick releases at the 30px edge miss attachment.
  updateCodexDockCandidate();
  if (codexDockCandidate && attachCodexDock()) return;
  hideCodexDockPreview();
  const finalDrop = classifyManualPetDrop(point);
  const drop = finalDrop && encountered?.kind
    ? {
        ...finalDrop,
        kind: encountered.kind,
        direction: encountered.direction || finalDrop.direction
      }
    : finalDrop;
  if (drop) windowRef.webContents.send("pulse:pet-drop", drop);
});
ipcMain.on("pulse:quit", () => { app.isQuitting = true; app.quit(); });

app.whenReady().then(() => {
  app.setAppUserModelId("com.codexpulse.windows");
  const startupSettings = readSettings();
  state.followCodexLaunch = startupSettings.followCodexLaunch === true;
  codexDockAttached = false;
  codexDockRestorePending = startupSettings.codexDockAttached === true;
  codexDockEdge = ["top", "bottom", "left", "right"].includes(startupSettings.codexDockEdge)
    ? startupSettings.codexDockEdge
    : "bottom";
  codexDockPreviousLayout = startupSettings.codexDockPreviousLayout || null;
  session.defaultSession.setDisplayMediaRequestHandler((_request, callback) => {
    void desktopCapturer.getSources({
      types: ["screen"],
      thumbnailSize: { width: 0, height: 0 }
    }).then((sources) => {
      if (!sources.length) {
        callback({});
        return;
      }
      const bounds = windowRef && !windowRef.isDestroyed()
        ? windowRef.getBounds()
        : screen.getPrimaryDisplay().bounds;
      const display = screen.getDisplayMatching(bounds);
      const displayId = String(display.id);
      const source = sources.find((candidate) =>
        String(candidate.display_id || "") === displayId
        || String(candidate.id || "").split(":")[1] === displayId
      ) || sources[0];
      callback({ video: source });
    }).catch(() => callback({}));
  }, { useSystemPicker: false });
  armLocalUsageDayTimer();
  powerMonitor.on("resume", () => {
    void handleLocalUsageDayBoundary(new Date()).finally(() => armLocalUsageDayTimer());
    triggerAutomaticUpdateCheck(true);
    if (windowRef && !windowRef.isDestroyed()) {
      windowRef.webContents.send("pulse:system-resume");
    }
  });
  powerMonitor.on("unlock-screen", () => triggerAutomaticUpdateCheck(true));
  initializeInformationBar();
  createWindow();
  startCodexWindowWatcher();
});

app.on("browser-window-focus", () => triggerAutomaticUpdateCheck(false));

app.on("before-quit", () => {
  app.isQuitting = true;
  cancelPetRoamAnimation();
  stopCodexDockFollow();
  clearTimeout(codexDockTransitionTimer);
  stopCodexWindowWatcher();
  if (codexDockPreviewRef && !codexDockPreviewRef.isDestroyed()) {
    codexDockPreviewRef.destroy();
  }
  clearTimeout(refreshTimer);
  clearTimeout(localUsageDayTimer);
  clearTimeout(weatherRefreshTimer);
  clearTimeout(updateRefreshTimer);
  updateDownloadAbortController?.abort();
  ++weatherRequestGeneration;
  stopAuthMonitoring();
  stopSessionMonitoring();
  if (rpc) rpc.close();
});
// 托盘应用关闭窗口后继续驻留；Windows 不自动退出。
app.on("window-all-closed", () => {});
