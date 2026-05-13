import XCTest
@testable import VocoAppCore

final class TranscriptionModelSelectionModelsTests: XCTestCase {
    func testDefaultSelectionUsesVolcengine() {
        XCTAssertEqual(TranscriptionModelSelection.default.providerID, .volcengine)
    }

    func testLocalRecommendedManifestContainsRequiredFiles() {
        let manifest = LocalSpeechModelManifest.recommended

        XCTAssertEqual(manifest.id, .recommendedSherpaOnnx)
        XCTAssertEqual(manifest.archiveFilename, "sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2")
        XCTAssertEqual(manifest.requiredFiles, ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"])
        XCTAssertEqual(manifest.expectedSHA256, "5462a1fce42693deae572af1e8c4687124b12aa85fe61ff4d3168bb5280e205f")
    }

    func testLocalModelStatusAllowsApplyOnlyWhenReady() {
        XCTAssertFalse(LocalSpeechModelStatus.notDownloaded.canApply)
        XCTAssertFalse(LocalSpeechModelStatus.downloading(LocalSpeechModelDownloadProgress(bytesWritten: 4, totalBytes: 10)).canApply)
        XCTAssertTrue(LocalSpeechModelStatus.ready.canApply)
        XCTAssertFalse(LocalSpeechModelStatus.failed("checksum mismatch").canApply)
    }

    func testModelSourceTitlesAreLocalized() {
        XCTAssertEqual(TranscriptionModelProviderID.volcengine.title(strings: VocoStrings(language: .zhHans)), "火山引擎")
        XCTAssertEqual(TranscriptionModelProviderID.volcengine.title(strings: VocoStrings(language: .en)), "Volcengine")
        XCTAssertEqual(TranscriptionModelProviderID.localRecommended.title(strings: VocoStrings(language: .zhHans)), "本地模型")
        XCTAssertEqual(TranscriptionModelProviderID.localRecommended.title(strings: VocoStrings(language: .en)), "Local Model")
    }
}
