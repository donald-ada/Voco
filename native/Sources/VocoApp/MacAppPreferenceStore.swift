import Foundation
import VocoAppCore

@MainActor
final class MacAppPreferenceStore: AppPreferenceStoring {
    private enum Keys {
        static let silentLaunchEnabled = "app.silentLaunchEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var silentLaunchEnabled: Bool {
        defaults.bool(forKey: Keys.silentLaunchEnabled)
    }

    func saveSilentLaunchEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.silentLaunchEnabled)
    }
}
