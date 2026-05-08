import Foundation
import VocoAppCore

@MainActor
enum SettingsOverviewPrimaryAction: Equatable {
    case requestMicrophonePermission
    case openAccessibilitySettings
    case selectSettings
    case selectModel
    case refresh
    case startTestRecording
    case unknown
}

@MainActor
enum SettingsOverviewPrimaryActionResolver {
    static func resolve(actionID: String) -> SettingsOverviewPrimaryAction {
        if actionID == SettingsWorkbenchActionID.checkMicrophone {
            return .requestMicrophonePermission
        }

        if actionID == SettingsWorkbenchActionID.openModel {
            return .selectModel
        }

        if actionID == SettingsWorkbenchActionID.openSettings {
            return .selectSettings
        }

        if actionID == SettingsWorkbenchActionID.openAccessibilitySettings {
            return .openAccessibilitySettings
        }

        if actionID == SettingsWorkbenchActionID.refresh {
            return .refresh
        }

        if actionID == SettingsWorkbenchActionID.startTestRecording {
            return .startTestRecording
        }

        return .unknown
    }
}
