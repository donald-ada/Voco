import Foundation
import VocoAppCore

@MainActor
final class MacVoiceInputPreferenceStore: VoiceInputPreferenceStoring {
    private enum Keys {
        static let hotkeyPreset = "voiceInput.hotkeyPreset"
        static let hotkeyMode = "voiceInput.hotkeyMode"
        static let audioInputDevice = "voiceInput.audioInputDevice"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotkeyPreset: HotkeyPreset? {
        guard let rawValue = defaults.string(forKey: Keys.hotkeyPreset) else {
            return nil
        }

        return HotkeyPreset(rawValue: rawValue)
    }

    var hotkeyMode: HotkeyMode? {
        guard let rawValue = defaults.string(forKey: Keys.hotkeyMode) else {
            return nil
        }

        return HotkeyMode(rawValue: rawValue)
    }

    var audioInputDevice: AudioInputDeviceSelection? {
        guard let data = defaults.data(forKey: Keys.audioInputDevice) else {
            return nil
        }

        return try? decoder.decode(AudioInputDeviceSelection.self, from: data)
    }

    func saveHotkeyPreset(_ preset: HotkeyPreset) {
        defaults.set(preset.rawValue, forKey: Keys.hotkeyPreset)
    }

    func saveHotkeyMode(_ mode: HotkeyMode) {
        defaults.set(mode.rawValue, forKey: Keys.hotkeyMode)
    }

    func saveAudioInputDevice(_ device: AudioInputDeviceSelection) {
        guard let data = try? encoder.encode(device) else {
            return
        }

        defaults.set(data, forKey: Keys.audioInputDevice)
    }
}
