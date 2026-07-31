"use strict";

function numberValue(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === "object" && "value" in value) return numberValue(value.value);
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function windowValue(window, camel, snake, legacySnake = null) {
  return numberValue(window?.[camel] ?? window?.[snake] ?? (legacySnake ? window?.[legacySnake] : null));
}

function snapshotWindows(snapshot, fallbackLimitID, sourcePriority) {
  if (!snapshot || typeof snapshot !== "object") return [];
  const limitID = String(
    snapshot.limitId
      ?? snapshot.limit_id
      ?? fallbackLimitID
      ?? "legacy"
  );
  const limitName = String(snapshot.limitName ?? snapshot.limit_name ?? "").trim();
  const reached = snapshot.rateLimitReachedType
    ?? snapshot.rate_limit_reached_type
    ?? null;
  const result = [];

  for (const [role, fallbackName] of [["primary", "每周用量"], ["secondary", "5 小时用量"]]) {
    const window = snapshot?.[role];
    if (!window || typeof window !== "object") continue;
    const duration = windowValue(
      window,
      "windowDurationMins",
      "window_duration_mins",
      "window_minutes"
    );
    const used = Math.min(
      100,
      Math.max(0, windowValue(window, "usedPercent", "used_percent") || 0)
    );
    const roundedDuration = Number.isFinite(duration) ? Math.round(duration) : null;
    const id = `${limitID}:${role}:${roundedDuration ?? "unknown"}`;
    const name = roundedDuration !== null && Math.abs(roundedDuration - 300) <= 5
      ? "5 小时用量"
      : roundedDuration !== null && Math.abs(roundedDuration - 10_080) <= 5
        ? "每周用量"
        : limitName || fallbackName;
    result.push({
      id,
      limitID,
      role,
      name,
      windowDurationMins: duration,
      usedPercent: used,
      remainingPercent: 100 - used,
      resetsAt: windowValue(window, "resetsAt", "resets_at"),
      isLimitReached: Boolean(reached) || used >= 100,
      sourcePriority
    });
  }
  return result;
}

function headlineScore(limit) {
  const duration = numberValue(limit?.windowDurationMins);
  let score = limit?.role === "primary" ? 40 : 0;
  if (duration !== null && Math.abs(duration - 10_080) <= 5) score += 1_000;
  else if (duration !== null) score += Math.min(300, duration / 100);
  if (String(limit?.limitID || "").toLowerCase() === "codex") score += 120;
  if (/每周|weekly/i.test(String(limit?.name || ""))) score += 80;
  score += Number(limit?.sourcePriority) || 0;
  return score;
}

function primaryQuotaLimit(limits) {
  const candidates = Array.isArray(limits) ? limits.filter(Boolean) : [];
  if (!candidates.length) return null;
  return [...candidates].sort((left, right) => {
    const score = headlineScore(right) - headlineScore(left);
    if (score) return score;
    return String(left.id || "").localeCompare(String(right.id || ""));
  })[0];
}

function normalizeCards(result) {
  const creditSummary = result?.rateLimitResetCredits
    ?? result?.rate_limit_reset_credits
    ?? {};
  const rawCredits = creditSummary.credits;
  if (Array.isArray(rawCredits)) {
    return rawCredits.map((card, index) => {
      const rawTypes = card.applicableLimitTypes
        ?? card.applicable_limit_types
        ?? card.resetType
        ?? card.reset_type
        ?? "codex_rate_limits";
      return {
        id: card.id || `card-${index}`,
        title: card.title || "Full reset",
        available: String(card.status || "available").toLowerCase() === "available",
        expiresAt: numberValue(card.expiresAt ?? card.expires_at),
        applicableLimitTypes: Array.isArray(rawTypes) ? rawTypes.map(String) : [String(rawTypes)]
      };
    });
  }
  const count = numberValue(creditSummary.availableCount ?? creditSummary.available_count) || 0;
  return Array.from({ length: count }, (_, index) => ({
    id: `card-${index}`,
    title: "Full reset",
    available: true,
    expiresAt: null,
    applicableLimitTypes: []
  }));
}

