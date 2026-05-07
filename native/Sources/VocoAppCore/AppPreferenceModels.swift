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

public enum AppDockPresentationAction: Equatable, Sendable {
    case showInDock
    case hideFromDock
}

public struct AppDockPresentationPolicy: Equatable, Sendable {
    public let displayInDockEnabled: Bool

    public init(displayInDockEnabled: Bool) {
        self.displayInDockEnabled = displayInDockEnabled
    }

    public var action: AppDockPresentationAction {
        displayInDockEnabled ? .showInDock : .hideFromDock
    }
}

@MainActor
public protocol AppPreferenceStoring: AnyObject {
    var silentLaunchEnabled: Bool { get }
    var displayInDockEnabled: Bool { get }

    func saveSilentLaunchEnabled(_ enabled: Bool)
    func saveDisplayInDockEnabled(_ enabled: Bool)
}

public final class NoOpAppPreferenceStore: AppPreferenceStoring {
    public init() {}

    public var silentLaunchEnabled: Bool {
        false
    }

    public var displayInDockEnabled: Bool {
        false
    }

    public func saveSilentLaunchEnabled(_ enabled: Bool) {}

    public func saveDisplayInDockEnabled(_ enabled: Bool) {}
}
