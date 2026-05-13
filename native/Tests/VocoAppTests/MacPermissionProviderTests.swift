import Dispatch
import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacPermissionProviderTests: XCTestCase {
    func testRequestMicrophoneAccessAcceptsBackgroundCallback() async {
        let callbackQueue = DispatchQueue(label: "test.voco.permission-callback")
        let provider = MacPermissionProvider(
            microphoneAccessRequester: { completion in
                callbackQueue.async {
                    completion(true)
                }
            },
            microphoneStateReader: { .granted },
            accessibilityStateReader: { .denied }
        )

        let snapshots = await provider.requestMicrophoneAccess()
        let expected: [PermissionSnapshot] = [
            .microphone(.granted),
            .accessibility(.denied)
        ]

        XCTAssertEqual(snapshots, expected)
    }
}
