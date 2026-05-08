import XCTest
@testable import VocoAppCore

final class InjectionSettingsModelsTests: XCTestCase {
    func testInjectionSettingsSnapshotUsesEnglishCopy() {
        let snapshot = InjectionSettingsSnapshot(lastInjection: nil, strings: VocoStrings(language: .en))

        XCTAssertEqual(snapshot.strategy.title, "Waiting to Insert")
        XCTAssertEqual(snapshot.focusedApp.title, "No Recent Target")
    }

    func testEnglishInjectionSettingsLocalizeSemanticInjectionSnapshot() {
        let success = TextInjectionSnapshot.success(
            targetAppName: "Notes",
            strategy: .directAccessibility
        )
        let successSnapshot = InjectionSettingsSnapshot(
            lastInjection: success,
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(successSnapshot.strategy.title, "Direct Accessibility insertion")
        XCTAssertEqual(successSnapshot.strategy.detail, "Inserted text with Direct Accessibility.")
        XCTAssertEqual(successSnapshot.focusedApp.detail, "Recent insertion target app.")

        let failure = TextInjectionSnapshot.failed(
            targetAppName: nil,
            strategy: .unavailable,
            error: .accessibilityPermissionMissing
        )
        let failureSnapshot = InjectionSettingsSnapshot(
            lastInjection: failure,
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(failureSnapshot.strategy.title, "Unavailable")
        XCTAssertEqual(
            failureSnapshot.strategy.detail,
            "Unable to insert text: allow Voco to use Accessibility in System Settings first."
        )
        XCTAssertEqual(failureSnapshot.focusedApp.title, "No Target App")
        XCTAssertEqual(
            failureSnapshot.focusedApp.detail,
            "Unable to insert text: allow Voco to use Accessibility in System Settings first."
        )
    }

    func testDefaultInjectionSettingsShowNoRecentTarget() {
        let snapshot = InjectionSettingsSnapshot(lastInjection: nil)

        XCTAssertEqual(snapshot.strategy.title, "等待插入")
        XCTAssertEqual(snapshot.strategy.detail, "完成一次转写后会显示采用的文本插入方式。")
        XCTAssertEqual(snapshot.focusedApp.title, "无近期目标")
        XCTAssertEqual(snapshot.focusedApp.detail, "尚未完成文本插入，无法显示最近聚焦 App。")
        XCTAssertFalse(snapshot.focusedApp.hasRecentTarget)
    }

    func testSuccessfulInjectionShowsStrategyAndFocusedApp() {
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .directAccessibility,
            succeeded: true,
            detail: "已通过辅助功能直接插入文本。"
        )

        let snapshot = InjectionSettingsSnapshot(lastInjection: injection)

        XCTAssertEqual(snapshot.strategy.title, "辅助功能直接插入")
        XCTAssertEqual(snapshot.strategy.detail, "已通过辅助功能直接插入文本。")
        XCTAssertEqual(snapshot.strategy.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(snapshot.focusedApp.title, "Notes")
        XCTAssertEqual(snapshot.focusedApp.detail, "最近插入目标 App。")
        XCTAssertTrue(snapshot.focusedApp.hasRecentTarget)
    }

    func testFailedInjectionShowsFailureDiagnostics() {
        let injection = TextInjectionSnapshot(
            targetAppName: nil,
            strategy: .unavailable,
            succeeded: false,
            detail: "无法插入文本：请先允许辅助功能。"
        )

        let snapshot = InjectionSettingsSnapshot(lastInjection: injection)

        XCTAssertEqual(snapshot.strategy.title, "不可用")
        XCTAssertEqual(snapshot.strategy.systemImage, "xmark.circle.fill")
        XCTAssertEqual(snapshot.focusedApp.title, "无目标 App")
        XCTAssertEqual(snapshot.focusedApp.detail, "无法插入文本：请先允许辅助功能。")
        XCTAssertFalse(snapshot.focusedApp.hasRecentTarget)
    }
}
