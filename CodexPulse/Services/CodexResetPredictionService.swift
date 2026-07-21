import Foundation
import Observation

enum ResetPredictionLevel: String, Codable, Equatable, Sendable {
    case none
    case low
    case possible
    case high
    case veryHigh
    case confirmed

    var displayName: String {
        switch self {
        case .none: return "暂无迹象"
        case .low: return "低可能"
        case .possible: return "存在可能"
        case .high: return "高可能"
        case .veryHigh: return "极高可能"
        case .confirmed: return "官方确认"
        }
    }

    static func resolve(index: Int) -> Self {
        switch index {
        case 100...: return .confirmed
        case 80...99: return .veryHigh
        case 60...79: return .high
        case 40...59: return .possible
        case 20...39: return .low
        default: return .none
        }
    }
}

enum ResetSignalSource: String, Codable, Hashable, Sendable {
    case openAI
    case openAIDevs
    case sama
    case thsottiaux
    case openAIStatus
    case helpCenter
    case codexChangelog
    case openAINews
    case codexGitHub

    var displayName: String {
        switch self {
        case .openAI: return "@OpenAI · RSS"
        case .openAIDevs: return "@OpenAIDevs · RSS"
        case .sama: return "@sama · RSS"
        case .thsottiaux: return "@thsottiaux · RSS"
        case .openAIStatus: return "OpenAI Status"
        case .helpCenter: return "OpenAI 帮助中心"
        case .codexChangelog: return "Codex 更新日志"
        case .openAINews: return "OpenAI News"
        case .codexGitHub: return "OpenAI Codex GitHub"
        }
    }

    var isOfficialSource: Bool {
        self == .helpCenter || self == .codexChangelog
            || self == .openAINews || self == .codexGitHub
    }

    var isThirdPartyXSource: Bool {
        self == .openAI || self == .openAIDevs || self == .sama || self == .thsottiaux
    }

    var isOpenAICorporateXSource: Bool {
        self == .openAI || self == .openAIDevs
    }
}

enum ResetSignalKind: String, Codable, Equatable, Sendable {
    case resetAnnouncement
    case bankedReset
    case compensation
    case limitIncrease
    case statusLimitConsumption
    case statusMajorOutage
    case statusOutage
    case modelCelebration
    case referralPromotion
    case hint
}

struct ResetPredictionSignal: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var canonicalID: String
    var source: ResetSignalSource
    var kind: ResetSignalKind
    var title: String
    var excerpt: String
    var sourceURL: String?
    var publishedAt: Date
    var baseWeight: Double
    var effectiveWeight: Double
    var reason: String
    var estimatedWindow: String?
    var completed: Bool
    var officialConfirmation: Bool
}

struct CodexResetPredictionSnapshot: Codable, Equatable, Sendable {
    var predictionIndex: Int
    var level: ResetPredictionLevel
    var officialConfirmed: Bool
    var estimatedWindow: String?
    var confidence: String
    var reasons: [String]
    var activeSignals: [ResetPredictionSignal]
    var history: [ResetPredictionSignal]
    var sourceWarnings: [String]
    var updatedAt: Date

    static let empty = CodexResetPredictionSnapshot(
        predictionIndex: 0,
        level: .none,
        officialConfirmed: false,
        estimatedWindow: nil,
        confidence: "暂无",
        reasons: [],
        activeSignals: [],
        history: [],
        sourceWarnings: [],
        updatedAt: .distantPast
    )
}

enum CodexResetPredictionError: LocalizedError {
    case invalidResponse(String)
    case server(String, Int)
    case invalidRSSProxyTemplate

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let source): return "\(source) 返回了无法识别的数据"
        case .server(let source, let code): return "\(source) 返回 HTTP \(code)"
        case .invalidRSSProxyTemplate: return "RSS 代理模板必须使用 HTTPS 并包含 {username}"
        }
    }
}

private struct RawResetEvidence: Sendable {
    var id: String
    var canonicalID: String
    var source: ResetSignalSource
    var title: String
    var text: String
    var sourceURL: String?
    var publishedAt: Date
    var impact: String?
    var codexContext: Bool
}

private struct ResetEvidenceCollection: Sendable {
    var evidence: [RawResetEvidence]
    var warnings: [String]
}

