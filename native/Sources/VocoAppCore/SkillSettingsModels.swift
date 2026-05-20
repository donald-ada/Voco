import Foundation

public enum SkillPreviewChangeSegmentKind: String, Equatable, Sendable {
    case unchanged
    case removed
    case inserted
}

public struct SkillPreviewChangeSegment: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: SkillPreviewChangeSegmentKind
    public let text: String
    public let ruleTitle: String?

    public init(
        id: Int,
        kind: SkillPreviewChangeSegmentKind,
        text: String,
        ruleTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.ruleTitle = ruleTitle
    }

}

public struct SkillPreviewSnapshot: Equatable, Sendable {
    public let originalText: String
    public let processedText: String
    public let matchedRuleTitles: [String]
    public let changeSegments: [SkillPreviewChangeSegment]

    public init(result: TranscriptPostProcessingResult) {
        self.originalText = result.originalText
        self.processedText = result.processedText
        self.matchedRuleTitles = result.diagnostics.map(\.ruleDisplayName)
        self.changeSegments = Self.makeChangeSegments(result: result)
    }

    private static func makeChangeSegments(result: TranscriptPostProcessingResult) -> [SkillPreviewChangeSegment] {
        var segments = [
            WorkingChangeSegment(kind: .unchanged, text: result.originalText, ruleTitle: nil)
        ]

        for diagnostic in result.diagnostics {
            segments = apply(diagnostic: diagnostic, to: segments)
        }

        return compacted(segments).enumerated().map { index, segment in
            SkillPreviewChangeSegment(
                id: index,
                kind: segment.kind,
                text: segment.text,
                ruleTitle: segment.ruleTitle
            )
        }
    }

    private static func apply(
        diagnostic: TranscriptPostProcessingDiagnostic,
        to segments: [WorkingChangeSegment]
    ) -> [WorkingChangeSegment] {
        var output: [WorkingChangeSegment] = []
        var remainingMatches = diagnostic.matchCount

        for segment in segments {
            guard remainingMatches > 0,
                  segment.kind != .removed,
                  !diagnostic.matchedText.isEmpty else {
                output.append(segment)
                continue
            }

            output.append(
                contentsOf: split(
                    segment,
                    matchedText: diagnostic.matchedText,
                    replacementText: diagnostic.replacementText,
                    ruleTitle: diagnostic.ruleDisplayName,
                    remainingMatches: &remainingMatches
                )
            )
        }

        return output
    }

    private static func split(
        _ segment: WorkingChangeSegment,
        matchedText: String,
        replacementText: String,
        ruleTitle: String,
        remainingMatches: inout Int
    ) -> [WorkingChangeSegment] {
        var output: [WorkingChangeSegment] = []
        var cursor = segment.text.startIndex

        while remainingMatches > 0,
              let range = segment.text.range(of: matchedText, range: cursor..<segment.text.endIndex) {
            appendSegment(
                kind: segment.kind,
                text: String(segment.text[cursor..<range.lowerBound]),
                ruleTitle: segment.ruleTitle,
                to: &output
            )
            appendSegment(kind: .removed, text: String(segment.text[range]), ruleTitle: ruleTitle, to: &output)
            appendSegment(kind: .inserted, text: replacementText, ruleTitle: ruleTitle, to: &output)
            remainingMatches -= 1
            cursor = range.upperBound
        }

        appendSegment(
            kind: segment.kind,
            text: String(segment.text[cursor..<segment.text.endIndex]),
            ruleTitle: segment.ruleTitle,
            to: &output
        )
        return output
    }

    private static func compacted(_ segments: [WorkingChangeSegment]) -> [WorkingChangeSegment] {
        var output: [WorkingChangeSegment] = []
        for segment in segments {
            appendSegment(kind: segment.kind, text: segment.text, ruleTitle: segment.ruleTitle, to: &output)
        }
        return output
    }

    private static func appendSegment(
        kind: SkillPreviewChangeSegmentKind,
        text: String,
        ruleTitle: String?,
        to segments: inout [WorkingChangeSegment]
    ) {
        guard !text.isEmpty else {
            return
        }

        if var last = segments.last,
           last.kind == kind,
           last.ruleTitle == ruleTitle {
            last.text += text
            segments[segments.count - 1] = last
            return
        }

        segments.append(WorkingChangeSegment(kind: kind, text: text, ruleTitle: ruleTitle))
    }

    private struct WorkingChangeSegment: Equatable {
        let kind: SkillPreviewChangeSegmentKind
        var text: String
        let ruleTitle: String?
    }
}

public enum SkillCatalogStatusTone: Equatable, Sendable {
    case active
    case neutral
}

