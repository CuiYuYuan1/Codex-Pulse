(() => {
  "use strict";

  const BASE_INTERVAL = 10_000_000;
  const MAXIMUM_SCALE = 10;

  function scaleForTodayTokens(rawTokens) {
    const numeric = Number(rawTokens);
    const tokens = Number.isFinite(numeric) ? Math.max(0, numeric) : 0;
    const growthSteps = Math.floor(tokens / BASE_INTERVAL);
    const scale = Math.round((1 + growthSteps * 0.1) * 10) / 10;
    return Math.min(MAXIMUM_SCALE, scale);
  }

  const api = Object.freeze({
    scaleForTodayTokens
  });
  if (typeof window !== "undefined") window.CodexPetGrowth = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})();
