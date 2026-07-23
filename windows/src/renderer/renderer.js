const elements = Object.fromEntries([
  "capsule", "detail", "miniCapsule", "miniRingProgress", "miniValue", "miniValuePrevious", "petAnimation", "weatherScene", "weatherAnimation", "weatherSpacer", "statusDot", "quotaRing", "quotaArc", "remaining", "todayTokens", "todayTokensPrevious", "chevron",
  "informationStrip", "informationWeatherContent", "informationTaskContent", "informationTaskStatus", "informationTaskSummary", "weatherMiniIcon", "weatherSummary", "informationLocation", "informationWeekday", "informationTime",
  "conversationDetail", "conversationMessages", "conversationLiveLabel", "conversationClose",
  "email", "plan", "taskBadge", "connectionMessage", "chooseCodex", "resetTime",
  "limitTitle", "progressTrack", "progressFill", "secondaryLimit", "cardsToggle", "cardsSummary", "cardsNearest", "cardsChevron",
  "cardsList", "tokenChart", "chartValue", "todayDetail", "totalTokens", "totalMetricLabel", "taskElapsed", "taskMetricLabel",
  "cliInfo", "refresh", "quit", "taskTunnel", "taskTunnelCanvas", "tunnelOutputLabel",
  "activityBandToggle", "activityBandPicker", "activityBandStyle", "activityBandStyleLabel", "activityBandStyleMenu",
  "themePicker", "themeStyle", "themeStyleLabel", "themeStyleMenu",
  "miniStylePicker", "miniStyle", "miniStyleLabel", "miniStyleMenu",
  "petPicker", "petCharacter", "petCharacterLabel", "petCharacterMenu",
  "moreSettingsToggle", "appearanceSettings",
  "informationBarToggle", "informationLocationButton", "informationLocationLabel", "locationChooser", "locationChooserClose", "locationSearch",
  "locationSearchStatus", "locationResults",
  "updateIndicator", "updateDetail", "updateVersionRoute", "updateReleaseTitle", "updateReleaseNotes", "updateProgress", "updateProgressStatus", "updateProgressLabel", "updateProgressFill", "updateProgressSize", "skipUpdateButton", "installUpdateButton"
].map((id) => [id, document.getElementById(id)]));

let expanded = false;
let miniMode = false;
let conversationExpanded = false;
let miniConversationExpanded = false;
let conversationCollapseTimer;
let miniConversationCollapseTimer;
let conversationStructureSignature = "";
let taskSummaryAnimation;
let lastTaskSummaryMotionAt = 0;
let detailMode = "standard";
let cardsExpanded = false;
let currentState;
let hoveredChartIndex = null;
let chartFrame;
let collapseTimer;
let detailAnimationTimer;
let detailTransitionGeneration = 0;
let cardsSignature = "";
let chartSignature = "";
let tunnelFrame;
let tunnelMode = "idle";
let tunnelLastFrame = 0;
let activityBandPreviewTimer;
let locationSearchTimer;
let locationSearchRequest = 0;
let locationResults = [];
let capsuleSingleClickTimer;
let miniTransitioning = false;
let collapsedWidthFrame;
let collapsedWidthSettleTimer;
let windowShapeFrame;
let lastCollapsedWindowWidth;
let adaptiveResizeInFlight = false;
let adaptiveResizeReleaseTimer;

const exactNumber = new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 0 });
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
function readChartPalette() {
  const styles = getComputedStyle(document.documentElement);
  return {
    blue: styles.getPropertyValue("--blue").trim() || "#1890ff",
    muted: styles.getPropertyValue("--muted").trim() || "rgba(255,255,255,.5)",
    line: styles.getPropertyValue("--line").trim() || "rgba(255,255,255,.1)"
  };
}
let chartPalette = readChartPalette();
const activityBandPreferenceKey = "codexPulse.activityBand";
const activityBandStyles = new Set(["classic", "aurora", "lava", "neon", "mono"]);
const activityBandLabels = Object.freeze({ classic: "经典", aurora: "极光", lava: "熔岩", neon: "霓虹", mono: "单色" });
let activityBandPreference = loadActivityBandPreference();
const themePreferenceKey = "codexPulse.theme";
const themeStyles = new Set(["classic", "midnight", "graphite", "forest", "amethyst"]);
const themeLabels = Object.freeze({
  classic: "经典玻璃",
  midnight: "午夜 HUD",
  graphite: "石墨哑光",
  forest: "森林柔雾",
  amethyst: "紫晶棱镜"
});
let themePreference = loadThemePreference();
const miniStylePreferenceKey = "codexPulse.miniStyle";
const apiMiniStylePreferenceKey = "codexPulse.apiMiniStyle";
const lastUsageModePreferenceKey = "codexPulse.lastUsageMode";
const miniStyles = new Set(["quota", "tokens", "status", "weather", "time"]);
const apiMiniStyles = new Set(["tokens", "status", "weather", "time"]);
const miniStyleLabels = Object.freeze({
  quota: "剩余额度",
  tokens: "今日 Token",
  status: "任务状态",
  weather: "天气温度",
  time: "当地时间"
});
let miniStylePreference = loadMiniStylePreference();
let apiMiniStylePreference = loadAPIMiniStylePreference();
const petPreferenceKey = "codexPulse.petCharacter";
const petCharacters = new Set(["dino", "cat", "bunny", "ghost", "robot"]);
const petCharacterLabels = Object.freeze({
  dino: "小恐龙",
  cat: "猫咪",
  bunny: "兔子",
  ghost: "幽灵",
  robot: "机器人"
});
let petCharacterPreference = loadPetPreference();
let activePreferenceMenu = null;

const weatherKinds = Object.freeze({
  clear: "晴",
  cloudy: "多云",
  overcast: "阴",
  fog: "雾",
  rain: "雨",
  snow: "雪",
  thunder: "雷雨",
  night: "晴",
  unknown: "天气"
});

function weatherKind(code, isDay = true) {
  const number = Number(code);
  if (!Number.isFinite(number)) return "unknown";
  if (number === 0) return isDay ? "clear" : "night";
  if (number === 1 || number === 2) return "cloudy";
  if (number === 3) return "overcast";
  if (number === 45 || number === 48) return "fog";
  if ((number >= 51 && number <= 67) || (number >= 80 && number <= 82)) return "rain";
  if ((number >= 71 && number <= 77) || number === 85 || number === 86) return "snow";
  if (number === 95 || number === 96 || number === 99) return "thunder";
  return "unknown";
}

function weatherLabel(code, isDay) {
  const kind = weatherKind(code, isDay);
  return weatherKinds[kind] || weatherKinds.unknown;
}

function weatherAssetName(code, isDay = true) {
  const number = Number(code);
  if (!Number.isFinite(number)) return isDay ? "partly-cloudy-day" : "partly-cloudy-night";
  if (number === 0) return isDay ? "clear-day" : "clear-night";
  if (number === 1 || number === 2) return isDay ? "partly-cloudy-day" : "partly-cloudy-night";
  if (number === 3) return isDay ? "overcast-day" : "overcast-night";
  if (number === 45 || number === 48) return isDay ? "fog-day" : "fog-night";
  if (number >= 51 && number <= 57) return isDay ? "partly-cloudy-day-drizzle" : "partly-cloudy-night-drizzle";
  if ((number >= 61 && number <= 67) || (number >= 80 && number <= 82)) {
    return isDay ? "partly-cloudy-day-rain" : "partly-cloudy-night-rain";
  }
  if ((number >= 71 && number <= 77) || number === 85 || number === 86) {
    return isDay ? "partly-cloudy-day-snow" : "partly-cloudy-night-snow";
  }
  if (number === 95 || number === 96 || number === 99) {
    return isDay ? "thunderstorms-day-rain" : "thunderstorms-night-rain";
  }
  return isDay ? "partly-cloudy-day" : "partly-cloudy-night";
}

function weatherAssetPath(code, isDay = true) {
  const motionVariant = reduceMotion ? "static" : "animated";
  return `assets/weather-animated/${motionVariant}/${weatherAssetName(code, isDay)}.svg`;
}

function syncPreferencePicker(trigger, label, menu, value, labels, disabled = false) {
  setText(label, labels[value] || value);
  trigger.disabled = disabled;
  trigger.setAttribute("aria-disabled", String(disabled));
  menu.querySelectorAll(".preference-option").forEach((option) => {
    const selected = option.dataset.value === value;
    option.setAttribute("aria-selected", String(selected));
    option.tabIndex = selected ? 0 : -1;
  });
}

function closePreferenceMenu(restoreFocus = false) {
  if (!activePreferenceMenu) return;
  const { picker, trigger, menu } = activePreferenceMenu;
  picker.classList.remove("open");
  trigger.setAttribute("aria-expanded", "false");
  menu.hidden = true;
  activePreferenceMenu = null;
  if (restoreFocus) trigger.focus();
}

function openPreferenceMenu(picker, trigger, menu) {
  if (trigger.disabled) return;
  if (activePreferenceMenu?.picker === picker) {
    closePreferenceMenu();
    return;
  }
  closePreferenceMenu();
  picker.classList.add("open");
  trigger.setAttribute("aria-expanded", "true");
  menu.hidden = false;
  activePreferenceMenu = { picker, trigger, menu };
  const selected = menu.querySelector('[aria-selected="true"]:not([hidden])')
    || menu.querySelector(".preference-option:not([hidden])");
  requestAnimationFrame(() => selected?.focus({ preventScroll: true }));
}

function bindPreferencePicker({ picker, trigger, menu, onSelect }) {
  trigger.addEventListener("click", () => openPreferenceMenu(picker, trigger, menu));
  trigger.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    openPreferenceMenu(picker, trigger, menu);
  });
  menu.addEventListener("click", (event) => {
    const option = event.target.closest(".preference-option");
    if (!option) return;
    onSelect(option.dataset.value);
    closePreferenceMenu(true);
  });
  menu.addEventListener("keydown", (event) => {
    const options = [...menu.querySelectorAll(".preference-option:not([hidden])")];
    const index = options.indexOf(document.activeElement);
    if (event.key === "Escape") {
      event.preventDefault();
      closePreferenceMenu(true);
      return;
    }
    let nextIndex = null;
    if (event.key === "ArrowDown") nextIndex = Math.min(options.length - 1, Math.max(0, index + 1));
    if (event.key === "ArrowUp") nextIndex = Math.max(0, index < 0 ? 0 : index - 1);
    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = options.length - 1;
    if (nextIndex === null) return;
    event.preventDefault();
    options[nextIndex]?.focus({ preventScroll: true });
  });
}

function loadThemePreference() {
  try {
    const saved = localStorage.getItem(themePreferenceKey);
    return themeStyles.has(saved) ? saved : "classic";
  } catch {
    return "classic";
  }
}

function applyThemePreference() {
  document.documentElement.dataset.theme = themePreference;
  syncPreferencePicker(elements.themeStyle, elements.themeStyleLabel, elements.themeStyleMenu, themePreference, themeLabels);
  try {
    localStorage.setItem(themePreferenceKey, themePreference);
  } catch { /* 设置仍在本次运行内生效。 */ }
  requestAnimationFrame(() => {
    chartPalette = readChartPalette();
    scheduleChartDraw();
  });
}

function loadActivityBandPreference() {
  try {
    const saved = JSON.parse(localStorage.getItem(activityBandPreferenceKey) || "null");
    return {
      enabled: saved?.enabled !== false,
      style: activityBandStyles.has(saved?.style) ? saved.style : "classic"
    };
  } catch {
    return { enabled: true, style: "classic" };
  }
}

function applyActivityBandPreference() {
  const { enabled, style } = activityBandPreference;
  elements.capsule.classList.toggle("activity-band-disabled", !enabled);
  elements.capsule.dataset.activityStyle = style;
  elements.activityBandToggle.setAttribute("aria-pressed", String(enabled));
  syncPreferencePicker(
    elements.activityBandStyle,
    elements.activityBandStyleLabel,
    elements.activityBandStyleMenu,
    style,
    activityBandLabels,
    !enabled
  );
  try {
    localStorage.setItem(activityBandPreferenceKey, JSON.stringify(activityBandPreference));
  } catch { /* 设置仍在本次运行内生效。 */ }
}

function loadMiniStylePreference() {
  try {
    const saved = localStorage.getItem(miniStylePreferenceKey);
    return miniStyles.has(saved) ? saved : "quota";
  } catch {
    return "quota";
  }
}

function loadAPIMiniStylePreference() {
  try {
    const saved = localStorage.getItem(apiMiniStylePreferenceKey);
    return apiMiniStyles.has(saved) ? saved : "time";
  } catch {
    return "time";
  }
}