actor CodexResetPredictionAPIClient {
    static let shared = CodexResetPredictionAPIClient()

    private let session: URLSession
    private let monitoredXAccounts: [(username: String, source: ResetSignalSource)] = [
        ("OpenAI", .openAI),
        ("OpenAIDevs", .openAIDevs),
        ("sama", .sama),
        ("thsottiaux", .thsottiaux)
    ]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: configuration)
    }

    fileprivate func collect(thirdPartyXRSSTemplate: String?) async -> ResetEvidenceCollection {
        var evidence: [RawResetEvidence] = []
        var warnings: [String] = []

        do {
            evidence.append(contentsOf: try await fetchStatusIncidents())
        } catch {
            warnings.append("OpenAI Status：\(error.localizedDescription)")
        }

        do {
            evidence.append(contentsOf: try await fetchOfficialDocuments())
        } catch {
            warnings.append("OpenAI 官方文档：\(error.localizedDescription)")
        }

        do {
            evidence.append(contentsOf: try await fetchCodexGitHubReleases())
        } catch {
            warnings.append("OpenAI Codex GitHub：\(error.localizedDescription)")
        }

        if let template = thirdPartyXRSSTemplate {
            let thirdParty = await fetchThirdPartyXFeeds(template: template)
            evidence.append(contentsOf: thirdParty.evidence)
            warnings.append(contentsOf: thirdParty.warnings)
        }

        var unique: [String: RawResetEvidence] = [:]
        for item in evidence {
            unique[item.id] = item
        }
        return ResetEvidenceCollection(evidence: Array(unique.values), warnings: warnings)
    }

    private func fetchStatusIncidents() async throws -> [RawResetEvidence] {
        guard let url = URL(string: "https://status.openai.com/api/v2/incidents.json") else {
            throw CodexResetPredictionError.invalidResponse("OpenAI Status")
        }
        let data = try await publicData(url: url, source: "OpenAI Status")
        let payload = try decode(StatusIncidentsResponse.self, from: data, source: "OpenAI Status")
        return payload.incidents.compactMap { incident in
            let updates = incident.incidentUpdates ?? []
            let combined = ([incident.name, "Status: \(incident.status)"] + updates.map(\.body))
                .joined(separator: "\n")
            guard combined.lowercased().contains("codex") else { return nil }
            guard let publishedAt = Self.parseDate(incident.updatedAt)
                ?? Self.parseDate(incident.createdAt) else { return nil }
            return RawResetEvidence(
                id: "status:\(incident.id)",
                canonicalID: "status:\(incident.id)",
                source: .openAIStatus,
                title: incident.name,
                text: combined,
                sourceURL: "https://status.openai.com/incidents/\(incident.id)",
                publishedAt: publishedAt,
                impact: incident.impact,
                codexContext: true
            )
        }
    }

    private func fetchOfficialDocuments() async throws -> [RawResetEvidence] {
        let documents: [(ResetSignalSource, String, String)] = [
            (.helpCenter, "Codex 套餐与用量", "https://help.openai.com/en/articles/11369540"),
            (.helpCenter, "Codex 推荐活动", "https://help.openai.com/en/articles/20001271"),
            (.codexChangelog, "Codex 更新日志", "https://developers.openai.com/codex/changelog"),
            (.openAINews, "OpenAI News", "https://openai.com/news/")
        ]
        var result: [RawResetEvidence] = []
        for document in documents {
            guard let url = URL(string: document.2) else { continue }
            var request = URLRequest(url: url)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request) else { continue }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                continue
            }
            guard let html = String(data: data, encoding: .utf8) else { continue }
            let text = Self.relevantOfficialSnippet(from: html)
            guard !text.isEmpty else { continue }
            let modifiedAt = Self.documentDate(html: html, response: http)
            result.append(RawResetEvidence(
                id: "doc:\(document.0.rawValue):\(document.2)",
                canonicalID: "doc:\(document.0.rawValue):\(document.2)",
                source: document.0,
                title: document.1,
                text: text,
                sourceURL: document.2,
                publishedAt: modifiedAt ?? .distantPast,
                impact: nil,
                codexContext: true
            ))
        }
        return result
    }

    private func fetchThirdPartyXFeeds(template: String) async -> ResetEvidenceCollection {
        guard template.contains("{username}") else {
            return ResetEvidenceCollection(
                evidence: [],
                warnings: ["第三方 X RSS：\(CodexResetPredictionError.invalidRSSProxyTemplate.localizedDescription)"]
            )
        }

        var evidence: [RawResetEvidence] = []
        var warnings: [String] = []
        for account in monitoredXAccounts {
            guard let url = Self.thirdPartyRSSURL(template: template, username: account.username) else {
                warnings.append("@\(account.username)：RSS 代理地址无效")
                continue
            }
            do {
                var request = URLRequest(url: url)
                request.setValue(
                    "application/rss+xml, application/atom+xml, application/xml, text/xml",
                    forHTTPHeaderField: "Accept"
                )
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw CodexResetPredictionError.invalidResponse("@\(account.username) RSS")
                }
                guard (200...299).contains(http.statusCode) else {
                    throw CodexResetPredictionError.server("@\(account.username) RSS", http.statusCode)
                }
                guard let xml = String(data: data, encoding: .utf8) else {
                    throw CodexResetPredictionError.invalidResponse("@\(account.username) RSS")
                }
                let lowercasedXML = xml.lowercased()
                guard lowercasedXML.contains("<rss") || lowercasedXML.contains("<feed") else {
                    throw CodexResetPredictionError.invalidResponse("@\(account.username) RSS")
                }
                let parsed = Self.parseThirdPartyFeed(
                    xml,
                    username: account.username,
                    source: account.source
                )
                evidence.append(contentsOf: parsed)
                if parsed.isEmpty {
                    warnings.append("@\(account.username) RSS：近 7 天没有可解析条目")
                }
            } catch {
                warnings.append("@\(account.username) RSS：\(error.localizedDescription)")
            }
        }
        return ResetEvidenceCollection(evidence: evidence, warnings: warnings)
    }

    private static func thirdPartyRSSURL(template: String, username: String) -> URL? {
        let value = template
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "{username}", with: username)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "") {
            return url
        }
        return nil
    }

    private static func parseThirdPartyFeed(
        _ xml: String,
        username: String,
        source: ResetSignalSource
    ) -> [RawResetEvidence] {
        let rssItems = xmlBlocks(named: "item", in: xml)
        let blocks = rssItems.isEmpty ? xmlBlocks(named: "entry", in: xml) : rssItems
        let cutoff = Date().addingTimeInterval(-7 * 86_400)

        return blocks.compactMap { block in
            let title = xmlValue("title", in: block) ?? "@\(username) 的 X 动态"
            let body = xmlValue("description", in: block)
                ?? xmlValue("content", in: block)
                ?? xmlValue("summary", in: block)
                ?? ""
            let link = xmlValue("link", in: block) ?? atomLink(in: block)
            let guid = xmlValue("guid", in: block) ?? xmlValue("id", in: block)
            let dateText = xmlValue("pubDate", in: block)
                ?? xmlValue("updated", in: block)
                ?? xmlValue("published", in: block)
            guard let publishedAt = parseFeedDate(dateText), publishedAt >= cutoff else { return nil }

            let text = plainText(from: "\(title) \(body)")
            let identifier = statusID(in: link ?? guid ?? "") ?? guid ?? link
                ?? "\(username):\(publishedAt.timeIntervalSince1970):\(title)"
            return RawResetEvidence(
                id: "third-party-rss:\(source.rawValue):\(identifier)",
                canonicalID: "x-post:\(identifier)",
                source: source,
                title: title,
                text: text,
                sourceURL: link,
                publishedAt: publishedAt,
                impact: nil,
                codexContext: false
            )
        }
    }

    private static func xmlBlocks(named name: String, in xml: String) -> [String] {
        let pattern = "<\(name)(?:\\s[^>]*)?>([\\s\\S]*?)</\(name)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap {
            guard let range = Range($0.range(at: 1), in: xml) else { return nil }
            return String(xml[range])
        }
    }

    private static func xmlValue(_ tag: String, in block: String) -> String? {
        atomValue(tag, in: block)
    }

    private static func parseFeedDate(_ value: String?) -> Date? {
        if let date = parseDate(value) { return date }
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func statusID(in value: String) -> String? {
        let pattern = #"/status/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private func fetchCodexGitHubReleases() async throws -> [RawResetEvidence] {
        guard let url = URL(string: "https://github.com/openai/codex/releases.atom") else {
            throw CodexResetPredictionError.invalidResponse("OpenAI Codex GitHub")
        }
        var request = URLRequest(url: url)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CodexResetPredictionError.invalidResponse("OpenAI Codex GitHub")
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw CodexResetPredictionError.invalidResponse("OpenAI Codex GitHub")
        }

        let entryPattern = #"<entry>([\s\S]*?)</entry>"#
        guard let regex = try? NSRegularExpression(pattern: entryPattern) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let entryRange = Range(match.range(at: 1), in: xml) else { return nil }
            let entry = String(xml[entryRange])
            guard let title = Self.atomValue("title", in: entry),
                  let updated = Self.parseDate(Self.atomValue("updated", in: entry)) else {
                return nil
            }
            let link = Self.atomLink(in: entry)
            let identifier = link ?? Self.atomValue("id", in: entry) ?? title
            let content = Self.atomValue("content", in: entry) ?? ""
            let text = Self.plainText(from: "\(title) \(content)")
            return RawResetEvidence(
                id: "github:\(identifier)",
                canonicalID: "github:\(identifier)",
                source: .codexGitHub,
                title: title,
                text: text,
                sourceURL: link,
                publishedAt: updated,
                impact: nil,
                codexContext: true
            )
        }
    }

    private func publicData(url: URL, source: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexResetPredictionError.invalidResponse(source)
        }
        guard (200...299).contains(http.statusCode) else {
            throw CodexResetPredictionError.server(source, http.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, source: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CodexResetPredictionError.invalidResponse(source)
        }
    }

    fileprivate static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func documentDate(html: String, response: HTTPURLResponse) -> Date? {
        let pattern = #"\"dateModified\"\s*:\s*\"([^\"]+)\""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html),
           let date = parseDate(String(html[range])) {
            return date
        }
        guard let lastModified = response.value(forHTTPHeaderField: "Last-Modified") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: lastModified)
    }

    private static func atomValue(_ tag: String, in entry: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: entry, range: NSRange(entry.startIndex..., in: entry)),
              let range = Range(match.range(at: 1), in: entry) else { return nil }
        return decodeHTMLEntities(String(entry[range]))
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
    }

    private static func atomLink(in entry: String) -> String? {
        let pattern = #"<link[^>]+href="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: entry, range: NSRange(entry.startIndex..., in: entry)),
              let range = Range(match.range(at: 1), in: entry) else { return nil }
        return decodeHTMLEntities(String(entry[range]))
    }

    private static func plainText(from html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">"
        ]
        return entities.reduce(text) { value, entity in
            value.replacingOccurrences(of: entity.key, with: entity.value)
        }
    }

    private static func relevantOfficialSnippet(from html: String) -> String {
        var text = html.replacingOccurrences(
            of: #"<script[\s\S]*?</script>|<style[\s\S]*?</style>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">"]
        for entity in entities { text = text.replacingOccurrences(of: entity.key, with: entity.value) }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let lower = text.lowercased()
        let keywords = [
            "banked reset", "rate-limit reset", "rate limit reset", "codex usage",
            "codex limit", "2x codex", "double codex", "extra codex", "codex referral"
        ]
        guard let match = keywords.compactMap({ lower.range(of: $0) }).min(by: {
            lower.distance(from: lower.startIndex, to: $0.lowerBound)
                < lower.distance(from: lower.startIndex, to: $1.lowerBound)
        }) else { return "" }
        let startOffset = max(0, lower.distance(from: lower.startIndex, to: match.lowerBound) - 350)
        let endOffset = min(text.count, lower.distance(from: lower.startIndex, to: match.upperBound) + 700)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return String(text[start..<end])
    }
}

