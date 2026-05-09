import Foundation

public struct TranscriptPostProcessingContext: Equatable, Sendable {
    public let targetAppName: String?

    public init(targetAppName: String?) {
        self.targetAppName = targetAppName
    }
}

public struct TranscriptPostProcessingDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let skillID: String
    public let ruleID: UUID
    public let ruleDisplayName: String
    public let matchedText: String
    public let replacementText: String
    public let matchCount: Int

    public init(
        id: UUID = UUID(),
        skillID: String,
        ruleID: UUID,
        ruleDisplayName: String,
        matchedText: String,
        replacementText: String,
        matchCount: Int
    ) {
        self.id = id
        self.skillID = skillID
        self.ruleID = ruleID
        self.ruleDisplayName = ruleDisplayName
        self.matchedText = matchedText
        self.replacementText = replacementText
        self.matchCount = matchCount
    }
}

public struct TranscriptPostProcessingResult: Codable, Equatable, Sendable {
    public let originalText: String
    public let processedText: String
    public let diagnostics: [TranscriptPostProcessingDiagnostic]

    public var changed: Bool {
        originalText != processedText
    }

    public init(
        originalText: String,
        processedText: String,
        diagnostics: [TranscriptPostProcessingDiagnostic] = []
    ) {
        self.originalText = originalText
        self.processedText = processedText
        self.diagnostics = diagnostics
    }

    public static func unchanged(_ text: String) -> TranscriptPostProcessingResult {
        TranscriptPostProcessingResult(originalText: text, processedText: text)
    }
}

public enum FillerCleanupMatchType: String, Codable, Equatable, Sendable {
    case plainText
    case regex
}

public enum FillerCleanupAction: Codable, Equatable, Sendable {
    case delete
    case replace(String)

    public var replacementText: String {
        switch self {
        case .delete:
            return ""
        case .replace(let text):
            return text
        }
    }
}

public struct FillerCleanupRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let matchText: String
    public let matchType: FillerCleanupMatchType
    public let action: FillerCleanupAction
    public let isEnabled: Bool
    public let order: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        matchText: String,
        matchType: FillerCleanupMatchType = .plainText,
        action: FillerCleanupAction,
        isEnabled: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.matchText = matchText
        self.matchType = matchType
        self.action = action
        self.isEnabled = isEnabled
        self.order = order
    }
}

public struct FillerCleanupSettings: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let rules: [FillerCleanupRule]

    public static let defaultRules: [FillerCleanupRule] = [
        FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, order: 0),
        FillerCleanupRule(displayName: "删除呃", matchText: "呃", action: .delete, order: 1),
        FillerCleanupRule(displayName: "删除啊", matchText: "啊", action: .delete, order: 2),
        FillerCleanupRule(displayName: "删除这个", matchText: "这个", action: .delete, order: 3),
        FillerCleanupRule(displayName: "删除那个", matchText: "那个", action: .delete, order: 4),
        FillerCleanupRule(displayName: "删除就是", matchText: "就是", action: .delete, order: 5),
        FillerCleanupRule(displayName: "删除然后", matchText: "然后", action: .delete, order: 6)
    ]

    public static let `default` = FillerCleanupSettings(isEnabled: false, rules: defaultRules)

    public init(isEnabled: Bool = false, rules: [FillerCleanupRule] = FillerCleanupSettings.defaultRules) {
        self.isEnabled = isEnabled
        self.rules = rules
    }

    public var orderedRulesForDisplay: [FillerCleanupRule] {
        rules.enumerated()
            .sorted { lhs, rhs in
                Self.compareRuleOrder(lhs, rhs)
            }
            .map(\.element)
    }

    private static func compareRuleOrder(
        _ lhs: EnumeratedSequence<[FillerCleanupRule]>.Element,
        _ rhs: EnumeratedSequence<[FillerCleanupRule]>.Element
    ) -> Bool {
        if lhs.element.order != rhs.element.order {
            return lhs.element.order < rhs.element.order
        }
        if lhs.element.displayName != rhs.element.displayName {
            return lhs.element.displayName < rhs.element.displayName
        }
        return lhs.offset < rhs.offset
    }
}