function usesAPIMiniStyle(state = currentState) {
  const auth = String(state?.account?.auth || "");
  const recognizedAPI = auth === "API Key" || isCustomProviderState(state);
  const recognizedAccount = auth === "ChatGPT";
  try {
    if (recognizedAPI) localStorage.setItem(lastUsageModePreferenceKey, "api");
    else if (recognizedAccount) localStorage.setItem(lastUsageModePreferenceKey, "account");
    if (!recognizedAPI && !recognizedAccount) {
      return localStorage.getItem(lastUsageModePreferenceKey) === "api";
    }
  } catch { /* 本次状态仍然足以决定模式。 */ }
  return recognizedAPI;
}

function effectiveMiniStyle(state = currentState) {
  return usesAPIMiniStyle(state) ? apiMiniStylePreference : miniStylePreference;
}

function miniTaskConversationAvailable(state = currentState) {
  if (!miniMode || !state) return false;
  const mode = modeFor(state);
  return mode === "working" || mode === "attention";
}

function cycleMiniDisplay() {
  const apiMode = usesAPIMiniStyle();
  const styles = apiMode
    ? ["tokens", "weather", "time"]
    : ["quota", "tokens", "weather", "time"];
  const current = effectiveMiniStyle();
  const currentIndex = styles.indexOf(current);
  const next = styles[(currentIndex >= 0 ? currentIndex + 1 : 0) % styles.length];
  if (apiMode) apiMiniStylePreference = next;
  else miniStylePreference = next;
  applyMiniStylePreference();
}

function applyMiniStylePreference({ rerender = true } = {}) {
  const apiMode = usesAPIMiniStyle();
  const activeStyle = effectiveMiniStyle();
  elements.capsule.dataset.miniStyle = activeStyle;
  const quotaOption = elements.miniStyleMenu.querySelector('[data-value="quota"]');
  if (quotaOption) quotaOption.hidden = apiMode;
  syncPreferencePicker(
    elements.miniStyle,
    elements.miniStyleLabel,
    elements.miniStyleMenu,
    activeStyle,
    miniStyleLabels
  );
  try {
    localStorage.setItem(miniStylePreferenceKey, miniStylePreference);
    localStorage.setItem(apiMiniStylePreferenceKey, apiMiniStylePreference);
  } catch { /* 设置仍在本次运行内生效。 */ }
  if (rerender && currentState) renderMini(currentState);
}

function loadPetPreference() {
  try {
    const saved = localStorage.getItem(petPreferenceKey);
    return petCharacters.has(saved) ? saved : "dino";
  } catch {
    return "dino";
  }
}

function applyPetPreference() {
  elements.capsule.dataset.pet = petCharacterPreference;
  syncPreferencePicker(
    elements.petCharacter,
    elements.petCharacterLabel,
    elements.petCharacterMenu,
    petCharacterPreference,
    petCharacterLabels
  );
  try {
    localStorage.setItem(petPreferenceKey, petCharacterPreference);
  } catch { /* 设置仍在本次运行内生效。 */ }
  if (currentState) renderMini(currentState);
}

function previewActivityBand() {
  clearTimeout(activityBandPreviewTimer);
  elements.capsule.classList.remove("activity-band-preview");
  // 强制重新创建动画时间线，确保连续切换预设时也从左侧完整预览。
  void elements.capsule.offsetWidth;
  if (!activityBandPreference.enabled) return;
  elements.capsule.classList.add("activity-band-preview");
  activityBandPreviewTimer = setTimeout(() => {
    elements.capsule.classList.remove("activity-band-preview");
  }, 1900);
}

applyThemePreference();
applyActivityBandPreference();
applyMiniStylePreference();
applyPetPreference();

function formatTokens(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "—";
  if (Math.abs(number) >= 1_000_000_000) return `${(number / 1_000_000_000).toFixed(1)}B`;
  if (Math.abs(number) >= 1_000_000) return `${(number / 1_000_000).toFixed(1)}M`;
  if (Math.abs(number) >= 1_000) return `${(number / 1_000).toFixed(1)}K`;
  return exactNumber.format(number);
}

function formatUsageTokens(value) {
  return formatTokens(value);
}

function formatLiveUsageTokens(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "—";
  if (Math.abs(number) >= 1_000_000_000) return `${(number / 1_000_000_000).toFixed(1)}B`;
  if (Math.abs(number) >= 1_000_000) return `${(number / 1_000_000).toFixed(1)}M`;
  if (Math.abs(number) >= 1_000) return `${(number / 1_000).toFixed(1)}K`;
  return exactNumber.format(number);
}

function formatDownloadBytes(value) {
  const bytes = Math.max(0, Number(value) || 0);
  if (bytes >= 1024 ** 3) return `${(bytes / (1024 ** 3)).toFixed(2)} GB`;
  return `${(bytes / (1024 ** 2)).toFixed(1)} MB`;
}

function isCustomProviderState(state) {
  const provider = String(state?.modelProvider || "").trim().toLowerCase();
  return Boolean(provider) && provider !== "openai";
}

function usesLocalUsageState(state) {
  return state?.connection === "connected"
    && (isCustomProviderState(state) || state.account?.auth !== "ChatGPT");
}

function setText(element, value) {
  const text = String(value);
  if (element.textContent !== text) element.textContent = text;
}

let tokenRollGeneration = 0;
let tokenRollAnimations = [];
let miniMonitorRollGeneration = 0;
let miniMonitorRollAnimations = [];

function setLiveTokenText(value, animated) {
  const current = elements.todayTokens;
  const previous = elements.todayTokensPrevious;
  const nextText = String(value);
  const oldText = current.textContent || "—";
  if (oldText === nextText) return;

  tokenRollGeneration += 1;
  const generation = tokenRollGeneration;
  tokenRollAnimations.forEach((animation) => animation.cancel());
  tokenRollAnimations = [];

  if (!animated || reduceMotion || oldText === "—" || nextText === "—") {
    previous.hidden = true;
    current.textContent = nextText;
    current.style.removeProperty("transform");
    current.style.removeProperty("opacity");
    previous.style.removeProperty("transform");
    previous.style.removeProperty("opacity");
    return;
  }

  previous.textContent = oldText;
  previous.hidden = false;
  current.textContent = nextText;
  const timing = { duration: 220, easing: "cubic-bezier(.2,.78,.3,1)", fill: "both" };
  const outgoing = previous.animate([
    { transform: "translateY(0)", opacity: 1 },
    { transform: "translateY(-110%)", opacity: 0 }
  ], timing);
  const incoming = current.animate([
    { transform: "translateY(110%)", opacity: 0 },
    { transform: "translateY(0)", opacity: 1 }
  ], timing);
  const completedAnimations = [outgoing, incoming];
  tokenRollAnimations = completedAnimations;
  Promise.allSettled(completedAnimations.map((animation) => animation.finished)).then(() => {
    if (generation !== tokenRollGeneration) return;
    previous.hidden = true;
    completedAnimations.forEach((animation) => animation.cancel());
    current.style.removeProperty("transform");
    current.style.removeProperty("opacity");
    previous.style.removeProperty("transform");
    previous.style.removeProperty("opacity");
    tokenRollAnimations = [];
  });
}

function setMiniMonitorText(value, animated) {
  const current = elements.miniValue;
  const previous = elements.miniValuePrevious;
  const nextText = String(value);
  const oldText = current.textContent || "—";
  if (oldText === nextText) return;

  miniMonitorRollGeneration += 1;
  const generation = miniMonitorRollGeneration;
  miniMonitorRollAnimations.forEach((animation) => animation.cancel());
  miniMonitorRollAnimations = [];

  if (!animated || reduceMotion || oldText === "—" || nextText === "—") {
    previous.hidden = true;
    current.textContent = nextText;
    current.style.removeProperty("transform");
    current.style.removeProperty("opacity");
    return;
  }

  previous.textContent = oldText;
  previous.hidden = false;
  current.textContent = nextText;
  const timing = { duration: 240, easing: "cubic-bezier(.2,.78,.3,1)", fill: "both" };
  const outgoing = previous.animate([
    { transform: "translateY(0)", opacity: 1 },
    { transform: "translateY(-105%)", opacity: 0 }
  ], timing);
  const incoming = current.animate([
    { transform: "translateY(105%)", opacity: 0 },
    { transform: "translateY(0)", opacity: 1 }
  ], timing);
  miniMonitorRollAnimations = [outgoing, incoming];
  Promise.allSettled(miniMonitorRollAnimations.map((animation) => animation.finished)).then(() => {
    if (generation !== miniMonitorRollGeneration) return;
    previous.hidden = true;
    current.style.removeProperty("transform");
    current.style.removeProperty("opacity");
    miniMonitorRollAnimations = [];
  });
}

function releaseNotesForDisplay(markdown) {
  const fallback = "此版本未提供详细更新说明，可前往 GitHub Release 查看完整变更。";
  const source = String(markdown || "").trim();
  if (!source) return fallback;

  const rendered = source
    .replace(/\r\n?/g, "\n")
    .replace(/\*{0,2}Full Changelog\*{0,2}\s*:\s*https:\/\/github\.com\/[^\s]+\/compare\/([^\s]+?)\.\.\.([^\s)]+)/gi,
      (_match, from, to) => `完整变更：${from} → ${to}`)
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\*\*([^*\n]+)\*\*/g, "$1")
    .replace(/__([^_\n]+)__/g, "$1")
    .replace(/\[([^\]]+)]\([^)]+\)/g, "$1")
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/^[*-]\s+/gm, "• ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return rendered || fallback;
}

function setClass(element, value) {
  if (element.className !== value) element.className = value;
}

function escapeHTML(value) {
  return String(value).replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
  })[character]);
}

function limitSummary(limit) {
  if (!limit) return "—";
  return `剩余 ${Math.round(limit.remainingPercent)}% · ${formatCountdown(limit.resetsAt)}`;
}

function usageColor(remaining) {
  if (!Number.isFinite(remaining)) return "var(--orange)";
  if (remaining < 20) return "var(--red)";
  if (remaining < 60) return "var(--orange)";
  return "var(--green)";
}

function formatCountdown(timestamp) {
  if (!timestamp) return "—";
  const seconds = Math.max(0, Math.floor(timestamp * 1000 - Date.now()) / 1000);
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return days ? `${days}d ${hours}h 后重置` : hours ? `${hours}h ${minutes}m 后重置` : `${minutes}m 后重置`;
}

function formatElapsed(startedAt) {
  if (!startedAt) return "—";
  const total = Math.max(0, Math.floor((Date.now() - startedAt) / 1000));
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return minutes ? `${minutes}:${String(seconds).padStart(2, "0")}` : `${seconds}s`;
}

function informationDateParts(info, now = new Date()) {
  const timezone = info?.weather?.timezone || info?.location?.timezone || undefined;
  try {
    const options = { timeZone: timezone, hour: "2-digit", minute: "2-digit", hour12: false };
    const time = new Intl.DateTimeFormat("zh-CN", options).format(now).replace(/^24:/, "00:");
    const weekday = new Intl.DateTimeFormat("zh-CN", { timeZone: timezone, weekday: "short" }).format(now);
    return { time, weekday };
  } catch {
    const time = new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit", hour12: false }).format(now).replace(/^24:/, "00:");
    const weekday = new Intl.DateTimeFormat("zh-CN", { weekday: "short" }).format(now);
    return { time, weekday };
  }
}

function updateInformationClock() {
  const info = currentState?.informationBar;
  if (!info?.enabled) return;
  const parts = informationDateParts(info);
  setText(elements.informationWeekday, parts.weekday);
  setText(elements.informationTime, parts.time);
}

