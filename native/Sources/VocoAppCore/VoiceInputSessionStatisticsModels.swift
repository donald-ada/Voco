import Foundation

public enum VoiceInputSessionStatisticsPeriod: String, CaseIterable, Identifiable, Sendable {
    case last7Days
    case last30Days
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last7Days:
            "近 7 天"
        case .last30Days:
            "近 30 天"
        case .all:
            "全部"
        }
    }

    var dayLimit: Int? {
        switch self {
        case .last7Days:
            7
        case .last30Days:
            30
        case .all:
            nil
        }
    }

    var chartDayCount: Int {
        switch self {
        case .last7Days:
            7
        case .last30Days, .all:
            14
        }
    }
}

public enum VoiceInputSessionStatisticsMetric: String, CaseIterable, Identifiable, Sendable {
    case sessions
    case words
    case duration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sessions:
            "会话"
        case .words:
            "字数"
        case .duration:
            "时长"
        }
    }
}

public struct VoiceInputSessionStatisticsDailyPoint: Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let label: String
    public let sessions: Int
    public let words: Int
    public let durationSeconds: Double
}

public struct VoiceInputSessionStatisticsContribution: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sessions: Int
    public let words: Int
    public let durationSeconds: Double
}

public struct VoiceInputSessionStatisticsHourRange: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let startHour: Int
    public let endHour: Int
    public let sessions: Int
    public let words: Int
    public let durationSeconds: Double
}

public struct VoiceInputSessionStatisticsHeatmapCell: Equatable, Identifiable, Sendable {
    public let id: String
    public let hourRangeLabel: String
    public let sessions: Int
    public let words: Int
    public let durationSeconds: Double
}

public struct VoiceInputSessionStatisticsHeatmapRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let weekdayTitle: String
    public let cells: [VoiceInputSessionStatisticsHeatmapCell]
}

public struct VoiceInputSessionStatisticsLengthBucket: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let sessions: Int
}

public struct VoiceInputSessionStatisticsRhythm: Equatable, Sendable {
    public let activeDayCount: Int
    public let busiestDayTitle: String
    public let peakHourSharePercent: Int
    public let appConcentrationPercent: Int
}

public struct VoiceInputSessionStatisticsSnapshot: Equatable, Sendable {
    public let period: VoiceInputSessionStatisticsPeriod
    public let sessions: [VoiceInputSessionSnapshot]
    public let totalSessions: Int
    public let totalWords: Int
    public let totalDurationSeconds: Double
    public let averageDurationSeconds: Double
    public let wordsPerMinute: Int
    public let activeAppCount: Int
    public let dailyPoints: [VoiceInputSessionStatisticsDailyPoint]
    public let appContributions: [VoiceInputSessionStatisticsContribution]
    public let providerContributions: [VoiceInputSessionStatisticsContribution]
    public let hourRanges: [VoiceInputSessionStatisticsHourRange]
    public let heatmapRows: [VoiceInputSessionStatisticsHeatmapRow]
    public let lengthBuckets: [VoiceInputSessionStatisticsLengthBucket]
    public let rhythm: VoiceInputSessionStatisticsRhythm

