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
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        switch self {
        case .last100:
            strings.language == .zhHans ? "最近 100 条" : "Last 100"
        case .last1000:
            strings.language == .zhHans ? "最近 1000 条" : "Last 1000"
        case .forever:
            strings.language == .zhHans ? "永久保留" : "Keep Forever"
        }
    }

    public var detail: String {
        detail(strings: VocoStrings())
    }

    public func detail(strings: VocoStrings) -> String {
        switch self {
        case .last100:
            strings.language == .zhHans ? "只保留最近 100 次会话。" : "Keep only the most recent 100 sessions."
        case .last1000:
            strings.language == .zhHans ? "只保留最近 1000 次会话。" : "Keep only the most recent 1000 sessions."
        case .forever:
            strings.language == .zhHans ? "不自动清理旧会话。" : "Do not automatically clean up old sessions."
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
    var appLanguage: AppLanguage { get }

    func saveSilentLaunchEnabled(_ enabled: Bool)
    func saveDisplayInDockEnabled(_ enabled: Bool)
    func saveVoiceInputSessionHistoryEnabled(_ enabled: Bool)
    func saveVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy)
    func saveAppLanguage(_ language: AppLanguage)
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

    public var appLanguage: AppLanguage {
        .default
    }

    public func saveSilentLaunchEnabled(_ enabled: Bool) {}

    public func saveDisplayInDockEnabled(_ enabled: Bool) {}

    public func saveVoiceInputSessionHistoryEnabled(_ enabled: Bool) {}

    public func saveVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy) {}

    public func saveAppLanguage(_ language: AppLanguage) {}
}
