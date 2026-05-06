import XCTest
@testable import VocoAppCore

final class AudioSettingsModelsTests: XCTestCase {
    func testDefaultAudioSettingsUseSystemInputAndIdleRuntime() {
        let snapshot = AudioSettingsSnapshot(lastAudio: nil)

        XCTAssertEqual(snapshot.inputDevice.title, "系统默认输入")
        XCTAssertEqual(snapshot.inputDevice.detail, "使用 macOS 当前默认麦克风；真实设备选择将在后续偏好设置中接入。")
        XCTAssertEqual(snapshot.levelMeter.title, "无近期采样")
        XCTAssertEqual(snapshot.levelMeter.detail, "开始一次录音后会显示最近峰值电平。")
        XCTAssertEqual(snapshot.sampleRate.title, "等待采样率")
        XCTAssertEqual(snapshot.sampleRate.detail, "暂无最近录音；目标转写采样率为 16,000 Hz。")
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
