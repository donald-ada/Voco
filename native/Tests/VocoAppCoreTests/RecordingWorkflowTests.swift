import XCTest
@testable import VocoAppCore

final class RecordingWorkflowTests: XCTestCase {
    func testStartRecordingStartsAudioCapture() async throws {
        let audio = FakeAudioCaptureEngine()
        let workflow = NativeRecordingWorkflow(
            audioCapture: audio,
            transcription: FakeTranscriptionEngine(),
            textInjection: FakeTextInjectionEngine()
        )

        try await workflow.startRecording()

        XCTAssertEqual(audio.startCount, 1)
        XCTAssertEqual(audio.stopCount, 0)
    }

    func testStopRecordingTranscribesAndInjectsFinalText() async throws {
        let capturedAudio = CapturedAudioSnapshot(durationSeconds: 1.25, sampleRate: 16_000, peakAmplitude: 0.72)
        let transcript = TranscriptSnapshot(
            finalText: "hello world",
            partials: ["hello"],
            providerName: "Fake ASR",
            latencyMilliseconds: 42
        )
        let injection = TextInjectionSnapshot(
            targetAppName: "TextEdit",
            strategy: .directAccessibility,
            succeeded: true,
            detail: "Inserted through accessibility"
        )
        let audio = FakeAudioCaptureEngine(capturedAudio: capturedAudio)
        let transcription = FakeTranscriptionEngine(transcript: transcript)
        let textInjection = FakeTextInjectionEngine(result: injection)
        let workflow = NativeRecordingWorkflow(
            audioCapture: audio,
            transcription: transcription,
            textInjection: textInjection
        )

        let result = try await workflow.stopRecording()

        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(transcription.inputs, [capturedAudio])
        XCTAssertEqual(textInjection.requests, ["hello world"])
        XCTAssertEqual(result.audio, capturedAudio)
        XCTAssertEqual(result.transcript, transcript)
        XCTAssertEqual(result.injection, injection)
    }

    func testStopRecordingSkipsInjectionForEmptyFinalText() async throws {
        let transcript = TranscriptSnapshot(
            finalText: " \n ",
            partials: [],
            providerName: "Fake ASR",
            latencyMilliseconds: 12
        )
        let transcription = FakeTranscriptionEngine(transcript: transcript)
        let textInjection = FakeTextInjectionEngine()
        let workflow = NativeRecordingWorkflow(
            audioCapture: FakeAudioCaptureEngine(),
            transcription: transcription,
            textInjection: textInjection
        )

        let result = try await workflow.stopRecording()

        XCTAssertTrue(textInjection.requests.isEmpty)
        XCTAssertEqual(result.injection.strategy, .skippedEmpty)
        XCTAssertTrue(result.injection.succeeded)
        XCTAssertEqual(result.injection.detail, "Final transcript was empty; skipped text insertion.")
    }

    func testStartRecordingFailureIsThrownWithDescriptiveMessage() async {
        let audio = FakeAudioCaptureEngine()
        audio.startError = RecordingWorkflowError("microphone unavailable")
        let workflow = NativeRecordingWorkflow(
            audioCapture: audio,
            transcription: FakeTranscriptionEngine(),
            textInjection: FakeTextInjectionEngine()
        )

        do {
            try await workflow.startRecording()
            XCTFail("Expected startRecording to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "microphone unavailable")
        }
    }
}

private final class FakeAudioCaptureEngine: AudioCaptureProviding {
    var startCount = 0
    var stopCount = 0
    var startError: Error?
    var stopError: Error?
    let capturedAudio: CapturedAudioSnapshot

    init(capturedAudio: CapturedAudioSnapshot = CapturedAudioSnapshot(durationSeconds: 0.5, sampleRate: 16_000, peakAmplitude: 0.4)) {
        self.capturedAudio = capturedAudio
    }

    func startCapture() async throws {
        startCount += 1

        if let startError {
            throw startError
        }
    }

    func stopCapture() async throws -> CapturedAudioSnapshot {
        stopCount += 1

        if let stopError {
            throw stopError
        }

        return capturedAudio
    }
}

private final class FakeTranscriptionEngine: TranscriptionProviding {
    var inputs: [CapturedAudioSnapshot] = []
    var error: Error?
    let transcript: TranscriptSnapshot

    init(
        transcript: TranscriptSnapshot = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "Fake ASR",
            latencyMilliseconds: nil
        )
    ) {
        self.transcript = transcript
    }

    func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        inputs.append(audio)

        if let error {
            throw error
        }

        return transcript
    }
}

private final class FakeTextInjectionEngine: TextInjectionProviding {
    var requests: [String] = []
    var error: Error?
    let result: TextInjectionSnapshot

    init(
        result: TextInjectionSnapshot = TextInjectionSnapshot(
            targetAppName: "TextEdit",
            strategy: .unicodeEvent,
            succeeded: true,
            detail: "Inserted through unicode events"
        )
    ) {
        self.result = result
    }

    func insert(_ text: String) async throws -> TextInjectionSnapshot {
        requests.append(text)

        if let error {
            throw error
        }

        return result
    }
}
