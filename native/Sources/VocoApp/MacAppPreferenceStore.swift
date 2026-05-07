import Foundation
import VocoAppCore

@MainActor
final class MacAppPreferenceStore: AppPreferenceStoring {
    private enum Keys {
        static let silentLaunchEnabled = "app.silentLaunchEnabled"
        static let displayInDockEnabled = "app.displayInDockEnabled"
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

    func saveSilentLaunchEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.silentLaunchEnabled)
    }

    func saveDisplayInDockEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.displayInDockEnabled)
    }
}
