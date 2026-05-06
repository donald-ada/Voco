import Foundation
import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class MacLegacyInstallProviderTests: XCTestCase {
    @MainActor
    func testProviderDetectsKnownUserLaunchAgent() throws {
        let home = try makeTemporaryHome()
        let launchAgent = LegacyInstallSnapshot.knownLaunchAgentURL(homeDirectory: home)
        try FileManager.default.createDirectory(
            at: launchAgent.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: launchAgent)
        defer { try? FileManager.default.removeItem(at: home) }

        let provider = MacLegacyInstallProvider(homeDirectory: home)

        let snapshot = provider.currentSnapshot()

        XCTAssertEqual(snapshot.status, .detected)
        XCTAssertEqual(snapshot.launchAgentPath, launchAgent.path)
    }

    @MainActor
    func testProviderRemovesOnlyKnownUserLaunchAgent() async throws {
        let home = try makeTemporaryHome()
        let launchAgent = LegacyInstallSnapshot.knownLaunchAgentURL(homeDirectory: home)
        let sibling = launchAgent.deletingLastPathComponent().appendingPathComponent("com.example.other.plist")
        try FileManager.default.createDirectory(
            at: launchAgent.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: launchAgent)
        try Data("other".utf8).write(to: sibling)
        defer { try? FileManager.default.removeItem(at: home) }

        let provider = MacLegacyInstallProvider(homeDirectory: home)

        let snapshot = try await provider.removeKnownLaunchAgent()

        XCTAssertEqual(snapshot.status, .notFound)
        XCTAssertFalse(FileManager.default.fileExists(atPath: launchAgent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    @MainActor
    func testProviderRemovalFailureIncludesExactPathAndOSError() async throws {
        let home = try makeTemporaryHome()
        let launchAgent = LegacyInstallSnapshot.knownLaunchAgentURL(homeDirectory: home)
        let launchAgentsDirectory = launchAgent.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: launchAgent)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: launchAgentsDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchAgentsDirectory.path)
            try? FileManager.default.removeItem(at: home)
        }

        let provider = MacLegacyInstallProvider(homeDirectory: home)

        do {
            _ = try await provider.removeKnownLaunchAgent()
            XCTFail("Expected removal to fail when LaunchAgents directory is not writable")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains(launchAgent.path))
            XCTAssertTrue(error.localizedDescription.contains("OS error"))
        }
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voco-legacy-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
