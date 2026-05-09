import Foundation

public struct SkillPreviewSnapshot: Equatable, Sendable {
    public let originalText: String
    public let processedText: String
    public let matchedRuleTitles: [String]

    public init(result: TranscriptPostProcessingResult) {
        self.originalText = result.originalText
        self.processedText = result.processedText
        self.matchedRuleTitles = result.diagnostics.map(\.ruleDisplayName)
    }
}

public struct SkillSettingsSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let isEnabled: Bool
    public let fillerCleanupTitle: String
    public let fillerCleanupDetail: String
    public let isFillerCleanupEnabled: Bool
    public let rules: [FillerCleanupRule]
    public let preview: SkillPreviewSnapshot

    public init(
        settings: SkillSettings,
        previewInput: String,
        strings: VocoStrings = VocoStrings()
    ) {
        let result = TranscriptPostProcessingPipeline(settings: settings).process(
            previewInput,
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )
        self.title = strings.skills.title
        self.detail = strings.skills.detail
        self.isEnabled = settings.isEnabled
        self.fillerCleanupTitle = strings.skills.fillerCleanupTitle
        self.fillerCleanupDetail = strings.skills.fillerCleanupDetail
        self.isFillerCleanupEnabled = settings.fillerCleanup.isEnabled
        self.rules = settings.fillerCleanup.orderedRulesForDisplay
        self.preview = SkillPreviewSnapshot(result: result)
    }
}
