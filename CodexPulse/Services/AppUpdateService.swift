import Foundation
import Observation
import Network
#if os(macOS)
import AppKit
#endif

struct AppRelease: Identifiable, Equatable, Sendable {
    let version: String
    let title: String
    let notes: String?
    let pageURL: URL
    let downloadURL: URL
    let expectedSHA256: String?

    var id: String { version }

    var displayNotes: String {
        let fallback = "此版本未提供详细更新说明，可前往 GitHub Release 查看完整变更。"
        guard let source = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else {
            return fallback
        }

        let renderedLines = source.components(separatedBy: .newlines).map { line -> String in
            guard line.localizedCaseInsensitiveContains("Full Changelog"),
                  let compareRange = line.range(of: "/compare/") else {
                return line
            }

            let comparison = line[compareRange.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " )"))
                .replacingOccurrences(of: "...", with: " → ")
            return comparison.isEmpty ? "完整变更请查看 GitHub Release" : "完整变更：\(comparison)"
        }
        let rendered = renderedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? fallback : rendered
    }
}

@MainActor
@Observable
final class AppUpdateService {
    static let shared = AppUpdateService()
    static let repository = "CuiYuYuan1/Codex-Pulse"
    static let releasesPageURL = URL(string: "https://github.com/\(repository)/releases")!

    private(set) var isChecking = false
    private(set) var statusMessage = "启动后及每 5 分钟自动检查 GitHub Releases"
    private(set) var lastCheckedAt: Date?
    private(set) var availableRelease: AppRelease?
    private(set) var skippedVersion: String?
    private(set) var installationStage: AppUpdateInstallationStage = .idle
    private(set) var downloadProgress: Double = 0
    private(set) var downloadedByteCount: Int64 = 0
    private(set) var expectedDownloadByteCount: Int64 = 0
    private(set) var installationMessage: String?

    @ObservationIgnored private var automaticCheckTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private let networkMonitor = NWPathMonitor()
    @ObservationIgnored private let networkMonitorQueue = DispatchQueue(label: "com.codexpulse.update-network")
    @ObservationIgnored private var downloadCoordinator: AppUpdateDownloadCoordinator?
    @ObservationIgnored private var downloadedUpdateURL: URL?
    private var lastAutomaticCheckAt: Date?
    private let skippedVersionKey = "pulse.update.skipped-version"
    private let automaticCheckInterval: TimeInterval = 5 * 60

