import Foundation
import ServiceManagement
import VocoAppCore

struct MacLaunchAtLoginProvider: LaunchAtLoginProviding {
    func currentState() -> LaunchAtLoginState {
        mapStatus(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) async throws -> LaunchAtLoginState {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }

        return currentState()
    }

    private func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}
