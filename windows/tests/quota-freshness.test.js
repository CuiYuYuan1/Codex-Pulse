"use strict";

const assert = require("assert");
const {
  mergeAuthoritativeLimits,
  mergeNormalizedLimits,
  normalizeLimits,
  primaryQuotaLimit,
  reconcileNormalizedLimits,
  whamResponseMatchesAccount
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

const cockpitWham = {
  account_id: "desktop-current-account",
  rate_limit: {
    limit_id: "codex",
    primary_window: {
      used_percent: 44,
      limit_window_seconds: 604_800,
      reset_at: resetAt
    }
  }
};
const cockpitWhamNormalized = normalizeLimits(cockpitWham);
assert.strictEqual(cockpitWhamNormalized.limits.length, 1);
assert.strictEqual(primaryQuotaLimit(cockpitWhamNormalized.limits).remainingPercent, 56);
assert.strictEqual(primaryQuotaLimit(cockpitWhamNormalized.limits).windowDurationMins, 10_080);
assert.strictEqual(primaryQuotaLimit(cockpitWhamNormalized.limits).resetsAt, resetAt);
assert.strictEqual(
  whamResponseMatchesAccount(cockpitWham, "desktop-current-account"),
  true,
  "a Wham root account_id must be accepted for the active Cockpit account"
);
assert.strictEqual(
  whamResponseMatchesAccount(cockpitWham, "previous-account"),
  false,
  "a Wham root account_id for a previous account must be rejected"
);
assert.strictEqual(
  whamResponseMatchesAccount({ accountId: "desktop-current-account" }, "desktop-current-account"),
  true,
  "camel-case Wham accountId must remain compatible"
);

const nestedCockpitWham = {
  account_id: "desktop-current-account",
  usage: {
    rate_limit: {
      primary_window: {
        used_percent: 23,
        limit_window_seconds: 604_800,
        reset_at: resetAt
      }
    }
  }
};
const nestedCockpitWhamNormalized = normalizeLimits(nestedCockpitWham);
assert.strictEqual(nestedCockpitWhamNormalized.limits.length, 1);
assert.strictEqual(primaryQuotaLimit(nestedCockpitWhamNormalized.limits).remainingPercent, 77);
assert.strictEqual(primaryQuotaLimit(nestedCockpitWhamNormalized.limits).windowDurationMins, 10_080);

const genericCodexWithSparkPlan = {
  rate_limit: {
    limit_id: "codex",
    limit_name: "通用使用限额",
    plan_type: "gpt-5.3-codex-spark",
    primary_window: {
      used_percent: 29,
      limit_window_seconds: 604_800,
      reset_at: resetAt
    }
  }
};
assert.strictEqual(
  primaryQuotaLimit(normalizeLimits(genericCodexWithSparkPlan).limits).remainingPercent,
  71,
  "explicit codex generic quota must not be filtered by unrelated Spark fields"
);

const oldAccountExhausted = normalizeLimits({
  rateLimitsByLimitId: {
    codex: {
      limitId: "codex",
      primary: {
        usedPercent: 99,
        windowDurationMins: 10_080,
        resetsAt: resetAt
      }
    }
  }
}).limits;
const currentAccountAuthoritative = mergeAuthoritativeLimits(
  oldAccountExhausted,
  cockpitWhamNormalized.limits
);
assert.strictEqual(
  primaryQuotaLimit(currentAccountAuthoritative).remainingPercent,
  56,
  "a direct current-account response must replace old-account 1% within the same reset cycle"
);

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

const proWithSparkEntitlement = {
  rate_limits_by_limit_id: {
    codex: {
      limit_id: "codex",
      limit_name: "通用使用限额",
      primary: {
        used_percent: 17,
        window_minutes: 10_080,
        resets_at: resetAt
      }
    },
    "gpt-5.3-codex-spark": {
      limit_id: "gpt-5.3-codex-spark",
      limit_name: "GPT-5.3-Codex-Spark 使用限额",
      primary: {
        used_percent: 0,
        window_minutes: 10_080,
        resets_at: resetAt + 86_400
      }
    }
  }
};
const proWithSparkNormalized = normalizeLimits(proWithSparkEntitlement);
assert.strictEqual(proWithSparkNormalized.limits.length, 1);
assert.strictEqual(primaryQuotaLimit(proWithSparkNormalized.limits).remainingPercent, 83);
assert.strictEqual(
  proWithSparkNormalized.limits.some((limit) => /spark/i.test(`${limit.id} ${limit.limitID} ${limit.name}`)),
  false,
  "GPT-5.3-Codex-Spark entitlement must not appear as generic Pro quota"
);

console.log("quota freshness fixtures: PASS");
