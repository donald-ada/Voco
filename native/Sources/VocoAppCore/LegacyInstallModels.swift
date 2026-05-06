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

    public static func detected(homeDirectory: URL) -> LegacyInstallSnapshot {
        detected(launchAgentURL: knownLaunchAgentURL(homeDirectory: homeDirectory))
    }

    public static func detected(launchAgentURL: URL) -> LegacyInstallSnapshot {
        LegacyInstallSnapshot(
            status: .detected,
            launchAgentURL: launchAgentURL,
            title: "检测到旧版后台启动项",
            detail: "检测到旧版 LaunchAgent：\(launchAgentURL.path)。如已改用 native Voco，可在这里移除该用户级启动项；不会触碰系统级 LaunchAgents，也不需要 sudo。"
        )
    }

    public static func notFound(launchAgentURL: URL) -> LegacyInstallSnapshot {
        LegacyInstallSnapshot(
            status: .notFound,
            launchAgentURL: launchAgentURL,
            title: "未检测到旧版启动项",
            detail: "未发现 \(launchAgentURL.path)。native Voco 使用登录项，不会安装旧版 LaunchAgent plist。"
        )
    }

    public static func failed(launchAgentURL: URL, message: String) -> LegacyInstallSnapshot {
        LegacyInstallSnapshot(
            status: .removalFailed(message),
            launchAgentURL: launchAgentURL,
            title: "旧版启动项移除失败",
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
    func currentSnapshot() -> LegacyInstallSnapshot
    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot
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

    public func currentSnapshot() -> LegacyInstallSnapshot {
        snapshot
    }

    public func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot {
        snapshot
    }
}
