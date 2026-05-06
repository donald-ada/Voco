import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacDoubaoTranscriptionProviderTests: XCTestCase {
    func testProviderReportsAuthenticationRequiredWithoutStoredAPIKey() {
        let provider = MacDoubaoTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(),
            transport: FakeDoubaoTransport(),
            legacyConfigURL: nil
        )

        XCTAssertEqual(provider.status, .authenticationRequired(providerName: "Doubao"))
    }

    func testProviderFailsBeforeTransportWhenCredentialIsMissing() async {
        let transport = FakeDoubaoTransport()
        let provider = MacDoubaoTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(),
            transport: transport,
            legacyConfigURL: nil
        )

        do {
            _ = try await provider.transcribe(
                CapturedAudioSnapshot(
                    durationSeconds: 1,
                    sampleRate: 16_000,
                    peakAmplitude: 0.2,
                    pcm16Samples: [1]
                )
            )
            XCTFail("Expected missing credential failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Doubao 认证失败：Keychain 中没有保存 Doubao API Key。"
            )
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testProviderBuildsRequestFromStoredAPIKeyAndForwardsProgress() async throws {
        let partial = TranscriptPartialSnapshot(
            text: "hello",
            stablePrefixLength: 0,
            providerName: "Doubao"
        )
        let transport = FakeDoubaoTransport(
            transcript: TranscriptSnapshot(
                finalText: "hello world",
                partials: ["hello"],
                providerName: "Doubao",
                latencyMilliseconds: 12
            ),
            partialsToEmit: [partial]
        )
        let provider = MacDoubaoTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-secret"),
            transport: transport,
            legacyConfigURL: nil
        )
        var received: [TranscriptPartialSnapshot] = []

        let transcript = try await provider.transcribe(
            CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2]
            )
        ) { progress in
            received.append(progress)
        }

        XCTAssertEqual(provider.status, .ready(providerName: "Doubao"))
        XCTAssertEqual(transcript.finalText, "hello world")
        XCTAssertEqual(received, [partial])
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.headers["X-Api-Key"], "sk-test-secret")
        XCTAssertNil(transport.requests.first?.safeDebugDescription.range(of: "sk-test-secret"))
    }

    func testProviderPrefersLegacyConfigAppIDAccessTokenCredentials() async throws {
        let legacyConfigURL = try makeLegacyDoubaoConfig(
            appID: "3145608744",
            accessToken: "legacy-token",
            resourceID: "volc.seedasr.sauc.duration"
        )
        defer { try? FileManager.default.removeItem(at: legacyConfigURL.deletingLastPathComponent()) }

        let transport = FakeDoubaoTransport()
        let provider = MacDoubaoTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(apiKey: "wrong-api-key"),
            transport: transport,
            legacyConfigURL: legacyConfigURL
        )

        _ = try await provider.transcribe(
            CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2]
            )
        )

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(
            transport.requests.first?.endpoint.absoluteString,
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        )
        XCTAssertEqual(transport.requests.first?.headers["X-Api-App-Key"], "3145608744")
        XCTAssertEqual(transport.requests.first?.headers["X-Api-Access-Key"], "legacy-token")
        XCTAssertNil(transport.requests.first?.headers["X-Api-Key"])
    }

    func testProviderStartsStreamingFromLegacyConfigCredentials() async throws {
        let legacyConfigURL = try makeLegacyDoubaoConfig(
            appID: "3145608744",
            accessToken: "legacy-token",
            resourceID: "volc.seedasr.sauc.duration"
        )
        defer { try? FileManager.default.removeItem(at: legacyConfigURL.deletingLastPathComponent()) }

        let transport = FakeDoubaoTransport()
        let provider = MacDoubaoTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(apiKey: "wrong-api-key"),
            transport: transport,
            legacyConfigURL: legacyConfigURL
        )

        _ = try await provider.startStreaming(progress: nil)

        XCTAssertEqual(transport.streamingRequests.count, 1)
        XCTAssertEqual(
            transport.streamingRequests.first?.endpoint.absoluteString,
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        )
        XCTAssertEqual(transport.streamingRequests.first?.headers["X-Api-App-Key"], "3145608744")
        XCTAssertEqual(transport.streamingRequests.first?.headers["X-Api-Access-Key"], "legacy-token")
        XCTAssertNil(transport.streamingRequests.first?.headers["X-Api-Key"])
    }

    func testURLSessionTransportStreamsBinaryFramesAndReturnsFinalTranscript() async throws {
        let finalFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionRequest.make(
            apiKey: "sk-test-secret",
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1]
            )
        )

        let transcript = try await transport.transcribe(request: request, progress: nil)

        XCTAssertEqual(transcript.finalText, "hello world")
        XCTAssertEqual(session.requests.count, 1)
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-Key"), "sk-test-secret")
        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.sentMessages.count, 2)
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingSendsAudioChunksAndReturnsFinalTranscript() async throws {
        let partialFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello","utterances":[{"text":"hello","start_time":0,"end_time":400,"definite":false}]}}"#,
            last: false
        )
        let finalFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(partialFrame), .data(finalFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionSessionRequest.make(apiKey: "sk-test-secret")
        var received: [TranscriptPartialSnapshot] = []

        let streamingSession = try await transport.startStreaming(request: request) { progress in
            received.append(progress)
        }
        await streamingSession.acceptAudioChunk([1, 2, 3])
        XCTAssertEqual(task.sentMessages.count, 1)
        let transcript = try await streamingSession.finish(
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2, 3]
            )
        )

        XCTAssertEqual(transcript.finalText, "hello world")
        XCTAssertEqual(received.map(\.text), ["hello"])
        XCTAssertEqual(session.requests.count, 1)
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-Key"), "sk-test-secret")
        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.sentMessages.count, 2)
        guard case .data(let lastFrame) = task.sentMessages.last else {
            XCTFail("Expected final audio frame")
            return
        }
        XCTAssertEqual(Array(lastFrame.prefix(4)), [0x11, 0x22, 0x01, 0x00])
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingUsesLatestPartialWhenFinalFrameHasNoText() async throws {
        let partialFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":false}]}}"#,
            last: false
        )
        let finalFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"","utterances":[]}}"#,
            last: true
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(partialFrame), .data(finalFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionSessionRequest.make(apiKey: "sk-test-secret")

        let streamingSession = try await transport.startStreaming(request: request, progress: nil)
        await streamingSession.acceptAudioChunk([1, 2, 3])
        let transcript = try await streamingSession.finish(
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2, 3]
            )
        )

        XCTAssertEqual(transcript.finalText, "hello world")
        XCTAssertEqual(transcript.partials, ["hello world"])
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingReturnsEmptyTranscriptWhenFinalFrameHasNoTextOrPartials() async throws {
        let finalFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"","utterances":[]}}"#,
            last: true
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionSessionRequest.make(apiKey: "sk-test-secret")

        let streamingSession = try await transport.startStreaming(request: request, progress: nil)
        let transcript = try await streamingSession.finish(
            audio: CapturedAudioSnapshot(
                durationSeconds: 0.1,
                sampleRate: 16_000,
                peakAmplitude: 0,
                pcm16Samples: Array(repeating: 0, count: 1_600)
            )
        )

        XCTAssertEqual(transcript.finalText, "")
        XCTAssertEqual(transcript.partials, [])
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingFlushesFullAudioFramesBeforeFinish() async throws {
        let finalFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionSessionRequest.make(apiKey: "sk-test-secret")
        let frameSamples = Array(repeating: Int16(1), count: 3_200)

        let streamingSession = try await transport.startStreaming(request: request, progress: nil)
        await streamingSession.acceptAudioChunk(frameSamples)

        XCTAssertEqual(task.sentMessages.count, 2)
        guard case .data(let audioFrame) = task.sentMessages.last else {
            XCTFail("Expected streaming audio frame")
            return
        }
        XCTAssertEqual(Array(audioFrame.prefix(4)), [0x11, 0x20, 0x01, 0x00])

        let transcript = try await streamingSession.finish(
            audio: CapturedAudioSnapshot(
                durationSeconds: 0.2,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: frameSamples
            )
        )

        XCTAssertEqual(transcript.finalText, "hello world")
        XCTAssertEqual(task.sentMessages.count, 3)
        guard case .data(let lastFrame) = task.sentMessages.last else {
            XCTFail("Expected final audio frame")
            return
        }
        XCTAssertEqual(Array(lastFrame.prefix(4)), [0x11, 0x22, 0x01, 0x00])
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingChunksSnapshotAudioWhenNoRealtimeChunksWereSent() async throws {
        let finalFrame = try DoubaoWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionSessionRequest.make(apiKey: "sk-test-secret")
        let samples = Array(repeating: Int16(1), count: 6_401)

        let streamingSession = try await transport.startStreaming(request: request, progress: nil)
        _ = try await streamingSession.finish(
            audio: CapturedAudioSnapshot(
                durationSeconds: 0.5,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: samples
            )
        )

        XCTAssertEqual(task.sentMessages.count, 4)
        let audioFrameHeaders = task.sentMessages.dropFirst().compactMap { message -> [UInt8]? in
            guard case .data(let frame) = message else {
                return nil
            }
            return Array(frame.prefix(4))
        }
        XCTAssertEqual(
            audioFrameHeaders,
            [
                [0x11, 0x20, 0x01, 0x00],
                [0x11, 0x20, 0x01, 0x00],
                [0x11, 0x22, 0x01, 0x00]
            ]
        )
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportPreservesServerErrorClassification() async throws {
        let errorFrame = DoubaoWireProtocol.buildTestServerErrorFrame(
            code: 45000002,
            message: "empty audio"
        )
        let task = FakeDoubaoWebSocketTask(receiveMessages: [.data(errorFrame)])
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionRequest.make(
            apiKey: "sk-test-secret",
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1]
            )
        )

        do {
            _ = try await transport.transcribe(request: request, progress: nil)
            XCTFail("Expected server error classification")
        } catch {
            XCTAssertEqual(error as? TranscriptionProviderError, .emptyAudio)
        }

        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportMapsPingFailureAndCancels() async throws {
        let task = FakeDoubaoWebSocketTask(sendError: URLError(.timedOut))
        let session = FakeDoubaoWebSocketSession(task: task)
        let transport = URLSessionDoubaoTranscriptionTransport(session: session)
        let request = try DoubaoTranscriptionRequest.make(
            apiKey: "sk-test-secret",
            audio: CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1]
            )
        )

        do {
            _ = try await transport.transcribe(request: request, progress: nil)
            XCTFail("Expected transport failure")
        } catch let providerError as TranscriptionProviderError {
            guard case .transport(let providerName, let message, let retryable) = providerError else {
                XCTFail("Expected transport error, got \(providerError)")
                return
            }
            XCTAssertEqual(providerName, "Doubao")
            XCTAssertTrue(message.contains("WebSocket connect to \(request.endpoint.absoluteString) failed"))
            XCTAssertTrue(retryable)
        } catch {
            XCTFail("Expected TranscriptionProviderError, got \(error)")
        }

        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    private func makeLegacyDoubaoConfig(
        appID: String,
        accessToken: String,
        resourceID: String
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voco-native-doubao-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.toml")
        let contents = """
        backend = "doubao"

        [doubao]
        app_id = "\(appID)"
        access_token = "\(accessToken)"
        endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        model_id = "bigmodel"
        resource_id = "\(resourceID)"
        """
        try Data(contents.utf8).write(to: url)
        return url
    }
}