private enum ResetPredictionEngine {
    static func evaluate(
        evidence: [RawResetEvidence],
        warnings: [String],
        reference: Date = Date()
    ) -> CodexResetPredictionSnapshot {
        var deduplicated: [String: ResetPredictionSignal] = [:]
        for item in evidence {
            guard let signal = classify(item, reference: reference) else { continue }
            if let current = deduplicated[signal.canonicalID], current.effectiveWeight >= signal.effectiveWeight {
                continue
            }
            deduplicated[signal.canonicalID] = signal
        }

        let signals = Array(deduplicated.values)
        let history = signals
            .filter { isHistorical($0, reference: reference) }
            .sorted { $0.publishedAt > $1.publishedAt }
        let active = signals
            .filter { !isHistorical($0, reference: reference) && $0.effectiveWeight >= 0.5 }
            .sorted { $0.effectiveWeight > $1.effectiveWeight }

        guard !active.isEmpty else {
            var empty = CodexResetPredictionSnapshot.empty
            empty.history = history
            empty.sourceWarnings = warnings
            empty.updatedAt = reference
            return empty
        }

        let strongestBySource = Dictionary(grouping: active, by: \.source).compactMapValues {
            $0.max(by: { $0.effectiveWeight < $1.effectiveWeight })
        }
        var index = strongestBySource.values.map(\.effectiveWeight).max() ?? 0
        var officialConfirmed = active.contains(where: \.officialConfirmation)

        let statusSignal = strongestBySource[.openAIStatus]
        let tiboSignal = strongestBySource[.thsottiaux]
        let samSignal = strongestBySource[.sama]
        let openAIXSignal = strongestBySource[.openAI]
        let openAIDevsXSignal = strongestBySource[.openAIDevs]
        let officialSignals = strongestBySource.values.filter { $0.source.isOfficialSource }
        if let statusSignal,
           officialSignals.contains(where: { sameEventWindow(statusSignal, $0) }) {
            index += 15
        }
        if officialSignals.contains(where: { first in
            officialSignals.contains(where: {
                $0.source != first.source && sameEventWindow(first, $0)
            })
        }) {
            index += 10
        }
        if let statusSignal, let tiboSignal, sameEventWindow(statusSignal, tiboSignal) {
            index += 15
        }
        if let tiboSignal, let samSignal, sameEventWindow(tiboSignal, samSignal) {
            index += 10
        }
        if let statusSignal, let openAIXSignal, sameEventWindow(statusSignal, openAIXSignal) {
            index += 15
        }
        if let openAIXSignal, let openAIDevsXSignal,
           sameEventWindow(openAIXSignal, openAIDevsXSignal) {
            index += 10
        }
        let modelSignals = active.filter { $0.kind == .modelCelebration }
        let officialResetSignals = active.filter {
            $0.source.isOfficialSource && $0.kind == .resetAnnouncement
        }
        if modelSignals.contains(where: { model in
            officialResetSignals.contains(where: { sameEventWindow(model, $0) })
        }) {
            officialConfirmed = true
        }

        if strongestBySource.keys.allSatisfy({ $0 == .openAIStatus }) {
            index = min(index, 55)
        }
        if officialConfirmed {
            index = 100
        } else {
            index = min(index, 99)
        }
        let resolvedIndex = min(100, max(0, Int(index.rounded())))
        let sourceCount = Set(active.map(\.source)).count
        let confidence: String
        if officialConfirmed {
            confidence = "官方确认"
        } else if sourceCount >= 3 {
            confidence = "高"
        } else if sourceCount == 2 || resolvedIndex >= 60 {
            confidence = "中高"
        } else if resolvedIndex >= 40 {
            confidence = "中"
        } else {
            confidence = "低"
        }

        var reasons = active.prefix(4).map(\.reason)
        if sourceCount >= 2 {
            reasons.append("最近时间窗口内出现 \(sourceCount) 个独立来源的相关信号")
        }
        if resolvedIndex >= 40 && !officialConfirmed {
            reasons.append("OpenAI 官方尚未确认额外额度发放")
        }

        return CodexResetPredictionSnapshot(
            predictionIndex: resolvedIndex,
            level: ResetPredictionLevel.resolve(index: resolvedIndex),
            officialConfirmed: officialConfirmed,
            estimatedWindow: active.compactMap(\.estimatedWindow).first,
            confidence: confidence,
            reasons: Array(reasons.prefix(5)),
            activeSignals: active,
            history: history,
            sourceWarnings: warnings,
            updatedAt: reference
        )
    }

