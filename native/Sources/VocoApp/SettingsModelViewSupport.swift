import VocoAppCore

enum ModelSourcePanelKind: Equatable {
    case volcengineCredentials
    case localModelDownload
    case localModelReady
    case localModelFailed

    static func resolve(
        selectedProviderID: TranscriptionModelProviderID,
        localModelStatus: LocalSpeechModelStatus
    ) -> ModelSourcePanelKind {
        guard selectedProviderID == .localRecommended else {
            return .volcengineCredentials
        }

        switch localModelStatus {
        case .ready:
            return .localModelReady
        case .failed, .unavailable:
            return .localModelFailed
        case .notDownloaded, .downloading, .verifying:
            return .localModelDownload
        }
    }
}
