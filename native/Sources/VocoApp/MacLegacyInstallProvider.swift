import Foundation
import Darwin
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

        try validateLaunchAgentsDirectoryForRemoval()

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

    private func validateLaunchAgentsDirectoryForRemoval() throws {
        let directoryURL = launchAgentURL.deletingLastPathComponent()
        var info = stat()
        guard lstat(directoryURL.path, &info) == 0 else {
            if errno == ENOENT {
                return
            }

            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw LegacyInstallCleanupError.removeFailed(
                path: launchAgentURL.path,
                underlying: POSIXError(code)
            )
        }

        if info.st_mode & S_IFMT == S_IFLNK {
            throw LegacyInstallCleanupError.unsafePath(
                path: launchAgentURL.path,
                detail: "LaunchAgents parent directory is a symlink: \(directoryURL.path)"
            )
        }
    }
}
