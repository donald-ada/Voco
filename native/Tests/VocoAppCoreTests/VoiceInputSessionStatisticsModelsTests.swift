import XCTest
@testable import VocoAppCore

final class VoiceInputSessionStatisticsModelsTests: XCTestCase {
    func testStatisticsSnapshotUsesEnglishLabels() {
        let snapshot = VoiceInputSessionStatisticsSnapshot.make(
            sessions: [],
            period: .last7Days,
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(VoiceInputSessionStatisticsPeriod.last7Days.title(strings: VocoStrings(language: .en)), "Last 7 Days")
        XCTAssertEqual(VoiceInputSessionStatisticsMetric.sessions.title(strings: VocoStrings(language: .en)), "Sessions")
        XCTAssertEqual(snapshot.lengthBuckets.map(\.title), ["Short", "Medium", "Long"])
        XCTAssertEqual(snapshot.lengthBuckets.map(\.detail), ["0-18 chars", "19-24 chars", "25+ chars"])
    }

    func testDashboardTreatsPreviousLocalizedAllAppsSelectionAsAllAfterLanguageSwitch() {
        let sessions = [
            makeSession(text: "old all label app", words: 8, duration: 4, day: 8, hour: 9, app: "全部", provider: "火山引擎"),
            makeSession(text: "notes", words: 12, duration: 6, day: 8, hour: 10, app: "Notes", provider: "火山引擎")
        ]

        let dashboard = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppName: "全部",
            strings: VocoStrings(language: .en),
            referenceDate: Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!,
            calendar: .gregorianUTC
        )

        XCTAssertEqual(dashboard.selectedAppName, "All")
        XCTAssertEqual(dashboard.scopedSnapshot.totalSessions, 2)
        XCTAssertEqual(dashboard.appOptions.first, "All")
    }

    func testDashboardStableAppIDCanSelectAppNamedLikeLegacyAllTitle() {
        let sessions = [
            makeSession(text: "old all label app", words: 8, duration: 4, day: 8, hour: 9, app: "全部", provider: "火山引擎"),
            makeSession(text: "notes", words: 12, duration: 6, day: 8, hour: 10, app: "Notes", provider: "火山引擎")
        ]

        let dashboard = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppName: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("全部"),
            strings: VocoStrings(language: .en),
            referenceDate: Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!,
            calendar: .gregorianUTC,
            selectedAppID: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("全部")
        )

