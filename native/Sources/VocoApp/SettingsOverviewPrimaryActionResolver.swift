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
}

@MainActor
enum SettingsOverviewPrimaryActionResolver {
    static func resolve(title: String) -> SettingsOverviewPrimaryAction {
        if title == SettingsWorkbenchActionTitle.checkMicrophone {
            return .requestMicrophonePermission
        }

        if title == PermissionKind.accessibility.recoveryActionTitle {
            return .openAccessibilitySettings
        }

        if title == "前往设置" || title.contains("输入") {
            return .selectSettings
        }

        if title == "前往模型" ||
            title.contains("模型") ||
            title.contains("Keychain") {
            return .selectModel
        }

        if title == "重新检查" {
            return .refresh
        }

        return .startTestRecording
    }
}
