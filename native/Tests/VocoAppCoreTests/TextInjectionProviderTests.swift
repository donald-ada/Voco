import XCTest
@testable import VocoAppCore

final class TextInjectionProviderTests: XCTestCase {
    @MainActor
    func testProviderSkipsEmptyTextWithoutInspectingClient() async throws {
        let client = FakeTextInsertionClient(context: .trusted())
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert(" \n ")

        XCTAssertEqual(result, .skippedEmpty)
        XCTAssertEqual(client.contextRequests, 0)
        XCTAssertTrue(client.insertions.isEmpty)
    }

    @MainActor
    func testProviderUsesClipboardFallbackBeforeDirectAccessibility() async throws {
        let client = FakeTextInsertionClient(context: .trusted(supportsDirectAccessibility: true))
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert("hello")

        XCTAssertEqual(client.insertions, [InsertionRequest(text: "hello", strategy: .clipboardFallback)])
        XCTAssertEqual(result.targetAppName, "Notes")
        XCTAssertEqual(result.strategy, .clipboardFallback)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.detail, "已通过剪贴板回退插入文本并恢复剪贴板。")
        XCTAssertEqual(
            result.detail(strings: VocoStrings(language: .en)),
            "Inserted text with clipboard fallback and restored the clipboard."
        )
    }

    @MainActor
    func testProviderFallsBackToUnicodeThenDirectAccessibility() async throws {
        let unicodeClient = FakeTextInsertionClient(
            context: .trusted(
                supportsDirectAccessibility: false,
                supportsUnicodeEvents: true,
                supportsClipboardFallback: false
            )
        )
        let unicodeProvider = NativeTextInjectionProvider(client: unicodeClient)

        let unicodeResult = try await unicodeProvider.insert("hello")

        XCTAssertEqual(unicodeClient.insertions, [InsertionRequest(text: "hello", strategy: .unicodeEvent)])
        XCTAssertEqual(unicodeResult.strategy, .unicodeEvent)

        let directClient = FakeTextInsertionClient(
            context: .trusted(
                supportsDirectAccessibility: true,
                supportsUnicodeEvents: false,
                supportsClipboardFallback: false
            )
        )
        let directProvider = NativeTextInjectionProvider(client: directClient)

        let directResult = try await directProvider.insert("hello")

        XCTAssertEqual(directClient.insertions, [InsertionRequest(text: "hello", strategy: .directAccessibility)])
        XCTAssertEqual(directResult.strategy, .directAccessibility)
        XCTAssertEqual(directResult.detail, "已通过辅助功能直接插入文本。")
    }

    @MainActor
    func testProviderReportsPermissionFailureWithoutCallingInsertionClient() async throws {
        let client = FakeTextInsertionClient(context: .untrusted())
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert("hello")

        XCTAssertEqual(result.strategy, .unavailable)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.detail, "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。")
        XCTAssertEqual(
            result.detail(strings: VocoStrings(language: .en)),
            "Unable to insert text: allow Voco to use Accessibility in System Settings first."
        )
        XCTAssertTrue(client.insertions.isEmpty)
    }

    @MainActor
    func testProviderReturnsFailedSnapshotWhenInsertionFails() async throws {
        let client = FakeTextInsertionClient(
            context: .trusted(
                supportsDirectAccessibility: true,
                supportsUnicodeEvents: false,
                supportsClipboardFallback: false
            )
        )
        client.error = TextInjectionError.insertionFailed(strategy: .directAccessibility, message: "AX error -25204")
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert("hello")

        XCTAssertEqual(result.targetAppName, "Notes")
        XCTAssertEqual(result.strategy, .directAccessibility)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.detail, "辅助功能直接插入失败：AX error -25204")
        XCTAssertEqual(
            result.detail(strings: VocoStrings(language: .en)),
            "Direct Accessibility insertion failed: AX error -25204"
        )
    }
}

private struct InsertionRequest: Equatable {
    let text: String
    let strategy: TextInjectionStrategy
}

@MainActor
private final class FakeTextInsertionClient: TextInsertionClient {
    let context: TextInjectionContext
    var error: Error?
    private(set) var contextRequests = 0
    private(set) var insertions: [InsertionRequest] = []

    init(context: TextInjectionContext) {
        self.context = context
    }

    func currentContext() async -> TextInjectionContext {
        contextRequests += 1
        return context
    }

    func insert(_ text: String, using strategy: TextInjectionStrategy) async throws {
        insertions.append(InsertionRequest(text: text, strategy: strategy))

        if let error {
            throw error
        }
    }
}

private extension TextInjectionContext {
    static func trusted(
        supportsDirectAccessibility: Bool = true,
        supportsUnicodeEvents: Bool = true,
        supportsClipboardFallback: Bool = true
    ) -> TextInjectionContext {
        TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: supportsDirectAccessibility,
            supportsUnicodeEvents: supportsUnicodeEvents,
            supportsClipboardFallback: supportsClipboardFallback
        )
    }

    static func untrusted() -> TextInjectionContext {
        TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: false,
            supportsDirectAccessibility: true,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
    }
}
