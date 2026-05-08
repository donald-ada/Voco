import XCTest
@testable import VocoAppCore

final class AudioSettingsModelsTests: XCTestCase {
    func testAudioSettingsSnapshotUsesEnglishCopy() {
        let snapshot = AudioSettingsSnapshot(lastAudio: nil, strings: VocoStrings(language: .en))

        XCTAssertEqual(snapshot.inputDevice.title, "System Default Input")
        XCTAssertEqual(snapshot.inputDevice.detail, "Follow the current default macOS microphone.")
        XCTAssertEqual(snapshot.levelMeter.title, "No Recent Sample")
        XCTAssertEqual(snapshot.levelMeter.detail, "The recent peak level appears after a recording.")
        XCTAssertEqual(snapshot.sampleRate.title, "Waiting for Sample Rate")
        XCTAssertEqual(snapshot.sampleRate.detail, "No recent recording. Target transcription sample rate is 16,000 Hz.")
    }

    func testRecentAudioSettingsSnapshotUsesEnglishDetail() {
        let audio = CapturedAudioSnapshot(durationSeconds: 1.25, sampleRate: 16_000, peakAmplitude: 0.5)

        let snapshot = AudioSettingsSnapshot(lastAudio: audio, strings: VocoStrings(language: .en))

        XCTAssertEqual(snapshot.levelMeter.title, "Level Normal")
        XCTAssertEqual(snapshot.levelMeter.detail, "Recent peak 50% · 1.25s")
    }

    func testAudioInputDeviceSelectionUsesEnglishCopy() {
        let strings = VocoStrings(language: .en)
        let device = AudioInputDeviceSelection.device(id: "studio-mic", title: "Studio Mic")

        XCTAssertEqual(AudioInputDeviceSelection.systemDefault.title(strings: strings), "System Default Input")
        XCTAssertEqual(AudioInputDeviceSelection.systemDefault.detail(strings: strings), "Follow the current default macOS microphone.")
        XCTAssertEqual(device.title(strings: strings), "Studio Mic")
        XCTAssertEqual(device.detail(strings: strings), "This microphone is selected for recording.")
    }

    func testDefaultAudioSettingsUseSystemInputAndIdleRuntime() {
        let snapshot = AudioSettingsSnapshot(lastAudio: nil)

        XCTAssertEqual(snapshot.inputDevice.title, "系统默认输入")
        XCTAssertEqual(snapshot.inputDevice.detail, "跟随 macOS 当前默认麦克风。")
        XCTAssertEqual(snapshot.levelMeter.title, "无近期采样")
        XCTAssertEqual(snapshot.levelMeter.detail, "开始一次录音后会显示最近峰值电平。")
        XCTAssertEqual(snapshot.sampleRate.title, "等待采样率")
        XCTAssertEqual(snapshot.sampleRate.detail, "暂无最近录音；目标转写采样率为 16,000 Hz。")
    }

    func testAudioSettingsReflectSelectedInputDevice() {
        let snapshot = AudioSettingsSnapshot(
            lastAudio: nil,
            inputDevice: .device(id: "studio-mic", title: "Studio Mic")
        )

        XCTAssertEqual(snapshot.inputDevice.title, "Studio Mic")
        XCTAssertEqual(snapshot.inputDevice.detail, "已选择此麦克风用于录音。")
        XCTAssertEqual(snapshot.inputDevice.systemImage, "mic.fill")
    }

    func testRecentAudioShowsLevelAndMatchedSampleRate() {
        let audio = CapturedAudioSnapshot(durationSeconds: 1.25, sampleRate: 16_000, peakAmplitude: 0.61)

        let snapshot = AudioSettingsSnapshot(lastAudio: audio)

        XCTAssertEqual(snapshot.levelMeter.title, "电平正常")
        XCTAssertEqual(snapshot.levelMeter.detail, "最近峰值 61% · 1.25s")
        XCTAssertEqual(snapshot.levelMeter.systemImage, "waveform")
        XCTAssertEqual(snapshot.sampleRate.title, "16,000 Hz")
        XCTAssertEqual(snapshot.sampleRate.detail, "最近录音采样率符合目标转写输入。")
        XCTAssertTrue(snapshot.sampleRate.matchesExpectedRate)
    }

    func testRecentAudioFlagsClippingAndUnexpectedSampleRate() {
        let audio = CapturedAudioSnapshot(durationSeconds: 0.5, sampleRate: 44_100, peakAmplitude: 0.93)

        let snapshot = AudioSettingsSnapshot(lastAudio: audio)

        XCTAssertEqual(snapshot.levelMeter.title, "电平接近削波")
        XCTAssertEqual(snapshot.levelMeter.detail, "最近峰值 93% · 0.50s")
        XCTAssertEqual(snapshot.sampleRate.title, "44,100 Hz")
        XCTAssertEqual(snapshot.sampleRate.detail, "最近录音采样率与目标 16,000 Hz 不一致。")
        XCTAssertFalse(snapshot.sampleRate.matchesExpectedRate)
    }
}
