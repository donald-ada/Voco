import XCTest
@testable import VocoAppCore

final class VoiceInputSessionModelsTests: XCTestCase {
    func testSessionSnapshotUsesRawTranscriptPreviewWithoutGeneratedTitle() {
        let session = VoiceInputSessionSnapshot(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            transcriptText: "把总览改成主页。右侧的语音输入流程不要再占四大行，改成一行表达。",
            wordCount: 34,
            durationSeconds: 42,
            createdAt: Date(timeIntervalSince1970: 1_714_800_000),
            targetAppName: "Codex",
            providerName: "火山引擎"
        )

        XCTAssertEqual(session.previewText(maxLength: 24), "把总览改成主页。右侧的语音输入流程不要再占四大行...")
        XCTAssertFalse(session.previewText(maxLength: 24).contains("产品原型修改说明"))
        XCTAssertEqual(session.durationTitle, "42s")
    }

    func testSessionPageDefaultsToTenRowsAndReportsVisibleRange() {
        let sessions = (1...12).map { index in
            VoiceInputSessionSnapshot(
                id: UUID(),
                transcriptText: "第 \(index) 条原始转写内容",
                wordCount: index,
                durationSeconds: Double(index),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                targetAppName: nil,
                providerName: "Fake ASR"
            )
        }

        let firstPage = VoiceInputSessionPage(sessions: sessions, page: 1)
        let secondPage = VoiceInputSessionPage(sessions: sessions, page: 2)

        XCTAssertEqual(firstPage.pageSize, 10)
        XCTAssertEqual(firstPage.entries.count, 10)
        XCTAssertEqual(firstPage.visibleRangeTitle, "1-10 / 12 条")
        XCTAssertEqual(secondPage.entries.count, 2)
        XCTAssertEqual(secondPage.visibleRangeTitle, "11-12 / 12 条")
    }
}
