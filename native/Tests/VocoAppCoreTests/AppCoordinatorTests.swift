import XCTest
@testable import VocoAppCore

final class AppCoordinatorTests: XCTestCase {
    @MainActor
    func testFinishingLaunchWithoutOnboardingShowsSetupState() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: false)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .needsOnboarding)
        XCTAssertEqual(coordinator.snapshot.title, "需要设置")
        XCTAssertEqual(coordinator.snapshot.systemImage, "exclamationmark.triangle")
        XCTAssertEqual(coordinator.snapshot.templateIconResourceName, "VocoMenuBarIconTemplate")
        XCTAssertTrue(coordinator.snapshot.canOpenSettings)
    }

    @MainActor
    func testFinishingLaunchWithOnboardingShowsReadyState() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.snapshot.title, "就绪")
        XCTAssertEqual(coordinator.snapshot.systemImage, "waveform")
        XCTAssertTrue(coordinator.snapshot.isRecordingActionEnabled)
    }

    @MainActor
    func testMenuRecordingToggleMovesThroughRecordingAndTranscribing() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()

        coordinator.toggleRecordingFromMenu()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(coordinator.snapshot.title, "录音中")
        XCTAssertEqual(coordinator.snapshot.systemImage, "record.circle")

        coordinator.toggleRecordingFromMenu()

        XCTAssertEqual(coordinator.status, .transcribing)
        XCTAssertEqual(coordinator.snapshot.title, "转写中")
        XCTAssertEqual(coordinator.snapshot.systemImage, "ellipsis.bubble")
    }

    @MainActor
    func testTranscriptionCompletionReturnsToReadyOrError() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()
        coordinator.toggleRecordingFromMenu()
        coordinator.toggleRecordingFromMenu()

        coordinator.finishTranscribing(result: .success)

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertNil(coordinator.lastErrorMessage)

        coordinator.fail("provider offline")

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "provider offline")
        XCTAssertEqual(coordinator.snapshot.title, "错误")
        XCTAssertEqual(coordinator.snapshot.systemImage, "xmark.octagon")
    }

    @MainActor
    func testLaunchAtLoginToggleIsStatefulForTheShell() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)

        coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(coordinator.launchAtLoginEnabled)

        coordinator.setLaunchAtLoginEnabled(false)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)
    }

    @MainActor
    func testFinishingLaunchWithMissingPermissionShowsOnboarding() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.denied),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .needsOnboarding)
        XCTAssertEqual(coordinator.permissionSummary.missingRequiredPermissions, [.microphone])
        XCTAssertFalse(coordinator.snapshot.isRecordingActionEnabled)
    }

    @MainActor
    func testRefreshingPermissionsMovesReadyAppToPermissionNeeded() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .ready)

        provider.current = [
            .microphone(.granted),
            .accessibility(.denied),
            .inputMonitoring(.granted)
        ]
        coordinator.refreshPermissions()

        XCTAssertEqual(coordinator.status, .permissionNeeded)
        XCTAssertEqual(coordinator.snapshot.title, "需要权限")
        XCTAssertEqual(coordinator.permissionSummary.missingRequiredPermissions, [.accessibility])
    }

    @MainActor
    func testRequestingMicrophonePermissionRefreshesPermissionsAndRestoresReady() async {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.notDetermined),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .needsOnboarding)

        await coordinator.requestMicrophonePermission()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.permissions, provider.requested)
        XCTAssertTrue(coordinator.permissionSummary.allRequiredGranted)
    }

    @MainActor
    func testPreparingSettingsPresentationRefreshesPermissionSnapshot() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)
        coordinator.finishLaunching()

        provider.current = [
            .microphone(.granted),
            .accessibility(.denied),
            .inputMonitoring(.denied)
        ]

        coordinator.prepareForSettingsPresentation()

        XCTAssertEqual(coordinator.permissions, provider.current)
        XCTAssertEqual(coordinator.status, .permissionNeeded)
    }
}

private final class FakePermissionProvider: PermissionProviding {
    var current: [PermissionSnapshot]
    let requested: [PermissionSnapshot]

    init(current: [PermissionSnapshot], requested: [PermissionSnapshot]) {
        self.current = current
        self.requested = requested
    }

    func currentSnapshots() -> [PermissionSnapshot] {
        current
    }

    func requestMicrophoneAccess() async -> [PermissionSnapshot] {
        requested
    }
}
