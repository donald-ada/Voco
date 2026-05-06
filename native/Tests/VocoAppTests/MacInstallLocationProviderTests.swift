import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class MacInstallLocationProviderTests: XCTestCase {
    func testProviderMapsBundleURLThroughCoreInstallLocationCheck() {
        let provider = MacInstallLocationProvider(
            bundleURL: URL(fileURLWithPath: "/Volumes/Voco/Voco.app")
        )

        let snapshot = provider.currentInstallLocation()

        XCTAssertEqual(snapshot.status, .mountedImage)
        XCTAssertEqual(snapshot.warningTitle, "从磁盘映像运行")
        XCTAssertFalse(snapshot.allowsLaunchAtLogin)
    }
}