    private static func sameEventWindow(
        _ lhs: ResetPredictionSignal,
        _ rhs: ResetPredictionSignal
    ) -> Bool {
        abs(lhs.publishedAt.timeIntervalSince(rhs.publishedAt)) <= 24 * 3_600
    }

    private static func classify(
        _ item: RawResetEvidence,
        reference: Date
    ) -> ResetPredictionSignal? {
        let text = item.text.lowercased()
        let codexRelevant = item.codexContext || text.contains("codex")
        guard codexRelevant else { return nil }
        if isNormalScheduledReset(text) { return nil }

        let activeAnnouncement = containsAny(text, [
            "starting today", "later today", "next 24 hours", "next hour", "for a limited time",
            "we are increasing", "we're increasing", "we will increase", "now available",
            "will reset", "have reset", "fully reset", "has been reset", "we're giving", "we are giving"
        ])
        let explicitReset = containsAny(text, [
            "fully reset", "global reset", "reset all", "will reset", "have reset",
            "has been reset", "rate-limit reset", "rate limit reset", "banked reset"
        ])
        let banked = containsAny(text, ["banked reset", "reset available", "banked codex"])
        let compensation = containsAny(text, [
            "compensat", "make it right", "restore the limits", "restored your limit",
            "additional reset", "extra reset"
        ])
        let limitIncrease = containsAny(text, [
            "2x codex", "double codex", "limits will increase", "increase codex limits",
            "increasing codex limits", "higher codex limits", "temporary additional codex usage",
            "temporarily remove", "removing the 5-hour", "extra codex usage"
        ])
        let referral = containsAny(text, ["referral", "invite a friend", "invite a coworker"])
            && containsAny(text, ["reset", "additional codex usage", "extra codex usage", "reward"])
        let modelLaunch = containsAny(text, [
            "new codex model", "new model", "model launch", "model release",
            "launching gpt", "released gpt", "introducing gpt"
        ])
            && containsAny(text, ["celebrat", "reset", "extra usage"])
        let hint = containsAny(text, ["soon", "stay tuned", "working on", "looking into"])
            && containsAny(text, ["reset", "rate limit", "usage limit", "more usage"])

        var kind: ResetSignalKind
        var baseWeight: Double
        var halfLife: Double
        var official = false
        var reason: String

        if item.source == .openAIStatus {
            let abnormalConsumption = containsAny(text, [
                "limits depleting", "limits being consumed", "usage limits depleting",
                "incorrectly rate limiting", "quota consumption", "usage limit abnormal"
            ])
            if abnormalConsumption {
                kind = .statusLimitConsumption
                baseWeight = 45
                reason = "OpenAI Status 确认 Codex 额度存在异常消耗或错误限流"
            } else if item.impact == "critical" || item.impact == "major" {
                kind = .statusMajorOutage
                baseWeight = 30
                reason = "OpenAI Status 确认 Codex 出现大范围严重故障"
            } else {
                kind = .statusOutage
                baseWeight = 15
                reason = "OpenAI Status 记录了一次 Codex 普通故障"
            }
            halfLife = 24
        } else if item.source.isOfficialSource && explicitReset && activeAnnouncement {
            kind = banked ? .bankedReset : .resetAnnouncement
            baseWeight = 100
            halfLife = 48
            official = true
            reason = "\(item.source.displayName) 明确确认 Codex 额外额度重置或发放"
        } else if item.source.isOfficialSource && compensation && activeAnnouncement {
            kind = .compensation
            baseWeight = 100
            halfLife = 48
            official = true
            reason = "\(item.source.displayName) 明确确认 Codex 故障补偿或额外额度发放"
        } else if item.source.isThirdPartyXSource && explicitReset {
            kind = banked ? .bankedReset : .resetAnnouncement
            baseWeight = 90
            halfLife = 48
            reason = "第三方 RSS 转发的 \(item.source.displayName) 动态明确提到 Codex reset"
        } else if item.source == .thsottiaux && (compensation || limitIncrease) {
            kind = compensation ? .compensation : .limitIncrease
            baseWeight = 75
            halfLife = limitIncrease ? 72 : 48
            reason = "第三方 RSS 转发的 @thsottiaux 动态提到补偿、恢复或增加 Codex 额度"
        } else if limitIncrease && item.source.isOpenAICorporateXSource && activeAnnouncement {
            kind = .limitIncrease
            baseWeight = 80
            halfLife = 72
            reason = "第三方 RSS 转发的 \(item.source.displayName) 动态提到提高 Codex 使用额度"
        } else if limitIncrease && item.source.isOfficialSource && activeAnnouncement {
            kind = .limitIncrease
            baseWeight = 85
            halfLife = 72
            official = false
            reason = "\(item.source.displayName) 明确提到临时提高 Codex 使用额度"
        } else if referral && item.source.isOfficialSource && activeAnnouncement {
            kind = .referralPromotion
            baseWeight = 100
            halfLife = 48
            official = true
            reason = "OpenAI 官方帮助中心确认正在发放推荐或邀请奖励"
        } else if referral && item.source.isOpenAICorporateXSource && activeAnnouncement {
            kind = .referralPromotion
            baseWeight = 85
            halfLife = 48
            reason = "第三方 RSS 转发的 OpenAI 账号动态提到推荐或邀请奖励"
        } else if modelLaunch {
            kind = .modelCelebration
            baseWeight = 70
            halfLife = 48
            reason = "Codex 新模型发布同时出现 celebrate/reset 相关描述"
        } else if hint && (item.source.isOfficialSource || item.source.isThirdPartyXSource) {
            kind = .hint
            baseWeight = 55
            halfLife = 12
            reason = item.source.isThirdPartyXSource
                ? "第三方 RSS 转发的 \(item.source.displayName) 动态暗示可能调整 Codex reset 或 limits"
                : "\(item.source.displayName) 暗示可能调整 Codex reset 或 limits"
        } else {
            return nil
        }

        let ageHours = max(0, reference.timeIntervalSince(item.publishedAt) / 3_600)
        let effectiveWeight = baseWeight * pow(0.5, ageHours / halfLife)
        let completed = containsAny(text, [
            "have reset", "has been reset", "fully reset", "reset is complete",
            "all impacted services have now fully recovered", "status: resolved"
        ])
        return ResetPredictionSignal(
            id: item.id,
            canonicalID: item.canonicalID,
            source: item.source,
            kind: kind,
            title: item.title,
            excerpt: String(item.text.prefix(500)),
            sourceURL: item.sourceURL,
            publishedAt: item.publishedAt,
            baseWeight: baseWeight,
            effectiveWeight: effectiveWeight,
            reason: reason,
            estimatedWindow: estimatedWindow(text: text, completed: completed),
            completed: completed,
            officialConfirmation: official
        )
    }

