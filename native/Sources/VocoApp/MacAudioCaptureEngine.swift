import AVFoundation
import Foundation
import VocoAppCore

@MainActor
final class MacAudioCaptureEngine: AudioCaptureProviding {
    private let engine = AVAudioEngine()
    private let store = LockedAudioCaptureStore()
    private var isCapturing = false

    func startCapture() async throws {
        guard !isCapturing else {
            throw RecordingWorkflowError("audio capture already running")
        }

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingWorkflowError("microphone input format unavailable")
        }

        store.reset()
        let requestedFrames = Int(format.sampleRate * 0.02)
        let bufferSize = AVAudioFrameCount(max(160, min(1024, requestedFrames)))
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format,
            block: Self.makeAudioTapBlock(store: store)
        )

        do {
            engine.prepare()
            try engine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecordingWorkflowError("audio capture failed to start: \(error.localizedDescription)")
        }
    }

    func stopCapture() async throws -> CapturedAudioSnapshot {
        guard isCapturing else {
            throw RecordingWorkflowError("audio capture is not running")
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        return try store.snapshot()
    }

    nonisolated static func makeAudioTapBlock(
        store: LockedAudioCaptureStore
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            store.append(buffer)
        }
    }
}

final class LockedAudioCaptureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var audioBuffer = AudioCaptureBuffer()
    private var failureMessage: String?

    func reset() {
        lock.lock()
        audioBuffer.reset()
        failureMessage = nil
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return
        }

        guard let floatChannelData = buffer.floatChannelData else {
            recordFailure("audio capture received a non-Float32 PCM buffer")
            return
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else {
            recordFailure("audio capture received a buffer with no channels")
            return
        }

        var channels: [[Float]] = []
        channels.reserveCapacity(channelCount)

        for channelIndex in 0..<channelCount {
            let channel = floatChannelData[channelIndex]
            channels.append(Array(UnsafeBufferPointer(start: channel, count: frameCount)))
        }

        lock.lock()
        audioBuffer.appendNonInterleavedFloat32(
            channels,
            sourceSampleRate: buffer.format.sampleRate
        )
        lock.unlock()
    }

    func snapshot() throws -> CapturedAudioSnapshot {
        lock.lock()
        if let failureMessage {
            lock.unlock()
            throw RecordingWorkflowError(failureMessage)
        }

        let result = audioBuffer.snapshot()
        lock.unlock()
        return result
    }

    private func recordFailure(_ message: String) {
        lock.lock()
        if failureMessage == nil {
            failureMessage = message
        }
        lock.unlock()
    }
}
