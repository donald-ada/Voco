import XCTest
@testable import VocoAppCore

final class InstallLocationModelsTests: XCTestCase {
    func testInstallLocationSnapshotUsesEnglishCopy() {
        let snapshot = InstallLocationCheck.snapshot(
            forAppBundlePath: "/Applications/Voco.app",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.title, "Installed")
        XCTAssertEqual(snapshot.detail, "Voco is running from /Applications/Voco.app and can be used for launch at login.")
    }
}