function renderMini(state, now = new Date()) {
  if (!state) return;
  const miniStyle = effectiveMiniStyle(state);
  const primary = state.limits?.[0];
  const remaining = Number(primary?.remainingPercent);
  const mode = modeFor(state);
  const weather = state.informationBar?.weather;
  const dateParts = informationDateParts(state.informationBar, now);
  let value = "—";
  let progress = 0;
  let color = "var(--blue)";
  let title = miniStyleLabels[miniStyle];

  switch (miniStyle) {
    case "tokens":
      value = state.connection === "connected"
        ? formatUsageTokens(state.usage?.today, state.usage?.todayEstimated === true)
        : "—";
      progress = 72;
      color = "var(--blue)";
      title = `今日 Token · ${value}`;
      break;
    case "status":
      value = mode === "attention" ? "授" : mode === "working" ? "思" : mode === "idle" ? "•" : "—";
      progress = mode === "working" || mode === "attention" ? 100 : mode === "idle" ? 24 : 0;
      color = mode === "attention" ? "var(--red)" : mode === "working" ? "var(--orange)" : "var(--green)";
      title = mode === "attention" ? "等待授权" : mode === "working" ? "思考中" : mode === "idle" ? "空闲" : "未连接";
      break;
    case "weather": {
      const temperature = Number(weather?.temperature);
      value = Number.isFinite(temperature) ? `${Math.round(temperature)}°` : "—";
      progress = Number.isFinite(temperature) ? 64 : 0;
      color = weather?.isDay === false ? "#8ebcff" : "#55b8ff";
      title = Number.isFinite(temperature)
        ? `${weatherLabel(weather.code, weather.isDay !== false)} ${Math.round(temperature)}${weather.unit || "°C"}`
        : "天气暂不可用";
      break;
    }
    case "time": {
      value = dateParts.time || "--:--";
      const timeParts = value.split(":").map(Number);
      progress = Number.isFinite(timeParts[1]) ? timeParts[1] / 60 * 100 : 0;
      color = "var(--blue)";
      title = `${dateParts.weekday || ""} ${value}`.trim();
      break;
    }
    case "quota":
    default: {
      const apiFallback = state.connection === "connected"
        && state.account?.auth === "API Key"
        && !primary;
      value = apiFallback ? "API" : Number.isFinite(remaining) ? `${Math.round(remaining)}%` : "—";
      progress = apiFallback ? 100 : Number.isFinite(remaining) ? Math.max(0, Math.min(100, remaining)) : 0;
      color = apiFallback ? "var(--blue)" : usageColor(remaining);
      title = apiFallback ? "API 按量计费" : Number.isFinite(remaining) ? `剩余额度 ${Math.round(remaining)}%` : "暂无额度";
      break;
    }
  }

  // 保留进度值供无障碍描述和旧结构兼容；宠物缩小态不再绘制圆环。
  const visualProgress = miniStyle === "quota" && progress >= 98 ? 100 : progress;
  const interactionPhase = Math.floor(now.getTime() / 1000) % 13;
  const petState = mode === "attention"
    ? "auth"
    : mode === "working"
    ? ((interactionPhase >= 9 && interactionPhase <= 11) ? "scratch" : "typing")
    : "idle";
  const petPath = `assets/pets-v2/codex_${petCharacterPreference}_v2_${petState}.gif`;
  if (elements.petAnimation.getAttribute("src") !== petPath) {
    elements.petAnimation.setAttribute("src", petPath);
  }
  elements.petAnimation.alt = `${petCharacterLabels[petCharacterPreference]} · ${mode === "attention" ? "等待授权" : mode === "working" ? "思考中" : mode === "idle" ? "空闲" : "未连接"}`;
  elements.capsule.classList.toggle("pet-idle", mode === "idle" || mode === "offline");
  const rawStartedAt = Number(state.task?.startedAt);
  const taskStartedAt = Number.isFinite(rawStartedAt) && rawStartedAt > 0
    ? (rawStartedAt < 1_000_000_000_000 ? rawStartedAt * 1000 : rawStartedAt)
    : now.getTime() - (now.getTime() % 8000);
  const activeElapsed = Math.max(0, (now.getTime() - taskStartedAt) / 1000);
  const accountQuotaAvailable = state.account?.auth !== "API Key" && Number.isFinite(remaining);
  const showsActiveQuota = (mode === "working" || mode === "attention")
    && accountQuotaAvailable
    && activeElapsed % 8 >= 5;
  const monitorValue = showsActiveQuota
    ? `额度${Math.round(Math.max(0, Math.min(100, remaining)))}%`
    : mode === "working"
    ? (petState === "scratch" ? "想一下" : "思考中")
    : mode === "attention"
    ? "等待授权"
    : value;
  const monitorColor = showsActiveQuota
    ? usageColor(remaining)
    : mode === "attention" ? "var(--red)" : mode === "working" ? "var(--orange)" : color;
  elements.capsule.classList.toggle("pet-quota-page", showsActiveQuota);
  setMiniMonitorText(monitorValue, miniMode);
  elements.miniCapsule.style.setProperty("--mini-progress", `${visualProgress}`);
  elements.miniCapsule.style.setProperty("--mini-color", monitorColor);
  elements.miniRingProgress.style.setProperty("--mini-progress", `${visualProgress}`);
  elements.miniRingProgress.style.setProperty("--mini-color", color);
  elements.miniRingProgress.classList.toggle("is-complete", visualProgress >= 100);
  const interactionHelp = mode === "working" || mode === "attention"
    ? "单击展开或收起当前对话"
    : "单击切换显示内容";
  elements.miniCapsule.title = `${petCharacterLabels[petCharacterPreference]} · ${title} · ${interactionHelp} · 双击恢复完整胶囊`;
  if (miniMode) {
    elements.capsule.setAttribute(
      "aria-label",
      `${petCharacterLabels[petCharacterPreference]}，${title}，${interactionHelp}，双击恢复完整胶囊`
    );
  }
}

function renderInformationBar(info = {}) {
  const enabled = Boolean(info.enabled && info.location);
  const weather = info.weather || null;
  const kind = weatherKind(weather?.code, weather?.isDay !== false);
  const dayClass = weather?.isDay === false ? "is-night" : "is-day";
  const wasEnabled = elements.capsule.classList.contains("information-enabled");
  elements.capsule.classList.toggle("information-enabled", enabled);
  elements.informationStrip.hidden = !enabled;
  elements.informationBarToggle.setAttribute("aria-pressed", String(enabled));
  elements.informationLocationButton.disabled = !enabled;
  elements.informationLocationButton.setAttribute("aria-disabled", String(!enabled));
  setText(elements.informationLocationLabel, info.location?.name || "选择地区");
  elements.informationLocationButton.title = info.location
    ? [info.location.name, info.location.admin1, info.location.country].filter(Boolean).join(" · ")
    : "选择地区";
  elements.weatherScene.className = `weather-scene weather-${kind} weather-${dayClass}${info.status === "error" ? " weather-error" : ""}`;
  const weatherAnimationPath = weatherAssetPath(weather?.code, weather?.isDay !== false);
  if (elements.weatherAnimation.getAttribute("src") !== weatherAnimationPath) {
    elements.weatherAnimation.setAttribute("src", weatherAnimationPath);
  }
  elements.weatherMiniIcon.className = `weather-mini-icon weather-${kind} weather-${dayClass}`;
  elements.informationStrip.dataset.weather = kind;
  if (!enabled) {
    clearTimeout(collapsedWidthSettleTimer);
    lastCollapsedWindowWidth = undefined;
    setText(elements.weatherSummary, "天气同步中");
    setText(elements.informationLocation, "选择地区");
    setText(elements.informationWeekday, "—");
    setText(elements.informationTime, "--:--");
    if (wasEnabled !== enabled && !expanded) scheduleCollapsedWindowWidthSync(false);
    return;
  }
  const temperature = Number(weather?.temperature);
  const weatherAge = Number.isFinite(Number(weather?.fetchedAt))
    ? Math.max(0, Date.now() - Number(weather.fetchedAt))
    : null;
  const weatherIsStale = weatherAge !== null && weatherAge > 10 * 60 * 1000;
  const weatherIsExpired = weatherAge !== null && weatherAge > 24 * 60 * 60 * 1000;
  const weatherIsCached = info.status === "error" || (info.status === "loading" && weatherIsStale);
  elements.informationStrip.classList.toggle("weather-expired", weatherIsExpired);
  const weatherText = Number.isFinite(temperature)
    ? `${weatherLabel(weather.code, weather.isDay !== false)} ${Math.round(temperature)}${weather.unit || "°C"}${weatherIsExpired ? " · 过期" : weatherIsCached ? " · 缓存" : ""}`
    : info.status === "error" ? "天气不可用" : "天气同步中";
  setText(elements.weatherSummary, weatherText);
  elements.weatherSummary.title = weatherIsExpired
    ? "天气数据已超过 24 小时，当前结果可能已过期；点击面板内刷新按钮重试"
    : info.message || (weatherIsCached ? "天气显示的是上次成功同步的结果" : "天气数据来自 Open-Meteo");
  setText(elements.informationLocation, info.location?.name || "—");
  elements.informationLocation.title = info.location
    ? `Location data by GeoNames · ${[info.location.name, info.location.admin1, info.location.country].filter(Boolean).join(" · ")}`
    : "Location data by GeoNames";
  updateInformationClock();
  if (wasEnabled !== enabled && !expanded) scheduleCollapsedWindowWidthSync(false);
}

function visibleTaskConversation(task = {}) {
  return Array.isArray(task.conversation)
    ? task.conversation.filter((message) => message
      && (message.role === "user" || message.role === "assistant")
      && typeof message.text === "string"
      && message.text.trim())
    : [];
}

function compactConversationText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function renderConversationMessages(messages, mode) {
  const signature = messages.map((message) => `${message.id}:${message.role}`).join("|");
  if (signature !== conversationStructureSignature) {
    elements.conversationMessages.replaceChildren();
    if (!messages.length) {
      const empty = document.createElement("div");
      empty.className = "conversation-empty";
      const pulse = document.createElement("span");
      pulse.className = "conversation-empty-pulse";
      const text = document.createElement("span");
      text.textContent = mode === "attention" ? "等待你确认后继续" : "Codex 正在组织回复…";
      empty.append(pulse, text);
      elements.conversationMessages.append(empty);
    } else {
      for (const message of messages) {
        const row = document.createElement("div");
        row.className = `conversation-message ${message.role}`;
        row.dataset.messageId = String(message.id || "");
        const label = document.createElement("span");
        label.className = "conversation-message-role";
        label.textContent = message.role === "user" ? "你" : "Codex";
        const text = document.createElement("p");
        text.className = "conversation-message-text";
        text.textContent = message.text;
        row.append(label, text);
        elements.conversationMessages.append(row);
      }
    }
    conversationStructureSignature = signature;
  } else if (messages.length) {
    const rows = elements.conversationMessages.querySelectorAll(".conversation-message");
    messages.forEach((message, index) => {
      const text = rows[index]?.querySelector(".conversation-message-text");
      if (text && text.textContent !== message.text) text.textContent = message.text;
    });
  } else {
    const emptyText = elements.conversationMessages.querySelector(".conversation-empty span:last-child");
    const value = mode === "attention" ? "等待你确认后继续" : "Codex 正在组织回复…";
    if (emptyText && emptyText.textContent !== value) emptyText.textContent = value;
  }
  const live = mode === "working" || messages.some((message) => message.isStreaming);
  elements.conversationLiveLabel.hidden = !live;
  if (conversationExpanded || miniConversationExpanded) {
    requestAnimationFrame(() => {
      elements.conversationMessages.scrollTop = elements.conversationMessages.scrollHeight;
    });
  }
}

function setConversationExpanded(nextExpanded) {
  const taskActive = currentState
    && (modeFor(currentState) === "working" || modeFor(currentState) === "attention")
    && elements.capsule.classList.contains("information-enabled")
    && !expanded
    && !miniMode;
  const next = Boolean(nextExpanded && taskActive);
  if (conversationExpanded === next) return;
  if (next && miniConversationExpanded) setMiniConversationExpanded(false, { immediate: true });
  conversationExpanded = next;
  clearTimeout(conversationCollapseTimer);
  elements.informationStrip.setAttribute("aria-expanded", String(next));
  const root = document.documentElement;
  if (next) {
    const collapsedRect = elements.informationStrip.getBoundingClientRect();
    elements.conversationDetail.style.setProperty(
      "--conversation-origin-scale-x",
      String(Math.max(0.05, collapsedRect.width / 342))
    );
    elements.conversationDetail.style.setProperty(
      "--conversation-origin-scale-y",
      String(Math.max(0.03, collapsedRect.height / 270))
    );
    root.classList.remove("conversation-closing");
    root.classList.add("conversation-expanded");
    elements.conversationDetail.hidden = false;
    elements.conversationDetail.setAttribute("aria-hidden", "false");
    // Commit the pill-sized start frame before adding `.open`. Without this
    // read Chromium can coalesce both mutations and skip the outward morph.
    elements.conversationDetail.getBoundingClientRect();
    requestAnimationFrame(() => {
      elements.conversationDetail.classList.add("open");
      scheduleWindowShapeSync();
    });
  } else {
    root.classList.remove("conversation-expanded");
    root.classList.add("conversation-closing");
    elements.conversationDetail.classList.remove("open");
    elements.conversationDetail.setAttribute("aria-hidden", "true");
    conversationCollapseTimer = setTimeout(() => {
      if (conversationExpanded) return;
      elements.conversationDetail.hidden = true;
      root.classList.remove("conversation-closing");
      scheduleWindowShapeSync();
    }, reduceMotion ? 0 : 300);
  }
}

