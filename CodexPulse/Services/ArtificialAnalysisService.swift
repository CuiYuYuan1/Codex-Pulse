import Foundation
import Observation
import Security

struct ArtificialAnalysisModel: Codable, Equatable, Identifiable, Sendable {
    struct Creator: Codable, Equatable, Sendable {
        var id: String?
        var name: String
    }

    var id: String
    var name: String
    var slug: String
    var releaseDate: String?
    var creator: Creator
    var intelligenceIndex: Double?
    var codingIndex: Double?
    var agenticIndex: Double?
    var costPerTaskUSD: Double?
    var inputPricePerMillionTokens: Double?
    var outputPricePerMillionTokens: Double?
    var outputTokensPerSecond: Double?
    var timeToFirstTokenSeconds: Double?

    var isOpenAI: Bool {
        creator.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "openai"
    }
}

struct ArtificialAnalysisRateLimit: Codable, Equatable, Sendable {
    var limit: Int?
    var remaining: Int?
    var resetsAt: Date?
}

struct ArtificialAnalysisSnapshot: Codable, Equatable, Sendable {
    var tier: String
    var intelligenceIndexVersion: Double
    var models: [ArtificialAnalysisModel]
    var fetchedAt: Date
    var rateLimit: ArtificialAnalysisRateLimit

    var qualityLeaders: [ArtificialAnalysisModel] {
        models
            .filter { $0.intelligenceIndex != nil }
            .sorted { ($0.intelligenceIndex ?? -.infinity) > ($1.intelligenceIndex ?? -.infinity) }
    }

    var costLeaders: [ArtificialAnalysisModel] {
        models
            .filter { ($0.costPerTaskUSD ?? 0) > 0 }
            .sorted { ($0.costPerTaskUSD ?? .infinity) < ($1.costPerTaskUSD ?? .infinity) }
    }

    var speedLeaders: [ArtificialAnalysisModel] {
        models
            .filter { ($0.outputTokensPerSecond ?? 0) > 0 }
            .sorted { ($0.outputTokensPerSecond ?? 0) > ($1.outputTokensPerSecond ?? 0) }
    }
}

enum ArtificialAnalysisError: LocalizedError {
    case invalidAPIKey
    case accessDenied
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int, message: String?)
    case invalidResponse
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key 无效或已失效"
        case .accessDenied:
            return "当前 Artificial Analysis 套餐无权访问该接口"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "今日 API 请求额度已用完，约 \(Int(retryAfter / 60)) 分钟后重试"
            }
            return "今日 API 请求额度已用完"
        case .server(let statusCode, let message):
            return message.map { "Artificial Analysis 返回 \(statusCode)：\($0)" }
                ?? "Artificial Analysis 返回 HTTP \(statusCode)"
        case .invalidResponse:
            return "Artificial Analysis 返回了无法识别的数据"
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain 操作失败：\(message ?? String(status))"
        }
    }
}

enum ArtificialAnalysisCredentialStore {
    private static let service = "com.codexpulse.app.artificial-analysis"
    private static let account = "data-api-key"

    /// 只查询条目元数据，不取出密钥内容。这样启动时可以恢复设置状态，
    /// 又不会为了一个暂时用不到的排行榜刷新触发 Keychain 密码确认。
    static func containsCredential() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func save(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            throw ArtificialAnalysisError.invalidAPIKey
        }
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = lookup
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ArtificialAnalysisError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw ArtificialAnalysisError.keychain(updateStatus)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ArtificialAnalysisError.keychain(status)
        }
    }
}

