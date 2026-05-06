import XCTest
@testable import VocoAppCore

final class RecordingWorkflowTests: XCTestCase {
    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testStopRecordingForwardsPartialProgress() async throws {
        let partial = TranscriptPartialSnapshot(
            text: "hello",
            stablePrefixLength: 0,
            providerName: "Fake ASR"
        )
        let transcription = FakeTranscriptionEngine(
            transcript: TranscriptSnapshot(
                finalText: "hello world",
                partials: ["hello"],
                providerName: "Fake ASR",
                latencyMilliseconds: 9
            ),
            partialsToEmit: [partial]
        )
        let workflow = NativeRecordingWorkflow(
            audioCapture: FakeAudioCaptureEngine(),
            transcription: transcription,
            textInjection: FakeTextInjectionEngine()
        )
        var received: [TranscriptPartialSnapshot] = []

        _ = try await workflow.stopRecording { progress in
            received.append(progress)
        }

        XCTAssertEqual(received, [partial])
    }

    @MainActor
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

    @MainActor
    func testStaticProvidersReturnConfiguredSnapshots() async throws {
        let audio = CapturedAudioSnapshot(
            durationSeconds: 0.2,
            sampleRate: 16_000,
            peakAmplitude: 0.1,
            pcm16Samples: [1, 2]
        )
        let transcript = try await StaticTranscriptionProvider().transcribe(audio)
        let injection = try await StaticTextInjectionProvider().insert("hello")

        XCTAssertEqual(transcript.providerName, "Unconfigured")
        XCTAssertEqual(transcript.finalText, "")
        XCTAssertEqual(injection.strategy, .skippedEmpty)
        XCTAssertTrue(injection.succeeded)
    }

    @MainActor
    func testUnavailableTranscriptionProviderFailsLoudly() async {
        let provider = UnavailableTranscriptionProvider()

        do {
            _ = try await provider.transcribe(
                CapturedAudioSnapshot(
                    durationSeconds: 1,
                    sampleRate: 16_000,
                    peakAmplitude: 0.2,
                    pcm16Samples: [1]
                )
            )
            XCTFail("Expected unavailable provider to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "转写服务未配置：请先在设置中配置 ASR provider。")
        }

        XCTAssertEqual(provider.status, .notConfigured)
    }

    @MainActor
    func testNativeRecordingWorkflowExposesTranscriptionStatus() {
        let workflow = NativeRecordingWorkflow(
            audioCapture: FakeAudioCaptureEngine(),
            transcription: UnavailableTranscriptionProvider(),
            textInjection: FakeTextInjectionEngine()
        )

        XCTAssertEqual(workflow.transcriptionStatus, .notConfigured)
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
    let partialsToEmit: [TranscriptPartialSnapshot]
    var status: TranscriptionProviderStatus {
        .ready(providerName: transcript.providerName)
    }

    init(
        transcript: TranscriptSnapshot = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "Fake ASR",
            latencyMilliseconds: nil
        ),
        partialsToEmit: [TranscriptPartialSnapshot] = []
    ) {
        self.transcript = transcript
        self.partialsToEmit = partialsToEmit
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        inputs.append(audio)

        if let error {
            throw error
        }

        for partial in partialsToEmit {
            progress?(partial)
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
