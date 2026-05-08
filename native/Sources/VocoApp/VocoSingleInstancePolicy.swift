import Foundation

struct VocoRunningApplicationSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

enum VocoSingleInstancePolicy {
    static func existingInstance(
        currentProcessIdentifier: pid_t,
        currentBundleIdentifier: String?,
        runningApplications: [VocoRunningApplicationSnapshot]
    ) -> VocoRunningApplicationSnapshot? {
        guard let currentBundleIdentifier, !currentBundleIdentifier.isEmpty else {
            return nil
        }

        return runningApplications
            .filter { application in
                application.processIdentifier < currentProcessIdentifier &&
                    application.bundleIdentifier == currentBundleIdentifier
            }
            .min { lhs, rhs in
                lhs.processIdentifier < rhs.processIdentifier
            }
    }
}

extension Notification.Name {
    static let vocoShowSettingsWindow = Notification.Name("com.voco.app.show-settings-window")
}
