import Foundation

public enum InstallLocationStatus: Equatable, Sendable {
    case final
    case mountedImage
    case unknown

    public var isFinal: Bool {
        self == .final
    }
}

public struct InstallLocationSnapshot: Equatable, Sendable {
    public let status: InstallLocationStatus
    public let appBundlePath: String
    public let title: String
    public let detail: String
    public let warningTitle: String?
    public let warningDetail: String?

    public init(
        status: InstallLocationStatus,
        appBundlePath: String,
        title: String,
        detail: String,
        warningTitle: String? = nil,
        warningDetail: String? = nil
    ) {
        self.status = status
        self.appBundlePath = appBundlePath
        self.title = title
        self.detail = detail
        self.warningTitle = warningTitle
        self.warningDetail = warningDetail
    }

    public var allowsLaunchAtLogin: Bool {
        status != .mountedImage
    }

    public static let unknown = InstallLocationSnapshot(
        status: .unknown,
        appBundlePath: "",
        title: "运行位置未知",
        detail: "尚未读取 Voco.app 的运行位置。"
    )
}

public enum InstallLocationCheck {
    public static func snapshot(forAppBundlePath rawPath: String) -> InstallLocationSnapshot {
        let path = normalized(rawPath)

        if isMountedImagePath(path) {
            return InstallLocationSnapshot(
                status: .mountedImage,
                appBundlePath: path,
                title: "磁盘映像",
                detail: "Voco 当前从 \(path) 运行，这不是最终安装位置。",
                warningTitle: "从磁盘映像运行",
                warningDetail: "请先把 Voco.app 移动到 /Applications，再开启登录时启动。你仍可临时试用当前会话。"
            )
        }

        if isApplicationsPath(path) {
            return InstallLocationSnapshot(
                status: .final,
                appBundlePath: path,
                title: "已安装",
                detail: "Voco 当前从 \(path) 运行，可用于登录时启动。"
            )
        }

        return InstallLocationSnapshot(
            status: .unknown,
            appBundlePath: path,
            title: "运行位置未确认",
            detail: "Voco 当前从 \(path) 运行。建议移动到 /Applications 后再开启登录时启动。"
        )
    }

    private static func normalized(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func isMountedImagePath(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/") && !isApplicationsPath(path)
    }

    private static func isApplicationsPath(_ path: String) -> Bool {
        if path == "/Applications/Voco.app" || path.hasPrefix("/Applications/") {
            return true
        }

        let components = path.split(separator: "/").map(String.init)
        return components.count >= 4 &&
            components[0] == "Users" &&
            components[2] == "Applications"
    }
}

public protocol InstallLocationProviding: Sendable {
    func currentInstallLocation() -> InstallLocationSnapshot
}

public struct StaticInstallLocationProvider: InstallLocationProviding {
    private let snapshot: InstallLocationSnapshot

    public init(snapshot: InstallLocationSnapshot = .unknown) {
        self.snapshot = snapshot
    }

    public func currentInstallLocation() -> InstallLocationSnapshot {
        snapshot
    }
}
