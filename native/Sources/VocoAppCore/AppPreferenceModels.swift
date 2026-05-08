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

public enum VoiceInputSessionRetentionPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case last100
    case last1000
    case forever

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .last100:
            "最近 100 条"
        case .last1000:
            "最近 1000 条"
        case .forever:
            "永久保留"
        }
    }

    public var detail: String {
        switch self {
        case .last100:
            "只保留最近 100 次会话。"
        case .last1000:
            "只保留最近 1000 次会话。"
        case .forever:
            "不自动清理旧会话。"
        }
    }

    public var limit: Int? {
        switch self {
        case .last100:
            100
        case .last1000:
            1000
        case .forever:
            nil
        }
    }

    public var loadLimit: Int {
        limit ?? Int.max
    }
}

@MainActor
public protocol AppPreferenceStoring: AnyObject {
    var silentLaunchEnabled: Bool { get }
    var displayInDockEnabled: Bool { get }
    var voiceInputSessionHistoryEnabled: Bool { get }
    var voiceInputSessionRetentionPolicy: VoiceInputSessionRetentionPolicy { get }

    func saveSilentLaunchEnabled(_ enabled: Bool)
    func saveDisplayInDockEnabled(_ enabled: Bool)
    func saveVoiceInputSessionHistoryEnabled(_ enabled: Bool)
    func saveVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy)
}

public final class NoOpAppPreferenceStore: AppPreferenceStoring {
    public init() {}

    public var silentLaunchEnabled: Bool {
        false
    }

    public var displayInDockEnabled: Bool {
        false
    }

    public var voiceInputSessionHistoryEnabled: Bool {
        true
    }

    public var voiceInputSessionRetentionPolicy: VoiceInputSessionRetentionPolicy {
        .last1000
    }

    public func saveSilentLaunchEnabled(_ enabled: Bool) {}

    public func saveDisplayInDockEnabled(_ enabled: Bool) {}

    public func saveVoiceInputSessionHistoryEnabled(_ enabled: Bool) {}

    public func saveVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy) {}
}
