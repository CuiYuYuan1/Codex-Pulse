import Foundation

@main
enum RateLimitFreshnessSmoke {
    static func main() throws {
        let observedAt = ISO8601DateFormatter().date(from: "2026-07-30T08:29:29Z")!
        let resetAt = Date(timeIntervalSince1970: 1_785_903_155)
        let envelope = """
        {
          "type": "event_msg",
          "timestamp": "2026-07-30T08:29:29Z",
          "payload": {
            "type": "token_count",
            "rate_limits": {
              "limit_id": "codex",
              "primary": {
                "used_percent": 96,
                "window_minutes": 10080,
                "resets_at": 1785903155
              },
              "secondary": null,
              "credits": {
                "balance": "0"
              }
            }
          }
        }
        """
        let object = try JSONSerialization.jsonObject(with: Data(envelope.utf8)) as! [String: Any]
        let payload = object["payload"] as! [String: Any]
        let rawLimits = payload["rate_limits"] as! [String: Any]
        let parsed = try require(
            LocalRateLimitParser.parse(rawLimits, observedAt: observedAt),
            "session snake_case rate_limits must parse"
        )
        let parsedBucket = try require(parsed.primaryBucket, "weekly bucket must exist")
        precondition(parsed.updatedAt == observedAt, "rollout timestamp must remain the observation time")
        precondition(parsedBucket.id == "codex-10080m")
        precondition(parsedBucket.name == "每周用量")
        precondition(parsedBucket.windowDurationSeconds == 604_800)
        precondition(parsedBucket.resetsAt == resetAt)
        precondition(parsedBucket.usedPercent == 96)
        precondition(parsedBucket.remainingPercent == 4)

        let resetCard = RateLimitResetCard(
            id: "card-1",
            acquiredAt: nil,
            expiresAt: resetAt.addingTimeInterval(86_400),
            applicableLimitTypes: ["codex"],
            isAvailable: true
        )
        let remote = RateLimitSnapshot(
            buckets: [
                RateLimitBucket(
                    id: "codex-10080m",
                    name: "官方每周额度",
                    usedPercent: 72,
                    windowDurationSeconds: 604_800,
                    resetsAt: resetAt,
                    isLimitReached: false,
                    remainingCredits: 42
                ),
                RateLimitBucket(
                    id: "codex-300m",
                    name: "5 小时用量",
                    usedPercent: 20,
                    windowDurationSeconds: 18_000,
                    resetsAt: observedAt.addingTimeInterval(3_600),
                    isLimitReached: false,
                    remainingCredits: nil
                )
            ],
            resetCards: [resetCard],
            updatedAt: observedAt.addingTimeInterval(-600)
        )

        let merge = try require(
            RateLimitFreshness.mergeLocal(current: remote, observation: parsed),
            "newer local percentage in the same cycle must merge"
        )
        let mergedWeekly = merge.merged.buckets.first { $0.id == "codex-10080m" }!
        precondition(mergedWeekly.usedPercent == 96)
        precondition(mergedWeekly.name == "官方每周额度", "remote display metadata must survive")
        precondition(mergedWeekly.remainingCredits == 42, "remote credit metadata must survive")
        precondition(merge.merged.buckets.count == 2, "unmentioned remote buckets must survive")
        precondition(merge.merged.resetCards == [resetCard], "reset cards must survive local updates")
        precondition(merge.acceptedObservation.buckets.count == 1)
        precondition(merge.acceptedObservation.resetCards.isEmpty)

        var regressing = parsed
        regressing.buckets[0].usedPercent = 70
        regressing.updatedAt = observedAt.addingTimeInterval(1)
        precondition(
            RateLimitFreshness.mergeLocal(current: merge.merged, observation: regressing) == nil,
            "same-cycle local observations must not move usage backwards"
        )

        var historicalCycle = parsed
        historicalCycle.buckets[0].usedPercent = 100
        historicalCycle.buckets[0].resetsAt = resetAt.addingTimeInterval(-86_400)
        historicalCycle.updatedAt = observedAt.addingTimeInterval(2)
        precondition(
            RateLimitFreshness.mergeLocal(current: merge.merged, observation: historicalCycle) == nil,
            "an older reset cycle must not overwrite the current cycle"
        )

        var resetCycle = parsed
        resetCycle.buckets[0].usedPercent = 5
        resetCycle.buckets[0].resetsAt = resetAt.addingTimeInterval(7 * 86_400)
        resetCycle.updatedAt = observedAt.addingTimeInterval(3)
        let resetMerge = try require(
            RateLimitFreshness.mergeLocal(current: merge.merged, observation: resetCycle),
            "a later reset cycle must accept a lower used percentage"
        )
        precondition(resetMerge.merged.primaryBucket?.usedPercent == 5)
        precondition(resetMerge.merged.resetCards == [resetCard])

        precondition(
            RateLimitFreshness.mergeLocal(current: .empty, observation: parsed) == nil,
            "local session data must not establish account-scoped buckets after an account switch"
        )

        let whamUsage = """
        {
          "rate_limits_by_limit_id": {
            "codex": {
              "limit_id": "codex",
              "limit_name": "Codex",
              "primary": {
                "used_percent": 9,
                "window_minutes": 10080,
                "resets_at": 1785903155
              }
            }
          },
          "rate_limit_reset_credits": {
            "available_count": 1
          }
        }
        """
        let whamWire = try RateLimitsWireParser.parse(Data(whamUsage.utf8))
        let wham = ProtocolMapper.rateLimits(from: whamWire)
        precondition(wham.primaryBucket?.usedPercent == 9)
        precondition(wham.primaryBucket?.remainingPercent == 91)
        precondition(wham.availableResetCardCount == 1)

        // Current Codex Desktop wham/usage shape is singular rate_limit with
        // primary_window + seconds. It must not be mistaken for an empty quota
        // response, otherwise the app falls back to a previous account cache.
        let desktopWhamUsage = """
        {
          "account_id": "active-desktop-account",
          "email": "active@example.com",
          "rate_limit": {
            "primary_window": {
              "used_percent": 44,
              "limit_window_seconds": 604800,
              "reset_at": 1785903155
            },
            "secondary_window": null
          },
          "rate_limit_reset_credits": {
            "available_count": 2
          }
        }
        """
        let desktopWhamWire = try RateLimitsWireParser.parse(Data(desktopWhamUsage.utf8))
        let desktopWham = ProtocolMapper.rateLimits(from: desktopWhamWire)
        precondition(desktopWham.primaryBucket?.usedPercent == 44)
        precondition(desktopWham.primaryBucket?.remainingPercent == 56)
        precondition(desktopWham.primaryBucket?.windowDurationSeconds == 604_800)
        precondition(desktopWham.primaryBucket?.resetsAt == resetAt)
        precondition(desktopWham.availableResetCardCount == 2)

        let nestedDesktopWhamUsage = """
        {
          "account_id": "active-desktop-account",
          "usage": {
            "rate_limit": {
              "primary_window": {
                "used_percent": 23,
                "limit_window_seconds": 604800,
                "reset_at": 1785903155
              }
            }
          }
        }
        """
        let nestedDesktopWhamWire = try RateLimitsWireParser.parse(Data(nestedDesktopWhamUsage.utf8))
        let nestedDesktopWham = ProtocolMapper.rateLimits(from: nestedDesktopWhamWire)
        precondition(nestedDesktopWham.primaryBucket?.usedPercent == 23)
        precondition(nestedDesktopWham.primaryBucket?.remainingPercent == 77)
        precondition(nestedDesktopWham.primaryBucket?.windowDurationSeconds == 604_800)

        let genericCodexWithSparkPlan = """
        {
          "rate_limit": {
            "limit_id": "codex",
            "limit_name": "通用使用限额",
            "plan_type": "gpt-5.3-codex-spark",
            "primary_window": {
              "used_percent": 29,
              "limit_window_seconds": 604800,
              "reset_at": 1785903155
            }
          }
        }
        """
        let genericWire = try RateLimitsWireParser.parse(Data(genericCodexWithSparkPlan.utf8))
        let genericLimits = ProtocolMapper.rateLimits(from: genericWire)
        precondition(genericLimits.primaryBucket?.remainingPercent == 71)

        // Pro accounts can receive a separate GPT-5.3-Codex-Spark weekly
        // entitlement. That model-specific bucket must not become the generic
        // Pro quota headline.
        let proWithSparkEntitlement = """
        {
          "rate_limits_by_limit_id": {
            "codex": {
              "limit_id": "codex",
              "limit_name": "通用使用限额",
              "primary": {
                "used_percent": 17,
                "window_minutes": 10080,
                "resets_at": 1785903155
              }
            },
            "gpt-5.3-codex-spark": {
              "limit_id": "gpt-5.3-codex-spark",
              "limit_name": "GPT-5.3-Codex-Spark 使用限额",
              "primary": {
                "used_percent": 0,
                "window_minutes": 10080,
                "resets_at": 1785989555
              }
            }
          }
        }
        """
        let proWire = try RateLimitsWireParser.parse(Data(proWithSparkEntitlement.utf8))
        let proLimits = ProtocolMapper.rateLimits(from: proWire)
        precondition(proLimits.buckets.count == 1)
        precondition(proLimits.primaryBucket?.remainingPercent == 83)
        precondition(!proLimits.buckets.contains { $0.id.lowercased().contains("spark") })

        print("Rate limit freshness smoke: PASS")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw NSError(domain: "RateLimitFreshnessSmoke", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        return value
    }
}