    init() {
        skippedVersion = UserDefaults.standard.string(forKey: skippedVersionKey)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var primaryUpdateActionTitle: String {
        switch installationStage {
        case .idle: "立即更新"
        case .downloading: "下载中 \(Int((downloadProgress * 100).rounded()))%"
        case .ready: "重启并更新"
        case .installing: "正在重启…"
        case .failed: downloadedUpdateURL == nil ? "重新下载" : "重试安装"
        }
    }

    var isPrimaryUpdateActionDisabled: Bool {
        availableRelease == nil || installationStage == .downloading || installationStage == .installing
    }

    func startAutomaticChecks() {
        guard automaticCheckTask == nil else { return }

        automaticCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.checkForUpdates(userInitiated: false, force: true)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.automaticCheckInterval * 1_000_000_000))
                } catch {
                    return
                }
                await self.checkForUpdates(userInitiated: false)
            }
        }

        #if os(macOS)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(userInitiated: false, force: true)
            }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(userInitiated: false)
            }
        }
        #endif

        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.checkForUpdates(userInitiated: false, force: true)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    func checkForUpdates(userInitiated: Bool, force: Bool = false) async {
        if !userInitiated, !force, let lastAutomaticCheckAt,
           Date().timeIntervalSince(lastAutomaticCheckAt) < automaticCheckInterval {
            return
        }
        if !userInitiated { lastAutomaticCheckAt = Date() }
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
                resetDownloadedUpdate(removeFile: true)
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
                let asset = Self.preferredDownloadAsset(from: payload.assets)
                let release = AppRelease(
                    version: remoteVersion,
                    title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? "CodexPulse v\(remoteVersion)",
                    notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    pageURL: pageURL,
                    downloadURL: downloadURL,
                    expectedSHA256: Self.normalizedSHA256(asset?.digest)
                )
                if Self.normalizedVersion(skippedVersion ?? "") == remoteVersion {
                    if availableRelease?.version != remoteVersion {
                        resetDownloadedUpdate(removeFile: true)
                    }
                    availableRelease = nil
                    statusMessage = "已跳过版本 v\(remoteVersion)"
                } else {
                    if let previousVersion = availableRelease?.version,
                       Self.normalizedVersion(previousVersion) != remoteVersion {
                        resetDownloadedUpdate(removeFile: true)
                    }
                    availableRelease = release
                    statusMessage = "发现新版本 v\(remoteVersion)"
                }
            } else {
                resetDownloadedUpdate(removeFile: true)
                availableRelease = nil
                statusMessage = "当前已是最新版 v\(currentVersion)"
            }
        } catch {
            statusMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }

    func openAvailableUpdate() {
        performPrimaryUpdateAction()
    }

    func performPrimaryUpdateAction() {
        switch installationStage {
        case .idle:
            downloadAvailableUpdate()
        case .ready:
            installDownloadedUpdateAndRestart()
        case .failed:
            if downloadedUpdateURL == nil {
                downloadAvailableUpdate()
            } else {
                installDownloadedUpdateAndRestart()
            }
        case .downloading, .installing:
            break
        }
    }

    func downloadAvailableUpdate() {
        guard let release = availableRelease else { return }
        guard MacUpdateSupport.isTrustedReleaseAssetURL(release.downloadURL) else {
            installationStage = .failed
            installationMessage = "更新地址校验失败，请稍后重新检查更新"
            return
        }

        resetDownloadedUpdate(removeFile: true)
        do {
            let destination = try MacUpdateSupport.downloadDestination(for: release.version)
            installationStage = .downloading
            downloadProgress = 0
            installationMessage = "正在下载 v\(release.version)…"
            statusMessage = installationMessage ?? statusMessage

            let coordinator = AppUpdateDownloadCoordinator(
                sourceURL: release.downloadURL,
                destinationURL: destination,
                progress: { [weak self] written, expected in
                    Task { @MainActor [weak self] in
                        guard let self, self.installationStage == .downloading else { return }
                        self.downloadedByteCount = written
                        self.expectedDownloadByteCount = max(0, expected)
                        if expected > 0 {
                            self.downloadProgress = min(1, max(0, Double(written) / Double(expected)))
                        }
                        self.installationMessage = "正在下载 v\(release.version)…"
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.downloadCoordinator = nil
                        guard self.availableRelease?.version == release.version else {
                            if case .success(let fileURL) = result {
                                try? FileManager.default.removeItem(at: fileURL)
                            }
                            return
                        }
                        switch result {
                        case .success(let fileURL):
                            do {
                                try await MacUpdateSupport.validateDownload(
                                    at: fileURL,
                                    expectedSHA256: release.expectedSHA256
                                )
                                self.downloadedUpdateURL = fileURL
                                self.downloadProgress = 1
                                self.installationStage = .ready
                                self.installationMessage = "下载完成，重启后自动安装 v\(release.version)"
                                self.statusMessage = self.installationMessage ?? self.statusMessage
                            } catch {
                                try? FileManager.default.removeItem(at: fileURL)
                                self.downloadedUpdateURL = nil
                                self.installationStage = .failed
                                self.installationMessage = "下载校验失败：\(error.localizedDescription)"
                                self.statusMessage = self.installationMessage ?? self.statusMessage
                            }
                        case .failure(let error):
                            self.downloadedUpdateURL = nil
                            self.installationStage = .failed
                            self.installationMessage = "下载失败：\(error.localizedDescription)"
                            self.statusMessage = self.installationMessage ?? self.statusMessage
                        }
                    }
                }
            )
            downloadCoordinator = coordinator
            coordinator.start()
        } catch {
            installationStage = .failed
            installationMessage = "无法准备更新：\(error.localizedDescription)"
            statusMessage = installationMessage ?? statusMessage
        }
    }

    func installDownloadedUpdateAndRestart() {
        guard let release = availableRelease, let downloadedUpdateURL else { return }
        installationStage = .installing
        installationMessage = "正在退出并安装 v\(release.version)…"
        statusMessage = installationMessage ?? statusMessage
        do {
            try MacUpdateSupport.launchInstaller(
                dmgURL: downloadedUpdateURL,
                currentAppURL: Bundle.main.bundleURL,
                version: release.version
            )
            #if os(macOS)
            NSApplication.shared.terminate(nil)
            #endif
        } catch {
            installationStage = .failed
            installationMessage = "无法自动安装：\(error.localizedDescription)"
            statusMessage = installationMessage ?? statusMessage
        }
    }

    func skipAvailableVersion() {
        guard let release = availableRelease else { return }
        resetDownloadedUpdate(removeFile: true)
        let version = Self.normalizedVersion(release.version)
        skippedVersion = version
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
        availableRelease = nil
        statusMessage = "已跳过版本 v\(version)"
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

    private static func preferredDownloadAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        #if os(macOS)
        return assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        #else
        return nil
        #endif
    }

    private static func preferredDownloadURL(from assets: [GitHubReleaseAsset]) -> URL? {
        preferredDownloadAsset(from: assets).flatMap { URL(string: $0.browserDownloadURL) }
    }

    private static func normalizedSHA256(_ digest: String?) -> String? {
        guard let value = digest?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let normalized = value.hasPrefix("sha256:") ? String(value.dropFirst(7)) : value
        return normalized.count == 64 && normalized.allSatisfy(\.isHexDigit) ? normalized : nil
    }

    private func resetDownloadedUpdate(removeFile: Bool) {
        downloadCoordinator?.cancel()
        downloadCoordinator = nil
        if removeFile, let downloadedUpdateURL {
            try? FileManager.default.removeItem(at: downloadedUpdateURL)
        }
        downloadedUpdateURL = nil
        installationStage = .idle
        downloadProgress = 0
        downloadedByteCount = 0
        expectedDownloadByteCount = 0
        installationMessage = nil
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
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, digest
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
