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
}
