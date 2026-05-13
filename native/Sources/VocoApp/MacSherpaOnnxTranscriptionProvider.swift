import Foundation
import VocoAppCore

@MainActor
final class MacSherpaOnnxTranscriptionProvider: TranscriptionProviding, RealtimeTranscriptionProviding {
    private let runtime: any SherpaOnnxRuntimeing
    private let modelStatusProvider: @MainActor () -> LocalSpeechModelStatus
    private let modelDirectoryProvider: @MainActor () throws -> URL

    init(
        runtime: any SherpaOnnxRuntimeing,
        modelStatusProvider: @escaping @MainActor () -> LocalSpeechModelStatus,
        modelDirectoryProvider: @escaping @MainActor () throws -> URL
    ) {
        self.runtime = runtime
        self.modelStatusProvider = modelStatusProvider
        self.modelDirectoryProvider = modelDirectoryProvider
    }

    var status: TranscriptionProviderStatus {
        switch modelStatusProvider() {
        case .ready:
            return .ready(providerName: localRecommendedTranscriptionProviderName)
        case .notDownloaded:
            return .failed(
                providerName: localRecommendedTranscriptionProviderName,
                message: LocalSpeechModelError.notDownloaded.localizedDescription
            )
        case .downloading:
            return .failed(providerName: localRecommendedTranscriptionProviderName, message: "本地模型正在下载。")
        case .verifying:
            return .failed(providerName: localRecommendedTranscriptionProviderName, message: "本地模型正在校验。")
        case .failed(let message), .unavailable(let message):
            return .failed(providerName: localRecommendedTranscriptionProviderName, message: message)
        }
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        let recognizer = try makeRecognizer()
        let session = SherpaOnnxStreamingTranscriptionSession(
            recognizer: recognizer,
            progress: progress
        )
        await session.acceptAudioChunk(audio.pcm16Samples)
        return try await session.finish(audio: audio)
    }

    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession {
        let recognizer = try makeRecognizer()
        recognizer.reset()
        return SherpaOnnxStreamingTranscriptionSession(
            recognizer: recognizer,
            progress: progress
        )
    }

    private func makeRecognizer() throws -> any SherpaOnnxOnlineRecognizing {
        do {
            let modelDirectory = try modelDirectoryProvider()
            return try runtime.makeOnlineRecognizer(modelDirectory: modelDirectory)
        } catch {
            throw TranscriptionProviderError.provider(
                providerName: localRecommendedTranscriptionProviderName,
                message: error.localizedDescription
            )
        }
    }
}

private actor SherpaOnnxStreamingTranscriptionSession: RealtimeTranscriptionSession {
    private let recognizer: any SherpaOnnxOnlineRecognizing
    private let progress: TranscriptionProgressHandler?
    private let startedAt = Date()
    private var partials: [String] = []
    private var lastPublishedText = ""
    private var acceptedSampleCount = 0
    private var isFinished = false

    init(
        recognizer: any SherpaOnnxOnlineRecognizing,
        progress: TranscriptionProgressHandler?
    ) {
        self.recognizer = recognizer
        self.progress = progress
    }

    func acceptAudioChunk(_ pcm16Samples: [Int16]) async {
        guard !isFinished, !pcm16Samples.isEmpty else {
            return
        }

        acceptedSampleCount += pcm16Samples.count
        recognizer.acceptWaveform(samples: Self.floatSamples(from: pcm16Samples), sampleRate: 16_000)
        await publishReadyPartials()
    }

    func finish(audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        guard !isFinished else {
            return makeTranscript(finalText: lastPublishedText)
        }

        isFinished = true

        if audio.pcm16Samples.count > acceptedSampleCount {
            let remaining = Array(audio.pcm16Samples[acceptedSampleCount...])
            acceptedSampleCount = audio.pcm16Samples.count
            recognizer.acceptWaveform(samples: Self.floatSamples(from: remaining), sampleRate: Int(audio.sampleRate.rounded()))
            await publishReadyPartials()
        }

        recognizer.inputFinished()
        await publishReadyPartials()

        let finalText = recognizer.currentResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeTranscript(finalText: finalText.isEmpty ? lastPublishedText : finalText)
    }

    func cancel() async {
        isFinished = true
        recognizer.reset()
    }

    private func publishReadyPartials() async {
        while recognizer.isReady {
            recognizer.decode()
            let text = recognizer.currentResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != lastPublishedText else {
                continue
            }

            let partial = TranscriptPartialSnapshot(
                text: text,
                stablePrefixLength: Self.commonPrefixLength(lastPublishedText, text),
                providerName: localRecommendedTranscriptionProviderName
            )
            lastPublishedText = text
            partials.append(text)
            await progress?(partial)
        }
    }

    private func makeTranscript(finalText: String) -> TranscriptSnapshot {
        TranscriptSnapshot(
            finalText: finalText,
            partials: partials,
            providerName: localRecommendedTranscriptionProviderName,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
    }

    private static func floatSamples(from pcm16Samples: [Int16]) -> [Float] {
        pcm16Samples.map { sample in
            let normalized = Float(sample) / Float(Int16.max)
            return min(max(normalized, -1), 1)
        }
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }
}
