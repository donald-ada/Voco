import Foundation

public struct AudioSettingsSnapshot: Equatable, Sendable {
    public let inputDevice: AudioInputDeviceSnapshot
    public let levelMeter: AudioLevelMeterSnapshot
    public let sampleRate: AudioSampleRateSnapshot

    public init(
        lastAudio: CapturedAudioSnapshot?,
        inputDeviceName: String = "系统默认输入",
        expectedSampleRate: Double = 16_000
    ) {
        self.inputDevice = AudioInputDeviceSnapshot(displayName: inputDeviceName)
        self.levelMeter = AudioLevelMeterSnapshot(lastAudio: lastAudio)
        self.sampleRate = AudioSampleRateSnapshot(
            lastAudio: lastAudio,
            expectedSampleRate: expectedSampleRate
        )
    }
}

public struct AudioInputDeviceSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public init(displayName: String) {
        self.title = displayName
        self.detail = "使用 macOS 当前默认麦克风；真实设备选择将在后续偏好设置中接入。"
        self.systemImage = "mic"
    }
}

public struct AudioLevelMeterSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public init(lastAudio: CapturedAudioSnapshot?) {
        guard let lastAudio else {
            self.title = "无近期采样"
            self.detail = "开始一次录音后会显示最近峰值电平。"
            self.systemImage = "waveform.path.ecg"
            return
        }

        let peakPercentage = Int((clamp(lastAudio.peakAmplitude) * 100).rounded())
        if peakPercentage >= 90 {
            self.title = "电平接近削波"
            self.systemImage = "exclamationmark.triangle.fill"
        } else if peakPercentage < 5 {
            self.title = "电平偏低"
            self.systemImage = "waveform.badge.minus"
        } else {
            self.title = "电平正常"
            self.systemImage = "waveform"
        }
        self.detail = String(
            format: "最近峰值 %d%% · %.2fs",
            peakPercentage,
            lastAudio.durationSeconds
        )
    }
}

public struct AudioSampleRateSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let matchesExpectedRate: Bool

    public init(lastAudio: CapturedAudioSnapshot?, expectedSampleRate: Double = 16_000) {
        guard let sampleRate = lastAudio?.sampleRate, sampleRate > 0 else {
            self.title = "等待采样率"
            self.detail = "暂无最近录音；目标转写采样率为 \(formatHertz(expectedSampleRate)) Hz。"
            self.systemImage = "clock"
            self.matchesExpectedRate = false
            return
        }

        self.title = "\(formatHertz(sampleRate)) Hz"
        let matchesExpectedRate = abs(sampleRate - expectedSampleRate) < 1
        self.matchesExpectedRate = matchesExpectedRate
        if matchesExpectedRate {
            self.detail = "最近录音采样率符合目标转写输入。"
            self.systemImage = "checkmark.circle.fill"
        } else {
            self.detail = "最近录音采样率与目标 \(formatHertz(expectedSampleRate)) Hz 不一致。"
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
