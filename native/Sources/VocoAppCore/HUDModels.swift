import Foundation

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
        lastTranscript: TranscriptSnapshot?,
        lastInjection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) {
        switch status {
        case .recording:
            self = HUDSnapshot(
                phase: .recording,
                title: "正在听",
                detail: "松开或再次按下快捷键结束录音",
                systemImage: "waveform.circle.fill",
                transcriptPreview: nil,
                autoHideAfterSeconds: nil
            )
        case .transcribing:
            self = HUDSnapshot(
                phase: .transcribing,
                title: "正在转写",
                detail: "正在生成文字...",
                systemImage: "ellipsis.bubble.fill",
                transcriptPreview: hudTranscriptPreview(from: lastTranscript),
                autoHideAfterSeconds: nil
            )
        case .injecting:
            self = HUDSnapshot(
                phase: .injecting,
                title: "正在插入",
                detail: "正在把转写文本插入当前 App",
                systemImage: "text.cursor",
                transcriptPreview: hudTranscriptPreview(from: lastTranscript),
                autoHideAfterSeconds: nil
            )
        case .providerOffline, .error:
            self = HUDSnapshot(
                phase: .error,
                title: "需要处理",
                detail: lastErrorMessage ?? lastInjection?.detail ?? "Voco 遇到错误。",
                systemImage: "exclamationmark.triangle.fill",
                transcriptPreview: nil,
                autoHideAfterSeconds: nil
            )
        case .ready:
            if let lastInjection, lastInjection.succeeded, lastInjection.strategy != .skippedEmpty {
                self = HUDSnapshot(
                    phase: .success,
                    title: "已插入",
                    detail: "\(lastInjection.targetAppName ?? "当前 App") · \(lastInjection.strategy.title)",
                    systemImage: "checkmark.circle.fill",
                    transcriptPreview: hudTranscriptPreview(from: lastTranscript),
                    autoHideAfterSeconds: 1.4
                )
            } else {
                self = .hidden
            }
        case .launching, .needsOnboarding, .permissionNeeded:
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

    if trimmed.count <= 80 {
        return trimmed
    }

    let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 80)
    return "\(trimmed[..<endIndex])..."
}
