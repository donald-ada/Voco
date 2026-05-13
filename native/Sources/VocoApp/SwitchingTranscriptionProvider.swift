import Foundation
import VocoAppCore

@MainActor
final class SwitchingTranscriptionProvider: TranscriptionProviding, RealtimeTranscriptionProviding {
    private let selectionProvider: @MainActor () -> TranscriptionModelSelection
    private let localModelStatusProvider: @MainActor () -> LocalSpeechModelStatus
    private let volcengineProvider: any TranscriptionProviding
    private let localProvider: any TranscriptionProviding

    init(
        selectionProvider: @escaping @MainActor () -> TranscriptionModelSelection,
        localModelStatusProvider: @escaping @MainActor () -> LocalSpeechModelStatus,
        volcengineProvider: any TranscriptionProviding,
        localProvider: any TranscriptionProviding
    ) {
        self.selectionProvider = selectionProvider
        self.localModelStatusProvider = localModelStatusProvider
        self.volcengineProvider = volcengineProvider
        self.localProvider = localProvider
    }

    var status: TranscriptionProviderStatus {
        switch selectionProvider().providerID {
        case .volcengine:
            return volcengineProvider.status
        case .localRecommended:
            let localStatus = localModelStatusProvider()
            guard localStatus.canApply else {
                return .failed(
                    providerName: localRecommendedTranscriptionProviderName,
                    message: Self.localModelUnavailableMessage(for: localStatus)
                )
            }
            return localProvider.status
        }
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        let provider = try activeProviderSnapshot()
        return try await provider.transcribe(audio, progress: progress)
    }

    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession {
        let provider = try activeProviderSnapshot()
        guard let realtimeProvider = provider as? any RealtimeTranscriptionProviding else {
            throw TranscriptionProviderError.provider(
                providerName: providerName(for: provider.status),
                message: "Selected provider does not support realtime transcription."
            )
        }
        return try await realtimeProvider.startStreaming(progress: progress)
    }

    private func activeProviderSnapshot() throws -> any TranscriptionProviding {
        switch selectionProvider().providerID {
        case .volcengine:
            return volcengineProvider
        case .localRecommended:
            let localStatus = localModelStatusProvider()
            guard localStatus.canApply else {
                throw TranscriptionProviderError.provider(
                    providerName: localRecommendedTranscriptionProviderName,
                    message: Self.localModelUnavailableMessage(for: localStatus)
                )
            }
            return localProvider
        }
    }

    private func providerName(for status: TranscriptionProviderStatus) -> String {
        switch status {
        case .notConfigured:
            return "Unconfigured"
        case .ready(let providerName),
             .authenticationRequired(let providerName),
             .offline(let providerName),
             .failed(let providerName, _):
            return providerName
        }
    }

    private static func localModelUnavailableMessage(for status: LocalSpeechModelStatus) -> String {
        switch status {
        case .notDownloaded:
            return LocalSpeechModelError.notDownloaded.localizedDescription
        case .downloading:
            return "本地模型正在下载。"
        case .verifying:
            return "本地模型正在校验。"
        case .ready:
            return ""
        case .failed(let message),
             .unavailable(let message):
            return message
        }
    }
}