        XCTAssertEqual(dashboard.selectedAppName, "全部")
        XCTAssertEqual(dashboard.selectedAppID, VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("全部"))
        XCTAssertEqual(dashboard.scopedSnapshot.totalSessions, 1)
        XCTAssertEqual(dashboard.scopedSnapshot.totalWords, 8)
    }

    func testDashboardUnknownAppSelectionIDStaysStableAcrossLanguageSwitch() {
        let referenceDate = Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let sessions = [
            makeSession(text: "unknown target", words: 8, duration: 4, day: 8, hour: 9, app: "", provider: "火山引擎"),
            makeSession(text: "notes", words: 12, duration: 6, day: 8, hour: 10, app: "Notes", provider: "火山引擎")
        ]
        let zhDashboard = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppID: VoiceInputSessionStatisticsDashboardSnapshot.unknownAppSelectionID,
            referenceDate: referenceDate,
            calendar: .gregorianUTC
        )

        XCTAssertEqual(zhDashboard.selectedAppName, "未知 App")
        XCTAssertEqual(zhDashboard.selectedAppID, VoiceInputSessionStatisticsDashboardSnapshot.unknownAppSelectionID)

        let enDashboard = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppName: zhDashboard.selectedAppID,
            strings: VocoStrings(language: .en),
            referenceDate: referenceDate,
            calendar: .gregorianUTC,
            selectedAppID: zhDashboard.selectedAppID
        )

        XCTAssertEqual(enDashboard.selectedAppName, "Unknown App")
        XCTAssertEqual(enDashboard.selectedAppID, VoiceInputSessionStatisticsDashboardSnapshot.unknownAppSelectionID)
        XCTAssertEqual(enDashboard.scopedSnapshot.totalSessions, 1)
        XCTAssertEqual(enDashboard.scopedSnapshot.totalWords, 8)
    }

    func testDashboardAppSelectionUsesStableRawKeysForUnknownAndLocalizedNames() {
        let referenceDate = Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let sessions = [
            makeSession(text: "empty target", words: 3, duration: 2, day: 8, hour: 8, app: "", provider: "火山引擎"),
            makeSession(text: "real zh unknown", words: 5, duration: 3, day: 8, hour: 9, app: "未知 App", provider: "火山引擎"),
            makeSession(text: "real en unknown", words: 7, duration: 4, day: 8, hour: 10, app: "Unknown App", provider: "火山引擎"),
            makeSession(text: "real zh all", words: 11, duration: 5, day: 8, hour: 11, app: "全部", provider: "火山引擎"),
            makeSession(text: "real en all", words: 13, duration: 6, day: 8, hour: 12, app: "All", provider: "火山引擎")
        ]

        let base = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppID: VoiceInputSessionStatisticsDashboardSnapshot.allAppsSelectionID,
            strings: VocoStrings(language: .en),
            referenceDate: referenceDate,
            calendar: .gregorianUTC,
            appOptionLimit: 10
        )

        XCTAssertEqual(base.baseSnapshot.activeAppCount, 5)
        XCTAssertTrue(base.appFilterOptions.contains(.init(id: VoiceInputSessionStatisticsDashboardSnapshot.unknownAppSelectionID, title: "Unknown App", appName: nil)))
        XCTAssertTrue(base.appFilterOptions.contains(.init(id: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("未知 App"), title: "未知 App", appName: "未知 App")))
        XCTAssertTrue(base.appFilterOptions.contains(.init(id: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("Unknown App"), title: "Unknown App", appName: "Unknown App")))
        XCTAssertTrue(base.appFilterOptions.contains(.init(id: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("全部"), title: "全部", appName: "全部")))
        XCTAssertTrue(base.appFilterOptions.contains(.init(id: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("All"), title: "All", appName: "All")))

        let unknown = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppID: VoiceInputSessionStatisticsDashboardSnapshot.unknownAppSelectionID,
            strings: VocoStrings(language: .en),
            referenceDate: referenceDate,
            calendar: .gregorianUTC,
            appOptionLimit: 10
        )
        XCTAssertEqual(unknown.selectedAppID, VoiceInputSessionStatisticsDashboardSnapshot.unknownAppSelectionID)
        XCTAssertEqual(unknown.scopedSnapshot.totalSessions, 1)
        XCTAssertEqual(unknown.scopedSnapshot.totalWords, 3)

        let realZHUnknown = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            selectedAppID: VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("未知 App"),
            strings: VocoStrings(language: .en),
            referenceDate: referenceDate,
            calendar: .gregorianUTC,
            appOptionLimit: 10
        )
        XCTAssertEqual(realZHUnknown.selectedAppID, VoiceInputSessionStatisticsDashboardSnapshot.appSelectionID("未知 App"))
        XCTAssertEqual(realZHUnknown.scopedSnapshot.totalSessions, 1)
        XCTAssertEqual(realZHUnknown.scopedSnapshot.totalWords, 5)
    }

    func testEnglishStatisticsSnapshotLocalizesVolcengineProviderName() {
        let sessions = [
            makeSession(text: "today", words: 8, duration: 4, day: 8, hour: 9, app: "Notes", provider: "火山引擎"),
            makeSession(text: "again", words: 4, duration: 2, day: 8, hour: 10, app: "Notes", provider: "火山引擎"),
            makeSession(text: "backup", words: 12, duration: 6, day: 8, hour: 11, app: "Notes", provider: "备用模型")
        ]

        let snapshot = VoiceInputSessionStatisticsSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            strings: VocoStrings(language: .en),
            referenceDate: Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!,
            calendar: .gregorianUTC
        )

        XCTAssertEqual(snapshot.providerContributions.map(\.name), ["Volcengine", "备用模型"])
    }

    func testProviderContributionsUseRawProviderKeyWhenDisplayNamesMatch() {
        let sessions = [
            makeSession(text: "raw zh provider", words: 8, duration: 4, day: 8, hour: 9, app: "Notes", provider: "火山引擎"),
            makeSession(text: "raw en provider", words: 12, duration: 6, day: 8, hour: 10, app: "Notes", provider: "Volcengine")
        ]

        let snapshot = VoiceInputSessionStatisticsSnapshot.make(
            sessions: sessions,
            period: .last7Days,
            strings: VocoStrings(language: .en),
            referenceDate: Calendar.gregorianUTC.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!,
            calendar: .gregorianUTC
        )

        XCTAssertEqual(snapshot.providerContributions.map(\.id), ["Volcengine", "火山引擎"])
        XCTAssertEqual(snapshot.providerContributions.map(\.name), ["Volcengine", "Volcengine"])
        XCTAssertEqual(snapshot.providerContributions.map(\.sessions), [1, 1])
    }

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
