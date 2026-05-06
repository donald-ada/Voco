import XCTest
@testable import VocoAppCore

final class OnboardingModelsTests: XCTestCase {
    func testStepOrderingMatchesFirstRunFlow() {
        XCTAssertEqual(
            OnboardingStepID.ordered,
            [
                .microphone,
                .accessibility,
                .inputMonitoring,
                .asrSetup,
                .launchAtLogin,
                .hotkeyTest
            ]
        )
    }

    func testPermissionStepsExposeStatusRetryAndRecoveryActions() throws {
        let snapshot = OnboardingSnapshot.make(
            permissions: [
                .microphone(.notDetermined),
                .accessibility(.denied),
                .inputMonitoring(.restricted)
            ],
            transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            launchAtLoginState: .enabled,
            hasSkippedLaunchAtLogin: false,
            hotkeyRuntimeState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            hasVerifiedHotkey: true
        )

        for stepID in [OnboardingStepID.microphone, .accessibility, .inputMonitoring] {
            let step = try XCTUnwrap(snapshot.step(id: stepID))
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.detail.isEmpty)
            XCTAssertFalse(step.systemImage.isEmpty)
            XCTAssertFalse(step.status.title.isEmpty)
            XCTAssertNotNil(step.retryAction)
            XCTAssertNotNil(step.recoveryAction)
            XCTAssertNotNil(step.recoveryAction?.settingsURLString)
        }

        XCTAssertEqual(snapshot.step(id: .microphone)?.retryAction?.title, "请求麦克风权限")
        XCTAssertEqual(snapshot.step(id: .accessibility)?.retryAction?.title, "重新检查权限")
    }

    func testASRLaunchAtLoginAndHotkeyStepsReflectRuntimeState() {
        let missingCredentialSnapshot = OnboardingSnapshot.make(
            permissions: grantedPermissions,
            transcriptionCredentials: .missing(provider: .doubao),
            launchAtLoginState: .disabled,
            hasSkippedLaunchAtLogin: false,
            hotkeyRuntimeState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            hasVerifiedHotkey: false
        )

        XCTAssertEqual(missingCredentialSnapshot.step(id: .asrSetup)?.status, .actionNeeded)
        XCTAssertEqual(missingCredentialSnapshot.step(id: .launchAtLogin)?.status, .actionNeeded)
        XCTAssertEqual(missingCredentialSnapshot.step(id: .hotkeyTest)?.status, .actionNeeded)
        XCTAssertFalse(missingCredentialSnapshot.isComplete)

        let completeSnapshot = OnboardingSnapshot.make(
            permissions: grantedPermissions,
            transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            launchAtLoginState: .disabled,
            hasSkippedLaunchAtLogin: true,
            hotkeyRuntimeState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            hasVerifiedHotkey: true
        )

        XCTAssertEqual(completeSnapshot.step(id: .asrSetup)?.status, .complete)
        XCTAssertEqual(completeSnapshot.step(id: .launchAtLogin)?.status, .skipped)
        XCTAssertEqual(completeSnapshot.step(id: .hotkeyTest)?.status, .complete)
        XCTAssertTrue(completeSnapshot.isComplete)
    }

    func testHotkeyStepIsBlockedWhenPermissionsOrRuntimeAreUnavailable() {
        let permissionBlockedSnapshot = OnboardingSnapshot.make(
            permissions: [
                .microphone(.granted),
                .accessibility(.denied),
                .inputMonitoring(.granted)
            ],
            transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            launchAtLoginState: .enabled,
            hasSkippedLaunchAtLogin: false,
            hotkeyRuntimeState: .permissionNeeded,
            hotkeyBinding: .default,
            hotkeyMode: .pressAndHold,
            hasVerifiedHotkey: false
        )

        XCTAssertEqual(permissionBlockedSnapshot.step(id: .hotkeyTest)?.status, .blocked)
        XCTAssertFalse(permissionBlockedSnapshot.isComplete)

        let failedRuntimeSnapshot = OnboardingSnapshot.make(
            permissions: grantedPermissions,
            transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            launchAtLoginState: .enabled,
            hasSkippedLaunchAtLogin: false,
            hotkeyRuntimeState: .failed("event tap failed"),
            hotkeyBinding: .default,
            hotkeyMode: .pressAndHold,
            hasVerifiedHotkey: false
        )

        XCTAssertEqual(failedRuntimeSnapshot.step(id: .hotkeyTest)?.status, .blocked)
        XCTAssertTrue(failedRuntimeSnapshot.step(id: .hotkeyTest)?.statusDetail.contains("event tap failed") == true)
    }

    func testInstallLocationDetectsMountedImagesAndFinalLocations() {
        let mountedImage = InstallLocationCheck.snapshot(forAppBundlePath: "/Volumes/Voco/Voco.app")
        XCTAssertEqual(mountedImage.status, .mountedImage)
        XCTAssertEqual(mountedImage.warningTitle, "从磁盘映像运行")
        XCTAssertFalse(mountedImage.allowsLaunchAtLogin)
        XCTAssertTrue(mountedImage.warningDetail?.contains("/Applications") == true)

        let globalApplications = InstallLocationCheck.snapshot(forAppBundlePath: "/Applications/Voco.app")
        XCTAssertEqual(globalApplications.status, .final)
        XCTAssertTrue(globalApplications.allowsLaunchAtLogin)
        XCTAssertNil(globalApplications.warningTitle)

        let userApplications = InstallLocationCheck.snapshot(forAppBundlePath: "/Users/alice/Applications/Voco.app")
        XCTAssertEqual(userApplications.status, .final)
        XCTAssertTrue(userApplications.allowsLaunchAtLogin)

        let unknown = InstallLocationCheck.snapshot(forAppBundlePath: "/tmp/Voco.app")
        XCTAssertEqual(unknown.status, .unknown)
        XCTAssertTrue(unknown.detail.contains("/tmp/Voco.app"))
    }

    func testCompletionMigrationUsesExplicitStoredDefaultsValue() {
        XCTAssertTrue(
            OnboardingCompletionMigration.resolvedCompletion(
                storedValue: true,
                permissions: [],
                transcriptionCredentials: .missing(provider: .doubao)
            )
        )
        XCTAssertFalse(
            OnboardingCompletionMigration.resolvedCompletion(
                storedValue: false,
                permissions: grantedPermissions,
                transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef")
            )
        )
    }

    func testCompletionMigrationPreservesConfiguredUpgradeWhenDefaultsKeyIsMissing() {
        XCTAssertTrue(
            OnboardingCompletionMigration.resolvedCompletion(
                storedValue: nil,
                permissions: grantedPermissions,
                transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef")
            )
        )
    }

    func testCompletionMigrationKeepsFirstRunWhenDefaultsKeyIsMissingAndSetupIsIncomplete() {
        XCTAssertFalse(
            OnboardingCompletionMigration.resolvedCompletion(
                storedValue: nil,
                permissions: grantedPermissions,
                transcriptionCredentials: .missing(provider: .doubao)
            )
        )
        XCTAssertFalse(
            OnboardingCompletionMigration.resolvedCompletion(
                storedValue: nil,
                permissions: [
                    .microphone(.granted),
                    .accessibility(.denied),
                    .inputMonitoring(.granted)
                ],
                transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef")
            )
        )
    }

    private var grantedPermissions: [PermissionSnapshot] {
        [
            .microphone(.granted),
            .accessibility(.granted),
            .inputMonitoring(.granted)
        ]
    }
}