public struct SkillCatalogItemSnapshot: Equatable, Identifiable, Sendable {
    public let id: String
    public let glyph: String
    public let title: String
    public let statusTitle: String
    public let statusTone: SkillCatalogStatusTone
    public let isConfigurable: Bool

    public init(
        id: String,
        glyph: String,
        title: String,
        statusTitle: String,
        statusTone: SkillCatalogStatusTone,
        isConfigurable: Bool
    ) {
        self.id = id
        self.glyph = glyph
        self.title = title
        self.statusTitle = statusTitle
        self.statusTone = statusTone
        self.isConfigurable = isConfigurable
    }
}

public enum FillerCleanupDetailTab: String, CaseIterable, Identifiable, Equatable, Sendable {
    case overview
    case words
    case hits

    public var id: String {
        rawValue
    }

    public func title(strings: VocoStrings) -> String {
        switch (self, strings.language) {
        case (.overview, .zhHans):
            "概览"
        case (.overview, .en):
            "Overview"
        case (.words, .zhHans):
            "词库"
        case (.words, .en):
            "Words"
        case (.hits, .zhHans):
            "命中"
        case (.hits, .en):
            "Hits"
        }
    }
}

public struct FillerCleanupDetailTabSnapshot: Equatable, Identifiable, Sendable {
    public let id: FillerCleanupDetailTab
    public let title: String

    public init(id: FillerCleanupDetailTab, title: String) {
        self.id = id
        self.title = title
    }
}

public struct FillerCleanupWordSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let actionTitle: String
    public let isEnabled: Bool
    public let isDefault: Bool
    public let order: Int

    public init(
        id: UUID,
        text: String,
        actionTitle: String,
        isEnabled: Bool,
        isDefault: Bool,
        order: Int
    ) {
        self.id = id
        self.text = text
        self.actionTitle = actionTitle
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.order = order
    }
}

public struct FillerCleanupHitSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let ruleID: UUID
    public let title: String
    public let matchedText: String
    public let actionTitle: String
    public let matchCount: Int

    public init(
        id: UUID,
        ruleID: UUID,
        title: String,
        matchedText: String,
        actionTitle: String,
        matchCount: Int
    ) {
        self.id = id
        self.ruleID = ruleID
        self.title = title
        self.matchedText = matchedText
        self.actionTitle = actionTitle
        self.matchCount = matchCount
    }
}

public struct FillerCleanupDetailSnapshot: Equatable, Sendable {
    public let tabs: [FillerCleanupDetailTabSnapshot]
    public let defaultWords: [FillerCleanupWordSnapshot]
    public let customWords: [FillerCleanupWordSnapshot]
    public let hitRows: [FillerCleanupHitSnapshot]
    public let enabledRuleCount: Int
    public let totalHitCount: Int

    public init(
        settings: FillerCleanupSettings,
        result: TranscriptPostProcessingResult,
        historicalSessions: [VoiceInputSessionSnapshot] = [],
        strings: VocoStrings
    ) {
        self.tabs = FillerCleanupDetailTab.allCases.map { tab in
            FillerCleanupDetailTabSnapshot(id: tab, title: tab.title(strings: strings))
        }

        let defaultMatchTexts = Set(FillerCleanupSettings.defaultRules.map(\.matchText))
        let wordRows = settings.orderedRulesForDisplay.map { rule in
            let isDefault = defaultMatchTexts.contains(rule.matchText)
            return FillerCleanupWordSnapshot(
                id: rule.id,
                text: rule.matchText,
                actionTitle: Self.actionTitle(for: rule.action, strings: strings),
                isEnabled: rule.isEnabled,
                isDefault: isDefault,
                order: rule.order
            )
        }

        self.defaultWords = wordRows.filter(\.isDefault)
        self.customWords = wordRows.filter { !$0.isDefault }
        self.enabledRuleCount = settings.rules.filter(\.isEnabled).count
        let hitDiagnostics = historicalSessions
            .flatMap(\.postProcessingDiagnostics)
            .filter { $0.skillID == FillerCleanupSkill.skillID }
        self.totalHitCount = hitDiagnostics.reduce(0) { $0 + $1.matchCount }

        self.hitRows = Self.aggregateHitRows(from: hitDiagnostics, strings: strings)
    }

