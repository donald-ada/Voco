import Foundation

public typealias AudioCaptureChunkHandler = @Sendable ([Int16]) -> Void

public struct CapturedAudioSnapshot: Equatable, Sendable {
    public let durationSeconds: Double
    public let sampleRate: Double
    public let peakAmplitude: Double
    public let pcm16Samples: [Int16]

    public init(durationSeconds: Double, sampleRate: Double, peakAmplitude: Double, pcm16Samples: [Int16] = []) {
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.peakAmplitude = peakAmplitude
        self.pcm16Samples = pcm16Samples
    }
}

public struct TranscriptSnapshot: Equatable, Sendable {
    public let finalText: String
    public let partials: [String]
    public let providerName: String
    public let latencyMilliseconds: Int?

    public init(finalText: String, partials: [String], providerName: String, latencyMilliseconds: Int?) {
        self.finalText = finalText
        self.partials = partials
        self.providerName = providerName
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public extension TranscriptSnapshot {
    func appendingPartial(_ partial: TranscriptPartialSnapshot) -> TranscriptSnapshot {
        let trimmedText = partial.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return self
        }

        return TranscriptSnapshot(
            finalText: finalText,
            partials: partials + [trimmedText],
            providerName: partial.providerName,
            latencyMilliseconds: latencyMilliseconds
        )
    }
}

public struct RecordingWorkflowResult: Equatable, Sendable {
    public let audio: CapturedAudioSnapshot
    public let transcript: TranscriptSnapshot
    public let injection: TextInjectionSnapshot

    public init(audio: CapturedAudioSnapshot, transcript: TranscriptSnapshot, injection: TextInjectionSnapshot) {
        self.audio = audio
        self.transcript = transcript
        self.injection = injection
    }
}

public struct RecordingWorkflowError: LocalizedError, Equatable, Sendable {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

@MainActor
public protocol AudioCaptureProviding {
    func startCapture() async throws
    func startCapture(audioChunkHandler: AudioCaptureChunkHandler?) async throws
    func stopCapture() async throws -> CapturedAudioSnapshot
}

public extension AudioCaptureProviding {
    func startCapture(audioChunkHandler: AudioCaptureChunkHandler?) async throws {
        try await startCapture()
    }
}

@MainActor
public protocol TranscriptionProviding {
    var status: TranscriptionProviderStatus { get }
    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot
}

public extension TranscriptionProviding {
    func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        try await transcribe(audio, progress: nil)
    }
}

public protocol RealtimeTranscriptionSession: Sendable {
    func acceptAudioChunk(_ pcm16Samples: [Int16]) async
    func finish(audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot
    func cancel() async
}

@MainActor
public protocol RealtimeTranscriptionProviding: TranscriptionProviding {
    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession
}

@MainActor
public protocol TextInjectionProviding {
    func insert(_ text: String) async throws -> TextInjectionSnapshot
}

@MainActor
public protocol RecordingWorkflowing: AnyObject {
    var transcriptionStatus: TranscriptionProviderStatus { get }
    func startRecording() async throws
    func startRecording(progress: TranscriptionProgressHandler?) async throws
    func stopRecording(progress: TranscriptionProgressHandler?) async throws -> RecordingWorkflowResult
}

public extension RecordingWorkflowing {
    func startRecording(progress: TranscriptionProgressHandler?) async throws {
        try await startRecording()
    }

    func stopRecording() async throws -> RecordingWorkflowResult {
        try await stopRecording(progress: nil)
    }
}

public final class NativeRecordingWorkflow: RecordingWorkflowing {
    private static let minimumTranscribableDurationSeconds = 0.25
    private static let minimumSpeechPeakAmplitude = 0.003

    private let audioCapture: any AudioCaptureProviding
    private let transcription: any TranscriptionProviding
    private let textInjection: any TextInjectionProviding
    private var currentStreamingSession: (any RealtimeTranscriptionSession)?

    public init(
        audioCapture: any AudioCaptureProviding,
        transcription: any TranscriptionProviding,
        textInjection: any TextInjectionProviding
    ) {
        self.audioCapture = audioCapture
        self.transcription = transcription
        self.textInjection = textInjection
    }

    public var transcriptionStatus: TranscriptionProviderStatus {
        transcription.status
    }

    public func startRecording() async throws {
        try await startRecording(progress: nil)
    }

