import Foundation
import SwiftUI

/// High/low and an SF Symbol for one agenda day.
struct DayWeather: Equatable {
    let highTemp: Int
    let lowTemp: Int
    let symbolName: String
}

struct WorkCity: Codable, Equatable, Identifiable {
    var name: String
    var region: String?
    var country: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }

    var displayName: String {
        if let region, !region.isEmpty, region != name {
            return "\(name), \(region)"
        }
        return name
    }
}

/// The store the associate works at, plus a cached daily forecast for that city.
@MainActor
final class WorkWeatherStore: ObservableObject {
    static let shared = WorkWeatherStore()

    @Published private(set) var city: WorkCity?
    @Published private(set) var forecast: [Date: DayWeather] = [:]
    @Published private(set) var isLoading = false

    private let cityKey = "workCity"
    private let forecastKey = "workWeatherForecast"
    private let fetchedKey = "workWeatherFetchedAt"
    private let cacheTTL: TimeInterval = 3 * 3600

    private init() {
        if let data = UserDefaults.standard.data(forKey: cityKey),
           let saved = try? JSONDecoder().decode(WorkCity.self, from: data) {
            city = saved
        }
        loadCachedForecast()
    }

    func setCity(_ city: WorkCity?) {
        self.city = city
        forecast = [:]
        if let city, let data = try? JSONEncoder().encode(city) {
            UserDefaults.standard.set(data, forKey: cityKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cityKey)
            UserDefaults.standard.removeObject(forKey: forecastKey)
            UserDefaults.standard.removeObject(forKey: fetchedKey)
        }
        Task { await refresh(force: true) }
    }

    func weather(on day: Date) -> DayWeather? {
        forecast[Calendar.current.startOfDay(for: day)]
    }

    func refreshIfNeeded() {
        Task { await refresh(force: false) }
    }

    func refresh(force: Bool) async {
        guard let city else { return }
        if !force, !forecast.isEmpty,
           let fetched = UserDefaults.standard.object(forKey: fetchedKey) as? Date,
           Date().timeIntervalSince(fetched) < cacheTTL {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let usesMetric = Locale.current.measurementSystem == .metric
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: usesMetric ? "celsius" : "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16")
        ]
        guard let url = components?.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
            var next: [Date: DayWeather] = [:]
            let calendar = Calendar.current
            for (index, dayString) in decoded.daily.time.enumerated() {
                guard let date = Self.parseDay(dayString) else { continue }
                let high = index < decoded.daily.temperature_2m_max.count
                    ? Int(decoded.daily.temperature_2m_max[index].rounded()) : 0
                let low = index < decoded.daily.temperature_2m_min.count
                    ? Int(decoded.daily.temperature_2m_min[index].rounded()) : 0
                let code = index < decoded.daily.weather_code.count
                    ? decoded.daily.weather_code[index] : 1
                next[calendar.startOfDay(for: date)] = DayWeather(
                    highTemp: high,
                    lowTemp: low,
                    symbolName: Self.symbol(for: code)
                )
            }
            forecast = next
            if let data = try? JSONEncoder().encode(ForecastCache(days: next.map {
                CachedDay(day: $0.key, high: $0.value.highTemp, low: $0.value.lowTemp, symbol: $0.value.symbolName)
            })) {
                UserDefaults.standard.set(data, forKey: forecastKey)
                UserDefaults.standard.set(Date(), forKey: fetchedKey)
            }
        } catch {
            // Keep whatever was cached.
        }
    }

    func searchCities(_ query: String) async -> [WorkCity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoGeocode.self, from: data)
            return (decoded.results ?? []).map {
                WorkCity(
                    name: $0.name,
                    region: $0.admin1,
                    country: $0.country ?? "",
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
        } catch {
            return []
        }
    }

    private func loadCachedForecast() {
        guard let data = UserDefaults.standard.data(forKey: forecastKey),
              let cached = try? JSONDecoder().decode(ForecastCache.self, from: data) else { return }
        var next: [Date: DayWeather] = [:]
        for day in cached.days {
            next[Calendar.current.startOfDay(for: day.day)] = DayWeather(
                highTemp: day.high,
                lowTemp: day.low,
                symbolName: day.symbol
            )
        }
        forecast = next
    }

    /// Open-Meteo daily dates are calendar days (`yyyy-MM-dd`), not timestamps.
    private static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func symbol(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

private struct OpenMeteoGeocode: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country: String?
    }
    let results: [Result]?
}

private struct OpenMeteoForecast: Decodable {
    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let weather_code: [Int]
    }
    let daily: Daily
}

private struct ForecastCache: Codable {
    var days: [CachedDay]
}

private struct CachedDay: Codable {
    var day: Date
    var high: Int
    var low: Int
    var symbol: String
}
