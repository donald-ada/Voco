import Foundation
import VocoAppCore

@MainActor
final class MacAppPreferenceStore: AppPreferenceStoring {
    private enum Keys {
        static let silentLaunchEnabled = "app.silentLaunchEnabled"
        static let displayInDockEnabled = "app.displayInDockEnabled"
        static let voiceInputSessionHistoryEnabled = "voiceInputSession.historyEnabled"
        static let voiceInputSessionRetentionPolicy = "voiceInputSession.retentionPolicy"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var silentLaunchEnabled: Bool {
        defaults.bool(forKey: Keys.silentLaunchEnabled)
    }

    var displayInDockEnabled: Bool {
        defaults.bool(forKey: Keys.displayInDockEnabled)
    }

    var voiceInputSessionHistoryEnabled: Bool {
        guard defaults.object(forKey: Keys.voiceInputSessionHistoryEnabled) != nil else {
            return true
        }

        return defaults.bool(forKey: Keys.voiceInputSessionHistoryEnabled)
    }

    var voiceInputSessionRetentionPolicy: VoiceInputSessionRetentionPolicy {
        guard let rawValue = defaults.string(forKey: Keys.voiceInputSessionRetentionPolicy),
              let policy = VoiceInputSessionRetentionPolicy(rawValue: rawValue)
        else {
            return .last1000
        }

        return policy
    }

    func saveSilentLaunchEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.silentLaunchEnabled)
    }

    func saveDisplayInDockEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.displayInDockEnabled)
    }

    func saveVoiceInputSessionHistoryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.voiceInputSessionHistoryEnabled)
    }

    func saveVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy) {
        defaults.set(policy.rawValue, forKey: Keys.voiceInputSessionRetentionPolicy)
    }
}
