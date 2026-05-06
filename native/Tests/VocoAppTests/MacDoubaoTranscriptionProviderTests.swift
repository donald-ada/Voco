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