@MainActor
private final class FakeDoubaoTransport: DoubaoTranscriptionTransporting {
    private(set) var requests: [DoubaoTranscriptionRequest] = []
    private(set) var streamingRequests: [DoubaoTranscriptionSessionRequest] = []
    let transcript: TranscriptSnapshot
    let partialsToEmit: [TranscriptPartialSnapshot]
    var error: Error?

    init(
        transcript: TranscriptSnapshot = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "Doubao",
            latencyMilliseconds: nil
        ),
        partialsToEmit: [TranscriptPartialSnapshot] = []
    ) {
        self.transcript = transcript
        self.partialsToEmit = partialsToEmit
    }

    func transcribe(
        request: DoubaoTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        requests.append(request)

        if let error {
            throw error
        }

        for partial in partialsToEmit {
            progress?(partial)
        }

        return transcript
    }

    func startStreaming(
        request: DoubaoTranscriptionSessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession {
        streamingRequests.append(request)

        if let error {
            throw error
        }

        return FakeDoubaoStreamingSession(transcript: transcript, partialsToEmit: partialsToEmit, progress: progress)
    }
}

private actor FakeDoubaoStreamingSession: RealtimeTranscriptionSession {
    let transcript: TranscriptSnapshot
    let partialsToEmit: [TranscriptPartialSnapshot]
    let progress: TranscriptionProgressHandler?

    init(
        transcript: TranscriptSnapshot,
        partialsToEmit: [TranscriptPartialSnapshot],
        progress: TranscriptionProgressHandler?
    ) {
        self.transcript = transcript
        self.partialsToEmit = partialsToEmit
        self.progress = progress
    }

    func acceptAudioChunk(_ pcm16Samples: [Int16]) async {
        for partial in partialsToEmit {
            await progress?(partial)
        }
    }

    func finish(audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        transcript
    }

    func cancel() async {}
}

@MainActor
private final class FakeDoubaoWebSocketSession: DoubaoWebSocketSessioning {
    private let task: FakeDoubaoWebSocketTask
    private(set) var requests: [URLRequest] = []

    init(task: FakeDoubaoWebSocketTask) {
        self.task = task
    }

    func webSocketTask(with request: URLRequest) -> any DoubaoWebSocketTasking {
        requests.append(request)
        return task
    }
}

@MainActor
private final class FakeDoubaoWebSocketTask: DoubaoWebSocketTasking, @unchecked Sendable {
    private let sendError: Error?
    private var receiveMessages: [URLSessionWebSocketTask.Message]
    private(set) var resumeCount = 0
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    private(set) var cancelCodes: [URLSessionWebSocketTask.CloseCode] = []

    init(
        sendError: Error? = nil,
        receiveMessages: [URLSessionWebSocketTask.Message] = []
    ) {
        self.sendError = sendError
        self.receiveMessages = receiveMessages
    }

    func resume() {
        resumeCount += 1
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        if let sendError {
            throw sendError
        }
        sentMessages.append(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard !receiveMessages.isEmpty else {
            throw URLError(.badServerResponse)
        }

        return receiveMessages.removeFirst()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelCodes.append(closeCode)
    }
}
