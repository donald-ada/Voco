import Foundation

public enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility

    public var id: String {
        rawValue
    }

    public var title: String {
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        strings.permissions.title(for: self)
    }

    public var description: String {
        description(strings: VocoStrings())
    }

    public func description(strings: VocoStrings) -> String {
        strings.permissions.description(for: self)
    }

    public var systemImage: String {
        switch self {
        case .microphone:
            "mic"
        case .accessibility:
            "accessibility"
        }
    }

    public var recoveryActionTitle: String {
        recoveryActionTitle(strings: VocoStrings())
    }

    public func recoveryActionTitle(strings: VocoStrings) -> String {
        strings.permissions.recoveryActionTitle(for: self)
    }

    public var settingsURLString: String {
        switch self {
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
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
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        strings.permissions.title(for: self)
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
