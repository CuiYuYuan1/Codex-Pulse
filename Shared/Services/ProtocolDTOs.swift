import Foundation

// MARK: - Wire protocol DTOs (aligned with openai/codex app-server schema v2)
// Wire format: JSON-RPC 2.0 over JSONL, with `"jsonrpc":"2.0"` omitted on the wire.

// MARK: Account

struct WireGetAccountResponse: Decodable, Sendable {
    var account: WireAccount?
    var requiresOpenaiAuth: Bool?
}

enum WireAccount: Decodable, Sendable {
    case apiKey
    case chatgpt(email: String?, planType: String?)
    case amazonBedrock(credentialSource: String?)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, email, planType, credentialSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        switch type {
        case "apiKey":
            self = .apiKey
        case "chatgpt":
            // planType may be string or missing
            let plan: String?
            if let s = try? c.decodeIfPresent(String.self, forKey: .planType) {
                plan = s
            } else {
                plan = nil
            }
            self = .chatgpt(
                email: try c.decodeIfPresent(String.self, forKey: .email),
                planType: plan
            )
        case "amazonBedrock":
            self = .amazonBedrock(
                credentialSource: try c.decodeIfPresent(String.self, forKey: .credentialSource)
            )
        default:
            self = .unknown(type: type)
        }
    }
}

// MARK: Rate limits — lenient dictionary-based parsing
// Official shape varies slightly by CLI version; never hard-fail the whole app.

struct WireGetAccountRateLimitsResponse: Sendable {
    var rateLimits: WireRateLimitSnapshot?
    var rateLimitsByLimitId: [String: WireRateLimitSnapshot]?
    var rateLimitResetCredits: WireRateLimitResetCreditsSummary?
}

struct WireRateLimitSnapshot: Sendable {
    var limitId: String?
    var limitName: String?
    var primary: WireRateLimitWindow?
    var secondary: WireRateLimitWindow?
    var credits: WireCreditsSnapshot?
    var planType: String?
    var rateLimitReachedType: String?
    var spendControlReached: Bool?
}

struct WireRateLimitWindow: Sendable {
    var usedPercent: Double?
    var windowDurationMins: Double?
    var resetsAt: Double?
}

struct WireCreditsSnapshot: Sendable {
    var hasCredits: Bool?
    var unlimited: Bool?
    var balance: Double?
}

struct WireRateLimitResetCreditsSummary: Sendable {
    var availableCount: Int?
    var credits: [WireRateLimitResetCredit]?
}

struct WireRateLimitResetCredit: Sendable {
    var id: String?
    var resetType: String?
    var status: String?
    var grantedAt: Double?
    var expiresAt: Double?
    var title: String?
    var description: String?
}

