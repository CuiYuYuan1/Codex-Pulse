const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const pulseStore = fs.readFileSync(
  path.join(root, "Shared/Services/PulseStore.swift"),
  "utf8"
);
const appServerClient = fs.readFileSync(
  path.join(root, "Shared/Services/StdioCodexAppServerClient.swift"),
  "utf8"
);
const windowsMain = fs.readFileSync(
  path.join(root, "windows/src/main.js"),
  "utf8"
);

function ordered(source, fragments, label) {
  let cursor = -1;
  for (const fragment of fragments) {
    const next = source.indexOf(fragment, cursor + 1);
    assert(next >= 0, `${label}: missing ${JSON.stringify(fragment)}`);
    assert(next > cursor, `${label}: invalid ordering for ${JSON.stringify(fragment)}`);
    cursor = next;
  }
}

// macOS must invalidate the old account before the app-server reconnect starts.
const authenticationCase = pulseStore.slice(
  pulseStore.indexOf("case .authenticationChanged:"),
  pulseStore.indexOf("case .rateLimitsUpdated", pulseStore.indexOf("case .authenticationChanged:"))
);
ordered(authenticationCase, [
  "prepareForAccountTransition()",
  "scheduleAuthenticationReconnect()"
], "macOS authentication transition");

// Clearing the visible account snapshot is part of the transition contract, not
// an eventual side effect of a successful network response.
const prepareTransition = pulseStore.slice(
  pulseStore.indexOf("private func prepareForAccountTransition()"),
  pulseStore.indexOf("private func isCurrentClient", pulseStore.indexOf("private func prepareForAccountTransition()"))
);
ordered(prepareTransition, [
  "accountRevision &+= 1",
  "confirmedAccountRevision = nil",
  "next.account = .empty",
  "next.rateLimits = .empty",
  "next.usage = deviceLocalUsage(from: snapshot.usage)",
  "apply(next)"
], "macOS immediate account-scope clearing");
assert(
  prepareTransition.includes("preserved device Token totals"),
  "macOS account switch must retain device-local Token aggregates"
);

assert(
  pulseStore.includes("confirmedAccountRevision == accountRevision"),
  "macOS account-scoped responses must be bound to the confirmed revision"
);
assert(
  pulseStore.includes("verifyAccountScopeBeforeInitialSync(using: stdio)"),
  "macOS startup must validate cached account scope"
);
assert(
  pulseStore.includes("scheduleAccountTransitionConfirmation(for: revision)"),
  "macOS switch must perform a confirmation refresh"
);

// Same-size auth.json rewrites must be detected, while a half-written file must
// remain stable for two samples before a reconnect is requested.
assert(
  appServerClient.includes("let contentFingerprint: UInt64"),
  "macOS auth watcher must compare content, not only metadata"
);
ordered(appServerClient, [
  "guard pendingState == next else",
  "self.lastState = next",
  "onChange()"
], "macOS stabilized auth watcher");

// Keep Windows on the same generation-isolation contract.
ordered(windowsMain, [
  "accountGeneration += 1;",
  "const localUsage = deviceLocalUsageSnapshot(state.usage);",
  "limits: [],",
  "usage: localUsage,",
  "await refreshAccount();",
  "await Promise.allSettled([refreshLimits(), refreshUsage(), refreshThreads()]);"
], "Windows account transition");
assert(
  windowsMain.includes("generation !== accountGeneration"),
  "Windows stale account requests must be rejected"
);

console.log("account switch contract: PASS");
