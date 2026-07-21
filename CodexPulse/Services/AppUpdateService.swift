import Foundation
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppRelease: Identifiable, Equatable, Sendable {
    let version: String
    let title: String
    let notes: String?
    let pageURL: URL
    let downloadURL: URL

    var id: String { version }
}

@MainActor
@Observable
final class AppUpdateService {
    static let repository = "CuiYuYuan1/Codex-Pulse"
    static let releasesPageURL = URL(string: "https://github.com/\(repository)/releases")!

    private(set) var isChecking = false
    private(set) var statusMessage = "启动时自动检查 GitHub Releases"
    private(set) var lastCheckedAt: Date?
    private(set) var availableRelease: AppRelease?
    var isShowingUpdateAlert = false

    private var didPerformAutomaticCheck = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func checkForUpdates(userInitiated: Bool) async {
        if !userInitiated, didPerformAutomaticCheck { return }
        if !userInitiated { didPerformAutomaticCheck = true }
        guard !isChecking else { return }

        isChecking = true
        if userInitiated { statusMessage = "正在检查 GitHub Releases…" }
        defer { isChecking = false }

        do {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
            )
            request.timeoutInterval = 12
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("CodexPulse/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            if http.statusCode == 404 {
                availableRelease = nil
                lastCheckedAt = Date()
                statusMessage = "GitHub 暂无已发布版本"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.httpStatus(http.statusCode)
            }

            let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
            guard let pageURL = URL(string: payload.htmlURL) else {
                throw UpdateError.invalidResponse
            }
            let remoteVersion = Self.normalizedVersion(payload.tagName)
            let downloadURL = Self.preferredDownloadURL(from: payload.assets) ?? pageURL
            lastCheckedAt = Date()

            if Self.isVersion(remoteVersion, newerThan: currentVersion) {
                let release = AppRelease(
                    version: remoteVersion,
                    title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? "CodexPulse v\(remoteVersion)",
                    notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    pageURL: pageURL,
                    downloadURL: downloadURL
                )
                availableRelease = release
                statusMessage = "发现新版本 v\(remoteVersion)"
                isShowingUpdateAlert = true
            } else {
                availableRelease = nil
                statusMessage = "当前已是最新版 v\(currentVersion)"
            }
        } catch {
            statusMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }

    func openAvailableUpdate() {
        let url = availableRelease?.downloadURL ?? Self.releasesPageURL
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    func openReleasesPage() {
        #if os(macOS)
        NSWorkspace.shared.open(Self.releasesPageURL)
        #endif
    }

    static func normalizedVersion(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.lowercased().hasPrefix("v") { result.removeFirst() }
        return result
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = ParsedVersion(normalizedVersion(candidate))
        let rhs = ParsedVersion(normalizedVersion(current))
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left > right }
        }
        if lhs.isPrerelease != rhs.isPrerelease { return !lhs.isPrerelease }
        return false
    }

    private static func preferredDownloadURL(from assets: [GitHubReleaseAsset]) -> URL? {
        #if os(macOS)
        let preferred = assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        #else
        let preferred: GitHubReleaseAsset? = nil
        #endif
        return preferred.flatMap { URL(string: $0.browserDownloadURL) }
    }
}

private struct ParsedVersion {
    let numbers: [Int]
    let isPrerelease: Bool

    init(_ value: String) {
        let components = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        numbers = components.first?.split(separator: ".").map { Int($0) ?? 0 } ?? [0]
        isPrerelease = components.count > 1
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "GitHub 返回了无效数据"
        case .httpStatus(let code): "GitHub 请求失败（HTTP \(code)）"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct AppUpdateAlertModifier: ViewModifier {
    @Environment(AppUpdateService.self) private var updates

    func body(content: Content) -> some View {
        @Bindable var updates = updates
        content.alert(
            "发现 CodexPulse 新版本",
            isPresented: $updates.isShowingUpdateAlert,
            presenting: updates.availableRelease
        ) { _ in
            Button("下载更新") { updates.openAvailableUpdate() }
            Button("稍后", role: .cancel) {}
        } message: { release in
            Text("v\(updates.currentVersion) → v\(release.version)\n\n\(release.notes ?? "新版本已发布，可前往 GitHub 下载并安装。")")
        }
    }
}

extension View {
    func appUpdateAlert() -> some View {
        modifier(AppUpdateAlertModifier())
    }
}