function setMiniConversationExpanded(nextExpanded, { immediate = false } = {}) {
  const next = Boolean(nextExpanded && miniTaskConversationAvailable());
  if (miniConversationExpanded === next
      && !(immediate && !next && !elements.conversationDetail.hidden)) return;
  miniConversationExpanded = next;
  clearTimeout(miniConversationCollapseTimer);
  const root = document.documentElement;
  const mode = currentState ? modeFor(currentState) : "idle";
  if (next) {
    const monitor = elements.miniCapsule.querySelector(".pet-monitor-frame").getBoundingClientRect();
    elements.conversationDetail.style.setProperty(
      "--conversation-origin-scale-x",
      String(Math.max(0.05, monitor.width / 342))
    );
    elements.conversationDetail.style.setProperty(
      "--conversation-origin-scale-y",
      String(Math.max(0.03, monitor.height / 246))
    );
    root.classList.add("mini-conversation-expanded");
    root.classList.toggle("mini-conversation-attention", mode === "attention");
    if (conversationExpanded) setConversationExpanded(false);
    renderConversationMessages(visibleTaskConversation(currentState?.task), mode);
    elements.conversationDetail.hidden = false;
    elements.conversationDetail.setAttribute("aria-hidden", "false");
    // Keep the pet fixed while the conversation surface grows from its monitor.
    elements.conversationDetail.getBoundingClientRect();
    requestAnimationFrame(() => {
      elements.conversationDetail.classList.add("open");
      scheduleWindowShapeSync();
    });
  } else {
    elements.conversationDetail.classList.remove("open");
    elements.conversationDetail.setAttribute("aria-hidden", "true");
    const finish = () => {
      if (miniConversationExpanded || conversationExpanded) return;
      elements.conversationDetail.hidden = true;
      root.classList.remove("mini-conversation-expanded");
      root.classList.remove("mini-conversation-attention");
      scheduleWindowShapeSync();
    };
    if (immediate || reduceMotion) finish();
    else miniConversationCollapseTimer = setTimeout(finish, 320);
  }
  if (currentState) renderMini(currentState);
  scheduleWindowShapeSync();
}

function handleMiniSingleClick() {
  if (miniTaskConversationAvailable()) {
    setMiniConversationExpanded(!miniConversationExpanded);
  } else {
    cycleMiniDisplay();
  }
}

function renderTaskInformation(state, mode) {
  const enabled = elements.capsule.classList.contains("information-enabled");
  const taskActive = enabled && (mode === "working" || mode === "attention") && !expanded && !miniMode;
  const messages = visibleTaskConversation(state.task);
  const assistant = [...messages].reverse().find((message) => message.role === "assistant");
  const summary = compactConversationText(
    assistant?.text || state.task?.title || (mode === "attention" ? "等待你确认后继续" : "Codex 正在组织回复…")
  );
  elements.informationStrip.classList.toggle("task-streaming", taskActive);
  elements.informationStrip.classList.toggle("task-attention", taskActive && mode === "attention");
  elements.informationStrip.disabled = !taskActive;
  elements.informationWeatherContent.setAttribute("aria-hidden", String(taskActive));
  elements.informationTaskContent.setAttribute("aria-hidden", String(!taskActive));
  setText(elements.informationTaskStatus, mode === "attention" ? "等待授权" : "思考中");
  const nextSummary = summary || "Codex 正在组织回复…";
  const summaryChanged = elements.informationTaskSummary.textContent !== nextSummary;
  setText(elements.informationTaskSummary, nextSummary);
  elements.informationTaskSummary.title = summary;
  const motionNow = performance.now();
  if (taskActive && summaryChanged && !reduceMotion && motionNow - lastTaskSummaryMotionAt >= 120) {
    lastTaskSummaryMotionAt = motionNow;
    taskSummaryAnimation?.cancel();
    taskSummaryAnimation = elements.informationTaskSummary.animate([
      { transform: "translateY(4px)", opacity: .38 },
      { transform: "translateY(0)", opacity: 1 }
    ], {
      duration: 180,
      easing: "cubic-bezier(.16,1,.3,1)"
    });
  }
  requestAnimationFrame(() => {
    const summaryElement = elements.informationTaskSummary;
    summaryElement.scrollLeft = summaryElement.scrollWidth;
  });
  renderConversationMessages(messages, mode);
  if (!taskActive && conversationExpanded) setConversationExpanded(false);
  const miniTaskActive = miniMode && (mode === "working" || mode === "attention");
  if (!miniTaskActive && miniConversationExpanded) setMiniConversationExpanded(false);
  document.documentElement.classList.toggle(
    "mini-conversation-attention",
    miniConversationExpanded && mode === "attention"
  );
}

function scheduleCollapsedWindowWidthSync(syncAfterRingTransition = true) {
  if (collapsedWidthFrame) cancelAnimationFrame(collapsedWidthFrame);
  if (syncAfterRingTransition) {
    clearTimeout(collapsedWidthSettleTimer);
    collapsedWidthSettleTimer = setTimeout(
      () => scheduleCollapsedWindowWidthSync(false),
      260
    );
  }
  collapsedWidthFrame = requestAnimationFrame(() => {
    collapsedWidthFrame = undefined;
    if (expanded || miniMode || miniTransitioning) return;
    const stage = document.querySelector(".stage");
    const stageStyle = getComputedStyle(stage);
    const horizontalPadding = parseFloat(stageStyle.paddingLeft) + parseFloat(stageStyle.paddingRight);
    const informationEnabled = elements.capsule.classList.contains("information-enabled");
    const widthProperty = informationEnabled
      ? "--information-capsule-width"
      : "--compact-capsule-width";
    // Measure intrinsic content first, then apply the exact macOS base width.
    // Only a long Token value is allowed to grow the capsule toward the right.
    elements.capsule.style.setProperty(widthProperty, "max-content");
    const naturalCapsuleWidth = elements.capsule.getBoundingClientRect().width;
    const macBaseWidth = (informationEnabled ? 275 : 235)
      + (elements.capsule.classList.contains("has-update") ? 28 : 0);
    const expandedCapsuleWidth = Math.max(macBaseWidth, Math.ceil(naturalCapsuleWidth));
    elements.capsule.style.setProperty(
      widthProperty,
      `${expandedCapsuleWidth}px`
    );
    hoverGeometry = null;
    elements.capsule.dataset.naturalWidth = String(naturalCapsuleWidth);
    elements.capsule.dataset.expandedWidth = String(expandedCapsuleWidth);
    scheduleWindowShapeSync();
    const targetWidth = Math.max(283, Math.min(471, Math.ceil(
      expandedCapsuleWidth + horizontalPadding
    )));
    if (lastCollapsedWindowWidth === targetWidth) return;
    lastCollapsedWindowWidth = targetWidth;
    adaptiveResizeInFlight = true;
    clearTimeout(adaptiveResizeReleaseTimer);
    void window.pulse.resize({
      mode: "collapsed",
      width: targetWidth,
      informationEnabled
    }).finally(() => {
      adaptiveResizeReleaseTimer = setTimeout(() => {
        adaptiveResizeInFlight = false;
      }, 80);
    });
  });
}

function paddedShapeRect(element, horizontalPadding, verticalPadding = horizontalPadding) {
  const rect = element.getBoundingClientRect();
  const left = Math.max(0, Math.floor(rect.left - horizontalPadding));
  const top = Math.max(0, Math.floor(rect.top - verticalPadding));
  const right = Math.min(innerWidth, Math.ceil(rect.right + horizontalPadding));
  const bottom = Math.min(innerHeight, Math.ceil(rect.bottom + verticalPadding));
  return { x: left, y: top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };
}

function currentWindowShape(expandedState = expanded) {
  if (miniMode) {
    const rects = [paddedShapeRect(elements.capsule, 12, 12)];
    if (!elements.conversationDetail.hidden) {
      rects.push(paddedShapeRect(elements.conversationDetail, 14, 18));
    }
    return rects;
  }
  // Keep the independently rendered hover/activity halo inside the native
  // Windows shape. Without this extra transparent perimeter setShape clips
  // the blur back to a thin colored line at the capsule edge.
  const capsuleRect = paddedShapeRect(elements.capsule, 14, 10);
  if (expandedState) {
    // The detail card starts at scale(.96) like macOS and grows to 1.0.
    // Keep enough native shape headroom for its final bounds throughout the
    // animation so the last few pixels never become temporarily non-clickable.
    const detailRect = paddedShapeRect(elements.detail, 18, 28);
    const left = Math.min(capsuleRect.x, detailRect.x);
    const top = Math.min(capsuleRect.y, detailRect.y);
    const right = Math.max(capsuleRect.x + capsuleRect.width, detailRect.x + detailRect.width);
    const bottom = Math.max(capsuleRect.y + capsuleRect.height, detailRect.y + detailRect.height);
    return [{ x: left, y: top, width: right - left, height: bottom - top }];
  }
  const rects = [capsuleRect];
  if (!elements.informationStrip.hidden) rects.push(paddedShapeRect(elements.informationStrip, 18, 16));
  if (!elements.conversationDetail.hidden) rects.push(paddedShapeRect(elements.conversationDetail, 18, 20));
  return rects;
}

async function syncWindowShape(expandedState = expanded) {
  if (typeof window.pulse.setWindowShape !== "function") return false;
  try { return await window.pulse.setWindowShape(currentWindowShape(expandedState)); }
  catch { return false; }
}

function scheduleWindowShapeSync() {
  if (windowShapeFrame) cancelAnimationFrame(windowShapeFrame);
  windowShapeFrame = requestAnimationFrame(() => {
    windowShapeFrame = null;
    void syncWindowShape();
  });
}

function modeFor(state) {
  if (state.connection !== "connected") return "offline";
  return state.task?.state || "idle";
}

function updateTaskMetric(state, mode = modeFor(state)) {
  const hasActiveTask = mode === "working" || mode === "attention";
  setText(elements.taskMetricLabel, hasActiveTask ? "任务时间" : "在线天数");
  setText(
    elements.taskElapsed,
    hasActiveTask
      ? formatElapsed(state.task?.startedAt)
      : state.connection === "connected" && Number.isFinite(Number(state.usage?.streakDays))
        ? `${Math.max(0, Math.round(Number(state.usage.streakDays)))}天`
        : "—"
  );
}

function tunnelPoint(progress, lane, width, height) {
  const centerY = height * 0.52;
  const mergeX = width * 0.47;
  const mergeProgress = 0.60;
  if (progress > mergeProgress) {
    const t = (progress - mergeProgress) / (1 - mergeProgress);
    return { x: mergeX + (width - mergeX) * t, y: centerY };
  }
  const t = progress / mergeProgress;
  const inverse = 1 - t;
  const p0 = { x: 0, y: centerY + lane * height * .43 };
  const p1 = { x: width * .16, y: p0.y };
  const p2 = { x: mergeX - width * .12, y: centerY + lane * height * .055 };
  const p3 = { x: mergeX, y: centerY };
  return {
    x: inverse ** 3 * p0.x + 3 * inverse ** 2 * t * p1.x + 3 * inverse * t ** 2 * p2.x + t ** 3 * p3.x,
    y: inverse ** 3 * p0.y + 3 * inverse ** 2 * t * p1.y + 3 * inverse * t ** 2 * p2.y + t ** 3 * p3.y
  };
}

