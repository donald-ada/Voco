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

    public static var unknown: InstallLocationSnapshot {
        unknown(strings: VocoStrings())
    }

    public static func unknown(strings: VocoStrings = VocoStrings()) -> InstallLocationSnapshot {
        InstallLocationSnapshot(
            status: .unknown,
            appBundlePath: "",
            title: strings.installLocation.unknownTitle,
            detail: strings.installLocation.unknownDetail
        )
    }
}

public enum InstallLocationCheck {
    public static func snapshot(
        forAppBundlePath rawPath: String,
        strings: VocoStrings = VocoStrings()
    ) -> InstallLocationSnapshot {
        let path = normalized(rawPath)

        if isMountedImagePath(path) {
            return InstallLocationSnapshot(
                status: .mountedImage,
                appBundlePath: path,
                title: strings.installLocation.mountedImageTitle,
                detail: strings.installLocation.mountedImageDetail(path: path),
                warningTitle: strings.installLocation.mountedImageWarningTitle,
                warningDetail: strings.installLocation.mountedImageWarningDetail
            )
        }

        if isApplicationsPath(path) {
            return InstallLocationSnapshot(
                status: .final,
                appBundlePath: path,
                title: strings.installLocation.installedTitle,
                detail: strings.installLocation.installedDetail(path: path)
            )
        }

        return InstallLocationSnapshot(
            status: .unknown,
            appBundlePath: path,
            title: strings.installLocation.unconfirmedTitle,
            detail: strings.installLocation.unconfirmedDetail(path: path)
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
    func currentInstallLocation(strings: VocoStrings) -> InstallLocationSnapshot
}

public extension InstallLocationProviding {
    func currentInstallLocation() -> InstallLocationSnapshot {
        currentInstallLocation(strings: VocoStrings())
    }
}

public struct StaticInstallLocationProvider: InstallLocationProviding {
    private let snapshot: InstallLocationSnapshot

    public init(snapshot: InstallLocationSnapshot = .unknown) {
        self.snapshot = snapshot
    }

    public func currentInstallLocation(strings: VocoStrings) -> InstallLocationSnapshot {
        snapshot.localized(strings: strings)
    }
}

private extension InstallLocationSnapshot {
    func localized(strings: VocoStrings) -> InstallLocationSnapshot {
        guard !appBundlePath.isEmpty else {
            return .unknown(strings: strings)
        }

        return InstallLocationCheck.snapshot(forAppBundlePath: appBundlePath, strings: strings)
    }
}
