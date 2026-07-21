import Foundation
import UserNotifications

enum PulseNotificationPermission: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unknown

    var displayName: String {
        switch self {
        case .notDetermined: return "尚未设置"
        case .denied: return "已关闭"
        case .authorized: return "已允许"
        case .provisional: return "临时允许"
        case .unknown: return "未知"
        }
    }
}

/// macOS 本地通知封装
final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
                granted, error in
                if let error {
                    PulseLog.write("notification authorization failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func authorizationStatus() async -> PulseNotificationPermission {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let permission: PulseNotificationPermission
                switch settings.authorizationStatus {
                case .notDetermined: permission = .notDetermined
                case .denied: permission = .denied
                case .authorized: permission = .authorized
                case .provisional: permission = .provisional
                @unknown default: permission = .unknown
                }
                continuation.resume(returning: permission)
            }
        }
    }

    func notifyRateLimit(percent: Double, threshold: Double, soundEnabled: Bool) {
        post(
            id: "\(NotificationIDs.rateLimitWarning)-\(Int(threshold))",
            title: "额度使用达到 \(Int(threshold))%",
            body: "主额度已使用 \(Int(percent))%，请注意任务规划。",
            soundEnabled: soundEnabled
        )
    }

    func notifyExhausted(soundEnabled: Bool) {
        post(
            id: NotificationIDs.rateLimitExhausted,
            title: "额度已耗尽",
            body: "主额度窗口已触发限额，任务可能暂停。",
            soundEnabled: soundEnabled
        )
    }

    func notifyRateLimitReset(soundEnabled: Bool) {
        post(
            id: NotificationIDs.rateLimitReset,
            title: "额度已重置",
            body: "主额度窗口已恢复，可以继续安排 Codex 任务。",
            soundEnabled: soundEnabled
        )
    }

    func notifyTaskCompleted(project: String?, soundEnabled: Bool) {
        post(
            id: NotificationIDs.taskCompleted,
            title: "任务已完成",
            body: project.map { "\($0) 的 Codex 任务已完成。" } ?? "Codex 任务已完成。",
            soundEnabled: soundEnabled
        )
    }

    func notifyTaskFailed(project: String?, soundEnabled: Bool) {
        post(
            id: NotificationIDs.taskFailed,
            title: "任务执行失败",
            body: project.map { "\($0) 的 Codex 任务失败。" } ?? "Codex 任务失败。",
            soundEnabled: soundEnabled
        )
    }

    func notifyAwaitingAuth(soundEnabled: Bool) {
        post(
            id: NotificationIDs.awaitingAuth,
            title: "等待用户授权",
            body: "Codex 正在等待你确认操作。",
            soundEnabled: soundEnabled
        )
    }

    func notifyAwaitingInput(soundEnabled: Bool) {
        post(
            id: NotificationIDs.awaitingInput,
            title: "等待用户输入",
            body: "Codex 需要你补充信息后才能继续。",
            soundEnabled: soundEnabled
        )
    }

    func notifyLongTask(taskID: String, project: String?, minutes: Int, soundEnabled: Bool) {
        post(
            id: "\(NotificationIDs.longTask)-\(taskID)",
            title: "Codex 任务仍在运行",
            body: project.map { "\($0) 已持续运行约 \(minutes) 分钟。" }
                ?? "当前 Codex 任务已持续运行约 \(minutes) 分钟。",
            soundEnabled: soundEnabled
        )
    }

    func notifyTokenSpike(tokensPerMinute: Int64, soundEnabled: Bool) {
        post(
            id: NotificationIDs.tokenSpike,
            title: "Token 消耗速度较高",
            body: "本机 Codex 当前约消耗 \(PulseFormatters.tokens(tokensPerMinute)) Token/分钟。",
            soundEnabled: soundEnabled
        )
    }

    func notifyResetCardExpiry(cardID: String, daysRemaining: Int, soundEnabled: Bool) {
        post(
            id: "\(NotificationIDs.resetCardExpiry)-\(cardID)",
            title: "额度重置卡即将到期",
            body: daysRemaining <= 1
                ? "有一张可用额度重置卡将在 24 小时内到期。"
                : "有一张可用额度重置卡将在约 \(daysRemaining) 天后到期。",
            soundEnabled: soundEnabled
        )
    }

    private func post(id: String, title: String, body: String, soundEnabled: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundEnabled ? .default : nil
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                PulseLog.write("notification \(id) failed: \(error.localizedDescription)")
            }
        }
    }
}

enum WebhookDeliveryError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Webhook 地址无效；仅支持 HTTPS 或本机 HTTP"
        case .invalidResponse: return "Webhook 返回了无效响应"
        case .httpStatus(let status): return "Webhook 返回 HTTP \(status)"
        case .transport(let message): return "Webhook 请求失败：\(message)"
        }
    }
}

private struct WebhookPayload: Encodable, Sendable {
    var event: String
    var title: String
    var body: String
    var timestamp: String
    var source: String
    var details: [String: String]
}

/// 明确自愿开启的出站 Webhook；不会读取或发送源码、对话、账号凭证。
actor WebhookService {
    static let shared = WebhookService()

    nonisolated static func validatedURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw.count <= 2_048,
              var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
        guard scheme == "https" || (scheme == "http" && loopbackHosts.contains(host)) else {
            return nil
        }
        guard components.user == nil, components.password == nil else { return nil }
        components.fragment = nil
        return components.url
    }

    func send(
        rawURL: String?,
        event: String,
        title: String,
        body: String,
        details: [String: String] = [:]
    ) async throws {
        guard let url = Self.validatedURL(rawURL) else {
            throw WebhookDeliveryError.invalidURL
        }
        let payload = WebhookPayload(
            event: event,
            title: title,
            body: body,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            source: AppConstants.appName,
            details: details
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bodyData = try encoder.encode(payload)

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Codex-Pulse/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = bodyData

        for attempt in 0..<2 {
            let response: URLResponse
            do {
                let result = try await URLSession.shared.data(for: request)
                response = result.1
            } catch {
                if attempt == 0 {
                    try await Task.sleep(nanoseconds: 900_000_000)
                    continue
                }
                throw WebhookDeliveryError.transport(error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else {
                throw WebhookDeliveryError.invalidResponse
            }
            if (200..<300).contains(http.statusCode) { return }
            if http.statusCode >= 500, attempt == 0 {
                try await Task.sleep(nanoseconds: 900_000_000)
                continue
            }
            throw WebhookDeliveryError.httpStatus(http.statusCode)
        }
    }
}
