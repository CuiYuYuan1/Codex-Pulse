"use strict";

const assert = require("assert");
const {
  mergeNormalizedLimits,
  normalizeLimits,
  primaryQuotaLimit,
  reconcileNormalizedLimits
} = require("../src/rate-limit-utils");

const resetAt = 1_786_003_200;
const legacyAndKeyed = {
  rateLimits: {
    limitId: "legacy",
    primary: {
      usedPercent: 72,
      windowDurationMins: 10_080,
      resetsAt: resetAt
    }
  },
  rateLimitsByLimitId: {
    codex: {
      limitId: "codex",
      primary: {
        usedPercent: 96,
        windowDurationMins: 10_080,
        resetsAt: resetAt
      },
      secondary: {
        usedPercent: 20,
        windowDurationMins: 300,
        resetsAt: resetAt - 86_400
      }
    }
  }
};

const normalized = normalizeLimits(legacyAndKeyed);
assert.strictEqual(normalized.limits.length, 2, "keyed windows must replace legacy duplicates");
assert.strictEqual(primaryQuotaLimit(normalized.limits).remainingPercent, 4);
assert.strictEqual(primaryQuotaLimit(normalized.limits).windowDurationMins, 10_080);
assert.strictEqual(normalized.limits[0].headline, true);

const staleRemote = {
  rateLimitsByLimitId: {
    codex: {
      limitId: "codex",
      primary: {
        usedPercent: 72,
        windowDurationMins: 10_080,
        resetsAt: resetAt
      }
    }
  }
};
const protectedLimits = reconcileNormalizedLimits(
  normalized.limits,
  normalizeLimits(staleRemote).limits,
  false
);
assert.strictEqual(
  primaryQuotaLimit(protectedLimits).remainingPercent,
  4,
  "a late response in the same reset cycle must not restore an older percentage"
);

const nextCycle = {
  rateLimitsByLimitId: {
    codex: {
      limitId: "codex",
      primary: {
        usedPercent: 5,
        windowDurationMins: 10_080,
        resetsAt: resetAt + 7 * 86_400
      }
    }
  }
};
const resetLimits = reconcileNormalizedLimits(
  protectedLimits,
  normalizeLimits(nextCycle).limits,
  false
);
assert.strictEqual(
  primaryQuotaLimit(resetLimits).remainingPercent,
  95,
  "a later reset cycle must accept a lower used percentage"
);

const localSnakeCase = {
  rate_limits_by_limit_id: {
    codex: {
      limit_id: "codex",
      primary: {
        used_percent: 98,
        window_minutes: 10_080,
        resets_at: resetAt
      }
    }
  }
};
const locallyMerged = mergeNormalizedLimits(normalized.limits, localSnakeCase);
assert.strictEqual(primaryQuotaLimit(locallyMerged).remainingPercent, 2);

const whamUsage = {
  rate_limits_by_limit_id: {
    codex: {
      limit_id: "codex",
      limit_name: "Codex",
      primary: {
        used_percent: 9,
        window_minutes: 10_080,
        resets_at: resetAt
      }
    }
  },
  rate_limit_reset_credits: {
    available_count: 1
  }
};
const whamNormalized = normalizeLimits(whamUsage);
assert.strictEqual(primaryQuotaLimit(whamNormalized.limits).remainingPercent, 91);
assert.strictEqual(whamNormalized.cards.length, 1);

console.log("quota freshness fixtures: PASS");
