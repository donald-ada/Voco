import Foundation
import VocoAppCore

struct MacLegacyInstallProvider: LegacyInstallProviding {
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func currentSnapshot() -> LegacyInstallSnapshot {
        if knownLaunchAgentExists {
            return .detected(launchAgentURL: launchAgentURL)
        }

        return .notFound(launchAgentURL: launchAgentURL)
    }

    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot {
        guard knownLaunchAgentExists else {
            return .notFound(launchAgentURL: launchAgentURL)
        }

        do {
            try fileManager.removeItem(at: launchAgentURL)
            return .notFound(launchAgentURL: launchAgentURL)
        } catch {
            throw LegacyInstallCleanupError.removeFailed(path: launchAgentURL.path, underlying: error)
        }
    }

    private var launchAgentURL: URL {
        LegacyInstallSnapshot.knownLaunchAgentURL(homeDirectory: homeDirectory)
    }

    private var knownLaunchAgentExists: Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: launchAgentURL.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
}