enum RateLimitsWireParser {
    static func parse(_ data: Data) throws -> WireGetAccountRateLimitsResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexServerError.invalidResponse("rateLimits root not object")
        }
        return parse(root)
    }

    static func parse(_ rawRoot: [String: Any]) -> WireGetAccountRateLimitsResponse {
        let root = (rawRoot["data"] as? [String: Any])
            ?? (rawRoot["result"] as? [String: Any])
            ?? rawRoot
        let single = parseSnapshot(
            firstDictionary(root, keys: ["rateLimits", "rate_limits"])
        )
        var byId: [String: WireRateLimitSnapshot] = [:]
        if let map = firstDictionary(root, keys: ["rateLimitsByLimitId", "rate_limits_by_limit_id"]) {
            for (key, value) in map {
                if let dict = value as? [String: Any], let snap = parseSnapshot(dict) {
                    byId[key] = snap
                }
            }
        }
        let credits = parseResetCredits(
            firstDictionary(root, keys: ["rateLimitResetCredits", "rate_limit_reset_credits"])
        )
        return WireGetAccountRateLimitsResponse(
            rateLimits: single,
            rateLimitsByLimitId: byId.isEmpty ? nil : byId,
            rateLimitResetCredits: credits
        )
    }

    private static func parseSnapshot(_ dict: [String: Any]?) -> WireRateLimitSnapshot? {
        guard let dict else { return nil }
        return WireRateLimitSnapshot(
            limitId: string(dict["limitId"] ?? dict["limit_id"]),
            limitName: string(dict["limitName"] ?? dict["limit_name"]),
            primary: parseWindow(dict["primary"] as? [String: Any]),
            secondary: parseWindow(dict["secondary"] as? [String: Any]),
            credits: parseCredits(dict["credits"] as? [String: Any]),
            planType: string(dict["planType"] ?? dict["plan_type"]),
            rateLimitReachedType: {
                if let s = dict["rateLimitReachedType"] as? String { return s }
                if let s = dict["rate_limit_reached_type"] as? String { return s }
                if dict["rateLimitReachedType"] is NSNull { return nil }
                if dict["rate_limit_reached_type"] is NSNull { return nil }
                if let n = dict["rateLimitReachedType"] { return "\(n)" }
                if let n = dict["rate_limit_reached_type"] { return "\(n)" }
                return nil
            }(),
            spendControlReached: bool(dict["spendControlReached"] ?? dict["spend_control_reached"])
        )
    }

    private static func parseWindow(_ dict: [String: Any]?) -> WireRateLimitWindow? {
        guard let dict else { return nil }
        return WireRateLimitWindow(
            usedPercent: number(dict["usedPercent"] ?? dict["used_percent"]),
            windowDurationMins: number(
                dict["windowDurationMins"]
                    ?? dict["window_duration_mins"]
                    ?? dict["window_minutes"]
            ),
            resetsAt: number(dict["resetsAt"] ?? dict["resets_at"])
        )
    }

    private static func parseCredits(_ dict: [String: Any]?) -> WireCreditsSnapshot? {
        guard let dict else { return nil }
        return WireCreditsSnapshot(
            hasCredits: bool(dict["hasCredits"] ?? dict["has_credits"]),
            unlimited: dict["unlimited"] as? Bool,
            balance: number(dict["balance"])
        )
    }

    private static func parseResetCredits(_ dict: [String: Any]?) -> WireRateLimitResetCreditsSummary? {
        guard let dict else { return nil }
        var list: [WireRateLimitResetCredit]? = nil
        if let arr = dict["credits"] as? [[String: Any]] {
            list = arr.map { c in
                WireRateLimitResetCredit(
                    id: string(c["id"]),
                    resetType: string(c["resetType"] ?? c["reset_type"]),
                    status: string(c["status"]),
                    grantedAt: number(c["grantedAt"] ?? c["granted_at"]),
                    expiresAt: number(c["expiresAt"] ?? c["expires_at"]),
                    title: string(c["title"]),
                    description: string(c["description"])
                )
            }
        }
        let count: Int?
        let rawAvailable = dict["availableCount"] ?? dict["available_count"]
        if let i = rawAvailable as? Int {
            count = i
        } else if let d = rawAvailable as? Double {
            count = Int(d)
        } else if let s = rawAvailable as? String, let i = Int(s) {
            count = i
        } else {
            count = nil
        }
        return WireRateLimitResetCreditsSummary(availableCount: count, credits: list)
    }

    private static func firstDictionary(_ root: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = root[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func string(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private static func bool(_ any: Any?) -> Bool? {
        switch any {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String:
            if ["true", "1", "yes"].contains(value.lowercased()) { return true }
            if ["false", "0", "no"].contains(value.lowercased()) { return false }
            return nil
        default: return nil
        }
    }

    private static func number(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let i as Int64: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}

// MARK: Usage
// 官方 schema: GetAccountTokenUsageResponse { summary, dailyUsageBuckets: [{startDate, tokens}] }

struct WireGetAccountTokenUsageResponse: Decodable, Sendable {
    var summary: WireAccountTokenUsageSummary?
    var dailyUsageBuckets: [WireAccountTokenUsageDailyBucket]?

    enum CodingKeys: String, CodingKey {
        case summary, dailyUsageBuckets
        case dailyBuckets, days, usage, data, result, tokenUsage, activity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(WireAccountTokenUsageSummary.self, forKey: .summary)
            ?? c.decodeIfPresent(WireAccountTokenUsageSummary.self, forKey: .usage)
            ?? c.decodeIfPresent(WireAccountTokenUsageSummary.self, forKey: .tokenUsage)
        dailyUsageBuckets = try c.decodeIfPresent([WireAccountTokenUsageDailyBucket].self, forKey: .dailyUsageBuckets)
            ?? c.decodeIfPresent([WireAccountTokenUsageDailyBucket].self, forKey: .dailyBuckets)
            ?? c.decodeIfPresent([WireAccountTokenUsageDailyBucket].self, forKey: .days)

        if summary == nil || dailyUsageBuckets == nil {
            for nest in [CodingKeys.data, CodingKeys.result, CodingKeys.activity] {
                guard let nested = try? c.nestedContainer(keyedBy: CodingKeys.self, forKey: nest) else { continue }
                if summary == nil {
                    summary = try? nested.decodeIfPresent(WireAccountTokenUsageSummary.self, forKey: .summary)
                }
                if dailyUsageBuckets == nil {
                    dailyUsageBuckets = try? nested.decodeIfPresent([WireAccountTokenUsageDailyBucket].self, forKey: .dailyUsageBuckets)
                        ?? nested.decodeIfPresent([WireAccountTokenUsageDailyBucket].self, forKey: .dailyBuckets)
                }
            }
        }
    }

    init(summary: WireAccountTokenUsageSummary? = nil, dailyUsageBuckets: [WireAccountTokenUsageDailyBucket]? = nil) {
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
    }
}

struct WireAccountTokenUsageSummary: Decodable, Sendable {
    var lifetimeTokens: FlexibleInt64?
    var peakDailyTokens: FlexibleInt64?
    var longestRunningTurnSec: FlexibleInt64?
    var currentStreakDays: FlexibleInt64?
    var longestStreakDays: FlexibleInt64?
    var totalTokens: FlexibleInt64?
    var todayTokens: FlexibleInt64?

    var resolvedLifetime: Int64? { (lifetimeTokens ?? totalTokens)?.value }
}

struct WireAccountTokenUsageDailyBucket: Decodable, Sendable {
    var startDate: String?
    var tokens: FlexibleInt64?

    enum CodingKeys: String, CodingKey {
        case startDate, tokens, date, day, tokenCount, total
        case inputTokens, outputTokens, cachedTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
            ?? c.decodeIfPresent(String.self, forKey: .date)
            ?? c.decodeIfPresent(String.self, forKey: .day)
        tokens = try c.decodeIfPresent(FlexibleInt64.self, forKey: .tokens)
            ?? c.decodeIfPresent(FlexibleInt64.self, forKey: .tokenCount)
            ?? c.decodeIfPresent(FlexibleInt64.self, forKey: .total)
        if tokens == nil {
            let input = (try? c.decodeIfPresent(FlexibleInt64.self, forKey: .inputTokens))?.value ?? 0
            let output = (try? c.decodeIfPresent(FlexibleInt64.self, forKey: .outputTokens))?.value ?? 0
            let cached = (try? c.decodeIfPresent(FlexibleInt64.self, forKey: .cachedTokens))?.value ?? 0
            // cachedTokens 通常是 inputTokens 的子集，不能再次相加，否则日用量会被双计。
            let sum = input + output
            if sum > 0 {
                tokens = FlexibleInt64(sum)
            } else if cached > 0 {
                tokens = FlexibleInt64(cached)
            }
        }
    }

    init(startDate: String?, tokens: FlexibleInt64?) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

// MARK: Threads

struct WireThreadListResponse: Decodable, Sendable {
    var data: [WireThread]?
    var nextCursor: String?
}

struct WireThread: Decodable, Sendable {
    var id: String?
    var preview: String?
    var cwd: FlexiblePath?
    var createdAt: FlexibleDouble?
    var updatedAt: FlexibleDouble?
    var recencyAt: FlexibleDouble?
    var cliVersion: String?
    var name: String?
    var modelProvider: String?
    var status: FlexibleStatus?
    var gitInfo: WireGitInfo?
}

/// cwd may be string or { "path": "..." } depending on schema version
struct FlexiblePath: Decodable, Sendable {
    var value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
            return
        }
        if let obj = try? c.decode([String: String].self) {
            value = obj["path"] ?? obj["absolutePath"] ?? obj.values.first
            return
        }
        value = nil
    }
}

struct FlexibleDouble: Decodable, Sendable {
    var value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }
}

struct FlexibleStatus: Decodable, Sendable {
    var value: String?
    var activeFlags: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
            activeFlags = []
            return
        }
        if let object = try? c.decode(StatusObject.self) {
            value = object.type
            activeFlags = object.activeFlags ?? []
            return
        }
        value = nil
        activeFlags = []
    }

    private struct StatusObject: Decodable {
        var type: String?
        var activeFlags: [String]?
    }
}

