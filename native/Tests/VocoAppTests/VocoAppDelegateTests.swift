import AppKit
import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class VocoAppDelegateTests: XCTestCase {
    func testDockReopenShowsExistingSettingsWindowWithoutDefaultReopenHandling() {
        let coordinator = AppCoordinator()
        let delegate = VocoAppDelegate()
        var presentedCoordinator: AppCoordinator?
        delegate.coordinator = coordinator
        delegate.showSettingsWindow = { presentedCoordinator = $0 }

        let shouldHandle = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: true
        )

        XCTAssertFalse(shouldHandle)
        XCTAssertTrue(presentedCoordinator === coordinator)
    }

    func testDuplicateLaunchActivatesExistingInstanceAndTerminatesCurrentOne() {
        let coordinator = AppCoordinator()
        let delegate = VocoAppDelegate()
        var activatedPID: pid_t?
        var postedShowSettingsNotification = false
        var terminatedCurrentApplication = false
        delegate.coordinator = coordinator
        delegate.currentProcessIdentifier = 20
        delegate.currentBundleIdentifier = "com.voco.app"
        delegate.runningApplications = {
            [
                VocoRunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.voco.app"),
                VocoRunningApplicationSnapshot(processIdentifier: 20, bundleIdentifier: "com.voco.app")
            ]
        }
        delegate.activateRunningApplication = { activatedPID = $0 }
        delegate.postShowSettingsWindowNotification = {
            postedShowSettingsNotification = true
        }
        delegate.terminateCurrentApplication = {
            terminatedCurrentApplication = true
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(activatedPID, 10)
        XCTAssertTrue(postedShowSettingsNotification)
        XCTAssertTrue(terminatedCurrentApplication)
    }

    func testFirstLaunchShowsSettingsWindowWhenSilentLaunchIsDisabled() {
        let coordinator = AppCoordinator()
        let delegate = VocoAppDelegate()
        var presentedCoordinator: AppCoordinator?
        delegate.coordinator = coordinator
        delegate.showSettingsWindow = { presentedCoordinator = $0 }
        delegate.currentProcessIdentifier = 10
        delegate.currentBundleIdentifier = "com.voco.app"
        delegate.runningApplications = {
            [
                VocoRunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.voco.app")
            ]
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertTrue(presentedCoordinator === coordinator)
    }

    func testFirstLaunchDoesNotShowSettingsWindowWhenSilentLaunchIsEnabled() {
        let coordinator = AppCoordinator()
        coordinator.setSilentLaunchEnabled(true)
        let delegate = VocoAppDelegate()
        var presentedCoordinator: AppCoordinator?
        delegate.coordinator = coordinator
        delegate.showSettingsWindow = { presentedCoordinator = $0 }
        delegate.currentProcessIdentifier = 10
        delegate.currentBundleIdentifier = "com.voco.app"
        delegate.runningApplications = {
            [
                VocoRunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.voco.app")
            ]
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertNil(presentedCoordinator)
    }

    func testOlderInstanceDoesNotTerminateWhenNewerInstanceExists() {
        let delegate = VocoAppDelegate()
        var activatedPID: pid_t?
        var terminatedCurrentApplication = false
        delegate.currentProcessIdentifier = 10
        delegate.currentBundleIdentifier = "com.voco.app"
        delegate.runningApplications = {
            [
                VocoRunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.voco.app"),
                VocoRunningApplicationSnapshot(processIdentifier: 20, bundleIdentifier: "com.voco.app")
            ]
        }
        delegate.activateRunningApplication = { activatedPID = $0 }
        delegate.terminateCurrentApplication = {
            terminatedCurrentApplication = true
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertNil(activatedPID)
        XCTAssertFalse(terminatedCurrentApplication)
    }

    func testLaunchSchedulesDelayedDuplicateCheckForLateWorkspaceRegistration() {
        let delegate = VocoAppDelegate()
        var activatedPID: pid_t?
        var terminatedCurrentApplication = false
        var runningApplications = [
            VocoRunningApplicationSnapshot(processIdentifier: 20, bundleIdentifier: "com.voco.app")
        ]
        var delayedCheck: (@MainActor () -> Void)?
        delegate.currentProcessIdentifier = 20
        delegate.currentBundleIdentifier = "com.voco.app"
        delegate.runningApplications = { runningApplications }
        delegate.activateRunningApplication = { activatedPID = $0 }
        delegate.terminateCurrentApplication = {
            terminatedCurrentApplication = true
        }
        delegate.scheduleDelayedSingleInstanceCheck = { check in
            delayedCheck = check
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        runningApplications = [
            VocoRunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.voco.app"),
            VocoRunningApplicationSnapshot(processIdentifier: 20, bundleIdentifier: "com.voco.app")
        ]
        delayedCheck?()

        XCTAssertEqual(activatedPID, 10)
        XCTAssertTrue(terminatedCurrentApplication)
    }

    func testFirstLaunchDoesNotTerminateCurrentApplication() {
        let delegate = VocoAppDelegate()
        var terminatedCurrentApplication = false
        delegate.currentProcessIdentifier = 10
        delegate.currentBundleIdentifier = "com.voco.app"
        delegate.runningApplications = {
            [
                VocoRunningApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.voco.app")
            ]
        }
        delegate.terminateCurrentApplication = {
            terminatedCurrentApplication = true
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertFalse(terminatedCurrentApplication)
    }
}
