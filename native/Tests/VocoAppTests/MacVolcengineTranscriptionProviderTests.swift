import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacVolcengineTranscriptionProviderTests: XCTestCase {
    func testProviderReportsAuthenticationRequiredWithoutStoredAPIKey() {
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(),
            transport: FakeVolcengineTransport()
        )

        XCTAssertEqual(provider.status, .authenticationRequired(providerName: "火山引擎"))
    }

    func testProviderFailsBeforeTransportWhenCredentialIsMissing() async {
        let transport = FakeVolcengineTransport()
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(),
            transport: transport
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
                "火山引擎认证失败：Keychain 中没有保存火山引擎凭证。"
            )
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testProviderBuildsRealtimeGatewayRequestFromStoredAPIKey() async throws {
        let openSpeechTransport = FakeVolcengineTransport()
        let gatewayTransport = FakeVolcengineRealtimeGatewayTransport(
            transcript: TranscriptSnapshot(
                finalText: "hello gateway",
                partials: [],
                providerName: "火山引擎",
                latencyMilliseconds: 12
            )
        )
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-secret"),
            transport: openSpeechTransport,
            realtimeGatewayTransport: gatewayTransport
        )

        let transcript = try await provider.transcribe(
            CapturedAudioSnapshot(
                durationSeconds: 1,
                sampleRate: 16_000,
                peakAmplitude: 0.2,
                pcm16Samples: [1, 2]
            )
        )

        XCTAssertEqual(provider.status, .ready(providerName: "火山引擎"))
        XCTAssertEqual(transcript.finalText, "hello gateway")
        XCTAssertTrue(openSpeechTransport.requests.isEmpty)
        XCTAssertEqual(gatewayTransport.requests.count, 1)
        XCTAssertEqual(
            gatewayTransport.requests.first?.endpoint.absoluteString,
            "wss://ai-gateway.vei.volces.com/v1/realtime?model=bigmodel"
        )
        XCTAssertEqual(gatewayTransport.requests.first?.headers["Authorization"], "Bearer sk-test-secret")
    }

    func testProviderBuildsRequestFromStoredAppIDAccessTokenCredential() async throws {
        let transport = FakeVolcengineTransport()
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(
                credential: .volcengineAppIDAccessToken(
                    appID: "3145608744",
                    accessToken: "legacy-token"
                )
            ),
            transport: transport
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
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
        )
        XCTAssertEqual(transport.requests.first?.headers["X-Api-App-Key"], "3145608744")
        XCTAssertEqual(transport.requests.first?.headers["X-Api-Access-Key"], "legacy-token")
        XCTAssertNil(transport.requests.first?.headers["X-Api-Key"])
    }

    func testProviderStartsStreamingFromStoredAppIDAccessTokenCredential() async throws {
        let transport = FakeVolcengineTransport()
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(
                credential: .volcengineAppIDAccessToken(
                    appID: "3145608744",
                    accessToken: "legacy-token"
                )
            ),
            transport: transport
        )

        _ = try await provider.startStreaming(progress: nil)

        XCTAssertEqual(transport.streamingRequests.count, 1)
        XCTAssertEqual(
            transport.streamingRequests.first?.endpoint.absoluteString,
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
        )
        XCTAssertEqual(transport.streamingRequests.first?.headers["X-Api-App-Key"], "3145608744")
        XCTAssertEqual(transport.streamingRequests.first?.headers["X-Api-Access-Key"], "legacy-token")
        XCTAssertNil(transport.streamingRequests.first?.headers["X-Api-Key"])
    }

    func testProviderRetriesLegacyStreamingWithBigASRResourceIDAfterHandshakeRejection() async throws {
        let transport = FakeVolcengineTransport()
        let legacyHourlyResourceID = "volc.bigasr.sauc.duration"
        transport.streamingErrorsByResourceID[volcengineDefaultResourceID] = TranscriptionProviderError.transport(
            providerName: "火山引擎",
            message: "OpenSpeech WebSocket 握手被服务端拒绝。endpoint=\(volcengineDefaultEndpoint)",
            retryable: true
        )
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(
                credential: .volcengineAppIDAccessToken(
                    appID: "3145608744",
                    accessToken: "legacy-token"
                )
            ),
            transport: transport
        )

        _ = try await provider.startStreaming(progress: nil)

        XCTAssertEqual(transport.streamingRequests.map(\.resourceID), [volcengineDefaultResourceID, legacyHourlyResourceID])
        XCTAssertEqual(transport.streamingRequests.last?.headers["X-Api-Resource-Id"], legacyHourlyResourceID)
    }

    func testProviderStartsRealtimeGatewayStreamingFromStoredAPIKey() async throws {
        let openSpeechTransport = FakeVolcengineTransport()
        let gatewayTransport = FakeVolcengineRealtimeGatewayTransport()
        let provider = MacVolcengineTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-secret"),
            transport: openSpeechTransport,
            realtimeGatewayTransport: gatewayTransport
        )

        _ = try await provider.startStreaming(progress: nil)

        XCTAssertTrue(openSpeechTransport.streamingRequests.isEmpty)
        XCTAssertEqual(gatewayTransport.streamingRequests.count, 1)
        XCTAssertEqual(
            gatewayTransport.streamingRequests.first?.endpoint.absoluteString,
            "wss://ai-gateway.vei.volces.com/v1/realtime?model=bigmodel"
        )
        XCTAssertEqual(gatewayTransport.streamingRequests.first?.headers["Authorization"], "Bearer sk-test-secret")
    }

    func testURLSessionTransportStreamsBinaryFramesAndReturnsFinalTranscript() async throws {
        let finalFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionRequest.make(
            auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"),
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
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-App-Key"), "3145608744")
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-Access-Key"), "legacy-token")
        XCTAssertNil(session.requests.first?.value(forHTTPHeaderField: "X-Api-Key"))
        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.sentMessages.count, 2)
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingSendsAudioChunksAndReturnsFinalTranscript() async throws {
        let partialFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello","utterances":[{"text":"hello","start_time":0,"end_time":400,"definite":false}]}}"#,
            last: false
        )
        let finalFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(partialFrame), .data(finalFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionSessionRequest.make(
            auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token")
        )
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
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-App-Key"), "3145608744")
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-Access-Key"), "legacy-token")
        XCTAssertNil(session.requests.first?.value(forHTTPHeaderField: "X-Api-Key"))
        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.sentMessages.count, 2)
        guard case .data(let lastFrame) = task.sentMessages.last else {
            XCTFail("Expected final audio frame")
            return
        }
        XCTAssertEqual(Array(lastFrame.prefix(4)), [0x11, 0x22, 0x01, 0x00])
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionRealtimeGatewayTransportStreamsJSONEventsAndReturnsFinalTranscript() async throws {
        let task = FakeVolcengineWebSocketTask(
            receiveMessages: [
                .string(#"{"type":"transcription_session.updated"}"#),
                .string(#"{"type":"conversation.item.input_audio_transcription.result","transcript":"hello"}"#),
                .string(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hello world"}"#)
            ]
        )
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineRealtimeGatewayTranscriptionTransport(session: session)
        let request = try VolcengineRealtimeGatewaySessionRequest.make(apiKey: "sk-gateway-secret")
        var received: [TranscriptPartialSnapshot] = []

        let streamingSession = try await transport.startStreaming(request: request) { partial in
            received.append(partial)
        }
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
        XCTAssertEqual(received.map(\.text), ["hello"])
        XCTAssertEqual(session.requests.first?.url?.absoluteString, "wss://ai-gateway.vei.volces.com/v1/realtime?model=bigmodel")
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-gateway-secret")
        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.sentMessages.count, 3)
        XCTAssertTrue(task.sentStringMessages[0].contains(#""type":"transcription_session.update""#))
        XCTAssertTrue(task.sentStringMessages[1].contains(#""type":"input_audio_buffer.append""#))
        XCTAssertTrue(task.sentStringMessages[2].contains(#""type":"input_audio_buffer.commit""#))
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportStreamingUsesLatestPartialWhenFinalFrameHasNoText() async throws {
        let partialFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":false}]}}"#,
            last: false
        )
        let finalFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"","utterances":[]}}"#,
            last: true
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(partialFrame), .data(finalFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionSessionRequest.make(auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"))

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
        let finalFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"","utterances":[]}}"#,
            last: true
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionSessionRequest.make(auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"))

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
        let finalFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionSessionRequest.make(auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"))
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
        let finalFrame = try VolcengineWireProtocol.buildTestServerResponseFrame(
            json: #"{"result":{"text":"hello world","utterances":[{"text":"hello world","start_time":0,"end_time":1000,"definite":true}]}}"#,
            last: true
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(finalFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionSessionRequest.make(auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"))
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
        let errorFrame = VolcengineWireProtocol.buildTestServerErrorFrame(
            code: 45000002,
            message: "empty audio"
        )
        let task = FakeVolcengineWebSocketTask(receiveMessages: [.data(errorFrame)])
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionRequest.make(
            auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"),
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
        let task = FakeVolcengineWebSocketTask(sendError: URLError(.timedOut))
        let session = FakeVolcengineWebSocketSession(task: task)
        let transport = URLSessionVolcengineTranscriptionTransport(session: session)
        let request = try VolcengineTranscriptionRequest.make(
            auth: .appIDAccessToken(appID: "3145608744", accessToken: "legacy-token"),
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
            XCTAssertEqual(providerName, "火山引擎")
            XCTAssertTrue(message.contains("WebSocket connect to \(request.endpoint.absoluteString) failed"))
            XCTAssertTrue(retryable)
        } catch {
            XCTFail("Expected TranscriptionProviderError, got \(error)")
        }

        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

}

@MainActor
private final class FakeVolcengineTransport: VolcengineTranscriptionTransporting {
    private(set) var requests: [VolcengineTranscriptionRequest] = []
    private(set) var streamingRequests: [VolcengineTranscriptionSessionRequest] = []
    let transcript: TranscriptSnapshot
    let partialsToEmit: [TranscriptPartialSnapshot]
    var error: Error?
    var streamingErrorsByResourceID: [String: Error] = [:]

    init(
        transcript: TranscriptSnapshot = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "火山引擎",
            latencyMilliseconds: nil
        ),
        partialsToEmit: [TranscriptPartialSnapshot] = []
    ) {
        self.transcript = transcript
        self.partialsToEmit = partialsToEmit
    }

    func transcribe(
        request: VolcengineTranscriptionRequest,
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
        request: VolcengineTranscriptionSessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession {
        streamingRequests.append(request)

        if let error = streamingErrorsByResourceID[request.resourceID] {
            throw error
        }

        if let error {
            throw error
        }

        return FakeVolcengineStreamingSession(transcript: transcript, partialsToEmit: partialsToEmit, progress: progress)
    }
}

@MainActor
private final class FakeVolcengineRealtimeGatewayTransport: VolcengineRealtimeGatewayTranscriptionTransporting {
    private(set) var requests: [VolcengineRealtimeGatewayTranscriptionRequest] = []
    private(set) var streamingRequests: [VolcengineRealtimeGatewaySessionRequest] = []
    let transcript: TranscriptSnapshot
    var error: Error?

    init(
        transcript: TranscriptSnapshot = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "火山引擎",
            latencyMilliseconds: nil
        )
    ) {
        self.transcript = transcript
    }

    func transcribe(
        request: VolcengineRealtimeGatewayTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        requests.append(request)

        if let error {
            throw error
        }

        return transcript
    }

    func startStreaming(
        request: VolcengineRealtimeGatewaySessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession {
        streamingRequests.append(request)

        if let error {
            throw error
        }

        return FakeVolcengineStreamingSession(transcript: transcript, partialsToEmit: [], progress: progress)
    }
}

private actor FakeVolcengineStreamingSession: RealtimeTranscriptionSession {
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
private final class FakeVolcengineWebSocketSession: VolcengineWebSocketSessioning {
    private let task: FakeVolcengineWebSocketTask
    private(set) var requests: [URLRequest] = []

    init(task: FakeVolcengineWebSocketTask) {
        self.task = task
    }

    func webSocketTask(with request: URLRequest) -> any VolcengineWebSocketTasking {
        requests.append(request)
        return task
    }
}

@MainActor
private final class FakeVolcengineWebSocketTask: VolcengineWebSocketTasking, @unchecked Sendable {
    private let sendError: Error?
    private var receiveMessages: [URLSessionWebSocketTask.Message]
    private(set) var resumeCount = 0
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    private(set) var cancelCodes: [URLSessionWebSocketTask.CloseCode] = []
    var sentStringMessages: [String] {
        sentMessages.compactMap { message in
            guard case .string(let text) = message else {
                return nil
            }
            return text
        }
    }

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