struct WireGitInfo: Decodable, Sendable {
    var branch: String?
    var repositoryUrl: String?
}

// MARK: Flexible numbers

struct FlexibleInt: Decodable, Sendable {
    var value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int(d); return }
        if let s = try? c.decode(String.self), let i = Int(s) { value = i; return }
        value = 0
    }
}

struct FlexibleInt64: Decodable, Sendable {
    var value: Int64
    init(_ value: Int64) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            throw DecodingError.valueNotFound(
                Int64.self,
                .init(codingPath: decoder.codingPath, debugDescription: "null FlexibleInt64")
            )
        }
        if let i = try? c.decode(Int64.self) { value = i; return }
        if let i = try? c.decode(Int.self) { value = Int64(i); return }
        if let d = try? c.decode(Double.self) { value = Int64(d); return }
        if let s = try? c.decode(String.self), let i = Int64(s) { value = i; return }
        throw DecodingError.typeMismatch(
            Int64.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported FlexibleInt64")
        )
    }
}

// MARK: Generic JSON-RPC envelopes

enum RPCWire {
    static func encodeRequest(id: Int, method: String, params: [String: Any]? = nil) throws -> Data {
        var obj: [String: Any] = [
            "id": id,
            "method": method
        ]
        obj["params"] = params ?? [String: Any]()
        var data = try JSONSerialization.data(withJSONObject: obj, options: [])
        data.append(0x0A)
        return data
    }

    static func encodeNotification(method: String, params: [String: Any]? = nil) throws -> Data {
        var obj: [String: Any] = ["method": method]
        obj["params"] = params ?? [String: Any]()
        var data = try JSONSerialization.data(withJSONObject: obj, options: [])
        data.append(0x0A)
        return data
    }
}
