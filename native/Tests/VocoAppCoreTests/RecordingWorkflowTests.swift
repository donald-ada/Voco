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
        let capturedAudio = CapturedAudioSnapshot(
            durationSeconds: 1.25,
            sampleRate: 16_000,
            peakAmplitude: 0.72,
            pcm16Samples: Array(repeating: 1, count: 20_000)
        )
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
        XCTAssertEqual(result.injection.detail, "最终转写为空，已跳过文本插入。")
        XCTAssertEqual(
            result.injection.detail(strings: VocoStrings(language: .en)),
            "Final transcript was empty; skipped text insertion."
        )
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
    func testStartRecordingStreamsAudioChunksToRealtimeTranscription() async throws {
        let partial = TranscriptPartialSnapshot(
            text: "live recording",
            stablePrefixLength: 0,
            providerName: "Fake ASR"
        )
        let audioCapture = FakeAudioCaptureEngine()
        let transcription = FakeRealtimeTranscriptionEngine(
            transcript: TranscriptSnapshot(
                finalText: "live recording final",
                partials: ["live recording"],
                providerName: "Fake ASR",
                latencyMilliseconds: 7
            ),
            partialsToEmitAfterAudio: [partial]
        )
        let workflow = NativeRecordingWorkflow(
            audioCapture: audioCapture,
            transcription: transcription,
            textInjection: FakeTextInjectionEngine()
        )
        var received: [TranscriptPartialSnapshot] = []

        try await workflow.startRecording { progress in
            received.append(progress)
        }
        audioCapture.emitAudioChunk([1, 2, 3])
        await transcription.waitUntilAudioChunksReceived()
        let result = try await workflow.stopRecording()
        let audioChunks = await transcription.streamingSession?.audioChunksSnapshot()

        XCTAssertEqual(received, [partial])
        XCTAssertEqual(audioChunks, [[1, 2, 3]])
        XCTAssertTrue(transcription.inputs.isEmpty)
        XCTAssertEqual(result.transcript.finalText, "live recording final")
    }

    @MainActor
    func testStopRecordingCancelsRealtimeTranscriptionAndSkipsInsertionForTooShortAudio() async throws {
        let audioCapture = FakeAudioCaptureEngine(
            capturedAudio: CapturedAudioSnapshot(
                durationSeconds: 0.08,
                sampleRate: 16_000,
                peakAmplitude: 0.5,
                pcm16Samples: Array(repeating: 1, count: 1_280)
            )
        )
        let transcription = FakeRealtimeTranscriptionEngine(
            transcript: TranscriptSnapshot(
                finalText: "should not be used",
                partials: [],
                providerName: "Fake ASR",
                latencyMilliseconds: nil
            ),
            partialsToEmitAfterAudio: []
        )
        let textInjection = FakeTextInjectionEngine()
        let workflow = NativeRecordingWorkflow(
            audioCapture: audioCapture,
            transcription: transcription,
            textInjection: textInjection
        )

        try await workflow.startRecording()
        let result = try await workflow.stopRecording()
        let didFinish = await transcription.streamingSession?.didFinish() ?? false
        let didCancel = await transcription.streamingSession?.didCancel() ?? false

        XCTAssertFalse(didFinish)
        XCTAssertTrue(didCancel)
        XCTAssertEqual(result.audio, audioCapture.capturedAudio)
        XCTAssertEqual(result.transcript.finalText, "")
        XCTAssertEqual(result.transcript.partials, [])
        XCTAssertEqual(result.injection, .skippedEmpty)
        XCTAssertTrue(textInjection.requests.isEmpty)
    }

    @MainActor
    func testStopRecordingSkipsTranscriptionAndInsertionForSilentAudio() async throws {
        let silentAudio = CapturedAudioSnapshot(
            durationSeconds: 1.0,
            sampleRate: 16_000,
            peakAmplitude: 0,
            pcm16Samples: Array(repeating: 0, count: 16_000)
        )
        let audioCapture = FakeAudioCaptureEngine(capturedAudio: silentAudio)
        let transcription = FakeTranscriptionEngine(
            transcript: TranscriptSnapshot(
                finalText: "should not be used",
                partials: [],
                providerName: "Fake ASR",
                latencyMilliseconds: nil
            )
        )
        let textInjection = FakeTextInjectionEngine()
        let workflow = NativeRecordingWorkflow(
            audioCapture: audioCapture,
            transcription: transcription,
            textInjection: textInjection
        )

        let result = try await workflow.stopRecording()

        XCTAssertTrue(transcription.inputs.isEmpty)
        XCTAssertEqual(result.audio, silentAudio)
        XCTAssertEqual(result.transcript.finalText, "")
        XCTAssertEqual(result.transcript.partials, [])
        XCTAssertEqual(result.injection, .skippedEmpty)
        XCTAssertTrue(textInjection.requests.isEmpty)
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
            XCTAssertEqual(error.localizedDescription, "模型未配置：请先在设置中配置火山引擎凭证。")
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
    private var audioChunkHandler: AudioCaptureChunkHandler?

    init(
        capturedAudio: CapturedAudioSnapshot = CapturedAudioSnapshot(
            durationSeconds: 0.5,
            sampleRate: 16_000,
            peakAmplitude: 0.4,
            pcm16Samples: Array(repeating: 1, count: 8_000)
        )
    ) {
        self.capturedAudio = capturedAudio
    }

    func startCapture() async throws {
        try await startCapture(audioChunkHandler: nil)
    }

    func startCapture(audioChunkHandler: AudioCaptureChunkHandler?) async throws {
        startCount += 1
        self.audioChunkHandler = audioChunkHandler

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

    func emitAudioChunk(_ samples: [Int16]) {
        audioChunkHandler?(samples)
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

private final class FakeRealtimeTranscriptionEngine: TranscriptionProviding, RealtimeTranscriptionProviding {
    var inputs: [CapturedAudioSnapshot] = []
    let transcript: TranscriptSnapshot
    let partialsToEmitAfterAudio: [TranscriptPartialSnapshot]
    private(set) var streamingSession: FakeRealtimeTranscriptionSession?
    var status: TranscriptionProviderStatus {
        .ready(providerName: transcript.providerName)
    }

    init(
        transcript: TranscriptSnapshot,
        partialsToEmitAfterAudio: [TranscriptPartialSnapshot]
    ) {
        self.transcript = transcript
        self.partialsToEmitAfterAudio = partialsToEmitAfterAudio
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        inputs.append(audio)
        return transcript
    }

    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession {
        let session = FakeRealtimeTranscriptionSession(
            transcript: transcript,
            partialsToEmitAfterAudio: partialsToEmitAfterAudio,
            progress: progress
        )
        streamingSession = session
        return session
    }

    func waitUntilAudioChunksReceived() async {
        await streamingSession?.waitUntilAudioChunksReceived()
    }
}

private actor FakeRealtimeTranscriptionSession: RealtimeTranscriptionSession {
    private var audioChunks: [[Int16]] = []
    private let transcript: TranscriptSnapshot
    private let partialsToEmitAfterAudio: [TranscriptPartialSnapshot]
    private let progress: TranscriptionProgressHandler?
    private var didEmitPartials = false
    private var finishCount = 0
    private var cancelCount = 0
    private var audioChunksContinuation: CheckedContinuation<Void, Never>?

    init(
        transcript: TranscriptSnapshot,
        partialsToEmitAfterAudio: [TranscriptPartialSnapshot],
        progress: TranscriptionProgressHandler?
    ) {
        self.transcript = transcript
        self.partialsToEmitAfterAudio = partialsToEmitAfterAudio
        self.progress = progress
    }

    func acceptAudioChunk(_ pcm16Samples: [Int16]) async {
        audioChunks.append(pcm16Samples)

        if !didEmitPartials {
            didEmitPartials = true
            for partial in partialsToEmitAfterAudio {
                await progress?(partial)
            }
        }

        audioChunksContinuation?.resume()
        audioChunksContinuation = nil
    }

    func finish(audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        finishCount += 1
        return transcript
    }

    func cancel() async {
        cancelCount += 1
    }

    func audioChunksSnapshot() -> [[Int16]] {
        audioChunks
    }

    func didFinish() -> Bool {
        finishCount > 0
    }

    func didCancel() -> Bool {
        cancelCount > 0
    }

    func waitUntilAudioChunksReceived() async {
        if !audioChunks.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            audioChunksContinuation = continuation
        }
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
