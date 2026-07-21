import Foundation

/// Codex 账号信息，对应 `account/read`
struct AccountInfo: Codable, Equatable, Sendable {
    var email: String?
    var planType: PlanType
    var authMode: AuthMode
    var isLoggedIn: Bool
    var workspaceName: String?
    var cliVersion: String?
    var lastSyncedAt: Date?

    /// 仅供界面、日志和诊断信息展示；原始邮箱只用于本机账号状态关联。
    var maskedEmail: String? {
        guard let email else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else {
            return Self.maskIdentifier(trimmed)
        }

        let localPart = String(parts[0])
        let domain = String(parts[1])
        return "\(Self.maskIdentifier(localPart))@\(domain)"
    }

    var displayEmail: String {
        maskedEmail ?? (isLoggedIn ? authMode.displayName : "未登录")
    }

    private static func maskIdentifier(_ value: String) -> String {
        switch value.count {
        case 0:
            return "***"
        case 1:
            return "*"
        case 2:
            return "\(value.prefix(1))*"
        case 3...4:
            return "\(value.prefix(1))***\(value.suffix(1))"
        default:
            let hiddenCount = max(3, value.count - 4)
            let prefix = String(value.prefix(2))
            let mask = String(repeating: "*", count: hiddenCount)
            let suffix = String(value.suffix(2))
            return prefix + mask + suffix
        }
    }

    enum PlanType: String, Codable, CaseIterable, Sendable {
        case free = "Free"
        case plus = "Plus"
        case pro = "Pro"
        case business = "Business"
        case team = "Team"
        case unknown = "Unknown"

        var displayName: String { rawValue }
    }

    enum AuthMode: String, Codable, Sendable {
        case chatGPT = "ChatGPT"
        case apiKey = "API Key"
        case none = "None"

        var displayName: String { rawValue }
    }

    static let empty = AccountInfo(
        email: nil,
        planType: .unknown,
        authMode: .none,
        isLoggedIn: false,
        workspaceName: nil,
        cliVersion: nil,
        lastSyncedAt: nil
    )
}
