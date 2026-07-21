import Foundation
import Observation

/// Open-Meteo WMO weather groups used by the capsule artwork.
enum WeatherCondition: String, Codable, Equatable, Sendable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case showers
    case thunderstorm

    init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67: self = .rain
        case 71...77, 85, 86: self = .snow
        case 80...82: self = .showers
        case 95, 96, 99: self = .thunderstorm
        default: self = .cloudy
        }
    }

    var displayName: String {
        switch self {
        case .clear: return "晴"
        case .partlyCloudy: return "多云间晴"
        case .cloudy: return "阴"
        case .fog: return "雾"
        case .drizzle: return "毛毛雨"
        case .rain: return "下雨"
        case .snow: return "下雪"
        case .showers: return "阵雨"
        case .thunderstorm: return "雷雨"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .showers: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        }
    }
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let temperature: Double
    let condition: WeatherCondition
    let isDay: Bool
    let observedAt: Date
}

enum OpenMeteoError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case server(Int)
    case noResults
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "天气服务地址无效"
        case .invalidResponse: return "天气服务返回了无法识别的数据"
        case .server(let status): return "天气服务暂不可用（HTTP \(status)）"
        case .noResults: return "没有找到匹配的地区"
        case .transport(let message): return "天气网络请求失败：\(message)"
        }
    }
}

private struct OpenMeteoGeocodingResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timezone: String?
        let country: String?
        let admin1: String?
    }

    let results: [Result]?
}

private struct OpenMeteoForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    let current: Current?
}

/// 无需 API Key 的 Open-Meteo 客户端。地理编码和天气接口均为免费公共接口，
/// 请求只发送用户主动选择的城市和经纬度，不发送 Codex 内容或账号信息。
actor OpenMeteoClient {
    static let shared = OpenMeteoClient()

    private let session: URLSession
    private var weatherCache: [String: (snapshot: WeatherSnapshot, fetchedAt: Date)] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func searchLocations(query: String) async throws -> [WeatherLocation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else {
            throw OpenMeteoError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw OpenMeteoError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexPulse/0.1 Weather", forHTTPHeaderField: "User-Agent")
        let data = try await data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenMeteoGeocodingResponse.self, from: data)
        let results = (response.results ?? []).compactMap { result -> WeatherLocation? in
            guard let timezone = result.timezone, !timezone.isEmpty else { return nil }
            return WeatherLocation(
                name: result.name,
                admin1: result.admin1,
                country: result.country,
                latitude: result.latitude,
                longitude: result.longitude,
                timezone: timezone
            )
        }
        guard !results.isEmpty else { throw OpenMeteoError.noResults }
        return results
    }

    func fetchWeather(for location: WeatherLocation) async throws -> WeatherSnapshot {
        let cacheKey = location.id
        if let cached = weatherCache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < 5 * 60 {
            return cached.snapshot
        }

        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            throw OpenMeteoError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: location.timezone),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        guard let url = components.url else { throw OpenMeteoError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexPulse/0.1 Weather", forHTTPHeaderField: "User-Agent")
        PulseLog.write("weather request start: \(location.name) · \(url.host ?? "Open-Meteo")")
        let data = try await data(for: request)
        let decoder = JSONDecoder()
        let response: OpenMeteoForecastResponse
        do {
            response = try decoder.decode(OpenMeteoForecastResponse.self, from: data)
        } catch {
            PulseLog.write(
                "weather decode failed: \(location.name) · \(error.localizedDescription)"
            )
            throw OpenMeteoError.invalidResponse
        }
        guard let current = response.current else { throw OpenMeteoError.invalidResponse }

        let snapshot = WeatherSnapshot(
            temperature: current.temperature2m,
            condition: WeatherCondition(wmoCode: current.weatherCode),
            isDay: current.isDay == 1,
            observedAt: Date()
        )
        weatherCache[cacheKey] = (snapshot, Date())
        PulseLog.write(
            "weather request ok: \(location.name) · \(snapshot.condition.displayName) · "
                + "\(String(format: "%.1f", snapshot.temperature))°C"
        )
        return snapshot
    }

    private func data(for request: URLRequest) async throws -> Data {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenMeteoError.invalidResponse
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw OpenMeteoError.server(httpResponse.statusCode)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let description = Self.transportDescription(error)
                PulseLog.write(
                    "weather request attempt \(attempt)/3 failed: "
                        + "\(request.url?.host ?? "Open-Meteo") · \(description)"
                )
                guard attempt < 3, Self.shouldRetry(error) else { break }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            }
        }
        if let openMeteoError = lastError as? OpenMeteoError {
            throw openMeteoError
        }
        throw OpenMeteoError.transport(Self.transportDescription(lastError))
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if case OpenMeteoError.server(let status) = error {
            return status == 408 || status == 429 || (500...599).contains(status)
        }
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .resourceUnavailable
        ].contains(urlError.code)
    }

    private static func transportDescription(_ error: Error?) -> String {
        guard let error else { return "未知网络错误" }
        if let urlError = error as? URLError {
            return "\(urlError.localizedDescription)（URLError \(urlError.code.rawValue)）"
        }
        return error.localizedDescription
    }
}

/// 供悬浮胶囊使用的轻量请求状态。生命周期由视图管理，任务取消时不会留下后台轮询。
@MainActor
@Observable
final class WeatherViewModel {
    private(set) var snapshot: WeatherSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var activeLocationID: String?
    private var monitorToken = UUID()

    private func cacheKey(for location: WeatherLocation) -> String {
        "pulse.weather.lastGood.\(location.id)"
    }

    private func loadCachedSnapshot(for location: WeatherLocation) -> WeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: location)) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    private func saveCachedSnapshot(_ snapshot: WeatherSnapshot, for location: WeatherLocation) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: location))
    }

    func monitor(location: WeatherLocation) async {
        let token = UUID()
        monitorToken = token
        if activeLocationID != location.id {
            // 先显示上一次成功结果，再由网络请求替换，重启或断网时也不会出现空白。
            snapshot = loadCachedSnapshot(for: location)
        }
        activeLocationID = location.id
        errorMessage = nil
        isLoading = true

        while !Task.isCancelled, token == monitorToken {
            var retryDelay: UInt64 = 15 * 60 * 1_000_000_000
            do {
                let next = try await OpenMeteoClient.shared.fetchWeather(for: location)
                guard !Task.isCancelled, token == monitorToken else { return }
                snapshot = next
                saveCachedSnapshot(next, for: location)
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, token == monitorToken else { return }
                errorMessage = error.localizedDescription
                retryDelay = 30 * 1_000_000_000
                PulseLog.write(
                    "weather monitor failed: \(location.name) · \(error.localizedDescription) · retry in 30s"
                )
            }
            isLoading = false

            do {
                try await Task.sleep(nanoseconds: retryDelay)
            } catch {
                return
            }
        }
    }

    func clear() {
        monitorToken = UUID()
        activeLocationID = nil
        snapshot = nil
        errorMessage = nil
        isLoading = false
    }
}