function drawTaskTunnel(timestamp = performance.now()) {
  const canvas = elements.taskTunnelCanvas;
  if (!canvas || tunnelMode === "idle") return;
  const width = 304;
  const height = 52;
  const dpr = Math.min(1.5, window.devicePixelRatio || 1);
  if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
  }
  const context = canvas.getContext("2d", { alpha: true });
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, width, height);
  const centerY = height * .52;
  const mergeX = width * .47;
  const attention = tunnelMode === "attention";
  const accent = attention ? "255,69,58" : "255,159,10";
  const incoming = "61,184,255";

  context.lineWidth = .7;
  for (let index = 0; index < 12; index += 1) {
    const lane = index / 11 * 2 - 1;
    const startY = centerY + lane * height * .43;
    context.beginPath();
    context.moveTo(0, startY);
    context.bezierCurveTo(width * .16, startY, mergeX - width * .12, centerY + lane * height * .055, mergeX, centerY);
    context.strokeStyle = `rgba(${incoming},.20)`;
    context.stroke();
  }

  const outputGradient = context.createLinearGradient(mergeX, 0, width, 0);
  outputGradient.addColorStop(0, `rgba(${accent},.72)`);
  outputGradient.addColorStop(1, `rgba(${accent},.12)`);
  context.beginPath();
  context.moveTo(mergeX, centerY);
  context.lineTo(width, centerY);
  context.strokeStyle = outputGradient;
  context.lineWidth = 1;
  context.stroke();

  const pulse = .75 + Math.sin(timestamp / (attention ? 260 : 420)) * .18;
  context.beginPath();
  context.arc(mergeX, centerY, 5.5, 0, Math.PI * 2);
  context.fillStyle = `rgba(${accent},${.08 * pulse})`;
  context.fill();
  context.beginPath();
  context.arc(mergeX, centerY, 2.1, 0, Math.PI * 2);
  context.fillStyle = `rgba(${accent},${.9 * pulse})`;
  context.fill();

  const seconds = timestamp / 1000;
  const speed = attention ? .10 : .23;
  for (let index = 0; index < 9; index += 1) {
    const progress = (index / 9 + seconds * speed) % 1;
    const lane = (((index * 7 + 3) % 12) / 11) * 2 - 1;
    const point = tunnelPoint(progress, lane, width, height);
    const tail = tunnelPoint(Math.max(0, progress - .045), lane, width, height);
    const particleColor = progress < .60 ? incoming : accent;
    const trail = context.createLinearGradient(tail.x, tail.y, point.x, point.y);
    trail.addColorStop(0, `rgba(${particleColor},0)`);
    trail.addColorStop(1, `rgba(${particleColor},.95)`);
    context.beginPath();
    context.moveTo(tail.x, tail.y);
    context.lineTo(point.x, point.y);
    context.strokeStyle = trail;
    context.lineWidth = 1.5;
    context.stroke();
    context.beginPath();
    context.arc(point.x, point.y, 1.45, 0, Math.PI * 2);
    context.fillStyle = `rgba(${particleColor},.98)`;
    context.fill();
  }
}

function animateTaskTunnel(timestamp) {
  tunnelFrame = null;
  if (!expanded || tunnelMode === "idle") return;
  if (timestamp - tunnelLastFrame >= 32) {
    tunnelLastFrame = timestamp;
    drawTaskTunnel(timestamp);
  }
  tunnelFrame = requestAnimationFrame(animateTaskTunnel);
}

function updateTaskTunnel(mode) {
  tunnelMode = mode === "working" || mode === "attention" ? mode : "idle";
  const visible = tunnelMode !== "idle";
  elements.taskTunnel.classList.toggle("active", visible);
  elements.taskTunnel.setAttribute("aria-hidden", String(!visible));
  elements.taskTunnel.style.setProperty("--tunnel-color", tunnelMode === "attention" ? "var(--red)" : "var(--orange)");
  setText(elements.tunnelOutputLabel, tunnelMode === "attention" ? "等待继续" : "响应流");
  if (tunnelFrame) cancelAnimationFrame(tunnelFrame);
  tunnelFrame = null;
  if (visible) drawTaskTunnel();
  if (visible && expanded && !reduceMotion) tunnelFrame = requestAnimationFrame(animateTaskTunnel);
}

function render(state) {
  currentState = state;
  applyMiniStylePreference({ rerender: false });
  const mode = modeFor(state);
  renderInformationBar(state.informationBar || {});
  renderTaskInformation(state, mode);
  const primary = state.limits?.[0];
  const secondary = state.limits?.[1];
  const remaining = primary?.remainingPercent;
  const connected = state.connection === "connected";
  const localUsageMode = usesLocalUsageState(state);
  const apiUsageFallback = localUsageMode && (!primary || isCustomProviderState(state));
  const taskActive = mode === "working" || mode === "attention";

  elements.capsule.classList.toggle("task-active", taskActive);
  elements.capsule.classList.toggle("task-attention", mode === "attention");
  elements.detail.classList.toggle("connected", connected);
  elements.detail.classList.toggle("task-active", taskActive);
  elements.cliInfo.setAttribute("aria-hidden", String(taskActive));
  setClass(elements.statusDot, `status-dot ${mode}`);
  setClass(elements.taskBadge, `task-badge ${mode}`);
  setText(elements.taskBadge, mode === "offline" ? "未连接" : state.task.label);
  const quotaValue = apiUsageFallback ? "API" : (remaining === undefined ? "—" : `${Math.round(remaining)}%`);
  setClass(elements.quotaRing, `quota-ring${apiUsageFallback ? " api" : ""}${quotaValue.length >= 4 ? " wide" : ""}`);
  setText(elements.remaining, quotaValue);
  const quotaProgress = Math.max(0, Math.min(100, remaining || 0));
  elements.quotaArc.style.setProperty("--quota", `${quotaProgress >= 98 ? 100 : quotaProgress}%`);
  setLiveTokenText(connected
    ? taskActive
      ? formatLiveUsageTokens(state.usage?.today)
      : formatUsageTokens(state.usage?.today, state.usage?.todayEstimated === true)
    : "—", taskActive);
  setText(elements.email, state.account?.maskedEmail || "—");
  const providerLabel = isCustomProviderState(state) ? state.modelProvider : state.account?.plan;
  setText(elements.plan, `${providerLabel || "—"} · ${state.account?.auth || "—"}`);
  const genericConnectedMessage = !state.message || state.message === "已连接";
  const connectionMessage = connected && genericConnectedMessage
    ? localUsageMode
      ? state.usage?.todayEstimated
        ? "已连接 · 本机 session 估算，非账单"
        : "已连接 · 本机 session 汇总，非账单"
      : `已连接 · 更新于 ${new Date(state.updatedAt || Date.now()).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })}`
    : state.message || "—";
  setText(elements.connectionMessage, connectionMessage);
  elements.connectionMessage.title = localUsageMode
    ? "第三方/API Key 模式下今日和近 7 日来自本机 Codex session；无法替代服务商账单"
    : connectionMessage;
  setText(elements.chooseCodex, state.connection === "discovering"
    ? "获取中…"
    : state.connection === "connecting" ? "连接中…" : "获取路径");
  elements.chooseCodex.disabled = state.connection === "discovering" || state.connection === "connecting";
  elements.chooseCodex.hidden = connected;
  setText(elements.limitTitle, apiUsageFallback ? "API 用量" : "每周用量");
  setText(elements.resetTime, apiUsageFallback ? "按 Token 计费" : limitSummary(primary));
  const remainingWidth = Math.max(0, Math.min(100, Number(remaining) || 0));
  elements.progressFill.style.width = `${remainingWidth}%`;
  elements.progressFill.style.setProperty("--progress-color", usageColor(remaining));
  elements.progressTrack.hidden = apiUsageFallback;
  setText(elements.secondaryLimit, apiUsageFallback
    ? "第三方/API Key 不使用 ChatGPT 额度 · Token 为本机汇总，非账单"
    : secondary
      ? `${secondary.name} · 剩余 ${Math.round(secondary.remainingPercent)}% · ${formatCountdown(secondary.resetsAt)}`
      : "5 小时用量 · 暂无数据");
  elements.cardsToggle.hidden = apiUsageFallback;
  elements.cardsList.hidden = apiUsageFallback;
  if (apiUsageFallback && cardsExpanded) {
    cardsExpanded = false;
    elements.cardsToggle.setAttribute("aria-expanded", "false");
    elements.cardsList.classList.remove("open");
    elements.detail.classList.remove("cards-open");
  }
  setText(elements.todayDetail, connected
    ? formatUsageTokens(state.usage?.today, state.usage?.todayEstimated === true)
    : "—");
  const hasLocalDaily = state.usage?.localDailyAvailable === true;
  setText(elements.totalTokens, localUsageMode
    ? hasLocalDaily
      ? formatUsageTokens(state.usage?.localSevenDayTokens, state.usage?.localHistoryEstimated === true)
      : "—"
    : connected ? formatTokens(state.usage?.total) : "—");
  setText(elements.totalMetricLabel, localUsageMode ? "本机近 7 日" : "累计");
  elements.totalTokens.title = localUsageMode
    ? "本机 Codex session 近 7 日汇总，不是 OpenAI 账户累计或账单"
    : "账户累计 Token";
  const usageSource = localUsageMode
    ? state.usage?.todayEstimated
      ? "第三方模型未提供 usage；当前数字来自本机 session 文本估算，不是服务商账单"
      : "第三方/API Key 模式：今日与近 7 日来自本机全部 session 的真实 token_count/usage 汇总"
    : "今日 Token 取 Codex App Server 与本机当天全部 session 汇总中的较大值；切换账号后立即更新";
  elements.todayTokens.title = usageSource;
  elements.todayDetail.title = usageSource;

  const update = state.appUpdate || {};
  const updateActionStates = new Set(["available", "downloading", "ready", "installing", "download-error"]);
  const hasAvailableUpdate = updateActionStates.has(update.status) && Boolean(update.availableVersion);
  elements.updateIndicator.hidden = !hasAvailableUpdate;
  elements.updateIndicator.title = hasAvailableUpdate
    ? `发现新版本 v${update.availableVersion} · 点击查看更新内容`
    : "";
  elements.capsule.classList.toggle("has-update", hasAvailableUpdate);
  setText(elements.updateVersionRoute, `v${update.currentVersion || "—"}  →  v${update.availableVersion || "—"}`);
  setText(elements.updateReleaseTitle, update.releaseTitle || `CodexPulse v${update.availableVersion || "—"}`);
  setText(elements.updateReleaseNotes, releaseNotesForDisplay(update.releaseNotes));
  const showsUpdateProgress = ["downloading", "ready", "installing", "download-error"].includes(update.status);
  const progress = Number.isFinite(Number(update.downloadProgress))
    ? Math.max(0, Math.min(1, Number(update.downloadProgress)))
    : null;
  elements.updateProgress.hidden = !showsUpdateProgress;
  setText(elements.updateProgressStatus, update.message || "正在准备更新…");
  setText(elements.updateProgressLabel,
    update.status === "ready" ? "完成"
      : update.status === "installing" ? "重启"
        : progress === null ? "—" : `${Math.round(progress * 100)}%`);
  elements.updateProgressFill.style.width = `${Math.round((progress || 0) * 100)}%`;
  elements.updateProgress.classList.toggle("ready", update.status === "ready");
  elements.updateProgress.classList.toggle("failed", update.status === "download-error");
  const downloadedSize = formatDownloadBytes(update.downloadedBytes);
  const totalSize = formatDownloadBytes(update.totalBytes);
  setText(elements.updateProgressSize,
    Number(update.totalBytes) > 0 ? `${downloadedSize} / ${totalSize}` : downloadedSize);
  setText(elements.installUpdateButton,
    update.status === "downloading" ? `下载中 ${Math.round((progress || 0) * 100)}%`
      : update.status === "ready" ? "重启并更新"
        : update.status === "installing" ? "正在重启…"
          : update.status === "download-error" ? "重新下载" : "立即更新");
  elements.installUpdateButton.disabled = update.status === "downloading" || update.status === "installing";
  elements.skipUpdateButton.disabled = update.status === "downloading" || update.status === "installing";
  if (!hasAvailableUpdate && detailMode === "update") {
    setDetailMode("standard");
    if (expanded) setExpanded(false);
  }
  elements.tokenChart.title = usageSource;
  updateTaskMetric(state, mode);
  setText(elements.cliInfo, state.cliPath ? `Codex：${state.cliPath}` : "Codex 路径：等待自动检测");
  updateTaskTunnel(mode);
  renderMini(state);

  const nextCardsSignature = JSON.stringify(state.resetCards || []);
  if (cardsSignature !== nextCardsSignature) {
    cardsSignature = nextCardsSignature;
    renderCards();
  }
  const nextChartSignature = JSON.stringify(state.usage?.daily || []);
  if (chartSignature !== nextChartSignature) {
    chartSignature = nextChartSignature;
    scheduleChartDraw();
  }
  scheduleCollapsedWindowWidthSync();
  scheduleWindowShapeSync();
}