actor ArtificialAnalysisAPIClient {
    static let shared = ArtificialAnalysisAPIClient()

    private let baseURL = URL(string: "https://artificialanalysis.ai/api/v2/language/models/free")
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func fetchModels(apiKey: String) async throws -> ArtificialAnalysisSnapshot {
        guard let baseURL else { throw ArtificialAnalysisError.invalidResponse }
        var page = 1
        var models: [ArtificialAnalysisModel] = []
        var seenIDs: Set<String> = []
        var tier = "free"
        var indexVersion = 0.0
        var latestRateLimit = ArtificialAnalysisRateLimit()

        while page <= 10 {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw ArtificialAnalysisError.invalidResponse
            }
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
            guard let url = components.url else { throw ArtificialAnalysisError.invalidResponse }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ArtificialAnalysisError.invalidResponse
            }
            latestRateLimit = rateLimit(from: http)
            guard http.statusCode == 200 else {
                try throwAPIError(statusCode: http.statusCode, data: data, response: http)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let payload = try? decoder.decode(APIResponse.self, from: data) else {
                throw ArtificialAnalysisError.invalidResponse
            }
            tier = payload.tier
            indexVersion = payload.intelligenceIndexVersion
            for item in payload.data where seenIDs.insert(item.id).inserted {
                models.append(item.model)
            }
            guard payload.pagination.hasMore else { break }
            page += 1
        }

        guard !models.isEmpty else { throw ArtificialAnalysisError.invalidResponse }
        return ArtificialAnalysisSnapshot(
            tier: tier,
            intelligenceIndexVersion: indexVersion,
            models: models,
            fetchedAt: Date(),
            rateLimit: latestRateLimit
        )
    }

    private func rateLimit(from response: HTTPURLResponse) -> ArtificialAnalysisRateLimit {
        let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init)
        let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init)
        let resetsAt = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap { TimeInterval($0) }
            .map { Date(timeIntervalSince1970: $0) }
        return ArtificialAnalysisRateLimit(limit: limit, remaining: remaining, resetsAt: resetsAt)
    }

    private func throwAPIError(
        statusCode: Int,
        data: Data,
        response: HTTPURLResponse
    ) throws -> Never {
        let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
        switch statusCode {
        case 401:
            throw ArtificialAnalysisError.invalidAPIKey
        case 403:
            throw ArtificialAnalysisError.accessDenied
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw ArtificialAnalysisError.rateLimited(retryAfter: retryAfter)
        default:
            throw ArtificialAnalysisError.server(statusCode: statusCode, message: message)
        }
    }
}

@MainActor
@Observable
final class ArtificialAnalysisLeaderboardStore {
    static let shared = ArtificialAnalysisLeaderboardStore()

    private(set) var snapshot: ArtificialAnalysisSnapshot?
    private(set) var isLoading = false
    private(set) var hasAPIKey = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    private let cacheLifetime: TimeInterval = 12 * 60 * 60
    private var didStart = false
    /// 密钥内容按需加载并在单次应用生命周期内缓存。未使用稳定 Developer ID
    /// 签名的构建可能在读取内容时弹出密码确认，不能在 init/refresh 各读一次。
    private var cachedAPIKey: String?

    init() {
        snapshot = ArtificialAnalysisCacheStore.load()
        hasAPIKey = ArtificialAnalysisCredentialStore.containsCredential()
    }

