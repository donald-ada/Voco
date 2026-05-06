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
        switch self {
        case .disabled:
            "已关闭"
        case .enabled:
            "已开启"
        case .requiresApproval:
            "需要批准"
        case .unavailable:
            "不可用"
        case .failed:
            "出错"
        }
    }

    public var detail: String {
        switch self {
        case .disabled:
            "Voco 不会在登录后自动启动。"
        case .enabled:
            "Voco 会在你登录 macOS 后自动启动。"
        case .requiresApproval:
            "需要在 System Settings 的 Login Items 中批准 Voco。"
        case .unavailable:
            "当前运行位置或系统状态不支持登录时启动。"
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
