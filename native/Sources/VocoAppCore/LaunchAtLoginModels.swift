import Foundation

public enum LaunchAtLoginState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
    case failed(String)

    public var isEnabled: Bool {
        self == .enabled
    }

    public var title: String {
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        switch self {
        case .disabled:
            strings.settings.launchAtLoginDisabledTitle
        case .enabled:
            strings.settings.enabledTitle
        case .requiresApproval:
            strings.settings.launchAtLoginRequiresApprovalTitle
        case .unavailable:
            strings.settings.launchAtLoginUnavailableTitle
        case .failed:
            strings.settings.launchAtLoginErrorTitle
        }
    }

    public var detail: String {
        detail(strings: VocoStrings())
    }

    public func detail(strings: VocoStrings) -> String {
        switch self {
        case .disabled:
            strings.settings.launchAtLoginDisabledStateDetail
        case .enabled:
            strings.settings.launchAtLoginEnabledStateDetail
        case .requiresApproval:
            strings.settings.launchAtLoginApprovalDetail
        case .unavailable:
            strings.settings.launchAtLoginUnavailableStateDetail
        case .failed(let message):
            message
        }
    }

    public var systemImage: String {
        switch self {
        case .enabled:
            "checkmark.circle.fill"
        case .disabled:
            "minus.circle"
        case .requiresApproval:
            "exclamationmark.triangle.fill"
        case .unavailable:
            "questionmark.circle"
        case .failed:
            "xmark.circle.fill"
        }
    }
}

@MainActor
public protocol LaunchAtLoginProviding {
    func currentState() -> LaunchAtLoginState
    func setEnabled(_ enabled: Bool) async throws -> LaunchAtLoginState
}

public struct StaticLaunchAtLoginProvider: LaunchAtLoginProviding {
    private let state: LaunchAtLoginState

    public init(state: LaunchAtLoginState = .disabled) {
        self.state = state
    }

    public func currentState() -> LaunchAtLoginState {
        state
    }

    public func setEnabled(_ enabled: Bool) async -> LaunchAtLoginState {
        state
    }
}
