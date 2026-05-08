import Foundation

public struct AudioSettingsSnapshot: Equatable, Sendable {
    public let inputDevice: AudioInputDeviceSnapshot
    public let levelMeter: AudioLevelMeterSnapshot
    public let sampleRate: AudioSampleRateSnapshot

    public init(
        lastAudio: CapturedAudioSnapshot?,
        strings: VocoStrings = VocoStrings(),
        inputDevice: AudioInputDeviceSelection = .systemDefault,
        expectedSampleRate: Double = 16_000
    ) {
        self.inputDevice = AudioInputDeviceSnapshot(selection: inputDevice, strings: strings)
        self.levelMeter = AudioLevelMeterSnapshot(lastAudio: lastAudio, strings: strings)
        self.sampleRate = AudioSampleRateSnapshot(
            lastAudio: lastAudio,
            strings: strings,
            expectedSampleRate: expectedSampleRate
        )
    }
}

public struct AudioInputDeviceSelection: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let systemImage: String
    public let isSystemDefault: Bool

    public static let systemDefault = AudioInputDeviceSelection(
        id: "system-default",
        title: "系统默认输入",
        detail: "跟随 macOS 当前默认麦克风。",
        systemImage: "mic",
        isSystemDefault: true
    )

    public static func device(id: String, title: String) -> AudioInputDeviceSelection {
        AudioInputDeviceSelection(
            id: id,
            title: title,
            detail: "已选择此麦克风用于录音。",
            systemImage: "mic.fill",
            isSystemDefault: false
        )
    }

    public func title(strings: VocoStrings) -> String {
        isSystemDefault ? strings.audio.systemDefaultInputTitle : title
    }

    public func detail(strings: VocoStrings) -> String {
        isSystemDefault ? strings.audio.systemDefaultInputDetail : strings.audio.selectedInputDetail
    }
}

public struct AudioInputDeviceSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public init(selection: AudioInputDeviceSelection, strings: VocoStrings = VocoStrings()) {
        self.title = selection.title(strings: strings)
        self.detail = selection.detail(strings: strings)
        self.systemImage = selection.systemImage
    }
}

public struct AudioLevelMeterSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public init(lastAudio: CapturedAudioSnapshot?, strings: VocoStrings = VocoStrings()) {
        guard let lastAudio else {
            self.title = strings.audio.noRecentSampleTitle
            self.detail = strings.audio.noRecentSampleDetail
            self.systemImage = "waveform.path.ecg"
            return
        }

        let peakPercentage = Int((clamp(lastAudio.peakAmplitude) * 100).rounded())
        if peakPercentage >= 90 {
            self.title = strings.audio.levelNearClippingTitle
            self.systemImage = "exclamationmark.triangle.fill"
        } else if peakPercentage < 5 {
            self.title = strings.audio.levelTooLowTitle
            self.systemImage = "waveform.badge.minus"
        } else {
            self.title = strings.audio.levelNormalTitle
            self.systemImage = "waveform"
        }
        self.detail = strings.audio.recentPeakDetail(
            peakPercentage: peakPercentage,
            durationSeconds: lastAudio.durationSeconds
        )
    }
}

public struct AudioSampleRateSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let matchesExpectedRate: Bool

    public init(
        lastAudio: CapturedAudioSnapshot?,
        strings: VocoStrings = VocoStrings(),
        expectedSampleRate: Double = 16_000
    ) {
        guard let sampleRate = lastAudio?.sampleRate, sampleRate > 0 else {
            self.title = strings.audio.waitingSampleRateTitle
            self.detail = strings.audio.waitingSampleRateDetail(rate: formatHertz(expectedSampleRate))
            self.systemImage = "clock"
            self.matchesExpectedRate = false
            return
        }

        self.title = "\(formatHertz(sampleRate)) Hz"
        let matchesExpectedRate = abs(sampleRate - expectedSampleRate) < 1
        self.matchesExpectedRate = matchesExpectedRate
        if matchesExpectedRate {
            self.detail = strings.audio.sampleRateMatchedDetail
            self.systemImage = "checkmark.circle.fill"
        } else {
            self.detail = strings.audio.sampleRateMismatchedDetail(rate: formatHertz(expectedSampleRate))
            self.systemImage = "exclamationmark.triangle.fill"
        }
    }
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func formatHertz(_ sampleRate: Double) -> String {
    let rounded = String(Int(sampleRate.rounded()))
    var grouped = ""

    for (offset, character) in rounded.reversed().enumerated() {
        if offset > 0, offset % 3 == 0 {
            grouped.append(",")
        }
        grouped.append(character)
    }

    return String(grouped.reversed())
}
