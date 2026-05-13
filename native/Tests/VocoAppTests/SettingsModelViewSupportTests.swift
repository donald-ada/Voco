import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class SettingsModelViewSupportTests: XCTestCase {
    func testVolcengineSelectionUsesCredentialPanel() {
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .volcengine,
                localModelStatus: .ready
            ),
            .volcengineCredentials
        )
    }

    func testLocalSelectionUsesDownloadPanelUntilReady() {
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .localRecommended,
                localModelStatus: .notDownloaded
            ),
            .localModelDownload
        )
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .localRecommended,
                localModelStatus: .downloading(
                    LocalSpeechModelDownloadProgress(bytesWritten: 4, totalBytes: 10)
                )
            ),
            .localModelDownload
        )
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .localRecommended,
                localModelStatus: .verifying
            ),
            .localModelDownload
        )
    }

    func testLocalSelectionUsesReadyPanelWhenModelInstalled() {
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .localRecommended,
                localModelStatus: .ready
            ),
            .localModelReady
        )
    }

    func testLocalSelectionUsesFailurePanelForUnavailableStates() {
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .localRecommended,
                localModelStatus: .failed("checksum mismatch")
            ),
            .localModelFailed
        )
        XCTAssertEqual(
            ModelSourcePanelKind.resolve(
                selectedProviderID: .localRecommended,
                localModelStatus: .unavailable("missing runtime")
            ),
            .localModelFailed
        )
    }
}
