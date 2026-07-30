import Foundation
import Observation

enum PulseAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

enum ActivityBandStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case aurora
    case lava
    case neon
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典"
        case .aurora: return "极光"
        case .lava: return "熔岩"
        case .neon: return "霓虹"
        case .mono: return "单色"
        }
    }
}

enum MiniCapsuleStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case quota
    case tokens
    case status
    case weather
    case time

    var id: String { rawValue }

    static var apiKeyCases: [MiniCapsuleStyle] {
        allCases.filter(\.isAvailableInAPIKeyMode)
    }

    var isAvailableInAPIKeyMode: Bool {
        self != .quota
    }

    var displayName: String {
        switch self {
        case .quota: return "剩余额度"
        case .tokens: return "今日 Token"
        case .status: return "任务状态"
        case .weather: return "天气温度"
        case .time: return "当地时间"
        }
    }
}

enum PetCharacter: String, Codable, CaseIterable, Identifiable, Sendable {
    case dino
    case cat
    case bunny
    case ghost
    case robot
    case fox
    case orb
    case orb2 = "orb_2"
    case orb3 = "orb_3"
    case orb4 = "orb_4"
    case blackHole = "black_hole"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dino: return "小恐龙"
        case .cat: return "猫咪"
        case .bunny: return "兔子"
        case .ghost: return "幽灵"
        case .robot: return "机器人"
        case .fox: return "九尾狐"
        case .orb: return "小圆球1"
        case .orb2: return "小圆球2"
        case .orb3: return "小圆球3"
        case .orb4: return "小圆球4"
        case .blackHole: return "事件视界"
        }
    }

    var isOrb: Bool {
        switch self {
        case .orb, .orb2, .orb3, .orb4:
            return true
        case .dino, .cat, .bunny, .ghost, .robot, .fox, .blackHole:
            return false
        }
    }

    var orbStyleIndex: Int? {
        switch self {
        case .orb: return 1
        case .orb2: return 2
        case .orb3: return 3
        case .orb4: return 4
        case .dino, .cat, .bunny, .ghost, .robot, .fox, .blackHole:
            return nil
        }
    }
}

enum PulseVisualTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case midnight
    case graphite
    case forest
    case amethyst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典玻璃"
        case .midnight: return "午夜 HUD"
        case .graphite: return "石墨哑光"
        case .forest: return "森林柔雾"
        case .amethyst: return "紫晶棱镜"
        }
    }
}