function renderCards() {
  const cards = [...(currentState?.resetCards || [])].sort((left, right) => {
    if (left.available !== right.available) return left.available ? -1 : 1;
    return (left.expiresAt || Number.MAX_SAFE_INTEGER) - (right.expiresAt || Number.MAX_SAFE_INTEGER);
  });
  const availableCount = cards.filter((card) => card.available).length;
  const nearest = cards.find((card) => card.available && card.expiresAt)?.expiresAt;
  setText(elements.cardsSummary, cards.length ? `${availableCount} 张可用 · 共 ${cards.length} 张` : "暂无明细");
  setText(elements.cardsNearest, nearest ? `最近 ${relativeExpiration(nearest)}` : "");
  elements.cardsList.innerHTML = cards.length
    ? cards.map((card, index) => {
        const expiration = card.expiresAt ? resetCardExpiration(card.expiresAt) : "官方明细暂未返回";
        const expirationClass = expirationColorClass(card.expiresAt);
        const types = Array.isArray(card.applicableLimitTypes) ? card.applicableLimitTypes : [];
        const statusIcon = card.available
          ? '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="7"/><path d="m4.8 8.1 2 2 4.4-4.5"/></svg>'
          : '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="7"/><path d="m5.5 5.5 5 5m0-5-5 5"/></svg>';
        return `<div class="card-item">
          <span class="card-status-icon${card.available ? "" : " unavailable"}" aria-hidden="true">${statusIcon}</span>
          <div class="card-copy">
            <div class="card-title-row"><strong>重置卡 ${index + 1}</strong><span class="card-availability${card.available ? "" : " unavailable"}">${card.available ? "可用" : "不可用"}</span></div>
            <div class="card-expiry"><span>到期</span><strong class="${expirationClass}">${escapeHTML(expiration)}</strong></div>
            ${types.length ? `<div class="card-applicable">适用：${escapeHTML(types.join("、"))}</div>` : ""}
          </div>
        </div>`;
      }).join("")
    : '<div class="card-item empty-card"><span class="card-status-icon unavailable" aria-hidden="true"><svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="7"/><path d="M5 8h6"/></svg></span><span>暂无重置卡数据</span></div>';
}

function relativeExpiration(timestamp) {
  const seconds = Math.round(timestamp * 1000 - Date.now()) / 1000;
  if (seconds <= 0) return "已到期";
  if (seconds < 3600) return `${Math.max(1, Math.ceil(seconds / 60))}分钟后`;
  if (seconds < 48 * 3600) return `${Math.ceil(seconds / 3600)}小时后`;
  const days = Math.ceil(seconds / 86400);
  if (days < 14) return `${days}天后`;
  if (days < 60) return `${Math.ceil(days / 7)}周后`;
  return `${Math.ceil(days / 30)}个月后`;
}