    private static func isHistorical(_ signal: ResetPredictionSignal, reference: Date) -> Bool {
        let age = reference.timeIntervalSince(signal.publishedAt)
        if signal.completed && age > 24 * 3_600 { return true }
        return age > 7 * 86_400
    }

    private static func estimatedWindow(text: String, completed: Bool) -> String? {
        if completed { return "已执行（24 小时内）" }
        if text.contains("in the next hour") || text.contains("next hour") { return "未来 1 小时" }
        if text.contains("later today") || text.contains("starting today") { return "今天" }
        if text.contains("over the next 24 hours") || text.contains("next 24 hours") { return "未来 24 小时" }
        return nil
    }

    private static func isNormalScheduledReset(_ text: String) -> Bool {
        let normal = containsAny(text, [
            "every 5 hours", "every five hours", "5-hour window", "five-hour window",
            "weekly limit resets", "resets weekly", "normal reset", "next reset in"
        ])
        let extra = containsAny(text, [
            "extra", "global", "compensat", "banked", "temporary", "fully reset", "all users"
        ])
        return normal && !extra
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }
}

@MainActor
@Observable
final class CodexResetPredictionStore {
    static let defaultNitterTemplate = "https://nitter.net/{username}/rss"
    static let defaultRSSHubTemplate = "https://rsshub.app/twitter/user/{username}"

