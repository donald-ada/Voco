import XCTest
@testable import VocoAppCore

final class PermissionModelsTests: XCTestCase {
    func testPermissionKindsOnlyIncludeRequiredVoiceInputPermissions() {
        XCTAssertEqual(PermissionKind.allCases, [.microphone, .accessibility])
    }

    func testPermissionKindsExposeUserVisibleMetadata() {
        XCTAssertEqual(PermissionKind.microphone.title, "麦克风")
        XCTAssertEqual(PermissionKind.microphone.systemImage, "mic")
        XCTAssertEqual(PermissionKind.microphone.recoveryActionTitle, "打开麦克风设置")
        XCTAssertEqual(
            PermissionKind.microphone.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )

        XCTAssertEqual(PermissionKind.accessibility.title, "辅助功能")
        XCTAssertEqual(PermissionKind.accessibility.systemImage, "accessibility")
        XCTAssertEqual(
            PermissionKind.accessibility.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testGrantStateSummariesAreUserVisible() {
        XCTAssertTrue(PermissionGrantState.granted.isGranted)
        XCTAssertFalse(PermissionGrantState.notDetermined.isGranted)
        XCTAssertFalse(PermissionGrantState.denied.isGranted)
        XCTAssertFalse(PermissionGrantState.restricted.isGranted)
        XCTAssertFalse(PermissionGrantState.unknown.isGranted)

        XCTAssertEqual(PermissionGrantState.granted.title, "已允许")
        XCTAssertEqual(PermissionGrantState.notDetermined.title, "未决定")
        XCTAssertEqual(PermissionGrantState.denied.title, "已拒绝")
        XCTAssertEqual(PermissionGrantState.restricted.title, "受限制")
        XCTAssertEqual(PermissionGrantState.unknown.title, "未知")
    }

    func testPermissionSummaryRequiresAllRequiredPermissions() {
        let summary = PermissionSummary(
            snapshots: [
                .microphone(.granted),
                .accessibility(.denied)
            ]
        )

        XCTAssertFalse(summary.allRequiredGranted)
        XCTAssertEqual(summary.missingRequiredPermissions, [.accessibility])
    }

    func testPermissionSummaryPassesWhenVoiceInputPermissionsAreGranted() {
        let summary = PermissionSummary(
            snapshots: [
                .microphone(.granted),
                .accessibility(.granted)
            ]
        )

        XCTAssertTrue(summary.allRequiredGranted)
        XCTAssertTrue(summary.missingRequiredPermissions.isEmpty)
    }
}
