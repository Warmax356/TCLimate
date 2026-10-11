import XCTest
@testable import TCLCore

final class EnergyReportTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T19:30:00Z")!
    private let zone = TimeZone(identifier: "Asia/Karachi")!

    func testDailyReadingsPreserveZeroAndMissingDays() {
        let report = EnergyReport.parse(["code": 0, "data": ["ecoDetails": [
            ["dataList": [["time": "2026-09-30", "totalElectricity": "4.00"]]],
            ["dataList": [
                ["time": "2026-10-12", "totalElectricity": "0.00"],
                ["time": "2026-10-11", "totalElectricity": "2.35"],
                ["time": "2026-10-01", "totalElectricity": 5],
                ["time": "2026-10-10", "totalElectricity": -1],
                ["time": "2026-10-09", "totalElectricity": Double.infinity],
                ["time": "2026-10-13", "totalElectricity": "0.00"]
            ]]
        ]]], now: now, timeZone: zone)
        XCTAssertEqual(report.today, "2026-10-12")
        XCTAssertEqual(report.todayKWh, 0)
        XCTAssertEqual(report.yesterdayKWh, 2.35)
        XCTAssertEqual(report.days.count, 2)
        XCTAssertNil(report.weekKWh)
        XCTAssertNil(report.message)
    }

    func testUnavailableIsDifferentFromZeroConsumption() {
        let rejected = EnergyReport.parse(["code": 10003], now: now, timeZone: zone)
        XCTAssertTrue(rejected.message?.contains("10003") == true)
        XCTAssertNil(rejected.todayKWh)
        let empty = EnergyReport.parse(["code": 0, "data": ["ecoDetails": []]], now: now, timeZone: zone)
        XCTAssertNotNil(empty.message)
        XCTAssertNil(empty.todayKWh)
        XCTAssertNotNil(EnergyReport.parse(["code": Double.nan], now: now, timeZone: zone).message)
    }
}