public struct SkillSettings: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let fillerCleanup: FillerCleanupSettings

    public static let `default` = SkillSettings(isEnabled: true, fillerCleanup: .default)

    public init(isEnabled: Bool = true, fillerCleanup: FillerCleanupSettings = .default) {
        self.isEnabled = isEnabled
        self.fillerCleanup = fillerCleanup
    }
}

@MainActor
public protocol SkillPreferenceStoring: AnyObject {
    var skillSettings: SkillSettings { get }

    func saveSkillSettings(_ settings: SkillSettings)
}

public final class NoOpSkillPreferenceStore: SkillPreferenceStoring {
    public init() {}

    public var skillSettings: SkillSettings {
        .default
    }

    public func saveSkillSettings(_ settings: SkillSettings) {}
}

public protocol TranscriptPostProcessingSkill: Sendable {
    var id: String { get }

    func process(_ text: String, context: TranscriptPostProcessingContext) -> SkillProcessingOutput
}

public struct SkillProcessingOutput: Equatable, Sendable {
    public let processedText: String
    public let diagnostics: [TranscriptPostProcessingDiagnostic]

    public init(processedText: String, diagnostics: [TranscriptPostProcessingDiagnostic] = []) {
        self.processedText = processedText
        self.diagnostics = diagnostics
    }

    public static func unchanged(_ text: String) -> SkillProcessingOutput {
        SkillProcessingOutput(processedText: text)
    }
}

public struct FillerCleanupSkill: TranscriptPostProcessingSkill {
    public static let skillID = "fillerCleanup"

    public let settings: FillerCleanupSettings

    public var id: String {
        Self.skillID
    }

    public init(settings: FillerCleanupSettings = .default) {
        self.settings = settings
    }

    public func process(_ text: String, context _: TranscriptPostProcessingContext) -> SkillProcessingOutput {
        guard settings.isEnabled else {
            return .unchanged(text)
        }

        var processedText = text
        var diagnostics: [TranscriptPostProcessingDiagnostic] = []

        for rule in orderedPlainTextRules {
            let matchCount = processedText.nonOverlappingOccurrenceCount(of: rule.matchText)
            guard matchCount > 0 else {
                continue
            }

            let replacementText = rule.action.replacementText
            processedText = processedText.replacingOccurrences(of: rule.matchText, with: replacementText)
            diagnostics.append(
                TranscriptPostProcessingDiagnostic(
                    skillID: Self.skillID,
                    ruleID: rule.id,
                    ruleDisplayName: rule.displayName,
                    matchedText: rule.matchText,
                    replacementText: replacementText,
                    matchCount: matchCount
                )
            )
        }

        return SkillProcessingOutput(processedText: processedText, diagnostics: diagnostics)
    }

    private var orderedPlainTextRules: [FillerCleanupRule] {
        settings.orderedRulesForDisplay
            .filter { rule in
                rule.isEnabled && rule.matchType == .plainText && !rule.matchText.isEmpty
            }
    }
}

public struct TranscriptPostProcessingPipeline: Sendable {
    public let settings: SkillSettings

    public init(settings: SkillSettings = .default) {
        self.settings = settings
    }

    public func process(
        _ text: String,
        context: TranscriptPostProcessingContext = TranscriptPostProcessingContext(targetAppName: nil)
    ) -> TranscriptPostProcessingResult {
        guard settings.isEnabled else {
            return .unchanged(text)
        }

        let fillerOutput = FillerCleanupSkill(settings: settings.fillerCleanup).process(text, context: context)
        return TranscriptPostProcessingResult(
            originalText: text,
            processedText: fillerOutput.processedText,
            diagnostics: fillerOutput.diagnostics
        )
    }
}

private extension String {
    func nonOverlappingOccurrenceCount(of needle: String) -> Int {
        guard !needle.isEmpty else {
            return 0
        }

        var count = 0
        var searchStartIndex = startIndex
        while let range = range(of: needle, range: searchStartIndex..<endIndex) {
            count += 1
            searchStartIndex = range.upperBound
        }
        return count
    }
}
