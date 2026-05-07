import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import VocoAppCore

@MainActor
final class MacAudioCaptureEngine: AudioCaptureProviding {
    private let engine = AVAudioEngine()
    private let store = LockedAudioCaptureStore()
    private var currentInputDevice: AudioInputDeviceSelection = .systemDefault
    private var isCapturing = false

    var availableInputDevices: [AudioInputDeviceSelection] {
        [.systemDefault] + Self.availableCoreAudioInputDevices()
    }

    var selectedInputDevice: AudioInputDeviceSelection {
        currentInputDevice
    }

    func setInputDevice(_ device: AudioInputDeviceSelection) {
        currentInputDevice = device
    }

    func startCapture() async throws {
        try await startCapture(audioChunkHandler: nil)
    }

    func startCapture(audioChunkHandler: AudioCaptureChunkHandler?) async throws {
        guard !isCapturing else {
            throw RecordingWorkflowError("audio capture already running")
        }

        let inputNode = engine.inputNode
        try Self.applyInputDevice(currentInputDevice, to: inputNode)
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
            block: Self.makeAudioTapBlock(
                store: store,
                audioChunkHandler: audioChunkHandler
            )
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
        store: LockedAudioCaptureStore,
        audioChunkHandler: AudioCaptureChunkHandler? = nil
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            store.append(buffer, audioChunkHandler: audioChunkHandler)
        }
    }

    private static func applyInputDevice(
        _ device: AudioInputDeviceSelection,
        to inputNode: AVAudioInputNode
    ) throws {
        guard !device.isSystemDefault else {
            return
        }

        guard let audioUnit = inputNode.audioUnit else {
            throw RecordingWorkflowError("microphone input unit unavailable")
        }

        guard var deviceID = coreAudioDeviceID(forUID: device.id) else {
            throw RecordingWorkflowError("selected microphone is unavailable: \(device.title)")
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw RecordingWorkflowError("failed to select microphone \(device.title): OSStatus \(status)")
        }
    }

    private static func availableCoreAudioInputDevices() -> [AudioInputDeviceSelection] {
        coreAudioInputDevices().compactMap { deviceID in
            guard
                let uid = coreAudioStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                let name = coreAudioStringProperty(deviceID, selector: kAudioObjectPropertyName)
            else {
                return nil
            }

            return .device(id: uid, title: name)
        }
    }

    private static func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        coreAudioInputDevices().first { deviceID in
            coreAudioStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) == uid
        }
    }

    private static func coreAudioInputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        )
        guard dataStatus == noErr else {
            return []
        }

        return devices.filter(hasInputStreams)
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func coreAudioStringProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            return nil
        }

        return value?.takeUnretainedValue() as String?
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

    func append(_ buffer: AVAudioPCMBuffer, audioChunkHandler: AudioCaptureChunkHandler? = nil) {
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
        let appendedSamples = audioBuffer.appendNonInterleavedFloat32(
            channels,
            sourceSampleRate: buffer.format.sampleRate
        )
        lock.unlock()

        if !appendedSamples.isEmpty {
            audioChunkHandler?(appendedSamples)
        }
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
