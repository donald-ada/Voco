import Foundation
import VocoAppCore

@MainActor
final class MacSkillPreferenceStore: SkillPreferenceStoring {
    private enum Keys {
        static let settings = "skills.settings"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var skillSettings: SkillSettings {
        guard let data = defaults.data(forKey: Keys.settings),
              let settings = try? decoder.decode(SkillSettings.self, from: data)
        else {
            return .default
        }

        return settings
    }

    func saveSkillSettings(_ settings: SkillSettings) {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: Keys.settings)
        } catch {
            NSLog("Voco: Unable to save skill settings: \(error.localizedDescription)")
        }
    }
}
