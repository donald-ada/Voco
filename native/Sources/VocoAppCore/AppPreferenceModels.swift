import Foundation

public enum AppLaunchPresentationAction: Equatable, Sendable {
    case showSettingsWindow
    case menuBarOnly
}

public struct AppLaunchPresentationPolicy: Equatable, Sendable {
    public let silentLaunchEnabled: Bool

    public init(silentLaunchEnabled: Bool) {
        self.silentLaunchEnabled = silentLaunchEnabled
    }

    public var action: AppLaunchPresentationAction {
        silentLaunchEnabled ? .menuBarOnly : .showSettingsWindow
    }
}

@MainActor
public protocol AppPreferenceStoring: AnyObject {
    var silentLaunchEnabled: Bool { get }

    func saveSilentLaunchEnabled(_ enabled: Bool)
}

public final class NoOpAppPreferenceStore: AppPreferenceStoring {
    public init() {}

    public var silentLaunchEnabled: Bool {
        false
    }

    public func saveSilentLaunchEnabled(_ enabled: Bool) {}
}
