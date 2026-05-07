import Foundation
import XCTest
@testable import VocoAppCore

final class LegacyInstallModelsTests: XCTestCase {
    func testKnownLaunchAgentPathExpandsInsideUserLibraryOnly() {
        let home = URL(fileURLWithPath: "/Users/alice")

        let snapshot = LegacyInstallSnapshot.detected(homeDirectory: home)

        XCTAssertEqual(snapshot.launchAgentPath, "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        XCTAssertEqual(snapshot.launchAgentURL.path, "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        XCTAssertEqual(snapshot.status, .detected)
        XCTAssertEqual(snapshot.title, "检测到旧版后台启动项")
        XCTAssertTrue(snapshot.detail.contains("com.voco.daemon.plist"))
        XCTAssertTrue(snapshot.requiresUserAction)
    }

    func testNoLegacyLaunchAgentHasNoUserAction() {
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")

        let snapshot = LegacyInstallSnapshot.notFound(launchAgentURL: launchAgent)

        XCTAssertEqual(snapshot.status, .notFound)
        XCTAssertEqual(snapshot.launchAgentPath, launchAgent.path)
        XCTAssertEqual(snapshot.title, "未检测到旧版启动项")
        XCTAssertFalse(snapshot.requiresUserAction)
    }

    func testRemovalFailureIncludesExactPathAndUnderlyingOSError() {
        let path = "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist"
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EACCES),
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )

        let error = LegacyInstallCleanupError.removeFailed(path: path, underlying: underlying)

        XCTAssertTrue(error.localizedDescription.contains(path))
        XCTAssertTrue(error.localizedDescription.contains("Permission denied"))
    }

    @MainActor
    func testCoordinatorRefreshesLegacyInstallSnapshot() {
        let provider = FakeLegacyInstallProvider(
            current: .detected(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
        )
        let coordinator = AppCoordinator(legacyInstallProvider: provider)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.legacyInstall.status, .detected)
        XCTAssertEqual(provider.refreshCount, 1)
    }

    @MainActor
    func testCoordinatorRemovalIsExplicitAndRefreshesAfterSuccess() async {
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        let provider = FakeLegacyInstallProvider(
            current: .detected(homeDirectory: URL(fileURLWithPath: "/Users/alice")),
            afterRemoval: .notFound(launchAgentURL: launchAgent)
        )
        let coordinator = AppCoordinator(legacyInstallProvider: provider)

        await coordinator.removeLegacyLaunchAgentFromUserAction()

        XCTAssertEqual(provider.removeCount, 1)
        XCTAssertEqual(coordinator.legacyInstall.status, .notFound)
        XCTAssertNil(coordinator.lastErrorMessage)
    }

    @MainActor
    func testCoordinatorIgnoresDuplicateLegacyRemovalWhileInFlight() async throws {
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        let provider = SlowLegacyInstallProvider(
            current: .detected(homeDirectory: URL(fileURLWithPath: "/Users/alice")),
            result: .notFound(launchAgentURL: launchAgent)
        )
        let coordinator = AppCoordinator(legacyInstallProvider: provider)

        let firstRemoval = Task { await coordinator.removeLegacyLaunchAgentFromUserAction() }
        await provider.waitForRemoveCount(1)
        XCTAssertTrue(coordinator.isRemovingLegacyLaunchAgent)

        let duplicateRemoval = Task { await coordinator.removeLegacyLaunchAgentFromUserAction() }
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(provider.removeCount, 1)

        await firstRemoval.value
        await duplicateRemoval.value

        XCTAssertEqual(provider.removeCount, 1)
        XCTAssertFalse(coordinator.isRemovingLegacyLaunchAgent)
        XCTAssertEqual(coordinator.legacyInstall.status, .notFound)
    }

    @MainActor
    func testCoordinatorRemovalFailureSurfacesPathAndKeepsWarningVisible() async {
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EACCES),
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )
        let provider = FakeLegacyInstallProvider(
            current: .detected(homeDirectory: URL(fileURLWithPath: "/Users/alice")),
            removalError: LegacyInstallCleanupError.removeFailed(path: launchAgent.path, underlying: underlying)
        )
        let coordinator = AppCoordinator(legacyInstallProvider: provider)

        await coordinator.removeLegacyLaunchAgentFromUserAction()

        XCTAssertEqual(provider.removeCount, 1)
        XCTAssertEqual(coordinator.legacyInstall.status, .removalFailed(coordinator.lastErrorMessage ?? ""))
        XCTAssertTrue(coordinator.legacyInstall.requiresUserAction)
        XCTAssertTrue(coordinator.lastErrorMessage?.contains(launchAgent.path) == true)
        XCTAssertTrue(coordinator.lastErrorMessage?.contains("Permission denied") == true)
    }

}

@MainActor
private final class FakeLegacyInstallProvider: LegacyInstallProviding {
    private var current: LegacyInstallSnapshot
    private let afterRemoval: LegacyInstallSnapshot?
    private let removalError: Error?
    private(set) var refreshCount = 0
    private(set) var removeCount = 0

    init(
        current: LegacyInstallSnapshot = .notFound(
            launchAgentURL: URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        ),
        afterRemoval: LegacyInstallSnapshot? = nil,
        removalError: Error? = nil
    ) {
        self.current = current
        self.afterRemoval = afterRemoval
        self.removalError = removalError
    }

    func currentSnapshot() -> LegacyInstallSnapshot {
        refreshCount += 1
        return current
    }

    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot {
        removeCount += 1
        if let removalError {
            throw removalError
        }
        if let afterRemoval {
            current = afterRemoval
        }
        return current
    }
}

@MainActor
private final class SlowLegacyInstallProvider: LegacyInstallProviding {
    private var current: LegacyInstallSnapshot
    private let result: LegacyInstallSnapshot
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var removeCount = 0

    init(current: LegacyInstallSnapshot, result: LegacyInstallSnapshot) {
        self.current = current
        self.result = result
    }

    func currentSnapshot() -> LegacyInstallSnapshot {
        current
    }

    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot {
        removeCount += 1
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
        try? await Task.sleep(nanoseconds: 100_000_000)
        current = result
        return result
    }

    func waitForRemoveCount(_ expectedCount: Int) async {
        if removeCount >= expectedCount {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