function resetCardExpiration(timestamp) {
  const date = new Date(timestamp * 1000);
  const now = new Date();
  const sameYear = date.getFullYear() === now.getFullYear();
  const prefix = sameYear ? "" : `${date.getFullYear()}年`;
  const time = `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
  return `${prefix}${date.getMonth() + 1}月${date.getDate()}日 ${time}（${relativeExpiration(timestamp)}）`;
}

function expirationColorClass(timestamp) {
  if (!timestamp) return "";
  const remaining = timestamp * 1000 - Date.now();
  if (remaining <= 24 * 3600 * 1000) return "urgent";
  if (remaining < 3 * 24 * 3600 * 1000) return "warning";
  return "";
}

function drawChart() {
  const canvas = elements.tokenChart;
  const dpr = window.devicePixelRatio || 1;
  const width = 304;
  const height = 130;
  if (canvas.width !== width * dpr || canvas.height !== height * dpr) {
    canvas.width = width * dpr;
    canvas.height = height * dpr;
  }
  const context = canvas.getContext("2d");
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
  context.clearRect(0, 0, width, height);
  const data = currentState?.usage?.daily?.length ? currentState.usage.daily : Array.from({ length: 7 }, (_, index) => ({ date: `0${index + 1}`, tokens: 0 }));
  const pad = { left: 8, right: 8, top: 12, bottom: 19 };
  const plotWidth = width - pad.left - pad.right;
  const plotHeight = height - pad.top - pad.bottom;
  const peak = Math.max(1, ...data.map((item) => Number(item.tokens) || 0)) * 1.15;
  const points = data.map((item, index) => ({
    x: pad.left + (plotWidth * index) / Math.max(1, data.length - 1),
    y: pad.top + plotHeight - ((Number(item.tokens) || 0) / peak) * plotHeight,
    item
  }));

  const { blue, muted, line } = chartPalette;
  context.lineWidth = 1;
  context.strokeStyle = line;
  for (let row = 0; row < 3; row += 1) {
    const y = pad.top + (plotHeight * row) / 2;
    context.beginPath(); context.moveTo(pad.left, y); context.lineTo(width - pad.right, y); context.stroke();
  }

  const gradient = context.createLinearGradient(0, pad.top, 0, height - pad.bottom);
  gradient.addColorStop(0, "rgba(24,144,255,.26)");
  gradient.addColorStop(1, "rgba(24,144,255,.01)");
  context.beginPath();
  points.forEach((point, index) => index ? context.lineTo(point.x, point.y) : context.moveTo(point.x, point.y));
  context.lineTo(points[points.length - 1].x, height - pad.bottom);
  context.lineTo(points[0].x, height - pad.bottom);
  context.closePath(); context.fillStyle = gradient; context.fill();

  context.beginPath();
  points.forEach((point, index) => index ? context.lineTo(point.x, point.y) : context.moveTo(point.x, point.y));
  context.strokeStyle = blue; context.lineWidth = 2; context.lineJoin = "round"; context.stroke();
  context.font = "8px Segoe UI";
  context.textAlign = "center";
  points.forEach((point, index) => {
    const selected = index === hoveredChartIndex;
    if (selected) {
      context.save(); context.setLineDash([3, 3]); context.strokeStyle = "rgba(24,144,255,.48)"; context.lineWidth = 1;
      context.beginPath(); context.moveTo(point.x, pad.top); context.lineTo(point.x, height - pad.bottom); context.stroke(); context.restore();
    }
    context.beginPath(); context.arc(point.x, point.y, selected ? 4.5 : 2.3, 0, Math.PI * 2); context.fillStyle = blue; context.fill();
    context.fillStyle = muted; context.fillText(String(point.item.date).slice(-5), point.x, height - 4);
  });

  if (hoveredChartIndex !== null && points[hoveredChartIndex]) {
    const item = points[hoveredChartIndex].item;
    elements.chartValue.textContent = `${item.date}\n${exactNumber.format(item.tokens)} Token`;
  } else {
    const sum = data.reduce((total, item) => total + (Number(item.tokens) || 0), 0);
    elements.chartValue.textContent = `合计 ${formatTokens(sum)}`;
  }
}

function scheduleChartDraw() {
  if (chartFrame) return;
  chartFrame = requestAnimationFrame(() => {
    chartFrame = null;
    drawChart();
  });
}

function setMoreSettingsExpanded(nextExpanded) {
  const settingsExpanded = Boolean(nextExpanded);
  closePreferenceMenu();
  elements.moreSettingsToggle.setAttribute("aria-expanded", String(settingsExpanded));
  elements.appearanceSettings.hidden = !settingsExpanded;
  elements.detail.classList.toggle("settings-open", settingsExpanded);
  requestAnimationFrame(scheduleWindowShapeSync);
}

function setDetailMode(mode) {
  detailMode = mode === "update" ? "update" : "standard";
  const showingUpdate = detailMode === "update";
  elements.detail.classList.toggle("update-mode", showingUpdate);
  elements.updateDetail.hidden = !showingUpdate;
  elements.updateDetail.setAttribute("aria-hidden", String(!showingUpdate));
  if (showingUpdate) {
    closePreferenceMenu();
    closeLocationChooser();
    setMoreSettingsExpanded(false);
  }
  requestAnimationFrame(scheduleWindowShapeSync);
}

function showUpdateDetails() {
  if (!currentState?.appUpdate?.availableVersion) return;
  clearTimeout(capsuleSingleClickTimer);
  setDetailMode("update");
  if (expanded) {
    requestAnimationFrame(scheduleWindowShapeSync);
  } else {
    setExpanded(true);
  }
}

function nextCompositeFrame() {
  return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
}

async function runCapsuleMorphTransition(mutate) {
  if (reduceMotion) {
    mutate();
    await nextCompositeFrame();
    return;
  }

  // Keep the outgoing animation holding opacity at zero until the incoming
  // animation has already taken ownership. The old implementation cancelled
  // before the DOM swap had composited, exposing the mini ring for two frames.
  // A non-overlapping handoff also avoids showing full and mini capsules at
  // once, which reads as a bright circular flash on transparent Windows.
  let incoming;
  const outgoing = elements.capsule.animate([
    { transform: "translate3d(0, 0, 0) scale(1)", opacity: 1 },
    { transform: "translate3d(0, 0, 0) scale(.72)", opacity: 0 }
  ], {
    duration: 150,
    easing: "cubic-bezier(.4,0,.6,1)",
    fill: "both"
  });
  try { await outgoing.finished; }
  catch { /* A newer state change or window resize may cancel the animation. */ }

  // Freeze the fully transparent outgoing state in ordinary inline style,
  // then dispose its compositor animation before changing the layout. This
  // prevents DirectComposition from retaining an old mini-ring animation
  // surface while the full quota ring is entering.
  elements.capsule.style.opacity = "0";
  elements.capsule.style.transform = "translate3d(0, 0, 0) scale(.72)";
  outgoing.cancel();
  mutate();
  await new Promise((resolve) => requestAnimationFrame(resolve));
  incoming = elements.capsule.animate([
    { transform: "translate3d(0, 0, 0) scale(.72)", opacity: 0 },
    { transform: "translate3d(0, 0, 0) scale(1)", opacity: 1 }
  ], {
    duration: 190,
    easing: "cubic-bezier(.16,1,.3,1)",
    fill: "both"
  });
  try { await incoming.ready; }
  catch { /* The animation can be superseded by a newer interaction. */ }
  elements.capsule.style.removeProperty("opacity");
  elements.capsule.style.removeProperty("transform");
  try { await incoming.finished; }
  catch { /* A newer state change or window resize may cancel the animation. */ }
  incoming.cancel();
}

async function setMiniMode(nextMiniMode, { expandAfterRestore = false } = {}) {
  const shouldMinimize = Boolean(nextMiniMode);
  if (miniTransitioning || miniMode === shouldMinimize) {
    if (expandAfterRestore && !miniMode && !miniTransitioning) setExpanded(true);
    return;
  }
  if (shouldMinimize) setConversationExpanded(false);
  else if (miniConversationExpanded) setMiniConversationExpanded(false, { immediate: true });
  miniTransitioning = true;
  clearTimeout(capsuleSingleClickTimer);
  clearTimeout(collapseTimer);
  const root = document.documentElement;
  elements.capsule.classList.remove("hovering");
  pendingGlow = null;
  hoverGeometry = null;

  if (shouldMinimize && expanded) {
    expanded = false;
    root.classList.remove("detail-expanded");
    elements.capsule.setAttribute("aria-expanded", "false");
    elements.detail.setAttribute("aria-hidden", "true");
    elements.detail.classList.remove("open");
    closePreferenceMenu();
    closeLocationChooser();
  }

  root.classList.add("mini-transitioning", "mini-transition-layout");
  resetMagnet(true);

  try {
    if (shouldMinimize) {
      // Keep the full stable surface available while the shared element moves
      // from the centered capsule to the right-edge mini anchor.
      if (typeof window.pulse.setWindowShape === "function") {
        await window.pulse.setWindowShape([{ x: 0, y: 0, width: innerWidth, height: innerHeight }]);
      }
      await runCapsuleMorphTransition(() => {
        miniMode = true;
        root.classList.add("mini-mode");
        elements.miniCapsule.setAttribute("aria-hidden", "false");
        elements.capsule.setAttribute(
          "aria-label",
          `${petCharacterLabels[petCharacterPreference]}，${miniStyleLabels[effectiveMiniStyle()]}，单击切换显示内容，双击恢复完整胶囊`
        );
        if (currentState) renderMini(currentState);
      });
      await window.pulse.resize("mini");
      await syncWindowShape(false);
    } else {
      if (expandAfterRestore) {
        root.classList.toggle(
          "compact-detail-window",
          elements.capsule.classList.contains("information-enabled")
        );
      }
      await window.pulse.resize(expandAfterRestore ? true : false);
      if (typeof window.pulse.setWindowShape === "function") {
        await window.pulse.setWindowShape([{ x: 0, y: 0, width: 390, height: 810 }]);
      }
      await nextCompositeFrame();
      await runCapsuleMorphTransition(() => {
        miniMode = false;
        root.classList.remove("mini-mode");
        elements.miniCapsule.setAttribute("aria-hidden", "true");
        elements.capsule.setAttribute("aria-label", "Codex-Pulse 悬浮胶囊");
      });
      if (expandAfterRestore) {
        expanded = true;
        root.classList.add("detail-expanded");
        clearTimeout(collapseTimer);
        elements.capsule.setAttribute("aria-expanded", "true");
        elements.detail.setAttribute("aria-hidden", "false");
        setMoreSettingsExpanded(false);
        elements.capsule.classList.remove("hovering");
        pendingGlow = null;
        updateTaskTunnel(currentState ? modeFor(currentState) : "idle");
        requestAnimationFrame(() => requestAnimationFrame(() => {
          if (expanded) elements.detail.classList.add("open");
        }));
      } else {
        root.classList.remove("detail-expanded");
      }
      await syncWindowShape(expandAfterRestore);
    }
  } finally {
    root.classList.remove("mini-transitioning", "mini-transition-layout");
    miniTransitioning = false;
    // The magnetic surface returns independently from the content. Keeping
    // the return spring alive avoids the lateral snap that Chromium showed
    // when a click landed while the hover attraction was still displaced.
    resetMagnet(false);
    scheduleWindowShapeSync();
  }

  if (expandAfterRestore && !expanded) setExpanded(true);
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function revealDetailAfterResize(generation) {
  try { await window.pulse.resize(true); }
  catch { return; }
  if (generation !== detailTransitionGeneration || !expanded || miniMode) return;
  await syncWindowShape(true);
  // BrowserWindow resize resolves after setBounds, but Chromium needs two
  // composites before a large transparent/backdrop surface is safe to reveal.
  await nextCompositeFrame();
  if (generation !== detailTransitionGeneration || !expanded || miniMode) return;
  elements.detail.classList.add("open");
  setTimeout(() => {
    if (generation === detailTransitionGeneration && expanded && !miniMode) {
      void syncWindowShape(true);
    }
  }, reduceMotion ? 0 : 380);
}

async function collapseDetailBeforeResize(generation) {
  // Let opacity/transform finish while the expanded texture still exists.
  await wait(reduceMotion ? 0 : 380);
  if (generation !== detailTransitionGeneration || expanded || miniMode) return;
  await nextCompositeFrame();
  if (generation !== detailTransitionGeneration || expanded || miniMode) return;
  await syncWindowShape(false);
  try { await window.pulse.resize(false); }
  catch { return; }
  if (generation !== detailTransitionGeneration || expanded || miniMode) return;
  await nextCompositeFrame();
  elements.detail.setAttribute("aria-hidden", "true");
  document.documentElement.classList.remove("compact-detail-window");
}

function setExpanded(nextExpanded) {
  if (nextExpanded && miniMode) {
    setDetailMode("standard");
    void setMiniMode(false, { expandAfterRestore: true });
    return;
  }
  if (miniTransitioning) return;
  if (expanded === nextExpanded) return;
  if (nextExpanded) setConversationExpanded(false);
  expanded = nextExpanded;
  document.documentElement.classList.toggle("detail-expanded", expanded);
  const transitionGeneration = ++detailTransitionGeneration;
  clearTimeout(collapseTimer);
  elements.capsule.setAttribute("aria-expanded", String(expanded));
  clearTimeout(detailAnimationTimer);
  elements.detail.classList.add("animating");
  detailAnimationTimer = setTimeout(() => elements.detail.classList.remove("animating"), reduceMotion ? 0 : 380);
  if (expanded) {
    elements.detail.setAttribute("aria-hidden", "false");
    document.documentElement.classList.toggle(
      "compact-detail-window",
      elements.capsule.classList.contains("information-enabled")
    );
    setMoreSettingsExpanded(false);
    elements.capsule.classList.remove("hovering");
    pendingGlow = null;
    hoverGeometry = null;
    resetMagnet(true);
    updateTaskTunnel(currentState ? modeFor(currentState) : "idle");
    void revealDetailAfterResize(transitionGeneration);
  } else {
    closePreferenceMenu();
    closeLocationChooser();
    if (tunnelFrame) cancelAnimationFrame(tunnelFrame);
    tunnelFrame = null;
    elements.detail.classList.remove("open");
    void collapseDetailBeforeResize(transitionGeneration);
  }
}

function toggleExpanded() {
  if (expanded) {
    setExpanded(false);
  } else {
    setDetailMode("standard");
    setExpanded(true);
  }
}

let capsulePointer;
let pendingGlow;
let glowFrame;
let lastGlowPaintAt = 0;
let hoverGeometry;
let pendingDrag;
let dragFrame;
const magnet = { x: 0, y: 0, renderX: 0, renderY: 0, vx: 0, vy: 0, targetX: 0, targetY: 0, returning: false, frame: null, lastTime: 0 };

function springStep(value, velocity, target, deltaSeconds, stiffness = 155, damping = 13) {
  // SwiftUI uses interpolatingSpring(stiffness: 155, damping: 13) when the
  // pointer leaves. Small fixed substeps keep the same soft return on 60–240Hz
  // displays and after a delayed Windows compositor frame.
  const steps = Math.max(1, Math.ceil(deltaSeconds / (1 / 120)));
  const step = deltaSeconds / steps;
  let nextValue = value;
  let nextVelocity = velocity;
  for (let index = 0; index < steps; index += 1) {
    const acceleration = -stiffness * (nextValue - target) - damping * nextVelocity;
    nextVelocity += acceleration * step;
    nextValue += nextVelocity * step;
  }
  return { value: nextValue, velocity: nextVelocity };
}

function applyMagnetFrame(timestamp) {
  magnet.frame = null;
  let followingPointer = false;
  const deltaSeconds = magnet.lastTime
    ? Math.min(1 / 30, Math.max(1 / 240, (timestamp - magnet.lastTime) / 1000))
    : 1 / 90;
  magnet.lastTime = timestamp;
  if (capsulePointer?.moved) {
    magnet.x = 0;
    magnet.y = 0;
    magnet.vx = 0;
    magnet.vy = 0;
  } else if (reduceMotion) {
    magnet.x = magnet.targetX;
    magnet.y = magnet.targetY;
    magnet.vx = 0;
    magnet.vy = 0;
  } else if (magnet.returning) {
    const horizontal = springStep(magnet.x, magnet.vx, magnet.targetX, deltaSeconds);
    const vertical = springStep(magnet.y, magnet.vy, magnet.targetY, deltaSeconds);
    magnet.x = horizontal.value;
    magnet.y = vertical.value;
    magnet.vx = horizontal.velocity;
    magnet.vy = vertical.velocity;
  } else {
    // Retarget a fast ease-out on every compositor frame. A 20ms time
    // constant reaches 90% in about 46ms: visibly attracted rather than
    // teleported, but far quicker than the previous 55ms/126ms response.
    const blend = 1 - Math.exp(-deltaSeconds / 0.020);
    magnet.vx = 0;
    magnet.vy = 0;
    magnet.x += (magnet.targetX - magnet.x) * blend;
    magnet.y += (magnet.targetY - magnet.y) * blend;
    followingPointer = true;
  }
  const moving = Math.abs(magnet.targetX - magnet.x) > 0.03
    || Math.abs(magnet.targetY - magnet.y) > 0.03
    || Math.abs(magnet.vx) > 0.35
    || Math.abs(magnet.vy) > 0.35;
  if (followingPointer || moving) {
    // Preserve subpixel coordinates. Physical-pixel rounding made the capsule
    // jump in 0.5/0.8px steps at common Windows scale factors. The individual
    // translate property also keeps magnetic motion separate from morphing.
    magnet.renderX = magnet.x;
    magnet.renderY = magnet.y;
    elements.capsule.style.translate = `${magnet.renderX.toFixed(3)}px ${magnet.renderY.toFixed(3)}px`;
    if (moving) magnet.frame = requestAnimationFrame(applyMagnetFrame);
  } else if (magnet.targetX === 0 && magnet.targetY === 0) {
    magnet.x = 0;
    magnet.y = 0;
    magnet.vx = 0;
    magnet.vy = 0;
    magnet.renderX = 0;
    magnet.renderY = 0;
    magnet.returning = false;
    magnet.lastTime = 0;
    elements.capsule.style.translate = "0px 0px";
    elements.capsule.classList.remove("magnet-active");
  }
}

function scheduleMagnet() {
  elements.capsule.classList.add("magnet-active");
  if (!magnet.frame) {
    magnet.lastTime = 0;
    magnet.frame = requestAnimationFrame(applyMagnetFrame);
  }
}

function resetMagnet(immediate = false) {
  magnet.targetX = 0;
  magnet.targetY = 0;
  magnet.returning = !immediate;
  if (immediate) {
    magnet.x = 0;
    magnet.y = 0;
    magnet.vx = 0;
    magnet.vy = 0;
    magnet.renderX = 0;
    magnet.renderY = 0;
    magnet.returning = false;
    magnet.lastTime = 0;
    elements.capsule.style.translate = "0px 0px";
    elements.capsule.classList.remove("magnet-active");
  } else {
    scheduleMagnet();
  }
}

function scheduleGlow(x, y, edge = "top") {
  pendingGlow = { x, y, edge };
  if (glowFrame) return;
  const paint = (timestamp) => {
    glowFrame = null;
    if (!pendingGlow) return;
    // Updating gradient centers invalidates masks and blur paint. Limit that
    // decorative work to 30fps so the 60/120Hz magnetic translate stays on
    // the compositor and responds first.
    if (timestamp - lastGlowPaintAt < 32) {
      glowFrame = requestAnimationFrame(paint);
      return;
    }
    const glow = pendingGlow;
    pendingGlow = null;
    lastGlowPaintAt = timestamp;
    elements.capsule.style.setProperty("--glow-x", `${glow.x}px`);
    elements.capsule.style.setProperty("--glow-y", `${glow.y}px`);
    elements.capsule.dataset.glowEdge = glow.edge;
  };
  glowFrame = requestAnimationFrame(paint);
}

function nearestCapsuleEdgePoint(x, y, width, height) {
  const distances = [x, width - x, y, height - y];
  const nearest = distances.indexOf(Math.min(...distances));
  switch (nearest) {
    case 0: return { x: 0, y, edge: "left" };
    case 1: return { x: width, y, edge: "right" };
    case 2: return { x, y: 0, edge: "top" };
    default: return { x, y: height, edge: "bottom" };
  }
}

function scheduleWindowDrag(x, y) {
  pendingDrag = { x, y };
  if (dragFrame) return;
  dragFrame = requestAnimationFrame(() => {
    dragFrame = null;
    if (pendingDrag) window.pulse.dragTo(pendingDrag.x, pendingDrag.y);
  });
}

elements.capsule.addEventListener("pointerenter", (event) => {
  if (!expanded && !miniMode) {
    const rect = elements.capsule.getBoundingClientRect();
    hoverGeometry = {
      left: rect.left - magnet.renderX,
      top: rect.top - magnet.renderY,
      width: rect.width,
      height: rect.height
    };
    elements.capsule.classList.add("hovering");
    if (!adaptiveResizeInFlight && !reduceMotion) {
      const localX = event.clientX - hoverGeometry.left;
      const localY = event.clientY - hoverGeometry.top;
      magnet.returning = false;
      magnet.targetX = Math.max(-1, Math.min(1, (localX / hoverGeometry.width - 0.5) * 2)) * 12;
      magnet.targetY = Math.max(-1, Math.min(1, (localY / hoverGeometry.height - 0.5) * 2)) * 8;
      scheduleMagnet();
    }
  }
});

elements.capsule.addEventListener("pointerleave", () => {
  if (capsulePointer) return;
  elements.capsule.classList.remove("hovering");
  pendingGlow = null;
  hoverGeometry = null;
  resetMagnet();
});

elements.capsule.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  capsulePointer = {
    id: event.pointerId,
    startX: event.screenX,
    startY: event.screenY,
    moved: false
  };
  elements.capsule.setPointerCapture(event.pointerId);
  window.pulse.beginDrag(event.screenX, event.screenY);
});

elements.capsule.addEventListener("pointermove", (event) => {
  if (!hoverGeometry) {
    const rect = elements.capsule.getBoundingClientRect();
    hoverGeometry = {
      left: rect.left - magnet.renderX,
      top: rect.top - magnet.renderY,
      width: rect.width,
      height: rect.height
    };
  }
  const localX = event.clientX - hoverGeometry.left;
  const localY = event.clientY - hoverGeometry.top;
  if (!expanded && !miniMode) {
    const glowPoint = nearestCapsuleEdgePoint(localX, localY, hoverGeometry.width, hoverGeometry.height);
    scheduleGlow(glowPoint.x, glowPoint.y, glowPoint.edge);
  }

  if (!expanded && !miniMode && !capsulePointer && !reduceMotion) {
    if (adaptiveResizeInFlight) {
      magnet.targetX = 0;
      magnet.targetY = 0;
    } else {
      const normalizedX = Math.max(-1, Math.min(1, (localX / hoverGeometry.width - 0.5) * 2));
      const normalizedY = Math.max(-1, Math.min(1, (localY / hoverGeometry.height - 0.5) * 2));
      magnet.returning = false;
      magnet.targetX = normalizedX * 12;
      magnet.targetY = normalizedY * 8;
    }
    scheduleMagnet();
  }

  if (!capsulePointer || capsulePointer.id !== event.pointerId) return;
  const distance = Math.hypot(event.screenX - capsulePointer.startX, event.screenY - capsulePointer.startY);
  if (distance >= 4 && !capsulePointer.moved) {
    capsulePointer.moved = true;
    resetMagnet(true);
  }
  if (capsulePointer.moved) {
    elements.capsule.classList.add("dragging");
    scheduleWindowDrag(event.screenX, event.screenY);
  }
});

function finishCapsulePointer(event) {
  if (!capsulePointer || capsulePointer.id !== event.pointerId) return;
  const shouldToggle = !capsulePointer.moved;
  capsulePointer = null;
  pendingDrag = null;
  elements.capsule.classList.remove("dragging");
  window.pulse.endDrag();
  if (elements.capsule.hasPointerCapture(event.pointerId)) {
    elements.capsule.releasePointerCapture(event.pointerId);
  }
  if (!elements.capsule.matches(":hover")) {
    elements.capsule.classList.remove("hovering");
    pendingGlow = null;
    hoverGeometry = null;
  }
  resetMagnet(false);
  if (shouldToggle) {
    clearTimeout(capsuleSingleClickTimer);
    capsuleSingleClickTimer = setTimeout(() => {
      if (miniMode) handleMiniSingleClick();
      else toggleExpanded();
    }, 300);
  }
}

elements.capsule.addEventListener("pointerup", finishCapsulePointer);
elements.capsule.addEventListener("dblclick", (event) => {
  if (event.button !== 0) return;
  event.preventDefault();
  clearTimeout(capsuleSingleClickTimer);
  void setMiniMode(!miniMode);
});
elements.capsule.addEventListener("pointercancel", (event) => {
  capsulePointer = null;
  pendingDrag = null;
  elements.capsule.classList.remove("dragging");
  elements.capsule.classList.remove("hovering");
  hoverGeometry = null;
  window.pulse.endDrag();
  resetMagnet(true);
  if (elements.capsule.hasPointerCapture(event.pointerId)) {
    elements.capsule.releasePointerCapture(event.pointerId);
  }
});
elements.capsule.addEventListener("keydown", (event) => {
  if (event.target !== elements.capsule) return;
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    if (miniMode) handleMiniSingleClick();
    else toggleExpanded();
  }
});

elements.informationStrip.addEventListener("click", (event) => {
  event.stopPropagation();
  if (elements.informationStrip.disabled) return;
  setConversationExpanded(!conversationExpanded);
});

elements.conversationClose.addEventListener("click", (event) => {
  event.stopPropagation();
  if (miniMode) setMiniConversationExpanded(false);
  else setConversationExpanded(false);
});

["pointerdown", "pointerup", "pointercancel", "dblclick"].forEach((type) => {
  elements.updateIndicator.addEventListener(type, (event) => event.stopPropagation());
});
elements.updateIndicator.addEventListener("click", (event) => {
  event.preventDefault();
  event.stopPropagation();
  showUpdateDetails();
});
elements.installUpdateButton.addEventListener("click", () => void window.pulse.performUpdate());
elements.skipUpdateButton.addEventListener("click", async () => {
  const version = currentState?.appUpdate?.availableVersion;
  if (!version) return;
  elements.skipUpdateButton.disabled = true;
  try {
    await window.pulse.skipUpdate(version);
    setExpanded(false);
  } finally {
    elements.skipUpdateButton.disabled = false;
  }
});

elements.cardsToggle.addEventListener("click", () => {
  cardsExpanded = !cardsExpanded;
  elements.cardsToggle.setAttribute("aria-expanded", String(cardsExpanded));
  elements.cardsList.classList.toggle("open", cardsExpanded);
  elements.detail.classList.toggle("cards-open", cardsExpanded);
  requestAnimationFrame(scheduleWindowShapeSync);
});
elements.moreSettingsToggle.addEventListener("click", () => {
  setMoreSettingsExpanded(elements.moreSettingsToggle.getAttribute("aria-expanded") !== "true");
});
elements.activityBandToggle.addEventListener("click", () => {
  activityBandPreference = { ...activityBandPreference, enabled: !activityBandPreference.enabled };
  applyActivityBandPreference();
  previewActivityBand();
});
bindPreferencePicker({
  picker: elements.activityBandPicker,
  trigger: elements.activityBandStyle,
  menu: elements.activityBandStyleMenu,
  onSelect: (value) => {
    const style = activityBandStyles.has(value) ? value : "classic";
    activityBandPreference = { ...activityBandPreference, style };
    applyActivityBandPreference();
    previewActivityBand();
  }
});
bindPreferencePicker({
  picker: elements.petPicker,
  trigger: elements.petCharacter,
  menu: elements.petCharacterMenu,
  onSelect: (value) => {
    petCharacterPreference = petCharacters.has(value) ? value : "dino";
    applyPetPreference();
  }
});
bindPreferencePicker({
  picker: elements.miniStylePicker,
  trigger: elements.miniStyle,
  menu: elements.miniStyleMenu,
  onSelect: (value) => {
    if (usesAPIMiniStyle()) {
      apiMiniStylePreference = apiMiniStyles.has(value) ? value : "time";
    } else {
      miniStylePreference = miniStyles.has(value) ? value : "quota";
    }
    applyMiniStylePreference();
  }
});
bindPreferencePicker({
  picker: elements.themePicker,
  trigger: elements.themeStyle,
  menu: elements.themeStyleMenu,
  onSelect: (value) => {
    themePreference = themeStyles.has(value) ? value : "classic";
    applyThemePreference();
  }
});

function locationResultLabel(location) {
  return [location?.name, location?.admin1, location?.country].filter(Boolean).join(" · ");
}

function renderLocationResults(results) {
  locationResults = Array.isArray(results) ? results : [];
  elements.locationResults.innerHTML = locationResults.length
    ? locationResults.map((location, index) => `
        <button class="location-result" type="button" role="option" data-index="${index}">
          <strong>${escapeHTML(location.name || "—")}</strong>
          <small>${escapeHTML([location.admin1, location.country].filter(Boolean).join(" · ") || "—")}</small>
        </button>`).join("")
    : "";
}

function openLocationChooser() {
  closePreferenceMenu();
  elements.locationChooser.hidden = false;
  elements.locationSearchStatus.textContent = "输入至少 2 个字符开始搜索";
  if (!elements.locationResults.children.length) renderLocationResults([]);
  requestAnimationFrame(() => elements.locationSearch.focus({ preventScroll: true }));
}

function closeLocationChooser() {
  elements.locationChooser.hidden = true;
  locationSearchRequest += 1;
}

async function searchLocationInput() {
  const query = elements.locationSearch.value.trim();
  clearTimeout(locationSearchTimer);
  if (query.length < 2) {
    locationSearchRequest += 1;
    renderLocationResults([]);
    elements.locationSearchStatus.textContent = "输入至少 2 个字符开始搜索";
    return;
  }
  const requestId = ++locationSearchRequest;
  elements.locationSearchStatus.textContent = "正在搜索…";
  locationSearchTimer = setTimeout(async () => {
    try {
      const response = await window.pulse.searchLocations(query);
      if (requestId !== locationSearchRequest) return;
      if (response?.error) {
        renderLocationResults([]);
        elements.locationSearchStatus.textContent = response.error;
        return;
      }
      renderLocationResults(response?.results || []);
      elements.locationSearchStatus.textContent = response?.results?.length ? "选择一个匹配的地区" : "没有找到匹配地区";
    } catch (error) {
      if (requestId !== locationSearchRequest) return;
      renderLocationResults([]);
      elements.locationSearchStatus.textContent = String(error?.message || "地区搜索失败");
    }
  }, 320);
}

async function chooseLocation(location) {
  elements.locationSearchStatus.textContent = "正在保存地区…";
  elements.locationResults.querySelectorAll("button").forEach((button) => { button.disabled = true; });
  try {
    const nextState = await window.pulse.setInformationBarLocation(location);
    if (nextState?.informationError) {
      elements.locationSearchStatus.textContent = nextState.informationError;
      return;
    }
    closeLocationChooser();
    render(nextState);
  } catch (error) {
    elements.locationSearchStatus.textContent = String(error?.message || "地区保存失败");
  } finally {
    elements.locationResults.querySelectorAll("button").forEach((button) => { button.disabled = false; });
  }
}

elements.informationBarToggle.addEventListener("click", async () => {
  const current = Boolean(currentState?.informationBar?.enabled);
  elements.informationBarToggle.disabled = true;
  try {
    const nextState = await window.pulse.setInformationBarEnabled(!current);
    render(nextState);
    if (!current && !nextState?.informationBar?.enabled) openLocationChooser();
    if (current) closeLocationChooser();
  } catch (error) {
    elements.locationSearchStatus.textContent = String(error?.message || "信息任务栏设置失败");
  } finally {
    elements.informationBarToggle.disabled = false;
  }
});
elements.informationLocationButton.addEventListener("click", () => {
  if (!elements.informationLocationButton.disabled) openLocationChooser();
});
elements.locationChooserClose.addEventListener("click", closeLocationChooser);
elements.locationSearch.addEventListener("input", searchLocationInput);
elements.locationResults.addEventListener("click", (event) => {
  const button = event.target.closest(".location-result");
  if (!button) return;
  const index = Number(button.dataset.index);
  if (locationResults[index]) void chooseLocation(locationResults[index]);
});
document.querySelectorAll("[data-external-link]").forEach((link) => {
  link.addEventListener("click", (event) => {
    event.preventDefault();
    void window.pulse.openExternal(link.href);
  });
});

elements.tokenChart.addEventListener("mousemove", (event) => {
  const rect = elements.tokenChart.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const plotLeft = 8;
  const plotWidth = 288;
  const nextIndex = Math.max(0, Math.min(6, Math.round(((x - plotLeft) / plotWidth) * 6)));
  if (nextIndex !== hoveredChartIndex) {
    hoveredChartIndex = nextIndex;
    scheduleChartDraw();
  }
});
elements.tokenChart.addEventListener("mouseleave", () => { hoveredChartIndex = null; scheduleChartDraw(); });
elements.chooseCodex.addEventListener("click", () => window.pulse.clearCodexPath());
elements.refresh.addEventListener("click", () => window.pulse.refresh());
elements.quit.addEventListener("click", () => window.pulse.quit());

// 展开后点击窗口内的透明留白区域也收起；详情卡和胶囊自身保持正常交互。
document.addEventListener("pointerdown", (event) => {
  if (activePreferenceMenu && !activePreferenceMenu.picker.contains(event.target)) {
    closePreferenceMenu();
  }
  if (!expanded) return;
  if (elements.capsule.contains(event.target) || elements.detail.contains(event.target)) return;
  setExpanded(false);
}, true);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && activePreferenceMenu) {
    event.preventDefault();
    closePreferenceMenu(true);
    return;
  }
  if (event.key === "Escape" && !elements.locationChooser.hidden) {
    event.preventDefault();
    closeLocationChooser();
  }
});

setInterval(() => {
  if (currentState) {
    updateTaskMetric(currentState);
    updateInformationClock();
    const primary = currentState.limits?.[0];
    const apiUsageFallback = usesLocalUsageState(currentState)
      && (!primary || isCustomProviderState(currentState));
    setText(elements.resetTime, apiUsageFallback ? "按 Token 计费" : limitSummary(primary));
    renderMini(currentState);
  }
}, 1000);

window.pulse.onState(render);
window.pulse.onCollapse(() => {
  // Window blur means “close details”, not “leave mini mode”. Keeping mini
  // stable lets users click anywhere on the desktop without restoring the
  // full capsule. Explicit tray/menu expand events still restore it below.
  if (!miniMode) setExpanded(false);
});
window.pulse.onExpand(() => {
  if (miniMode) void setMiniMode(false, { expandAfterRestore: true });
  else setExpanded(true);
});
window.addEventListener("online", () => window.pulse.notifyNetworkOnline());
window.pulse.getState().then(render);
