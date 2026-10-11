import Foundation

public struct EnergyDay: Identifiable, Equatable {
    public let date: String
    public let kWh: Double
    public var id: String { date }
}

public struct EnergyReport {
    public let days: [EnergyDay]
    public let fetchedAt: Date
    public let message: String?
    public let today: String
    public let yesterday: String
    public let start: String
    public var todayKWh: Double? { days.first { $0.date == today }?.kWh }
    public var yesterdayKWh: Double? { days.first { $0.date == yesterday }?.kWh }
    public var weekKWh: Double? { days.count == 7 ? days.reduce(0) { $0 + $1.kWh } : nil }

    static func window(now: Date, timeZone: TimeZone) -> (start: String, yesterday: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: calendar.date(byAdding: .day, value: -6, to: now)!),
                formatter.string(from: calendar.date(byAdding: .day, value: -1, to: now)!),
                formatter.string(from: now))
    }

    static func parse(_ response: [String: Any], now: Date = Date(), timeZone: TimeZone = .current) -> EnergyReport {
        let window = window(now: now, timeZone: timeZone)
        var days: [EnergyDay] = []
        var message: String?
        if number(response["code"]) == 0, let data = response["data"] as? [String: Any] {
            let months = data["ecoDetails"] as? [[String: Any]] ?? []
            let entries = months.flatMap { $0["dataList"] as? [[String: Any]] ?? [] }
            var unique: [String: Double] = [:]
            for entry in entries {
                guard let date = entry["time"] as? String,
                      date.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
                      date >= window.start, date <= window.end,
                      let value = number(entry["totalElectricity"] ?? entry["electricity"]), value.isFinite, value >= 0 else { continue }
                unique[date] = value
            }
            days = unique.map { EnergyDay(date: $0.key, kWh: $0.value) }.sorted { $0.date < $1.date }
            if days.isEmpty { message = "TCL has no electricity readings for this AC in the last 7 days." }
        } else {
            let code = number(response["code"]).flatMap { $0.isFinite ? String(format: "%.0f", $0) : nil } ?? "unknown"
            message = "Electricity statistics are unavailable from TCL for this AC (code \(code))."
        }
        return EnergyReport(days: days, fetchedAt: now, message: message,
                            today: window.end, yesterday: window.yesterday, start: window.start)
    }
}
