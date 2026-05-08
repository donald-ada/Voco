import Foundation

public enum LegacyInstallStatus: Equatable, Sendable {
    case notFound
    case detected
    case removalFailed(String)
}

public struct LegacyInstallSnapshot: Equatable, Sendable {
    public static let launchAgentFileName = "com.voco.daemon.plist"

    public let status: LegacyInstallStatus
    public let launchAgentURL: URL
    public let title: String
    public let detail: String

    public init(
        status: LegacyInstallStatus,
        launchAgentURL: URL,
        title: String,
        detail: String
    ) {
        self.status = status
        self.launchAgentURL = launchAgentURL
        self.title = title
        self.detail = detail
    }

    public var launchAgentPath: String {
        launchAgentURL.path
    }

    public var requiresUserAction: Bool {
        switch status {
        case .notFound:
            false
        case .detected, .removalFailed:
            true
        }
    }

    public var systemImage: String {
        switch status {
        case .notFound:
            "checkmark.circle"
        case .detected:
            "exclamationmark.triangle.fill"
        case .removalFailed:
            "xmark.octagon.fill"
        }
    }

    public static func knownLaunchAgentURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent(launchAgentFileName, isDirectory: false)
            .standardizedFileURL
    }

    public static func detected(
        homeDirectory: URL,
        strings: VocoStrings = VocoStrings()
    ) -> LegacyInstallSnapshot {
        detected(launchAgentURL: knownLaunchAgentURL(homeDirectory: homeDirectory), strings: strings)
    }

    public static func detected(
        launchAgentURL: URL,
        strings: VocoStrings = VocoStrings()
    ) -> LegacyInstallSnapshot {
        LegacyInstallSnapshot(
            status: .detected,
            launchAgentURL: launchAgentURL,
            title: strings.legacyInstall.detectedTitle,
            detail: strings.legacyInstall.detectedDetail(path: launchAgentURL.path)
        )
    }

    public static func notFound(
        launchAgentURL: URL,
        strings: VocoStrings = VocoStrings()
    ) -> LegacyInstallSnapshot {
        LegacyInstallSnapshot(
            status: .notFound,
            launchAgentURL: launchAgentURL,
            title: strings.legacyInstall.notFoundTitle,
            detail: strings.legacyInstall.notFoundDetail(path: launchAgentURL.path)
        )
    }

    public static func failed(
        launchAgentURL: URL,
        message: String,
        strings: VocoStrings = VocoStrings()
    ) -> LegacyInstallSnapshot {
        LegacyInstallSnapshot(
            status: .removalFailed(message),
            launchAgentURL: launchAgentURL,
            title: strings.legacyInstall.removalFailedTitle,
            detail: message
        )
    }
}

public enum LegacyInstallCleanupError: LocalizedError {
    case removeFailed(path: String, underlying: Error)
    case unsafePath(path: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .removeFailed(let path, let underlying):
            "移除旧版 LaunchAgent 失败：\(path)；OS error: \(underlying.localizedDescription)"
        case .unsafePath(let path, let detail):
            "移除旧版 LaunchAgent 失败：\(path)；safety error: \(detail)"
        }
    }
}

@MainActor
public protocol LegacyInstallProviding {
    func currentSnapshot(strings: VocoStrings) -> LegacyInstallSnapshot
    func removeKnownLaunchAgent(strings: VocoStrings) async throws -> LegacyInstallSnapshot
}

public extension LegacyInstallProviding {
    func currentSnapshot() -> LegacyInstallSnapshot {
        currentSnapshot(strings: VocoStrings())
    }

    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot {
        try await removeKnownLaunchAgent(strings: VocoStrings())
    }
}

public struct StaticLegacyInstallProvider: LegacyInstallProviding {
    private let snapshot: LegacyInstallSnapshot

    public init(
        snapshot: LegacyInstallSnapshot = .notFound(
            launchAgentURL: LegacyInstallSnapshot.knownLaunchAgentURL(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        )
    ) {
        self.snapshot = snapshot
    }

    public func currentSnapshot(strings: VocoStrings) -> LegacyInstallSnapshot {
        snapshot.localized(strings: strings)
    }

    public func removeKnownLaunchAgent(strings: VocoStrings) async throws -> LegacyInstallSnapshot {
        snapshot.localized(strings: strings)
    }
}

private extension LegacyInstallSnapshot {
    func localized(strings: VocoStrings) -> LegacyInstallSnapshot {
        switch status {
        case .notFound:
            .notFound(launchAgentURL: launchAgentURL, strings: strings)
        case .detected:
            .detected(launchAgentURL: launchAgentURL, strings: strings)
        case .removalFailed(let message):
            .failed(launchAgentURL: launchAgentURL, message: message, strings: strings)
        }
    }
}
