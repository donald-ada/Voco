import XCTest
@testable import VocoAppCore

final class VoiceInputSessionStatisticsModelsTests: XCTestCase {
    func testStatisticsSnapshotAggregatesRecentSessionsForDashboard() {
        let calendar = Calendar.gregorianUTC
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let sessions = [
            makeSession(text: "今天短句", words: 10, duration: 5, day: 8, hour: 9, app: "Codex", provider: "火山引擎"),
            makeSession(text: "今天长段", words: 26, duration: 13, day: 8, hour: 15, app: "Notes", provider: "火山引擎"),
            makeSession(text: "昨天中段", words: 20, duration: 10, day: 7, hour: 15, app: "Notes", provider: "备用模型"),
            makeSession(text: "八天前不在近七天", words: 30, duration: 15, month: 4, day: 30, hour: 11, app: "Codex", provider: "火山引擎"),
            makeSession(text: "本月稍早", words: 16, duration: 8, month: 4, day: 18, hour: 20, app: "Mail", provider: "火山引擎")
        ]

        let snapshot = VoiceInputSessionStatisticsSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.totalSessions, 3)
        XCTAssertEqual(snapshot.totalWords, 56)
        XCTAssertEqual(snapshot.totalDurationSeconds, 28, accuracy: 0.001)
        XCTAssertEqual(snapshot.averageDurationSeconds, 28.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.wordsPerMinute, 120)
        XCTAssertEqual(snapshot.activeAppCount, 2)
        XCTAssertEqual(snapshot.dailyPoints.count, 7)
        XCTAssertEqual(snapshot.dailyPoints.last?.label, "5/8")
        XCTAssertEqual(snapshot.dailyPoints.last?.sessions, 2)
        XCTAssertEqual(snapshot.appContributions.map(\.name), ["Notes", "Codex"])
        XCTAssertEqual(snapshot.appContributions.map(\.words), [46, 10])
        XCTAssertEqual(snapshot.providerContributions.map(\.name), ["火山引擎", "备用模型"])
        XCTAssertEqual(snapshot.providerContributions.map(\.sessions), [2, 1])
        XCTAssertEqual(snapshot.hourRanges.first { $0.label == "14-18" }?.sessions, 2)
        XCTAssertEqual(snapshot.hourRanges.first { $0.label == "06-10" }?.sessions, 1)
        XCTAssertEqual(snapshot.lengthBuckets.map(\.sessions), [1, 1, 1])
        XCTAssertEqual(snapshot.heatmapRows.first { $0.weekdayTitle == "周五" }?.cells.first { $0.hourRangeLabel == "06-10" }?.sessions, 1)
    }

    func testAllPeriodKeepsOlderSessionsAndComputesRhythm() {
        let calendar = Calendar.gregorianUTC
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let sessions = [
            makeSession(text: "今天短句", words: 10, duration: 5, day: 8, hour: 9, app: "Codex", provider: "火山引擎"),
            makeSession(text: "今天长段", words: 26, duration: 13, day: 8, hour: 15, app: "Notes", provider: "火山引擎"),
            makeSession(text: "昨天中段", words: 20, duration: 10, day: 7, hour: 15, app: "Notes", provider: "备用模型"),
            makeSession(text: "八天前", words: 30, duration: 15, month: 4, day: 30, hour: 11, app: "Codex", provider: "火山引擎"),
            makeSession(text: "本月稍早", words: 16, duration: 8, month: 4, day: 18, hour: 20, app: "Mail", provider: "火山引擎")
        ]

        let snapshot = VoiceInputSessionStatisticsSnapshot.make(
            sessions: sessions,
            period: .all,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.totalSessions, 5)
        XCTAssertEqual(snapshot.dailyPoints.count, 14)
        XCTAssertEqual(snapshot.rhythm.activeDayCount, 4)
        XCTAssertEqual(snapshot.rhythm.busiestDayTitle, "5/8")
        XCTAssertEqual(snapshot.rhythm.peakHourSharePercent, 40)
        XCTAssertEqual(snapshot.rhythm.appConcentrationPercent, 45)
    }

    func testDashboardSnapshotScopesSessionsToSelectedApp() {
        let calendar = Calendar.gregorianUTC
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let sessions = [
            makeSession(text: "今天短句", words: 10, duration: 5, day: 8, hour: 9, app: "Codex", provider: "火山引擎"),
            makeSession(text: "今天长段", words: 26, duration: 13, day: 8, hour: 15, app: "Notes", provider: "火山引擎"),
            makeSession(text: "昨天中段", words: 20, duration: 10, day: 7, hour: 15, app: "Notes", provider: "备用模型")
        ]

        let dashboard = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppName: "Notes",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(dashboard.appOptions, ["全部", "Notes", "Codex"])
        XCTAssertEqual(dashboard.selectedAppName, "Notes")
        XCTAssertEqual(dashboard.baseSnapshot.totalSessions, 3)
        XCTAssertEqual(dashboard.scopedSnapshot.totalSessions, 2)
        XCTAssertEqual(dashboard.scopedSnapshot.totalWords, 46)
    }

    func testDashboardSnapshotFallsBackToAllAppsWhenSelectionIsUnavailable() {
        let calendar = Calendar.gregorianUTC
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let sessions = [
            makeSession(text: "今天短句", words: 10, duration: 5, day: 8, hour: 9, app: "Codex", provider: "火山引擎")
        ]

        let dashboard = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppName: "Missing",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(dashboard.selectedAppName, "全部")
        XCTAssertEqual(dashboard.scopedSnapshot.totalSessions, 1)
    }

    private func makeSession(
        text: String,
        words: Int,
        duration: Double,
        month: Int = 5,
        day: Int,
        hour: Int,
        app: String,
        provider: String
    ) -> VoiceInputSessionSnapshot {
        let date = Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        return VoiceInputSessionSnapshot(
            transcriptText: text,
            wordCount: words,
            durationSeconds: duration,
            createdAt: date,
            targetAppName: app,
            providerName: provider
        )
    }
}

private extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
