(function exposeCodexDockMetrics(globalScope) {
  "use strict";

  function formatTokens(value) {
    if (value === null || value === undefined || value === "") return "—";
    const number = Number(value);
    if (!Number.isFinite(number)) return "—";
    const absolute = Math.abs(number);
    if (absolute >= 1_000_000_000_000) return `${(number / 1_000_000_000_000).toFixed(3)}T`;
    if (absolute >= 1_000_000_000) return `${(number / 1_000_000_000).toFixed(3)}B`;
    if (absolute >= 1_000_000) return `${(number / 1_000_000).toFixed(3)}M`;
    if (absolute >= 1_000) return `${(number / 1_000).toFixed(3)}K`;
    return number.toFixed(3);
  }

  function cacheHitRate(inputTokens, cachedInputTokens) {
    const input = Number(inputTokens);
    const cached = Number(cachedInputTokens);
    if (!Number.isFinite(input) || input <= 0 || !Number.isFinite(cached)) return null;
    return Math.max(0, Math.min(1, cached / input));
  }

  function formatPercentRatio(value) {
    const number = Number(value);
    return Number.isFinite(number) ? `${(Math.max(0, Math.min(1, number)) * 100).toFixed(1)}%` : "—";
  }

  function formatUSD(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return "—";
    const normalized = Math.max(0, number);
    if (normalized >= 1_000) return `$${(normalized / 1_000).toFixed(2)}K`;
    if (normalized >= 100) return `$${normalized.toFixed(1)}`;
    if (normalized >= 1) return `$${normalized.toFixed(2)}`;
    if (normalized >= 0.01) return `$${normalized.toFixed(3)}`;
    return `$${normalized.toFixed(4)}`;
  }

  function dateTimeParts(info, now = new Date(), includeSeconds = true) {
    const timezone = info?.weather?.timezone || info?.location?.timezone || undefined;
    const timeOptions = {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    };
    if (includeSeconds) timeOptions.second = "2-digit";
    try {
      const time = new Intl.DateTimeFormat("zh-CN", timeOptions)
        .format(now)
        .replace(/^24:/, "00:");
      const weekday = new Intl.DateTimeFormat("zh-CN", {
        timeZone: timezone,
        weekday: "short"
      }).format(now);
      const date = new Intl.DateTimeFormat("zh-CN", {
        timeZone: timezone,
        year: "numeric",
        month: "long",
        day: "numeric"
      }).format(now);
      return { time, weekday, date, timezone };
    } catch {
      return dateTimeParts({ weather: null, location: null }, now, includeSeconds);
    }
  }

  function changedGlyphIndices(previous, next) {
    const left = Array.from(String(previous ?? ""));
    const right = Array.from(String(next ?? ""));
    const length = Math.max(left.length, right.length);
    const indices = [];
    for (let index = 0; index < length; index += 1) {
      if (left[index] !== right[index]) indices.push(index);
    }
    return indices;
  }

  function pointerResult(axis, cancelled = false) {
    if (cancelled) return "cancel";
    if (axis === "reorder") return "reorder";
    if (axis === "detach") return "detach";
    return "activate";
  }

  const api = Object.freeze({
    changedGlyphIndices,
    cacheHitRate,
    dateTimeParts,
    formatPercentRatio,
    formatTokens,
    formatUSD,
    pointerResult
  });

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  globalScope.CodexDockMetrics = api;
})(typeof globalThis === "undefined" ? window : globalThis);