    private(set) var snapshot: CodexResetPredictionSnapshot
    private(set) var isLoading = false
    private(set) var isEnabled: Bool
    private(set) var isThirdPartyXRSSEnabled: Bool
    private(set) var thirdPartyXRSSTemplate: String
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    private let cacheLifetime: TimeInterval = 30 * 60
    private let monitorInterval: UInt64 = 30 * 60 * 1_000_000_000
    private var didStart = false
    private var monitorTask: Task<Void, Never>?

    init() {
        snapshot = CodexResetPredictionCacheStore.load() ?? .empty
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "codexResetPredictionEnabled") == nil {
            isEnabled = true
            defaults.set(true, forKey: "codexResetPredictionEnabled")
        } else {
            isEnabled = defaults.bool(forKey: "codexResetPredictionEnabled")
        }
        if defaults.object(forKey: "codexResetThirdPartyXRSSEnabled") == nil {
            isThirdPartyXRSSEnabled = true
            defaults.set(true, forKey: "codexResetThirdPartyXRSSEnabled")
        } else {
            isThirdPartyXRSSEnabled = defaults.bool(forKey: "codexResetThirdPartyXRSSEnabled")
        }
        thirdPartyXRSSTemplate = defaults.string(forKey: "codexResetThirdPartyXRSSTemplate")
            ?? Self.defaultNitterTemplate
    }

    var isCacheStale: Bool {
        snapshot.updatedAt == .distantPast
            || Date().timeIntervalSince(snapshot.updatedAt) >= cacheLifetime
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        beginMonitoringIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "codexResetPredictionEnabled")
        if enabled {
            beginMonitoringIfNeeded()
        } else {
            monitorTask?.cancel()
            monitorTask = nil
            statusMessage = "额外重置预测已关闭"
        }
    }

    func setThirdPartyXRSSEnabled(_ enabled: Bool) {
        isThirdPartyXRSSEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "codexResetThirdPartyXRSSEnabled")
        statusMessage = enabled ? "第三方 X RSS 监控已启用" : "第三方 X RSS 监控已关闭"
        Task { await refresh(force: true) }
    }

    func saveThirdPartyXRSSTemplate(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("{username}"),
              let sampleURL = URL(string: value.replacingOccurrences(of: "{username}", with: "OpenAI")),
              let scheme = sampleURL.scheme?.lowercased(),
              scheme == "https" || (
                scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(sampleURL.host ?? "")
              ) else {
            errorMessage = CodexResetPredictionError.invalidRSSProxyTemplate.localizedDescription
            statusMessage = nil
            return false
        }
        thirdPartyXRSSTemplate = value
        isThirdPartyXRSSEnabled = true
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: "codexResetThirdPartyXRSSTemplate")
        defaults.set(true, forKey: "codexResetThirdPartyXRSSEnabled")
        errorMessage = nil
        statusMessage = "第三方 X RSS 代理模板已保存"
        Task { await refresh(force: true) }
        return true
    }

    func refresh(force: Bool = false) async {
        guard isEnabled, !isLoading else { return }
        guard force || isCacheStale else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let collection = await CodexResetPredictionAPIClient.shared.collect(
            thirdPartyXRSSTemplate: isThirdPartyXRSSEnabled ? thirdPartyXRSSTemplate : nil
        )
        var next = ResetPredictionEngine.evaluate(
            evidence: collection.evidence,
            warnings: collection.warnings
        )
        next.history = mergeHistory(previous: snapshot, next: next)
        snapshot = next
        CodexResetPredictionCacheStore.save(next)
        statusMessage = "已分析 \(collection.evidence.count) 条监控信号"
        if collection.evidence.isEmpty && !collection.warnings.isEmpty {
            errorMessage = collection.warnings.joined(separator: " · ")
            statusMessage = nil
        }
    }

    private func beginMonitoringIfNeeded() {
        guard isEnabled, monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isCacheStale { await self.refresh() }
                try? await Task.sleep(nanoseconds: self.monitorInterval)
            }
        }
    }

    private func mergeHistory(
        previous: CodexResetPredictionSnapshot,
        next: CodexResetPredictionSnapshot
    ) -> [ResetPredictionSignal] {
        let activeIDs = Set(next.activeSignals.map(\.id))
        let newlyHistorical = previous.activeSignals.filter { !activeIDs.contains($0.id) }
        var byID: [String: ResetPredictionSignal] = [:]
        for signal in previous.history + newlyHistorical + next.history {
            byID[signal.id] = signal
        }
        return Array(byID.values).sorted { $0.publishedAt > $1.publishedAt }.prefix(50).map { $0 }
    }
}

private enum CodexResetPredictionCacheStore {
    private static var url: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = support.appendingPathComponent("CodexPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("codex_reset_prediction.json")
    }

    static func load() -> CodexResetPredictionSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexResetPredictionSnapshot.self, from: data)
    }

    static func save(_ snapshot: CodexResetPredictionSnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private struct StatusIncidentsResponse: Decodable {
    struct Incident: Decodable {
        struct Update: Decodable {
            var body: String
        }

        var id: String
        var name: String
        var impact: String?
        var status: String
        var createdAt: String?
        var updatedAt: String?
        var resolvedAt: String?
        var incidentUpdates: [Update]?

        enum CodingKeys: String, CodingKey {
            case id, name, impact, status
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case resolvedAt = "resolved_at"
            case incidentUpdates = "incident_updates"
        }
    }

    var incidents: [Incident]
}