function normalizeLimits(result) {
  const collected = [];
  const legacy = result?.rateLimits ?? result?.rate_limits;
  if (legacy) {
    collected.push(...snapshotWindows(
      legacy,
      legacy.limitId ?? legacy.limit_id ?? "legacy",
      0
    ));
  }

  const byID = result?.rateLimitsByLimitId ?? result?.rate_limits_by_limit_id;
  if (byID && typeof byID === "object") {
    for (const [key, snapshot] of Object.entries(byID).sort(([left], [right]) =>
      left.localeCompare(right))) {
      collected.push(...snapshotWindows(snapshot, key, 20));
    }
  }

  const byStableID = new Map();
  for (const limit of collected) {
    const existing = byStableID.get(limit.id);
    if (!existing || limit.sourcePriority >= existing.sourcePriority) {
      byStableID.set(limit.id, limit);
    }
  }

  let limits = [...byStableID.values()];
  const keyedStructural = new Set(
    limits
      .filter((limit) => limit.sourcePriority > 0)
      .map((limit) => `${limit.role}:${Math.round(limit.windowDurationMins || 0)}`)
  );
  limits = limits.filter((limit) =>
    limit.sourcePriority > 0
      || !keyedStructural.has(`${limit.role}:${Math.round(limit.windowDurationMins || 0)}`)
  );

  const headline = primaryQuotaLimit(limits);
  limits = limits
    .map((limit) => ({
      ...limit,
      headline: limit.id === headline?.id,
      sourcePriority: undefined
    }))
    .sort((left, right) => {
      if (left.headline !== right.headline) return left.headline ? -1 : 1;
      const duration = (right.windowDurationMins || 0) - (left.windowDurationMins || 0);
      if (duration) return duration;
      return left.name.localeCompare(right.name, "zh-CN");
    });

  return { limits, cards: normalizeCards(result) };
}

function matchingLimit(existing, incoming) {
  return existing.find((candidate) => candidate.id === incoming.id)
    || existing.find((candidate) => {
      const sameRole = candidate.role === incoming.role;
      const leftDuration = numberValue(candidate.windowDurationMins);
      const rightDuration = numberValue(incoming.windowDurationMins);
      return sameRole && (
        leftDuration === null
        || rightDuration === null
        || Math.abs(leftDuration - rightDuration) <= 5
      );
    });
}

function fresherLimit(existing, incoming) {
  if (!existing) return incoming;
  const oldReset = numberValue(existing.resetsAt);
  const nextReset = numberValue(incoming.resetsAt);
  if (oldReset !== null && nextReset !== null) {
    if (nextReset < oldReset - 2) return existing;
    if (nextReset > oldReset + 2) return incoming;
  }

  const oldUsed = numberValue(existing.usedPercent);
  const nextUsed = numberValue(incoming.usedPercent);
  if (oldUsed !== null && nextUsed !== null && nextUsed + 0.001 < oldUsed) {
    return {
      ...incoming,
      usedPercent: oldUsed,
      remainingPercent: Math.max(0, Math.min(100, 100 - oldUsed)),
      isLimitReached: Boolean(existing.isLimitReached) || oldUsed >= 100
    };
  }
  return incoming;
}

function finalizeLimits(limits) {
  const headline = primaryQuotaLimit(limits);
  return limits
    .map((limit) => ({ ...limit, headline: limit.id === headline?.id }))
    .sort((left, right) => {
      if (left.headline !== right.headline) return left.headline ? -1 : 1;
      return (right.windowDurationMins || 0) - (left.windowDurationMins || 0);
    });
}

function reconcileNormalizedLimits(existingLimits, incomingLimits, retainUnmentioned = false) {
  const existing = Array.isArray(existingLimits) ? existingLimits.filter(Boolean) : [];
  const incoming = Array.isArray(incomingLimits) ? incomingLimits.filter(Boolean) : [];
  if (!incoming.length) return existing;

  const result = retainUnmentioned
    ? new Map(existing.map((limit) => [limit.id, { ...limit, headline: false }]))
    : new Map();

  for (const limit of incoming) {
    const match = matchingLimit(existing, limit);
    const accepted = fresherLimit(match, limit);
    if (match && result.has(match.id) && match.id !== accepted.id) {
      result.delete(match.id);
    }
    result.set(accepted.id, { ...accepted, headline: false });
  }
  return finalizeLimits([...result.values()]);
}

function mergeNormalizedLimits(existingLimits, updateResult) {
  return reconcileNormalizedLimits(
    existingLimits,
    normalizeLimits(updateResult).limits,
    true
  );
}

module.exports = {
  mergeNormalizedLimits,
  normalizeLimits,
  primaryQuotaLimit,
  reconcileNormalizedLimits,
  snapshotWindows
};