/// 用户选择的天气位置。经纬度和时区直接来自 Open-Meteo 地理编码接口，
/// 这样天气请求不需要再次猜测用户输入，也能在离线时继续显示地区和本地时间。
struct WeatherLocation: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String {
        "\(latitude.rounded(toPlaces: 4)),\(longitude.rounded(toPlaces: 4))"
    }

    var name: String
    var admin1: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var timezone: String

    var displayName: String {
        var parts = [name]
        if let admin1, !admin1.isEmpty, admin1 != name {
            parts.append(admin1)
        }
        if let country, !country.isEmpty, !parts.contains(country) {
            parts.append(country)
        }
        return parts.joined(separator: " · ")
    }

    var countryDisplayName: String {
        country?.isEmpty == false ? country! : ""
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

/// 用户可配置项
struct PulseSettings: Codable, Equatable, Sendable {
    var refreshIntervalSeconds: TimeInterval
    var alertThresholds: [Double]
    var launchAtLogin: Bool
    var soundEnabled: Bool
    var webhookURL: String?
    var webhookEnabled: Bool
    var useMockWhenCLIUnavailable: Bool
    var showTokensInMenuBar: Bool
    var historyRetentionDays: Int
    /// Optional 保证旧版本已保存的 JSON 缺少字段时仍可正常迁移。
    var appearanceMode: PulseAppearanceMode?
    /// nil 表示旧配置，迁移为默认 30 分钟；0 表示用户主动关闭。
    var longTaskAlertMinutes: Int?
    /// nil 迁移为默认 1M/min；0 表示关闭。
    var tokenSpikeThresholdPerMinute: Int64?
    /// 默认关闭，避免无意发送项目标识。
    var webhookIncludeProjectName: Bool?
    /// 应用内系统通知总开关；nil 兼容旧配置并迁移为开启。
    var notificationsEnabled: Bool?
    /// 0 表示关闭，nil 兼容旧配置并迁移为提前 3 天提醒。
    var resetCardExpiryAlertDays: Int?
    /// 本地额度样本与预测开关；nil 兼容旧配置并迁移为开启。
    var rateLimitForecastEnabled: Bool?
    /// 思考灯带开关与配色；Optional 用于兼容旧版本配置。
    var activityBandEnabled: Bool?
    var activityBandStyle: ActivityBandStyle?
    /// 界面材质主题；与浅色/深色模式相互独立。
    var visualTheme: PulseVisualTheme?
    /// 双击缩小后显示在宠物屏幕内的简洁内容；nil 兼容旧配置并迁移为剩余额度。
    var miniCapsuleStyle: MiniCapsuleStyle?
    /// API Key 模式没有 ChatGPT 额度，使用独立的缩小展示选择，旧配置默认为时间。
    var apiMiniCapsuleStyle: MiniCapsuleStyle?
    /// 缩小态桌面宠物；旧配置默认迁移为小恐龙。
    var petCharacter: PetCharacter?
    /// Codex 桌面端启动时自动显示悬浮工具；默认关闭，避免改变旧用户的窗口习惯。
    var followCodexLaunch: Bool?
    /// 信息任务栏（天气 · 地区 · 星期 · 当前时间）；默认关闭，兼容旧配置。
    var informationBarEnabled: Bool?
    /// 信息任务栏使用的地区及天气请求坐标；默认不选择地区。
    var weatherLocation: WeatherLocation?

    static let `default` = PulseSettings(
        refreshIntervalSeconds: AppConstants.defaultRefreshInterval,
        alertThresholds: AppConstants.defaultAlertThresholds,
        launchAtLogin: false,
        soundEnabled: true,
        webhookURL: nil,
        webhookEnabled: false,
        useMockWhenCLIUnavailable: true,
        showTokensInMenuBar: true,
        historyRetentionDays: AppConstants.historyRetentionDays,
        appearanceMode: .system,
        longTaskAlertMinutes: 30,
        tokenSpikeThresholdPerMinute: 1_000_000,
        webhookIncludeProjectName: false,
        notificationsEnabled: true,
        resetCardExpiryAlertDays: 3,
        rateLimitForecastEnabled: true,
        activityBandEnabled: true,
        activityBandStyle: .classic,
        visualTheme: .classic,
        miniCapsuleStyle: .quota,
        apiMiniCapsuleStyle: .time,
        petCharacter: .dino,
        followCodexLaunch: false,
        informationBarEnabled: false,
        weatherLocation: nil
    )

    var resolvedAppearanceMode: PulseAppearanceMode {
        get { appearanceMode ?? .system }
        set { appearanceMode = newValue }
    }

    var resolvedLongTaskAlertMinutes: Int {
        get { longTaskAlertMinutes ?? 30 }
        set { longTaskAlertMinutes = newValue }
    }

    var resolvedTokenSpikeThresholdPerMinute: Int64 {
        get { tokenSpikeThresholdPerMinute ?? 1_000_000 }
        set { tokenSpikeThresholdPerMinute = newValue }
    }

    var resolvedWebhookIncludeProjectName: Bool {
        get { webhookIncludeProjectName ?? false }
        set { webhookIncludeProjectName = newValue }
    }

    var resolvedNotificationsEnabled: Bool {
        get { notificationsEnabled ?? true }
        set { notificationsEnabled = newValue }
    }

    var resolvedResetCardExpiryAlertDays: Int {
        get { resetCardExpiryAlertDays ?? 3 }
        set { resetCardExpiryAlertDays = newValue }
    }

    var resolvedRateLimitForecastEnabled: Bool {
        get { rateLimitForecastEnabled ?? true }
        set { rateLimitForecastEnabled = newValue }
    }

    var resolvedActivityBandEnabled: Bool {
        get { activityBandEnabled ?? true }
        set { activityBandEnabled = newValue }
    }

    var resolvedActivityBandStyle: ActivityBandStyle {
        get { activityBandStyle ?? .classic }
        set { activityBandStyle = newValue }
    }

    var resolvedVisualTheme: PulseVisualTheme {
        get { visualTheme ?? .classic }
        set { visualTheme = newValue }
    }

    var resolvedMiniCapsuleStyle: MiniCapsuleStyle {
        get { miniCapsuleStyle ?? .quota }
        set { miniCapsuleStyle = newValue }
    }

    var resolvedAPIMiniCapsuleStyle: MiniCapsuleStyle {
        get {
            let style = apiMiniCapsuleStyle ?? .time
            return style.isAvailableInAPIKeyMode ? style : .time
        }
        set {
            apiMiniCapsuleStyle = newValue.isAvailableInAPIKeyMode ? newValue : .time
        }
    }

    var resolvedPetCharacter: PetCharacter {
        get { petCharacter ?? .dino }
        set { petCharacter = newValue }
    }

    var resolvedFollowCodexLaunch: Bool {
        get { followCodexLaunch ?? false }
        set { followCodexLaunch = newValue }
    }

    var resolvedInformationBarEnabled: Bool {
        get { informationBarEnabled ?? false }
        set { informationBarEnabled = newValue }
    }

    /// 规范到 5 / 10 / 15 秒
    mutating func normalizeRefreshInterval() {
        let options = AppConstants.refreshIntervalOptions
        let v = refreshIntervalSeconds
        if !options.contains(v) {
            // 取最近合法值
            refreshIntervalSeconds = options.min(by: { abs($0 - v) < abs($1 - v) }) ?? 10
        }
        historyRetentionDays = AppConstants.historyRetentionOptions.min(
            by: { abs($0 - historyRetentionDays) < abs($1 - historyRetentionDays) }
        ) ?? AppConstants.historyRetentionDays
        if !AppConstants.longTaskAlertMinuteOptions.contains(resolvedLongTaskAlertMinutes) {
            resolvedLongTaskAlertMinutes = 30
        }
        if !AppConstants.tokenSpikeThresholdOptions.contains(resolvedTokenSpikeThresholdPerMinute) {
            resolvedTokenSpikeThresholdPerMinute = 1_000_000
        }
        if !AppConstants.resetCardExpiryAlertDayOptions.contains(resolvedResetCardExpiryAlertDays) {
            resolvedResetCardExpiryAlertDays = 3
        }
        alertThresholds = Array(Set(alertThresholds.map { min(100, max(1, $0)) })).sorted()
        webhookURL = webhookURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if webhookURL?.isEmpty == true { webhookURL = nil }
    }

    var normalizedRefreshInterval: TimeInterval {
        var copy = self
        copy.normalizeRefreshInterval()
        return copy.refreshIntervalSeconds
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    private let key = "pulse_settings"

    func load() -> PulseSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(PulseSettings.self, from: data) else {
            return .default
        }
        var fixed = s
        fixed.normalizeRefreshInterval()
        // 信息任务栏必须绑定一个已确认的地区；旧版/手动编辑配置可能只
        // 保存了开关，自动纠正后避免出现“已开启但界面没有天气”的空状态。
        if fixed.resolvedInformationBarEnabled && fixed.weatherLocation == nil {
            fixed.resolvedInformationBarEnabled = false
            save(fixed)
        }
        return fixed
    }

    func save(_ settings: PulseSettings) {
        var s = settings
        s.normalizeRefreshInterval()
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
