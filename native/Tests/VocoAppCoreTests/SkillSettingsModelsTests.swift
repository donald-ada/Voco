import XCTest
@testable import VocoAppCore

final class SkillSettingsModelsTests: XCTestCase {
    func testSkillSettingsSnapshotUsesChineseCopyByDefault() {
        let snapshot = SkillSettingsSnapshot(settings: .default, previewInput: "嗯测试")

        XCTAssertEqual(snapshot.title, "技能")
        XCTAssertEqual(snapshot.fillerCleanupTitle, "语气词清理")
    }

    func testSkillSettingsSnapshotBuildsImplementedSkillLibraryOnly() {
        let snapshot = SkillSettingsSnapshot(
            settings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: true)
            ),
            previewInput: "嗯测试"
        )

        XCTAssertEqual(snapshot.catalogItems.map(\.id), [FillerCleanupSkill.skillID])
        XCTAssertEqual(snapshot.catalogItems.map(\.glyph), ["CL"])
        XCTAssertEqual(snapshot.catalogItems.first?.title, "语气词清理")
        XCTAssertEqual(snapshot.catalogItems.first?.statusTitle, "已开启")
        XCTAssertTrue(snapshot.catalogItems.first?.isConfigurable == true)
    }

    func testSkillSettingsSnapshotLocalizesImplementedSkillStatus() {
        let snapshot = SkillSettingsSnapshot(
            settings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: false)
            ),
            previewInput: "um test",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.catalogItems.map(\.id), [FillerCleanupSkill.skillID])
        XCTAssertEqual(snapshot.catalogItems.first?.title, "Filler Cleanup")
        XCTAssertEqual(snapshot.catalogItems.first?.statusTitle, "Disabled")
    }

    func testFillerCleanupDetailSplitsDefaultAndCustomWords() {
        let customRule = FillerCleanupRule(
            displayName: "就是吧",
            matchText: "就是吧",
            action: .replace(" "),
            isEnabled: true,
            order: 99
        )
        let disabledDefaultRule = FillerCleanupRule(
            displayName: "删除就是",
            matchText: "就是",
            action: .delete,
            isEnabled: false,
            order: 5
        )
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, order: 0),
                    disabledDefaultRule,
                    customRule
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(settings: settings, previewInput: "嗯这个")

        XCTAssertEqual(snapshot.fillerCleanupDetail.tabs.map(\.title), ["概览", "词库", "命中"])
        XCTAssertEqual(snapshot.fillerCleanupDetail.defaultWords.map(\.text), ["嗯", "就是"])
        XCTAssertEqual(snapshot.fillerCleanupDetail.defaultWords.map(\.isEnabled), [true, false])
        XCTAssertEqual(snapshot.fillerCleanupDetail.customWords.map(\.text), ["就是吧"])
        XCTAssertEqual(snapshot.fillerCleanupDetail.customWords.first?.actionTitle, "替换为空格")
    }

    func testFillerCleanupDetailDoesNotCountPreviewTextAsHistoricalHits() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, order: 0),
                    FillerCleanupRule(displayName: "删除这个", matchText: "这个", action: .delete, order: 1),
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(settings: settings, previewInput: "嗯这个嗯")

        XCTAssertEqual(snapshot.preview.processedText, "")
        XCTAssertEqual(snapshot.fillerCleanupDetail.totalHitCount, 0)
        XCTAssertTrue(snapshot.fillerCleanupDetail.hitRows.isEmpty)
    }

    func testSkillPreviewChangeSegmentsMarkDeletedFillerWords() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, order: 0)
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(settings: settings, previewInput: "嗯今天开始")

        XCTAssertEqual(
            segmentSummaries(snapshot.preview.changeSegments),
            [
                "removed|嗯|删除嗯",
                "unchanged|今天开始|"
            ]
        )
    }

    func testSkillPreviewChangeSegmentsMarkReplacementWords() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "替换那个啥", matchText: "那个啥", action: .replace("项目"), order: 0)
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(settings: settings, previewInput: "那个啥今天继续")

        XCTAssertEqual(snapshot.preview.processedText, "项目今天继续")
        XCTAssertEqual(
            segmentSummaries(snapshot.preview.changeSegments),
            [
                "removed|那个啥|替换那个啥",
                "inserted|项目|替换那个啥",
                "unchanged|今天继续|"
            ]
        )
    }

    func testSkillPreviewChangeSegmentsStayUnchangedWhenNoRuleMatches() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, order: 0)
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(settings: settings, previewInput: "今天开始")

        XCTAssertEqual(
            segmentSummaries(snapshot.preview.changeSegments),
            [
                "unchanged|今天开始|"
            ]
        )
    }

    func testFillerCleanupDetailAggregatesHitRowsFromHistoricalSessions() {
        let ruleID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let ignoredRuleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let sessions = [
            VoiceInputSessionSnapshot(
                transcriptText: "今天继续",
                rawTranscriptText: "嗯今天继续",
                postProcessingDiagnostics: [
                    TranscriptPostProcessingDiagnostic(
                        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                        skillID: FillerCleanupSkill.skillID,
                        ruleID: ruleID,
                        ruleDisplayName: "删除嗯",
                        matchedText: "嗯",
                        replacementText: "",
                        matchCount: 2
                    ),
                    TranscriptPostProcessingDiagnostic(
                        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                        skillID: "otherSkill",
                        ruleID: ignoredRuleID,
                        ruleDisplayName: "其他技能",
                        matchedText: "其他",
                        replacementText: "",
                        matchCount: 9
                    )
                ],
                wordCount: 4,
                durationSeconds: 5,
                createdAt: Date(timeIntervalSince1970: 2),
                targetAppName: "Notes",
                providerName: "火山引擎"
            ),
            VoiceInputSessionSnapshot(
                transcriptText: "继续",
                rawTranscriptText: "嗯这个继续",
                postProcessingDiagnostics: [
                    TranscriptPostProcessingDiagnostic(
                        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                        skillID: FillerCleanupSkill.skillID,
                        ruleID: ruleID,
                        ruleDisplayName: "删除嗯",
                        matchedText: "嗯",
                        replacementText: "",
                        matchCount: 3
                    ),
                    TranscriptPostProcessingDiagnostic(
                        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                        skillID: FillerCleanupSkill.skillID,
                        ruleID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                        ruleDisplayName: "删除这个",
                        matchedText: "这个",
                        replacementText: "",
                        matchCount: 1
                    )
                ],
                wordCount: 2,
                durationSeconds: 4,
                createdAt: Date(timeIntervalSince1970: 1),
                targetAppName: "Notes",
                providerName: "火山引擎"
            )
        ]
        let snapshot = SkillSettingsSnapshot(
            settings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: true)
            ),
            previewInput: "啊啊啊",
            historicalSessions: sessions
        )

        XCTAssertEqual(snapshot.fillerCleanupDetail.totalHitCount, 6)
        XCTAssertEqual(snapshot.fillerCleanupDetail.hitRows.map(\.matchedText), ["嗯", "这个"])
        XCTAssertEqual(snapshot.fillerCleanupDetail.hitRows.map(\.matchCount), [5, 1])
        XCTAssertEqual(snapshot.fillerCleanupDetail.hitRows.map(\.actionTitle), ["删除", "删除"])
        XCTAssertFalse(snapshot.fillerCleanupDetail.hitRows.contains { $0.title.contains("删除") })
    }

    func testSkillSettingsSnapshotUsesEnglishCopyAndPreview() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, isEnabled: true, order: 0)]
            )
        )
        let snapshot = SkillSettingsSnapshot(
            settings: settings,
            previewInput: "嗯hello",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.title, "Skills")
        XCTAssertEqual(snapshot.fillerCleanupTitle, "Filler Cleanup")
        XCTAssertEqual(snapshot.preview.originalText, "嗯hello")
        XCTAssertEqual(snapshot.preview.processedText, "hello")
        XCTAssertEqual(snapshot.preview.matchedRuleTitles, ["删除嗯"])
    }

    func testSkillSettingsSnapshotRulesMatchPreviewOrderWhenRuleOrderTies() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "B rule", matchText: "beta", action: .delete, order: 0),
                    FillerCleanupRule(displayName: "A rule", matchText: "alpha", action: .delete, order: 0),
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(
            settings: settings,
            previewInput: "alpha beta",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.rules.map(\.displayName), ["A rule", "B rule"])
        XCTAssertEqual(snapshot.preview.matchedRuleTitles, snapshot.rules.map(\.displayName))
    }

    func testFillerCleanupSettingsOrderedRulesForDisplayUsesProcessingTieBreakers() {
        let settings = FillerCleanupSettings(
            isEnabled: true,
            rules: [
                FillerCleanupRule(displayName: "B rule", matchText: "beta", action: .delete, order: 0),
                FillerCleanupRule(displayName: "A rule", matchText: "alpha", action: .delete, order: 0),
                FillerCleanupRule(displayName: "C rule", matchText: "gamma", action: .delete, order: 1),
            ]
        )

        XCTAssertEqual(settings.orderedRulesForDisplay.map(\.displayName), ["A rule", "B rule", "C rule"])
    }

    private func segmentSummaries(_ segments: [SkillPreviewChangeSegment]) -> [String] {
        segments.map { segment in
            "\(segment.kind.rawValue)|\(segment.text)|\(segment.ruleTitle ?? "")"
        }
    }
}
