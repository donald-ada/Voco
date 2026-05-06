import AVFoundation
import XCTest
@testable import VocoApp

@MainActor
final class MacAudioCaptureEngineTests: XCTestCase {
    func testTapBlockCanRunOffMainActorQueue() async throws {
        let store = LockedAudioCaptureStore()
        let tapBlock = MacAudioCaptureEngine.makeAudioTapBlock(store: store)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "test.voco.audio-tap").async {
                do {
                    let buffer = try Self.makeMonoBuffer(samples: [0.5, -0.25, 0.0, 0.25])
                    tapBlock(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.sampleRate, 16_000)
        XCTAssertEqual(snapshot.pcm16Samples.count, 4)
        XCTAssertEqual(snapshot.peakAmplitude, 0.5, accuracy: 0.001)
    }

    func testTapBlockForwardsResampledPCMChunks() throws {
        let store = LockedAudioCaptureStore()
        let chunks = LockedPCMChunks()
        let tapBlock = MacAudioCaptureEngine.makeAudioTapBlock(store: store) { samples in
            chunks.append(samples)
        }

        let buffer = try Self.makeMonoBuffer(samples: [0.5, -0.25, 0.0, 0.25])
        tapBlock(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))

        let capturedChunks = chunks.snapshot()
        XCTAssertEqual(capturedChunks.count, 1)
        XCTAssertEqual(capturedChunks.first?.count, 4)
        XCTAssertEqual(capturedChunks.first?.first, 16_383)
    }

    nonisolated private static func makeMonoBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw XCTSkip("Unable to create test PCM format")
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw XCTSkip("Unable to create test PCM buffer")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else {
            throw XCTSkip("Test PCM buffer has no Float32 channel data")
        }

        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }

        return buffer
    }
}

private final class LockedPCMChunks: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [[Int16]] = []

    func append(_ samples: [Int16]) {
        lock.lock()
        chunks.append(samples)
        lock.unlock()
    }

    func snapshot() -> [[Int16]] {
        lock.lock()
        let result = chunks
        lock.unlock()
        return result
    }
}
