import Foundation

@MainActor
public protocol VoiceInputPreferenceStoring: AnyObject {
    var hotkeyPreset: HotkeyPreset? { get }
    var hotkeyMode: HotkeyMode? { get }
    var audioInputDevice: AudioInputDeviceSelection? { get }

    func saveHotkeyPreset(_ preset: HotkeyPreset)
    func saveHotkeyMode(_ mode: HotkeyMode)
    func saveAudioInputDevice(_ device: AudioInputDeviceSelection)
}

public final class NoOpVoiceInputPreferenceStore: VoiceInputPreferenceStoring {
    public init() {}

    public var hotkeyPreset: HotkeyPreset? {
        nil
    }

    public var hotkeyMode: HotkeyMode? {
        nil
    }

    public var audioInputDevice: AudioInputDeviceSelection? {
        nil
    }

    public func saveHotkeyPreset(_ preset: HotkeyPreset) {}

    public func saveHotkeyMode(_ mode: HotkeyMode) {}

    public func saveAudioInputDevice(_ device: AudioInputDeviceSelection) {}
}
