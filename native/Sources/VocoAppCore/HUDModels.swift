import Foundation

private let hudTranscriptPreviewMaxCharacters = 64

public enum HUDPhase: Equatable, Sendable {
    case hidden
    case recording
    case transcribing
    case injecting
    case success
    case error
}

public struct HUDSnapshot: Equatable, Sendable {
    public let phase: HUDPhase
    public let title: String
    public let detail: String
    public let systemImage: String
    public let transcriptPreview: String?
    public let autoHideAfterSeconds: Double?

    public var isVisible: Bool {
        phase != .hidden
    }

    public init(
        status: AppRuntimeStatus,
        strings: VocoStrings = VocoStrings(),
        lastTranscript: TranscriptSnapshot?,
        currentTranscript: TranscriptSnapshot? = nil,
        lastInjection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) {
        let hudStrings = strings.hud
        switch status {
        case .recording:
            self = HUDSnapshot(
                phase: .recording,
                title: hudStrings.recordingTitle,
                detail: hudStrings.recordingDetail,
                systemImage: "waveform.circle.fill",
                transcriptPreview: hudTranscriptPreview(from: currentTranscript),
                autoHideAfterSeconds: nil
            )
        case .transcribing:
            self = HUDSnapshot(
                phase: .transcribing,
                title: hudStrings.transcribingTitle,
                detail: hudStrings.transcribingDetail,
                systemImage: "ellipsis.bubble.fill",
                transcriptPreview: hudTranscriptPreview(from: currentTranscript),
                autoHideAfterSeconds: nil
            )
        case .injecting:
            self = HUDSnapshot(
                phase: .injecting,
                title: hudStrings.injectingTitle,
                detail: hudStrings.injectingDetail,
                systemImage: "text.cursor",
                transcriptPreview: hudTranscriptPreview(from: currentTranscript),
                autoHideAfterSeconds: nil
            )
        case .providerOffline, .error:
            self = HUDSnapshot(
                phase: .error,
                title: hudStrings.errorTitle,
                detail: lastErrorMessage ?? lastInjection?.detail ?? hudStrings.genericErrorDetail,
                systemImage: "exclamationmark.triangle.fill",
                transcriptPreview: nil,
                autoHideAfterSeconds: nil
            )
        case .ready:
            self = .hidden
        case .launching, .permissionNeeded:
            self = .hidden
        }
    }

    private init(
        phase: HUDPhase,
        title: String,
        detail: String,
        systemImage: String,
        transcriptPreview: String?,
        autoHideAfterSeconds: Double?
    ) {
        self.phase = phase
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.transcriptPreview = transcriptPreview
        self.autoHideAfterSeconds = autoHideAfterSeconds
    }

    public static var hidden: HUDSnapshot {
        HUDSnapshot(
            phase: .hidden,
            title: "",
            detail: "",
            systemImage: "waveform",
            transcriptPreview: nil,
            autoHideAfterSeconds: nil
        )
    }
}

private func hudTranscriptPreview(from transcript: TranscriptSnapshot?) -> String? {
    guard let transcript else {
        return nil
    }

    let source = transcript.finalText.isEmpty ? transcript.partials.last ?? "" : transcript.finalText
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    if trimmed.count <= hudTranscriptPreviewMaxCharacters {
        return trimmed
    }

    return String(trimmed.suffix(hudTranscriptPreviewMaxCharacters))
}
