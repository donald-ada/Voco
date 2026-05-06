import Foundation

public enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .microphone:
            "麦克风"
        case .accessibility:
            "辅助功能"
        case .inputMonitoring:
            "输入监控"
        }
    }

    public var description: String {
        switch self {
        case .microphone:
            "用于录制语音并生成转写文本。"
        case .accessibility:
            "用于把转写文本插入当前正在输入的 App。"
        case .inputMonitoring:
            "仅用于诊断低层键盘监听能力；默认快捷键不需要。"
        }
    }

    public var systemImage: String {
        switch self {
        case .microphone:
            "mic"
        case .accessibility:
            "accessibility"
        case .inputMonitoring:
            "keyboard"
        }
    }

    public var recoveryActionTitle: String {
        switch self {
        case .microphone:
            "打开麦克风设置"
        case .accessibility:
            "打开辅助功能设置"
        case .inputMonitoring:
            "打开输入监控设置"
        }
    }

    public var settingsURLString: String {
        switch self {
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }
}

public enum PermissionGrantState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unknown

    public var isGranted: Bool {
        self == .granted
    }

    public var title: String {
        switch self {
        case .notDetermined:
            "未决定"
        case .granted:
            "已允许"
        case .denied:
            "已拒绝"
        case .restricted:
            "受限制"
        case .unknown:
            "未知"
        }
    }

    public var systemImage: String {
        switch self {
        case .granted:
            "checkmark.circle.fill"
        case .notDetermined:
            "questionmark.circle"
        case .denied:
            "xmark.circle.fill"
        case .restricted:
            "lock.circle.fill"
        case .unknown:
            "exclamationmark.circle"
        }
    }
}

public struct PermissionSnapshot: Equatable, Sendable, Identifiable {
    public let kind: PermissionKind
    public let state: PermissionGrantState
    public let isRequired: Bool

    public var id: PermissionKind {
        kind
    }

    public init(kind: PermissionKind, state: PermissionGrantState, isRequired: Bool = true) {
        self.kind = kind
        self.state = state
        self.isRequired = isRequired
    }

    public static func microphone(_ state: PermissionGrantState, isRequired: Bool = true) -> PermissionSnapshot {
        PermissionSnapshot(kind: .microphone, state: state, isRequired: isRequired)
    }

    public static func accessibility(_ state: PermissionGrantState, isRequired: Bool = true) -> PermissionSnapshot {
        PermissionSnapshot(kind: .accessibility, state: state, isRequired: isRequired)
    }

    public static func inputMonitoring(_ state: PermissionGrantState, isRequired: Bool = false) -> PermissionSnapshot {
        PermissionSnapshot(kind: .inputMonitoring, state: state, isRequired: isRequired)
    }
}

public struct PermissionSummary: Equatable, Sendable {
    public let snapshots: [PermissionSnapshot]

    public init(snapshots: [PermissionSnapshot]) {
        self.snapshots = snapshots
    }

    public var allRequiredGranted: Bool {
        missingRequiredPermissions.isEmpty
    }

    public var missingRequiredPermissions: [PermissionKind] {
        snapshots
            .filter { $0.isRequired && !$0.state.isGranted }
            .map(\.kind)
    }
}

@MainActor
public protocol PermissionProviding {
    func currentSnapshots() -> [PermissionSnapshot]
    func requestMicrophoneAccess() async -> [PermissionSnapshot]
}

public struct StaticPermissionProvider: PermissionProviding {
    private let snapshots: [PermissionSnapshot]

    public init(snapshots: [PermissionSnapshot]) {
        self.snapshots = snapshots
    }

    public static var allGranted: StaticPermissionProvider {
        StaticPermissionProvider(
            snapshots: PermissionKind.allCases.map {
                PermissionSnapshot(kind: $0, state: .granted)
            }
        )
    }

    public func currentSnapshots() -> [PermissionSnapshot] {
        snapshots
    }

    public func requestMicrophoneAccess() async -> [PermissionSnapshot] {
        snapshots
    }
}
