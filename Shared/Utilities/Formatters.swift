import Foundation

enum PulseFormatters {
    static func tokens(_ value: Int64?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    /// 活动任务中的紧凑 Token 文案。胶囊只保留一位小数，完整数值仍在
    /// 详情数据中保留，避免百万级用量把主胶囊撑得过宽。
    static func liveTokens(_ value: Int64?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    /// 重置倒计时：≥24h 用 d；否则 h/m/s
    /// 例：3d 4h · 16h 46m · 12m 05s · 45s
    static func countdown(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else { return "—" }
        let total = Int(interval.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 {
            if hours > 0 {
                return String(format: "%dd %dh", days, hours)
            }
            return String(format: "%dd", days)
        }
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func relativeDate(_ date: Date?, relativeTo reference: Date = Date()) -> String {
        guard let date else { return "—" }
        // RelativeDateTimeFormatter may render sub-second clock skew as
        // “0 秒后”. Treat the immediate sync window as “刚刚”.
        if abs(date.timeIntervalSince(reference)) < 1.5 { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    static func shortTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// `7月25日 14:00`（跨年时带年份），用于重置卡到期等需要绝对时间的场景。
    static func absoluteDateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        f.dateFormat = sameYear ? "M月d日 HH:mm" : "yyyy年M月d日 HH:mm"
        return f.string(from: date)
    }
}
