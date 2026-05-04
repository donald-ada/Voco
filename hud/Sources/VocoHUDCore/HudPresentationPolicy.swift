public enum HudPanelAction: Equatable, Sendable {
    case show
    case hide
    case unchanged
}

public struct HudPresentationAction: Equatable, Sendable {
    public let topPanel: HudPanelAction
    public let autoHideError: Bool
}

public enum HudPresentationPolicy {
    public static func action(for event: HudEvent, isVisible: Bool) -> HudPresentationAction {
        switch event {
        case .state(.hidden, _):
            HudPresentationAction(topPanel: .hide, autoHideError: false)
        case .state(.error, _):
            HudPresentationAction(topPanel: .show, autoHideError: true)
        case .state:
            HudPresentationAction(topPanel: .show, autoHideError: false)
        case .amplitude:
            HudPresentationAction(topPanel: .unchanged, autoHideError: false)
        case .transcript:
            HudPresentationAction(topPanel: isVisible ? .show : .hide, autoHideError: false)
        }
    }
}
