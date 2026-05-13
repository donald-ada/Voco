import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class SwitchingTranscriptionProviderTests: XCTestCase {
    func testDefaultSelectionDelegatesTranscribeToVolcengine() async throws {
        let selection = ModelSelectionBox(.default)
        let volcengine = FakeSwitchingTranscriptionProvider(providerName: "火山引擎", finalText: "cloud")
        let local = FakeSwitchingTranscriptionProvider(providerName: "本地模型", finalText: "local")
        let provider = SwitchingTranscriptionProvider(
            selectionProvider: { selection.value },
            localModelStatusProvider: { .ready },
            volcengineProvider: volcengine,
            localProvider: local
        )

        let transcript = try await provider.transcribe(.fixture, progress: nil)

        XCTAssertEqual(transcript.finalText, "cloud")
        XCTAssertEqual(volcengine.transcribeCount, 1)
        XCTAssertEqual(local.transcribeCount, 0)
        selection.value = TranscriptionModelSelection(providerID: .localRecommended)
        XCTAssertEqual(provider.status, .ready(providerName: "本地模型"))
    }

    func testLocalReadySelectionDelegatesToLocalProvider() async throws {
        let volcengine = FakeSwitchingTranscriptionProvider(providerName: "火山引擎", finalText: "cloud")
        let local = FakeSwitchingTranscriptionProvider(providerName: "本地模型", finalText: "local")
        let provider = SwitchingTranscriptionProvider(
            selectionProvider: { TranscriptionModelSelection(providerID: .localRecommended) },
            localModelStatusProvider: { .ready },
            volcengineProvider: volcengine,
            localProvider: local
        )

        let transcript = try await provider.transcribe(.fixture, progress: nil)

        XCTAssertEqual(transcript.finalText, "local")
        XCTAssertEqual(volcengine.transcribeCount, 0)
        XCTAssertEqual(local.transcribeCount, 1)
    }

    func testLocalSelectionThrowsWhenModelIsNotReady() async {
        let provider = SwitchingTranscriptionProvider(
            selectionProvider: { TranscriptionModelSelection(providerID: .localRecommended) },
            localModelStatusProvider: { .notDownloaded },
            volcengineProvider: FakeSwitchingTranscriptionProvider(providerName: "火山引擎", finalText: "cloud"),
            localProvider: FakeSwitchingTranscriptionProvider(providerName: "本地模型", finalText: "local")
        )

        do {
            _ = try await provider.transcribe(.fixture, progress: nil)
            XCTFail("Expected local provider failure")
        } catch let error as TranscriptionProviderError {
            XCTAssertEqual(
                error,
                .provider(providerName: localRecommendedTranscriptionProviderName, message: "本地模型未下载。")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingSessionKeepsProviderChosenAtStart() async throws {
        let selection = ModelSelectionBox(.default)
        let volcengine = FakeSwitchingTranscriptionProvider(providerName: "火山引擎", finalText: "cloud")
        let local = FakeSwitchingTranscriptionProvider(providerName: "本地模型", finalText: "local")
        let provider = SwitchingTranscriptionProvider(
            selectionProvider: { selection.value },
            localModelStatusProvider: { .ready },
            volcengineProvider: volcengine,
            localProvider: local
        )

        let session = try await provider.startStreaming(progress: nil)
        selection.value = TranscriptionModelSelection(providerID: .localRecommended)
        await session.acceptAudioChunk([1, 2, 3])

        let audioChunks = await volcengine.streamingSession?.audioChunksSnapshot()
        XCTAssertEqual(audioChunks, [[1, 2, 3]])
        XCTAssertNil(local.streamingSession)
    }
}

@MainActor
private final class ModelSelectionBox {
    var value: TranscriptionModelSelection

    init(_ value: TranscriptionModelSelection) {
        self.value = value
    }
}

private extension CapturedAudioSnapshot {
    static let fixture = CapturedAudioSnapshot(
        durationSeconds: 0.5,
        sampleRate: 16_000,
        peakAmplitude: 0.5,
        pcm16Samples: Array(repeating: 1, count: 8_000)
    )
}

private final class FakeSwitchingTranscriptionProvider: TranscriptionProviding, RealtimeTranscriptionProviding {
    let providerName: String
    let finalText: String
    private(set) var transcribeCount = 0
    private(set) var streamingSession: FakeSwitchingTranscriptionSession?

    init(providerName: String, finalText: String) {
        self.providerName = providerName
        self.finalText = finalText
    }

    var status: TranscriptionProviderStatus {
        .ready(providerName: providerName)
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        transcribeCount += 1
        return TranscriptSnapshot(
            finalText: finalText,
            partials: [],
            providerName: providerName,
            latencyMilliseconds: nil
        )
    }

    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession {
        let session = FakeSwitchingTranscriptionSession(
            finalText: finalText,
            providerName: providerName
        )
        streamingSession = session
        return session
    }
}

private actor FakeSwitchingTranscriptionSession: RealtimeTranscriptionSession {
    private let finalText: String
    private let providerName: String
    private var audioChunks: [[Int16]] = []

    init(finalText: String, providerName: String) {
        self.finalText = finalText
        self.providerName = providerName
    }

    func acceptAudioChunk(_ pcm16Samples: [Int16]) async {
        audioChunks.append(pcm16Samples)
    }

    func finish(audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        TranscriptSnapshot(
            finalText: finalText,
            partials: [],
            providerName: providerName,
            latencyMilliseconds: nil
        )
    }

    func cancel() async {}

    func audioChunksSnapshot() -> [[Int16]] {
        audioChunks
    }
}
