import Foundation

/// 简单本地日志：控制台 + 文件，便于排查「突然断掉」。
/// 性能与隐私要点：
/// - 复用同一个 FileHandle，避免每行都 open/seek/close；
/// - 按大小滚动（pulse.log → pulse.log.1），日志不会无限增长；
/// - 提供 redact() 遮蔽邮箱/Token 等敏感串，避免明文落盘。
enum PulseLog {
    private static let queue = DispatchQueue(label: "com.codexpulse.log")

    /// 单个日志文件上限（字节）；超过即滚动到 .1。
    private static let maxFileBytes = 512 * 1024
    /// 保留的历史文件数量（pulse.log.1 … pulse.log.N）。
    private static let rotatedCopies = 2

    // 以下状态只在 `queue` 上访问。
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var bytesWritten: Int = 0

    static var logDirectoryURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CodexPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("pulse.log")
    }

    static func write(_ message: String) {
        let line = "\(isoNow())  \(message)\n"
        NSLog("[CodexPulse] %@", message)
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            appendLocked(data)
        }
    }

    /// 遮蔽邮箱与长 token/密钥，用于日志中引用敏感内容时。
    static func redact(_ text: String) -> String {
        var result = text

        // 邮箱：保留首字符与域名，其余用 * 代替。
        if let emailRegex = try? NSRegularExpression(
            pattern: "([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+)"
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = emailRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1***$2"
            )
        }

        // 疑似 token / key（sk-…、Bearer …、长 base64/hex 串）。
        if let tokenRegex = try? NSRegularExpression(
            pattern: "(sk-[A-Za-z0-9]{4})[A-Za-z0-9_-]{8,}|([A-Za-z0-9_-]{6})[A-Za-z0-9_-]{26,}"
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = tokenRegex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1$2…«已遮蔽»"
            )
        }

        return result
    }

    static func tail(maxBytes: Int = 16_000) -> String {
        queue.sync {
            let url = logFileURL
            guard let data = try? Data(contentsOf: url) else {
                return "(尚无日志文件: \(url.path))"
            }
            if data.count <= maxBytes {
                return String(data: data, encoding: .utf8) ?? ""
            }
            let slice = data.suffix(maxBytes)
            return "…\n" + (String(data: slice, encoding: .utf8) ?? "")
        }
    }

    /// 关闭并清空当前日志文件（供「清除本地数据」调用）。
    static func reset() {
        queue.sync {
            try? handle?.close()
            handle = nil
            bytesWritten = 0
            let fm = FileManager.default
            try? fm.removeItem(at: logFileURL)
            for index in 1...rotatedCopies {
                try? fm.removeItem(at: rotatedURL(index))
            }
        }
    }

    // MARK: - Private (queue-confined)

    private static func appendLocked(_ data: Data) {
        let fh = ensureHandleLocked()
        guard let fh else {
            // 句柄不可用时退回一次性写入，至少不丢日志。
            try? data.write(to: logFileURL)
            return
        }
        do {
            try fh.write(contentsOf: data)
            bytesWritten += data.count
            if bytesWritten >= maxFileBytes {
                rotateLocked()
            }
        } catch {
            // 写失败：丢弃句柄，下次重开。
            try? fh.close()
            handle = nil
        }
    }

    private static func ensureHandleLocked() -> FileHandle? {
        if let handle { return handle }
        let url = logFileURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let fh = try? FileHandle(forWritingTo: url) else { return nil }
        let end = (try? fh.seekToEnd()) ?? 0
        bytesWritten = Int(end)
        handle = fh
        return fh
    }

    private static func rotateLocked() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default

        // pulse.log.(N-1) → pulse.log.N，最旧的被覆盖。
        if rotatedCopies >= 1 {
            for index in stride(from: rotatedCopies, through: 1, by: -1) {
                let dst = rotatedURL(index)
                let src = index == 1 ? logFileURL : rotatedURL(index - 1)
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
        } else {
            try? fm.removeItem(at: logFileURL)
        }
        bytesWritten = 0
    }

    private static func rotatedURL(_ index: Int) -> URL {
        logDirectoryURL.appendingPathComponent("pulse.log.\(index)")
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