    public static func make(
        sessions: [VoiceInputSessionSnapshot],
        period: VoiceInputSessionStatisticsPeriod,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> VoiceInputSessionStatisticsSnapshot {
        let filteredSessions = filteredSessions(
            sessions,
            period: period,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let totalSessions = filteredSessions.count
        let totalWords = filteredSessions.reduce(0) { $0 + $1.wordCount }
        let totalDurationSeconds = filteredSessions.reduce(0) { $0 + $1.durationSeconds }
        let averageDurationSeconds = totalSessions > 0 ? totalDurationSeconds / Double(totalSessions) : 0
        let wordsPerMinute = totalDurationSeconds > 0
            ? Int((Double(totalWords) / (totalDurationSeconds / 60)).rounded())
            : 0
        let activeAppCount = Set(filteredSessions.map { normalizedAppName($0.targetAppName) }).count
        let dailyPoints = makeDailyPoints(
            sessions: filteredSessions,
            dayCount: period.chartDayCount,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let hourRanges = makeHourRanges(sessions: filteredSessions, calendar: calendar)
        let appContributions = makeContributions(
            sessions: filteredSessions,
            name: { normalizedAppName($0.targetAppName) },
            sort: { $0.words != $1.words ? $0.words > $1.words : $0.name < $1.name }
        )
        let providerContributions = makeContributions(
            sessions: filteredSessions,
            name: \.providerName,
            sort: { $0.sessions != $1.sessions ? $0.sessions > $1.sessions : $0.name < $1.name }
        )

        return VoiceInputSessionStatisticsSnapshot(
            period: period,
            sessions: filteredSessions,
            totalSessions: totalSessions,
            totalWords: totalWords,
            totalDurationSeconds: totalDurationSeconds,
            averageDurationSeconds: averageDurationSeconds,
            wordsPerMinute: wordsPerMinute,
            activeAppCount: activeAppCount,
            dailyPoints: dailyPoints,
            appContributions: appContributions,
            providerContributions: providerContributions,
            hourRanges: hourRanges,
            heatmapRows: makeHeatmapRows(sessions: filteredSessions, calendar: calendar),
            lengthBuckets: makeLengthBuckets(sessions: filteredSessions),
            rhythm: makeRhythm(
                sessions: filteredSessions,
                dailyPoints: dailyPoints,
                hourRanges: hourRanges,
                appContributions: appContributions,
                totalSessions: totalSessions,
                totalWords: totalWords,
                calendar: calendar
            )
        )
    }

    private static func filteredSessions(
        _ sessions: [VoiceInputSessionSnapshot],
        period: VoiceInputSessionStatisticsPeriod,
        referenceDate: Date,
        calendar: Calendar
    ) -> [VoiceInputSessionSnapshot] {
        let referenceDayStart = calendar.startOfDay(for: referenceDate)
        let exclusiveUpperBound = calendar.date(
            byAdding: .day,
            value: 1,
            to: referenceDayStart
        ) ?? referenceDate
        let lowerBound = period.dayLimit.flatMap { dayLimit in
            calendar.date(
                byAdding: .day,
                value: -(dayLimit - 1),
                to: referenceDayStart
            )
        }

        return sessions
            .filter { session in
                guard session.createdAt < exclusiveUpperBound else {
                    return false
                }
                guard let lowerBound else {
                    return true
                }
                return session.createdAt >= lowerBound
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private static func makeDailyPoints(
        sessions: [VoiceInputSessionSnapshot],
        dayCount: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> [VoiceInputSessionStatisticsDailyPoint] {
        let startDate = calendar.date(
            byAdding: .day,
            value: -(max(1, dayCount) - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) ?? calendar.startOfDay(for: referenceDate)

        return (0..<max(1, dayCount)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            let daySessions = sessions.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
            return VoiceInputSessionStatisticsDailyPoint(
                id: dayKey(date, calendar: calendar),
                date: date,
                label: dayLabel(date, calendar: calendar),
                sessions: daySessions.count,
                words: daySessions.reduce(0) { $0 + $1.wordCount },
                durationSeconds: daySessions.reduce(0) { $0 + $1.durationSeconds }
            )
        }
    }

    private static func makeContributions(
        sessions: [VoiceInputSessionSnapshot],
        name: (VoiceInputSessionSnapshot) -> String,
        sort: (VoiceInputSessionStatisticsContribution, VoiceInputSessionStatisticsContribution) -> Bool
    ) -> [VoiceInputSessionStatisticsContribution] {
        Dictionary(grouping: sessions, by: name)
            .map { name, sessions in
                VoiceInputSessionStatisticsContribution(
                    id: name,
                    name: name,
                    sessions: sessions.count,
                    words: sessions.reduce(0) { $0 + $1.wordCount },
                    durationSeconds: sessions.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            .sorted(by: sort)
    }

    private static func makeHourRanges(
        sessions: [VoiceInputSessionSnapshot],
        calendar: Calendar
    ) -> [VoiceInputSessionStatisticsHourRange] {
        hourRangeDefinitions.map { range in
            let rangeSessions = sessions.filter { session in
                let hour = calendar.component(.hour, from: session.createdAt)
                return hour >= range.start && hour < range.end
            }
            return VoiceInputSessionStatisticsHourRange(
                id: range.label,
                label: range.label,
                startHour: range.start,
                endHour: range.end,
                sessions: rangeSessions.count,
                words: rangeSessions.reduce(0) { $0 + $1.wordCount },
                durationSeconds: rangeSessions.reduce(0) { $0 + $1.durationSeconds }
            )
        }
    }

    private static func makeHeatmapRows(
        sessions: [VoiceInputSessionSnapshot],
        calendar: Calendar
    ) -> [VoiceInputSessionStatisticsHeatmapRow] {
        weekdayDefinitions.map { weekday in
            let cells = hourRangeDefinitions.map { range in
                let cellSessions = sessions.filter { session in
                    let hour = calendar.component(.hour, from: session.createdAt)
                    return calendar.component(.weekday, from: session.createdAt) == weekday.calendarWeekday
                        && hour >= range.start
                        && hour < range.end
                }
                return VoiceInputSessionStatisticsHeatmapCell(
                    id: "\(weekday.title)-\(range.label)",
                    hourRangeLabel: range.label,
                    sessions: cellSessions.count,
                    words: cellSessions.reduce(0) { $0 + $1.wordCount },
                    durationSeconds: cellSessions.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            return VoiceInputSessionStatisticsHeatmapRow(
                id: weekday.title,
                weekdayTitle: weekday.title,
                cells: cells
            )
        }
    }

    private static func makeLengthBuckets(sessions: [VoiceInputSessionSnapshot]) -> [VoiceInputSessionStatisticsLengthBucket] {
        [
            VoiceInputSessionStatisticsLengthBucket(
                id: "short",
                title: "短句",
                detail: "0-18 字",
                sessions: sessions.filter { $0.wordCount <= 18 }.count
            ),
            VoiceInputSessionStatisticsLengthBucket(
                id: "medium",
                title: "中段",
                detail: "19-24 字",
                sessions: sessions.filter { $0.wordCount > 18 && $0.wordCount <= 24 }.count
            ),
            VoiceInputSessionStatisticsLengthBucket(
                id: "long",
                title: "长段",
                detail: "25 字以上",
                sessions: sessions.filter { $0.wordCount > 24 }.count
            )
        ]
    }

    private static func makeRhythm(
        sessions: [VoiceInputSessionSnapshot],
        dailyPoints: [VoiceInputSessionStatisticsDailyPoint],
        hourRanges: [VoiceInputSessionStatisticsHourRange],
        appContributions: [VoiceInputSessionStatisticsContribution],
        totalSessions: Int,
        totalWords: Int,
        calendar: Calendar
    ) -> VoiceInputSessionStatisticsRhythm {
        let dayGroups = Dictionary(grouping: sessions) { session in
            dayKey(session.createdAt, calendar: calendar)
        }
        let busiestDay = dayGroups
            .map { key, sessions in
                (key: key, title: dayLabel(sessions[0].createdAt, calendar: calendar), sessions: sessions.count)
            }
            .sorted { lhs, rhs in
                if lhs.sessions != rhs.sessions {
                    return lhs.sessions > rhs.sessions
                }
                return lhs.key > rhs.key
            }
            .first
        let peakHourSessions = hourRanges.map(\.sessions).max() ?? 0
        let topAppWords = appContributions.first?.words ?? 0

        return VoiceInputSessionStatisticsRhythm(
            activeDayCount: dayGroups.count,
            busiestDayTitle: busiestDay?.title ?? dailyPoints.last?.label ?? "--",
            peakHourSharePercent: percentage(numerator: peakHourSessions, denominator: totalSessions),
            appConcentrationPercent: percentage(numerator: topAppWords, denominator: totalWords)
        )
    }

    private static func normalizedAppName(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "未知 App"
        }
        return value
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private static func percentage(numerator: Int, denominator: Int) -> Int {
        guard denominator > 0 else {
            return 0
        }
        return Int((Double(numerator) / Double(denominator) * 100).rounded())
    }

    private static let hourRangeDefinitions: [(label: String, start: Int, end: Int)] = [
        ("00-06", 0, 6),
        ("06-10", 6, 10),
        ("10-14", 10, 14),
        ("14-18", 14, 18),
        ("18-22", 18, 22),
        ("22-24", 22, 24)
    ]

    private static let weekdayDefinitions: [(title: String, calendarWeekday: Int)] = [
        ("周一", 2),
        ("周二", 3),
        ("周三", 4),
        ("周四", 5),
        ("周五", 6),
        ("周六", 7),
        ("周日", 1)
    ]
}

public struct VoiceInputSessionStatisticsDashboardSnapshot: Equatable, Sendable {
    public static let allAppsTitle = "全部"

    public let period: VoiceInputSessionStatisticsPeriod
    public let appOptions: [String]
    public let selectedAppName: String
    public let baseSnapshot: VoiceInputSessionStatisticsSnapshot
    public let scopedSnapshot: VoiceInputSessionStatisticsSnapshot

    public static func empty(
        period: VoiceInputSessionStatisticsPeriod,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> VoiceInputSessionStatisticsDashboardSnapshot {
        make(
            sessions: [],
            period: period,
            selectedAppName: allAppsTitle,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    public static func make(
        sessions: [VoiceInputSessionSnapshot],
        period: VoiceInputSessionStatisticsPeriod,
        selectedAppName: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        appOptionLimit: Int = 5
    ) -> VoiceInputSessionStatisticsDashboardSnapshot {
        let baseSnapshot = VoiceInputSessionStatisticsSnapshot.make(
            sessions: sessions,
            period: period,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let visibleAppOptions = Array(baseSnapshot.appContributions.prefix(max(0, appOptionLimit)).map(\.name))
        var appOptions = [allAppsTitle]
        appOptions.append(contentsOf: visibleAppOptions)

        let normalizedSelection = normalizedAppName(selectedAppName)
        if normalizedSelection != allAppsTitle,
           !appOptions.contains(normalizedSelection),
           baseSnapshot.appContributions.contains(where: { $0.name == normalizedSelection }) {
            appOptions.append(normalizedSelection)
        }

        let resolvedSelection = appOptions.contains(normalizedSelection)
            ? normalizedSelection
            : allAppsTitle
        let scopedSnapshot: VoiceInputSessionStatisticsSnapshot
        if resolvedSelection == allAppsTitle {
            scopedSnapshot = baseSnapshot
        } else {
            let scopedSessions = baseSnapshot.sessions.filter {
                normalizedAppName($0.targetAppName) == resolvedSelection
            }
            scopedSnapshot = VoiceInputSessionStatisticsSnapshot.make(
                sessions: scopedSessions,
                period: period,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        return VoiceInputSessionStatisticsDashboardSnapshot(
            period: period,
            appOptions: appOptions,
            selectedAppName: resolvedSelection,
            baseSnapshot: baseSnapshot,
            scopedSnapshot: scopedSnapshot
        )
    }

    private static func normalizedAppName(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "未知 App"
        }

        return value
    }
}
