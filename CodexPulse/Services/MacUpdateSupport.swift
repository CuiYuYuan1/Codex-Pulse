import CryptoKit
import Foundation

enum AppUpdateInstallationStage: String, Equatable, Sendable {
    case idle
    case downloading
    case ready
    case installing
    case failed
}

final class AppUpdateDownloadCoordinator: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    typealias ProgressHandler = (Int64, Int64) -> Void
    typealias CompletionHandler = (Result<URL, Error>) -> Void

    private let sourceURL: URL
    private let destinationURL: URL
    private let progressHandler: ProgressHandler
    private let completionHandler: CompletionHandler
    private var task: URLSessionDownloadTask?
    private var didComplete = false
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(
        sourceURL: URL,
        destinationURL: URL,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.progressHandler = progress
        self.completionHandler = completion
    }

    func start() {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 30
        request.setValue("CodexPulse-Updater", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw MacUpdateError.invalidDownloadResponse
            }
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            finish(.success(destinationURL))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completionHandler(result)
        session.finishTasksAndInvalidate()
    }
}

enum MacUpdateSupport {
    static func isTrustedReleaseAssetURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else { return false }
        return url.path.lowercased().hasPrefix("/cuiyuyuan1/codex-pulse/releases/download/")
            && url.pathExtension.lowercased() == "dmg"
    }

    static func downloadDestination(for version: String) throws -> URL {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MacUpdateError.applicationSupportUnavailable
        }
        let directory = support
            .appendingPathComponent("CodexPulse", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeVersion = version.replacingOccurrences(
            of: "[^0-9A-Za-z._-]",
            with: "-",
            options: .regularExpression
        )
        return directory.appendingPathComponent("CodexPulse-macOS-\(safeVersion).dmg")
    }

    static func validateDownload(at url: URL, expectedSHA256: String?) async throws {
        try await Task.detached(priority: .utility) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 1_000_000 else {
                throw MacUpdateError.invalidDownloadedFile
            }
            guard let expectedSHA256 else { return }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expectedSHA256.lowercased() else {
                throw MacUpdateError.checksumMismatch
            }
        }.value
    }

    static func launchInstaller(dmgURL: URL, currentAppURL: URL, version: String) throws {
        let fileManager = FileManager.default
        let appURL = currentAppURL.standardizedFileURL
        guard appURL.pathExtension.lowercased() == "app" else {
            throw MacUpdateError.invalidCurrentApplication
        }
        guard !appURL.path.hasPrefix("/Volumes/") else {
            throw MacUpdateError.runningFromDiskImage
        }
        let parent = appURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw MacUpdateError.installLocationNotWritable
        }

        let scriptURL = try downloadDestination(for: version)
            .deletingLastPathComponent()
            .appendingPathComponent("install-\(version).sh")
        let logURL = scriptURL.deletingLastPathComponent().appendingPathComponent("install-\(version).log")
        let script = """
        #!/bin/sh
        set -eu
        DMG="$1"
        TARGET="$2"
        PARENT="$3"
        PID="$4"
        LOG="$5"
        exec >>"$LOG" 2>&1
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
        MOUNT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/codexpulse-update.XXXXXX")"
        BACKUP="${TARGET}.codexpulse-previous"
        cleanup() {
          /usr/bin/hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
          /bin/rmdir "$MOUNT" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT
        /usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT"
        SOURCE="$MOUNT/CodexPulse.app"
        test -d "$SOURCE"
        test -w "$PARENT"
        /bin/rm -rf "$BACKUP"
        /bin/mv "$TARGET" "$BACKUP"
        if /usr/bin/ditto "$SOURCE" "$TARGET"; then
          /bin/rm -rf "$BACKUP"
          /usr/bin/open -n "$TARGET"
        else
          /bin/rm -rf "$TARGET"
          /bin/mv "$BACKUP" "$TARGET"
          exit 1
        fi
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            dmgURL.path,
            appURL.path,
            parent.path,
            String(ProcessInfo.processInfo.processIdentifier),
            logURL.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

enum MacUpdateError: LocalizedError {
    case applicationSupportUnavailable
    case invalidDownloadResponse
    case invalidDownloadedFile
    case checksumMismatch
    case invalidCurrentApplication
    case runningFromDiskImage
    case installLocationNotWritable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable: "无法访问应用支持目录"
        case .invalidDownloadResponse: "下载服务器返回了无效响应"
        case .invalidDownloadedFile: "下载的安装包不完整"
        case .checksumMismatch: "安装包 SHA-256 校验不一致"
        case .invalidCurrentApplication: "当前程序不是可替换的应用包"
        case .runningFromDiskImage: "请先把 CodexPulse 拖到“应用程序”后再自动更新"
        case .installLocationNotWritable: "当前安装目录不可写，请将 CodexPulse 放到有权限的应用目录"
        }
    }
}
