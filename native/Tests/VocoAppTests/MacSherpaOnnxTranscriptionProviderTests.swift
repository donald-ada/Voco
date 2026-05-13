import Foundation
import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacSherpaOnnxTranscriptionProviderTests: XCTestCase {
    func testProviderStatusReflectsLocalModelReadiness() {
        let readyProvider = MacSherpaOnnxTranscriptionProvider(
            runtime: FakeSherpaOnnxRuntime(),
            modelStatusProvider: { .ready },
            modelDirectoryProvider: { URL(fileURLWithPath: "/tmp/model") }
        )
        XCTAssertEqual(readyProvider.status, .ready(providerName: localRecommendedTranscriptionProviderName))

        let unavailableProvider = MacSherpaOnnxTranscriptionProvider(
            runtime: FakeSherpaOnnxRuntime(),
            modelStatusProvider: { .notDownloaded },
            modelDirectoryProvider: { URL(fileURLWithPath: "/tmp/model") }
        )
        XCTAssertEqual(
            unavailableProvider.status,
            .failed(
                providerName: localRecommendedTranscriptionProviderName,
                message: "本地模型未下载。"
            )
        )
    }

    func testTranscribePublishesPartialsAndReturnsFinalTranscript() async throws {
        let recognizer = FakeSherpaOnnxRecognizer(results: ["你", "你好"])
        let runtime = FakeSherpaOnnxRuntime(recognizer: recognizer)
        let provider = MacSherpaOnnxTranscriptionProvider(
            runtime: runtime,
            modelStatusProvider: { .ready },
            modelDirectoryProvider: { URL(fileURLWithPath: "/tmp/model") }
        )
        let audio = CapturedAudioSnapshot(
            durationSeconds: 0.1,
            sampleRate: 16_000,
            peakAmplitude: 0.5,
            pcm16Samples: [1, 2, 3, 4]
        )
        var partials: [TranscriptPartialSnapshot] = []

        let transcript = try await provider.transcribe(audio) { partial in
            partials.append(partial)
        }

        XCTAssertEqual(runtime.modelDirectories, [URL(fileURLWithPath: "/tmp/model")])
        XCTAssertEqual(partials.map(\.text), ["你", "你好"])
        XCTAssertEqual(transcript.finalText, "你好")
        XCTAssertEqual(transcript.partials, ["你", "你好"])
        XCTAssertEqual(transcript.providerName, localRecommendedTranscriptionProviderName)
        XCTAssertEqual(recognizer.acceptedSampleCounts, [4])
        XCTAssertTrue(recognizer.inputFinishedCalled)
    }

    func testStreamingSessionPublishesLivePartialsBeforeFinish() async throws {
        let recognizer = FakeSherpaOnnxRecognizer(results: ["今", "今天"])
        let provider = MacSherpaOnnxTranscriptionProvider(
            runtime: FakeSherpaOnnxRuntime(recognizer: recognizer),
            modelStatusProvider: { .ready },
            modelDirectoryProvider: { URL(fileURLWithPath: "/tmp/model") }
        )
        var partials: [TranscriptPartialSnapshot] = []
        let session = try await provider.startStreaming { partial in
            partials.append(partial)
        }

        await session.acceptAudioChunk([1, 2, 3])
        let transcript = try await session.finish(
            audio: CapturedAudioSnapshot(
                durationSeconds: 0.1,
                sampleRate: 16_000,
                peakAmplitude: 0.5,
                pcm16Samples: [1, 2, 3]
            )
        )

        XCTAssertEqual(partials.map(\.text), ["今", "今天"])
        XCTAssertEqual(partials.last?.stablePrefixLength, 1)
        XCTAssertEqual(transcript.finalText, "今天")
        XCTAssertEqual(transcript.partials, ["今", "今天"])
        XCTAssertEqual(recognizer.acceptedSampleCounts, [3])
    }
}

private final class FakeSherpaOnnxRuntime: SherpaOnnxRuntimeing, @unchecked Sendable {
    private let recognizer: FakeSherpaOnnxRecognizer
    private(set) var modelDirectories: [URL] = []

    init(recognizer: FakeSherpaOnnxRecognizer = FakeSherpaOnnxRecognizer(results: [])) {
        self.recognizer = recognizer
    }

    func makeOnlineRecognizer(modelDirectory: URL) throws -> any SherpaOnnxOnlineRecognizing {
        modelDirectories.append(modelDirectory)
        return recognizer
    }
}

private final class FakeSherpaOnnxRecognizer: SherpaOnnxOnlineRecognizing, @unchecked Sendable {
    private var queuedResults: [String]
    private var currentText = ""
    private(set) var acceptedSampleCounts: [Int] = []
    private(set) var inputFinishedCalled = false

    init(results: [String]) {
        self.queuedResults = results
    }

    func acceptWaveform(samples: [Float], sampleRate: Int) {
        acceptedSampleCounts.append(samples.count)
    }

    func inputFinished() {
        inputFinishedCalled = true
    }

    func decode() {
        guard !queuedResults.isEmpty else {
            return
        }
        currentText = queuedResults.removeFirst()
    }

    func reset() {
        currentText = ""
    }

    var isReady: Bool {
        !queuedResults.isEmpty
    }

    var currentResult: SherpaOnnxRecognitionResult {
        SherpaOnnxRecognitionResult(text: currentText)
    }
}
