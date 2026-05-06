import XCTest
@testable import VocoApp
import VocoAppCore

@MainActor
final class MacDoubaoTranscriptionProviderTests: XCTestCase {
    func testProviderReportsAuthenticationRequiredWithoutStoredAPIKey() {
        let provider = MacDoubaoTranscriptionProvider(
            credentialStore: InMemoryTranscriptionCredentialStore(),
            transport: FakeDoubaoTransport()
        )

        XCTAssertEqual(provider.status, .authenticationRequired(providerName: "Doubao"))
    }

    func testProviderFailsBeforeTransportWhenCredentialIsMissing() async {
        let transport = FakeDoubaoTransport()
        let provider = MacDoubaoTranscriptionProvider(
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
            transport: transport
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

    func testURLSessionTransportFailsLoudlyAfterSuccessfulPingAndCancels() async throws {
        let task = FakeDoubaoWebSocketTask()
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
            XCTFail("Expected provider foundation to fail loudly after handshake")
        } catch {
            XCTAssertEqual(
                error as? TranscriptionProviderError,
                .provider(
                    providerName: "Doubao",
                    message: "Native Doubao WebSocket handshake succeeded, but binary audio streaming is not enabled in this build."
                )
            )
        }

        XCTAssertEqual(session.requests.count, 1)
        XCTAssertEqual(session.requests.first?.value(forHTTPHeaderField: "X-Api-Key"), "sk-test-secret")
        XCTAssertEqual(task.resumeCount, 1)
        XCTAssertEqual(task.sendPingCount, 1)
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }

    func testURLSessionTransportMapsPingFailureAndCancels() async throws {
        let task = FakeDoubaoWebSocketTask(pingError: URLError(.timedOut))
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
        XCTAssertEqual(task.sendPingCount, 1)
        XCTAssertEqual(task.cancelCodes, [.goingAway])
    }
}

@MainActor
private final class FakeDoubaoTransport: DoubaoTranscriptionTransporting {
    private(set) var requests: [DoubaoTranscriptionRequest] = []
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
private final class FakeDoubaoWebSocketTask: DoubaoWebSocketTasking {
    private let pingError: Error?
    private(set) var resumeCount = 0
    private(set) var sendPingCount = 0
    private(set) var cancelCodes: [URLSessionWebSocketTask.CloseCode] = []

    init(pingError: Error? = nil) {
        self.pingError = pingError
    }

    func resume() {
        resumeCount += 1
    }

    func sendPing() async throws {
        sendPingCount += 1

        if let pingError {
            throw pingError
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelCodes.append(closeCode)
    }
}
