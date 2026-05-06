import Foundation

public struct CapturedAudioSnapshot: Equatable, Sendable {
    public let durationSeconds: Double
    public let sampleRate: Double
    public let peakAmplitude: Double

    public init(durationSeconds: Double, sampleRate: Double, peakAmplitude: Double) {
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.peakAmplitude = peakAmplitude
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

public enum TextInjectionStrategy: Equatable, Sendable {
    case directAccessibility
    case unicodeEvent
    case clipboardFallback
    case skippedEmpty

    public var title: String {
        switch self {
        case .directAccessibility:
            "辅助功能直接插入"
        case .unicodeEvent:
            "Unicode 事件"
        case .clipboardFallback:
            "剪贴板回退"
        case .skippedEmpty:
            "空文本跳过"
        }
    }
}

public struct TextInjectionSnapshot: Equatable, Sendable {
    public let targetAppName: String?
    public let strategy: TextInjectionStrategy
    public let succeeded: Bool
    public let detail: String

    public init(targetAppName: String?, strategy: TextInjectionStrategy, succeeded: Bool, detail: String) {
        self.targetAppName = targetAppName
        self.strategy = strategy
        self.succeeded = succeeded
        self.detail = detail
    }

    public static var skippedEmpty: TextInjectionSnapshot {
        TextInjectionSnapshot(
            targetAppName: nil,
            strategy: .skippedEmpty,
            succeeded: true,
            detail: "Final transcript was empty; skipped text insertion."
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

public protocol AudioCaptureProviding {
    func startCapture() async throws
    func stopCapture() async throws -> CapturedAudioSnapshot
}

public protocol TranscriptionProviding {
    func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot
}

public protocol TextInjectionProviding {
    func insert(_ text: String) async throws -> TextInjectionSnapshot
}

public protocol RecordingWorkflowing: AnyObject {
    func startRecording() async throws
    func stopRecording() async throws -> RecordingWorkflowResult
}

public final class NativeRecordingWorkflow: RecordingWorkflowing {
    private let audioCapture: any AudioCaptureProviding
    private let transcription: any TranscriptionProviding
    private let textInjection: any TextInjectionProviding

    public init(
        audioCapture: any AudioCaptureProviding,
        transcription: any TranscriptionProviding,
        textInjection: any TextInjectionProviding
    ) {
        self.audioCapture = audioCapture
        self.transcription = transcription
        self.textInjection = textInjection
    }

    public func startRecording() async throws {
        try await audioCapture.startCapture()
    }

    public func stopRecording() async throws -> RecordingWorkflowResult {
        let audio = try await audioCapture.stopCapture()
        let transcript = try await transcription.transcribe(audio)
        let insertion = try await insertionSnapshot(for: transcript)

        return RecordingWorkflowResult(audio: audio, transcript: transcript, injection: insertion)
    }

    private func insertionSnapshot(for transcript: TranscriptSnapshot) async throws -> TextInjectionSnapshot {
        let trimmedText = transcript.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .skippedEmpty
        }

        return try await textInjection.insert(transcript.finalText)
    }
}

public final class StaticRecordingWorkflow: RecordingWorkflowing {
    private let result: RecordingWorkflowResult
    private let startError: Error?
    private let stopError: Error?

    public init(
        result: RecordingWorkflowResult = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 0, sampleRate: 0, peakAmplitude: 0),
            transcript: TranscriptSnapshot(finalText: "", partials: [], providerName: "Unconfigured", latencyMilliseconds: nil),
            injection: .skippedEmpty
        ),
        startError: Error? = nil,
        stopError: Error? = nil
    ) {
        self.result = result
        self.startError = startError
        self.stopError = stopError
    }

    public func startRecording() async throws {
        if let startError {
            throw startError
        }
    }

    public func stopRecording() async throws -> RecordingWorkflowResult {
        if let stopError {
            throw stopError
        }

        return result
    }
}