    private static func aggregateHitRows(
        from diagnostics: [TranscriptPostProcessingDiagnostic],
        strings: VocoStrings
    ) -> [FillerCleanupHitSnapshot] {
        var groups: [FillerCleanupHitGroupKey: FillerCleanupHitGroup] = [:]

        for diagnostic in diagnostics {
            let key = FillerCleanupHitGroupKey(
                matchedText: diagnostic.matchedText,
                replacementText: diagnostic.replacementText
            )
            if var group = groups[key] {
                group.matchCount += diagnostic.matchCount
                groups[key] = group
            } else {
                groups[key] = FillerCleanupHitGroup(
                    id: diagnostic.id,
                    ruleID: diagnostic.ruleID,
                    matchedText: diagnostic.matchedText,
                    replacementText: diagnostic.replacementText,
                    matchCount: diagnostic.matchCount
                )
            }
        }

        return groups.values
            .sorted { lhs, rhs in
                if lhs.matchCount != rhs.matchCount {
                    return lhs.matchCount > rhs.matchCount
                }
                if lhs.matchedText != rhs.matchedText {
                    return lhs.matchedText < rhs.matchedText
                }
                return lhs.replacementText < rhs.replacementText
            }
            .map { group in
                let actionTitle = group.replacementText.isEmpty
                    ? Self.deleteTitle(strings: strings)
                    : Self.replaceTitle(replacementText: group.replacementText, strings: strings)
                return FillerCleanupHitSnapshot(
                    id: group.id,
                    ruleID: group.ruleID,
                    title: group.matchedText,
                    matchedText: group.matchedText,
                    actionTitle: actionTitle,
                    matchCount: group.matchCount
                )
            }
    }

    private struct FillerCleanupHitGroupKey: Hashable {
        let matchedText: String
        let replacementText: String
    }

    private struct FillerCleanupHitGroup {
        let id: UUID
        let ruleID: UUID
        let matchedText: String
        let replacementText: String
        var matchCount: Int
    }

    public static func actionTitle(for action: FillerCleanupAction, strings: VocoStrings) -> String {
        switch action {
        case .delete:
            return deleteTitle(strings: strings)
        case .replace(let text):
            return replaceTitle(replacementText: text, strings: strings)
        }
    }

    private static func deleteTitle(strings: VocoStrings) -> String {
        strings.skills.deleteActionTitle
    }

    private static func replaceTitle(replacementText: String, strings: VocoStrings) -> String {
        if replacementText == " " {
            return strings.language == .zhHans ? "替换为空格" : "Replace with Space"
        }
        if replacementText.isEmpty {
            return strings.language == .zhHans ? "替换为空字符串" : "Replace with Empty String"
        }
        return strings.language == .zhHans ? "替换为\(replacementText)" : "Replace with \(replacementText)"
    }
}

public struct SkillSettingsSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let isEnabled: Bool
    public let catalogItems: [SkillCatalogItemSnapshot]
    public let fillerCleanupTitle: String
    public let fillerCleanupDetail: FillerCleanupDetailSnapshot
    public let isFillerCleanupEnabled: Bool
    public let rules: [FillerCleanupRule]
    public let preview: SkillPreviewSnapshot

    public init(
        settings: SkillSettings,
        previewInput: String,
        historicalSessions: [VoiceInputSessionSnapshot] = [],
        strings: VocoStrings = VocoStrings()
    ) {
        let result = TranscriptPostProcessingPipeline(settings: settings).process(
            previewInput,
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )
        self.title = strings.skills.title
        self.detail = strings.skills.detail
        self.isEnabled = settings.isEnabled
        self.catalogItems = Self.catalogItems(settings: settings, strings: strings)
        self.fillerCleanupTitle = strings.skills.fillerCleanupTitle
        self.fillerCleanupDetail = FillerCleanupDetailSnapshot(
            settings: settings.fillerCleanup,
            result: result,
            historicalSessions: historicalSessions,
            strings: strings
        )
        self.isFillerCleanupEnabled = settings.fillerCleanup.isEnabled
        self.rules = settings.fillerCleanup.orderedRulesForDisplay
        self.preview = SkillPreviewSnapshot(result: result)
    }

    private static func catalogItems(settings: SkillSettings, strings: VocoStrings) -> [SkillCatalogItemSnapshot] {
        [
            SkillCatalogItemSnapshot(
                id: FillerCleanupSkill.skillID,
                glyph: "CL",
                title: strings.skills.fillerCleanupTitle,
                statusTitle: settings.fillerCleanup.isEnabled ? localized("已开启", "Enabled", strings: strings) : localized("已关闭", "Disabled", strings: strings),
                statusTone: settings.fillerCleanup.isEnabled ? .active : .neutral,
                isConfigurable: true
            )
        ]
    }

    private static func localized(_ zhHans: String, _ en: String, strings: VocoStrings) -> String {
        strings.language == .zhHans ? zhHans : en
    }
}
