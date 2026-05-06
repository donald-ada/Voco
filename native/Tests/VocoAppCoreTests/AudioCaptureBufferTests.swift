import XCTest
@testable import VocoAppCore

final class AudioCaptureBufferTests: XCTestCase {
    func testSnapshotFromSilenceHasZeroAmplitudeAndExpectedDuration() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendMonoFloat32(Array(repeating: 0, count: 160), sourceSampleRate: 16_000)
        let snapshot = buffer.snapshot()

        XCTAssertEqual(snapshot.sampleRate, 16_000)
        XCTAssertEqual(snapshot.pcm16Samples.count, 160)
        XCTAssertEqual(snapshot.durationSeconds, 0.01, accuracy: 0.0001)
        XCTAssertEqual(snapshot.peakAmplitude, 0)
    }

    func testFloatSamplesAreClippedAndConvertedToInt16() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendMonoFloat32([-2.0, -0.5, 0.0, 0.5, 2.0], sourceSampleRate: 16_000)

        XCTAssertEqual(buffer.snapshot().pcm16Samples, [Int16.min + 1, -16_383, 0, 16_383, Int16.max])
        XCTAssertEqual(buffer.snapshot().peakAmplitude, 1.0, accuracy: 0.0001)
    }

    func testStereoInputIsDownmixedBeforeConversion() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendNonInterleavedFloat32(
            [[1.0, -1.0], [-1.0, 1.0]],
            sourceSampleRate: 16_000
        )

        XCTAssertEqual(buffer.snapshot().pcm16Samples, [0, 0])
        XCTAssertEqual(buffer.snapshot().peakAmplitude, 0)
    }

    func testInputIsResampledFrom48kHzTo16kHz() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendMonoFloat32(Array(repeating: 0.25, count: 480), sourceSampleRate: 48_000)

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.sampleRate, 16_000)
        XCTAssertEqual(snapshot.pcm16Samples.count, 160)
        XCTAssertEqual(snapshot.durationSeconds, 0.01, accuracy: 0.0001)
        XCTAssertEqual(snapshot.peakAmplitude, 0.25, accuracy: 0.001)
    }

    func testResetDropsCapturedSamples() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)
        buffer.appendMonoFloat32([0.5, 0.5], sourceSampleRate: 16_000)

        buffer.reset()

        let snapshot = buffer.snapshot()
        XCTAssertTrue(snapshot.pcm16Samples.isEmpty)
        XCTAssertEqual(snapshot.durationSeconds, 0)
        XCTAssertEqual(snapshot.peakAmplitude, 0)
    }
}
