import XCTest
@testable import VocoAppCore

final class TextInjectionModelsTests: XCTestCase {
    func testStrategyTitlesAreUserVisible() {
        XCTAssertEqual(TextInjectionStrategy.directAccessibility.title, "辅助功能直接插入")
        XCTAssertEqual(TextInjectionStrategy.unicodeEvent.title, "Unicode 事件")
        XCTAssertEqual(TextInjectionStrategy.clipboardFallback.title, "剪贴板回退")
        XCTAssertEqual(TextInjectionStrategy.unavailable.title, "不可用")
        XCTAssertEqual(TextInjectionStrategy.skippedEmpty.title, "空文本跳过")
    }

    func testContextSelectsPreferredAvailableStrategy() {
        let allAvailable = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: true,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
        XCTAssertEqual(allAvailable.preferredStrategy, .directAccessibility)

        let unicodeOnly = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: false,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
        XCTAssertEqual(unicodeOnly.preferredStrategy, .unicodeEvent)

        let clipboardOnly = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: false,
            supportsUnicodeEvents: false,
            supportsClipboardFallback: true
        )
        XCTAssertEqual(clipboardOnly.preferredStrategy, .clipboardFallback)

        let notTrusted = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: false,
            supportsDirectAccessibility: true,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
        XCTAssertNil(notTrusted.preferredStrategy)
    }

    func testErrorsExposeUserVisibleMessages() {
        XCTAssertEqual(
            TextInjectionError.accessibilityPermissionMissing.localizedDescription,
            "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。"
        )
        XCTAssertEqual(
            TextInjectionError.noSupportedStrategy(targetAppName: "Terminal").localizedDescription,
            "无法插入文本：Terminal 没有可用的文本插入方式。"
        )
        XCTAssertEqual(
            TextInjectionError.clipboardRestoreFailed(message: "write failed").localizedDescription,
            "剪贴板回退后恢复原剪贴板失败：write failed"
        )
    }
}