    var isCacheStale: Bool {
        guard let fetchedAt = snapshot?.fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) >= cacheLifetime
    }

    /// 返回当前“模型 + 推理档位”在 Artificial Analysis 中对应的编程指数。
    /// reasoning effort 仅用于定位同一模型的 low/high/max 版本，绝不再被当成
    /// 编程能力本身展示。
    func programmingIndex(model rawModel: String?, reasoningEffort: String?) -> Double? {
        guard let rawModel, let snapshot else { return nil }
        let modelKey = Self.normalizedModelKey(rawModel)
        let requestedEffort = Self.modelEffort(in: rawModel)
            ?? Self.normalizedEffort(reasoningEffort)
        let requestedBase = Self.modelBase(modelKey)
        guard !requestedBase.isEmpty else { return nil }

        return snapshot.models
            .filter { $0.isOpenAI && $0.codingIndex != nil }
            .compactMap { candidate -> (score: Int, value: Double)? in
                guard let value = candidate.codingIndex else { return nil }
                let slugKey = Self.normalizedModelKey(candidate.slug)
                let nameKey = Self.normalizedModelKey(candidate.name)
                let candidateBase = Self.modelBase(slugKey)
                guard candidateBase == requestedBase
                        || Self.modelBase(nameKey) == requestedBase else {
                    return nil
                }
                let candidateEffort = Self.modelEffort(in: candidate.name)
                    ?? Self.modelEffort(in: candidate.slug)
                var score = slugKey == modelKey || nameKey == modelKey ? 120 : 100
                if let requestedEffort {
                    score += candidateEffort == requestedEffort ? 40 : -40
                } else if candidateEffort == "max" {
                    score += 5
                }
                return (score, value)
            }
            .max(by: { $0.score < $1.score })?
            .value
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        guard hasAPIKey, isCacheStale else { return }
        Task { await refresh() }
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        guard force || isCacheStale else { return }
        guard let apiKey = loadAPIKeyIfNeeded() else {
            hasAPIKey = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let next = try await ArtificialAnalysisAPIClient.shared.fetchModels(apiKey: apiKey)
            snapshot = next
            ArtificialAnalysisCacheStore.save(next)
            hasAPIKey = true
            statusMessage = "已同步 \(next.models.count) 个模型"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func saveAPIKey(_ value: String) async -> Bool {
        do {
            try ArtificialAnalysisCredentialStore.save(value)
            cachedAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
            hasAPIKey = true
            statusMessage = "API Key 已保存到 macOS Keychain"
            errorMessage = nil
            await refresh(force: true)
            return errorMessage == nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            return false
        }
    }

    func removeAPIKey() {
        do {
            try ArtificialAnalysisCredentialStore.delete()
            cachedAPIKey = nil
            hasAPIKey = false
            errorMessage = nil
            statusMessage = "API Key 已从 Keychain 删除；排行榜缓存仍保留"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func loadAPIKeyIfNeeded() -> String? {
        if let cachedAPIKey { return cachedAPIKey }
        guard hasAPIKey else { return nil }
        let value = ArtificialAnalysisCredentialStore.read()
        cachedAPIKey = value
        hasAPIKey = value != nil
        return value
    }

    private static func normalizedModelKey(_ rawValue: String) -> String {
        String(
            rawValue
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
        )
    }

    private static func normalizedEffort(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = String(
            rawValue
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
        )
        switch normalized {
        case "minimal": return "minimal"
        case "low": return "low"
        case "medium": return "medium"
        case "high": return "high"
        case "xhigh", "extrahigh": return "xhigh"
        case "max", "maximum": return "max"
        case "nonreasoning", "none": return "nonreasoning"
        default: return nil
        }
    }

    private static func modelEffort(in rawValue: String) -> String? {
        let key = normalizedModelKey(rawValue)
        for effort in ["nonreasoning", "minimal", "medium", "xhigh", "high", "low", "maximum", "max"] {
            if key.hasSuffix(effort) {
                return effort == "maximum" ? "max" : effort
            }
        }
        return nil
    }

    private static func modelBase(_ key: String) -> String {
        for effort in ["nonreasoning", "minimal", "medium", "xhigh", "high", "low", "maximum", "max"] {
            if key.hasSuffix(effort) {
                return String(key.dropLast(effort.count))
            }
        }
        return key
    }
}

private enum ArtificialAnalysisCacheStore {
    private static var url: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = support.appendingPathComponent("CodexPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("artificial_analysis_models.json")
    }

    static func load() -> ArtificialAnalysisSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ArtificialAnalysisSnapshot.self, from: data)
    }

    static func save(_ snapshot: ArtificialAnalysisSnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private struct APIResponse: Decodable {
    var tier: String
    var intelligenceIndexVersion: Double
    var pagination: Pagination
    var data: [APIModel]

    struct Pagination: Decodable {
        var page: Int
        var pageSize: Int
        var totalPages: Int
        var hasMore: Bool
    }
}

private struct APIModel: Decodable {
    var id: String
    var name: String
    var slug: String
    var releaseDate: String?
    var modelCreator: ArtificialAnalysisModel.Creator
    var evaluations: Evaluations?
    var artificialAnalysisIntelligenceIndexCost: IntelligenceCost?
    var pricing: Pricing?
    var performance: Performance?

    var model: ArtificialAnalysisModel {
        ArtificialAnalysisModel(
            id: id,
            name: name,
            slug: slug,
            releaseDate: releaseDate,
            creator: modelCreator,
            intelligenceIndex: evaluations?.artificialAnalysisIntelligenceIndex,
            codingIndex: evaluations?.artificialAnalysisCodingIndex,
            agenticIndex: evaluations?.artificialAnalysisAgenticIndex,
            costPerTaskUSD: artificialAnalysisIntelligenceIndexCost?.costPerTask?.totalCost,
            inputPricePerMillionTokens: pricing?.price1mInputTokens,
            outputPricePerMillionTokens: pricing?.price1mOutputTokens,
            outputTokensPerSecond: performance?.medianOutputTokensPerSecond,
            timeToFirstTokenSeconds: performance?.medianTimeToFirstTokenSeconds
        )
    }

    struct Evaluations: Decodable {
        var artificialAnalysisIntelligenceIndex: Double?
        var artificialAnalysisCodingIndex: Double?
        var artificialAnalysisAgenticIndex: Double?
    }

    struct IntelligenceCost: Decodable {
        var totalCost: Double?
        var costPerTask: CostPerTask?

        struct CostPerTask: Decodable {
            var totalCost: Double?
        }
    }

    struct Pricing: Decodable {
        var price1mInputTokens: Double?
        var price1mOutputTokens: Double?
    }

    struct Performance: Decodable {
        var medianOutputTokensPerSecond: Double?
        var medianTimeToFirstTokenSeconds: Double?
    }
}

private struct APIErrorResponse: Decodable {
    var error: String?
}