    public func startRecording(progress: TranscriptionProgressHandler? = nil) async throws {
        guard currentStreamingSession == nil else {
            throw RecordingWorkflowError("transcription stream already running")
        }

        if let realtimeTranscription = transcription as? any RealtimeTranscriptionProviding {
            let streamingSession = try await realtimeTranscription.startStreaming(progress: progress)
            currentStreamingSession = streamingSession

            do {
                try await audioCapture.startCapture { samples in
                    Task {
                        await streamingSession.acceptAudioChunk(samples)
                    }
                }
            } catch {
                currentStreamingSession = nil
                await streamingSession.cancel()
                throw error
            }
        } else {
            try await audioCapture.startCapture()
        }
    }

    public func stopRecording(progress: TranscriptionProgressHandler? = nil) async throws -> RecordingWorkflowResult {
        let audio: CapturedAudioSnapshot
        do {
            audio = try await audioCapture.stopCapture()
        } catch {
            if let streamingSession = currentStreamingSession {
                currentStreamingSession = nil
                await streamingSession.cancel()
            }
            throw error
        }

        let transcript: TranscriptSnapshot
        if !Self.isTranscribableAudio(audio) {
            if let streamingSession = currentStreamingSession {
                currentStreamingSession = nil
                await streamingSession.cancel()
            }

            transcript = emptyTranscript()
            let insertion = try await insertionSnapshot(for: transcript)
            return RecordingWorkflowResult(audio: audio, transcript: transcript, injection: insertion)
        }

        if let streamingSession = currentStreamingSession {
            currentStreamingSession = nil
            transcript = try await streamingSession.finish(audio: audio)
        } else {
            transcript = try await transcription.transcribe(audio, progress: progress)
        }
        let insertion = try await insertionSnapshot(for: transcript)

        return RecordingWorkflowResult(audio: audio, transcript: transcript, injection: insertion)
    }

    private static func isTranscribableAudio(_ audio: CapturedAudioSnapshot) -> Bool {
        audio.durationSeconds >= minimumTranscribableDurationSeconds
            && !audio.pcm16Samples.isEmpty
            && audio.peakAmplitude >= minimumSpeechPeakAmplitude
    }

    private func emptyTranscript() -> TranscriptSnapshot {
        TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: transcriptionProviderName,
            latencyMilliseconds: nil
        )
    }

    private var transcriptionProviderName: String {
        switch transcription.status {
        case .notConfigured:
            return "Unconfigured"
        case .ready(let providerName),
             .authenticationRequired(let providerName),
             .offline(let providerName),
             .failed(let providerName, _):
            return providerName
        }
    }

    private func insertionSnapshot(for transcript: TranscriptSnapshot) async throws -> TextInjectionSnapshot {
        let trimmedText = transcript.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .skippedEmpty
        }

        return try await textInjection.insert(transcript.finalText)
    }
}

public final class StaticTranscriptionProvider: TranscriptionProviding {
    private let transcript: TranscriptSnapshot

    public init(
        transcript: TranscriptSnapshot = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "Unconfigured",
            latencyMilliseconds: nil
        )
    ) {
        self.transcript = transcript
    }

    public var status: TranscriptionProviderStatus {
        .ready(providerName: transcript.providerName)
    }

    public func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler? = nil
    ) async throws -> TranscriptSnapshot {
        transcript
    }
}

public final class UnavailableTranscriptionProvider: TranscriptionProviding {
    public init() {}

    public var status: TranscriptionProviderStatus {
        .notConfigured
    }

    public func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler? = nil
    ) async throws -> TranscriptSnapshot {
        throw TranscriptionProviderError.notConfigured
    }
}

public final class StaticTextInjectionProvider: TextInjectionProviding {
    private let result: TextInjectionSnapshot

    public init(result: TextInjectionSnapshot = .skippedEmpty) {
        self.result = result
    }

    public func insert(_ text: String) async throws -> TextInjectionSnapshot {
        result
    }
}

public final class StaticRecordingWorkflow: RecordingWorkflowing {
    public let transcriptionStatus: TranscriptionProviderStatus
    private let result: RecordingWorkflowResult
    private let startError: Error?
    private let stopError: Error?

    public init(
        result: RecordingWorkflowResult = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 0, sampleRate: 0, peakAmplitude: 0),
            transcript: TranscriptSnapshot(finalText: "", partials: [], providerName: "Unconfigured", latencyMilliseconds: nil),
            injection: .skippedEmpty
        ),
        transcriptionStatus: TranscriptionProviderStatus = .notConfigured,
        startError: Error? = nil,
        stopError: Error? = nil
    ) {
        self.result = result
        self.transcriptionStatus = transcriptionStatus
        self.startError = startError
        self.stopError = stopError
    }

    public func startRecording() async throws {
        if let startError {
            throw startError
        }
    }

    public func stopRecording(progress: TranscriptionProgressHandler? = nil) async throws -> RecordingWorkflowResult {
        if let stopError {
            throw stopError
        }

        return result
    }
}
