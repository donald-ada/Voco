import Foundation

public enum DiagnosticCategory: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case permission
    case installLocation
    case audio
    case hotkey
    case asr
    case injection
    case failure

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .permission:
            "权限"
        case .installLocation:
            "安装位置"
        case .audio:
            "音频"
        case .hotkey:
            "快捷键"
        case .asr:
            "ASR"
        case .injection:
            "输入"
        case .failure:
            "最近失败"
        }
    }

    public var systemImage: String {
        switch self {
        case .permission:
            "lock.shield"
        case .installLocation:
            "externaldrive"
        case .audio:
            "waveform"
        case .hotkey:
            "keyboard"
        case .asr:
            "text.bubble"
        case .injection:
            "text.cursor"
        case .failure:
            "exclamationmark.triangle"
        }
    }
}

public enum DiagnosticSeverity: String, Codable, Comparable, Equatable, Sendable {
    case ok
    case warning
    case error

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .ok:
            0
        case .warning:
            1
        case .error:
            2
        }
    }

    public var title: String {
        switch self {
        case .ok:
            "正常"
        case .warning:
            "需要注意"
        case .error:
            "错误"
        }
    }

    public var systemImage: String {
        switch self {
        case .ok:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }
}

public struct DiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let category: DiagnosticCategory
    public let severity: DiagnosticSeverity
    public let title: String
    public let detail: String

    public init(
        id: String = UUID().uuidString,
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        title: String,
        detail: String
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

public struct DiagnosticsSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let appStatusTitle: String
    public let events: [DiagnosticEvent]

    public init(
        generatedAt: Date = Date(),
        appStatusTitle: String,
        events: [DiagnosticEvent]
    ) {
        self.generatedAt = generatedAt
        self.appStatusTitle = appStatusTitle
        self.events = events
    }

    public init(
        appStatusTitle: String,
        permissions: [PermissionSnapshot],
        audio: CapturedAudioSnapshot?,
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        asrStatus: TranscriptionProviderStatus,
        credentials: TranscriptionCredentialSnapshot,
        installLocation: InstallLocationSnapshot? = nil,
        transcript: TranscriptSnapshot?,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?,
        generatedAt: Date = Date()
    ) {
        self.init(
            generatedAt: generatedAt,
            appStatusTitle: appStatusTitle,
            events: DiagnosticEventFactory.events(
                permissions: permissions,
                audio: audio,
                hotkeyState: hotkeyState,
                hotkeyBinding: hotkeyBinding,
                hotkeyMode: hotkeyMode,
                asrStatus: asrStatus,
                credentials: credentials,
                installLocation: installLocation,
                transcript: transcript,
                injection: injection,
                lastErrorMessage: lastErrorMessage
            )
        )
    }

    public var categories: [DiagnosticCategory] {
        events.reduce(into: []) { categories, event in
            if !categories.contains(event.category) {
                categories.append(event.category)
            }
        }
    }

    public var overallSeverity: DiagnosticSeverity {
        events.map(\.severity).max() ?? .ok
    }
}

public enum DiagnosticRedactor {
    public static let secretPlaceholder = "[redacted secret]"
    public static let transcriptPlaceholder = "[redacted transcript]"

    public static func redact(
        _ value: String,
        secrets: [String] = [],
        transcriptBodies: [String] = []
    ) -> String {
        var redacted = value

        for secret in secrets.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !secret.isEmpty {
            redacted = redacted.replacingOccurrences(of: secret, with: secretPlaceholder)
        }

        for transcript in transcriptBodies.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !transcript.isEmpty {
            redacted = redacted.replacingOccurrences(of: transcript, with: transcriptPlaceholder)
        }

        return redactAPIKeyLikePatterns(in: redacted)
    }

    private static func redactAPIKeyLikePatterns(in value: String) -> String {
        let patterns = [
            #"\bsk-[A-Za-z0-9][A-Za-z0-9._-]{8,}\b"#,
            #"(?i)\b(?:api[_-]?key|token|secret)\s*[:=]\s*["']?[A-Za-z0-9][A-Za-z0-9._-]{12,}["']?"#
        ]

        return patterns.reduce(value) { redacted, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return redacted
            }

            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            return expression.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: secretPlaceholder
            )
        }
    }
}

public enum DiagnosticEventFactory {
    public static func events(
        permissions: [PermissionSnapshot],
        audio: CapturedAudioSnapshot?,
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        asrStatus: TranscriptionProviderStatus,
        credentials: TranscriptionCredentialSnapshot,
        installLocation: InstallLocationSnapshot? = nil,
        transcript: TranscriptSnapshot?,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) -> [DiagnosticEvent] {
        var events = permissionEvents(permissions)
        if let installLocationEvent = installLocationEvent(installLocation) {
            events.append(installLocationEvent)
        }
        events.append(audioEvent(audio))
        events.append(hotkeyEvent(state: hotkeyState, binding: hotkeyBinding, mode: hotkeyMode))
        events.append(asrStatusEvent(asrStatus))
        events.append(credentialEvent(credentials))

        if let transcript {
            events.append(transcriptEvent(transcript))
        }

        events.append(injectionEvent(injection))
        events.append(failureEvent(lastErrorMessage))
        return events
    }

    private static func permissionEvents(_ permissions: [PermissionSnapshot]) -> [DiagnosticEvent] {
        guard !permissions.isEmpty else {
            return [
                DiagnosticEvent(
                    category: .permission,
                    severity: .warning,
                    title: "权限状态未知",
                    detail: "尚未读取 macOS 权限状态。"
                )
            ]
        }

        return permissions.map { permission in
            DiagnosticEvent(
                category: .permission,
                severity: permissionSeverity(permission),
                title: permission.kind.title,
                detail: "\(permission.state.title) · \(permission.isRequired ? "必需" : "可选")"
            )
        }
    }

    private static func permissionSeverity(_ permission: PermissionSnapshot) -> DiagnosticSeverity {
        switch permission.state {
        case .granted:
            .ok
        case .notDetermined, .unknown:
            .warning
        case .denied, .restricted:
            permission.isRequired ? .error : .warning
        }
    }

    private static func installLocationEvent(_ snapshot: InstallLocationSnapshot?) -> DiagnosticEvent? {
        guard let snapshot, snapshot.status == .mountedImage else {
            return nil
        }

        return DiagnosticEvent(
            category: .installLocation,
            severity: .warning,
            title: snapshot.warningTitle ?? snapshot.title,
            detail: snapshot.warningDetail ?? snapshot.detail
        )
    }

    private static func audioEvent(_ audio: CapturedAudioSnapshot?) -> DiagnosticEvent {
        guard let audio else {
            return DiagnosticEvent(
                category: .audio,
                severity: .warning,
                title: "无近期采样",
                detail: "完成一次录音后会显示最近音频指标。"
            )
        }

        let sampleRateMatches = abs(audio.sampleRate - 16_000) < 1
        let severity: DiagnosticSeverity
        if audio.peakAmplitude >= 0.95 || !sampleRateMatches {
            severity = .warning
        } else {
            severity = .ok
        }

        return DiagnosticEvent(
            category: .audio,
            severity: severity,
            title: "最近音频",
            detail: String(
                format: "%.2fs · %.0f Hz · %d samples · peak %.2f",
                audio.durationSeconds,
                audio.sampleRate,
                audio.pcm16Samples.count,
                audio.peakAmplitude
            )
        )
    }

    private static func hotkeyEvent(
        state: HotkeyRuntimeState,
        binding: HotkeyBinding,
        mode: HotkeyMode
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            category: .hotkey,
            severity: hotkeySeverity(state),
            title: state.title,
            detail: "\(binding.displayName) · \(mode.title) · \(state.detail)"
        )
    }

    private static func hotkeySeverity(_ state: HotkeyRuntimeState) -> DiagnosticSeverity {
        switch state {
        case .listening:
            .ok
        case .inactive, .permissionNeeded:
            .warning
        case .failed:
            .error
        }
    }

    private static func asrStatusEvent(_ status: TranscriptionProviderStatus) -> DiagnosticEvent {
        DiagnosticEvent(
            category: .asr,
            severity: asrSeverity(status),
            title: status.title,
            detail: status.detail
        )
    }

    private static func asrSeverity(_ status: TranscriptionProviderStatus) -> DiagnosticSeverity {
        switch status {
        case .ready:
            .ok
        case .notConfigured, .authenticationRequired:
            .warning
        case .offline, .failed:
            .error
        }
    }

    private static func credentialEvent(_ credentials: TranscriptionCredentialSnapshot) -> DiagnosticEvent {
        let severity: DiagnosticSeverity
        if credentials.lastErrorMessage != nil {
            severity = .error
        } else if credentials.hasAPIKey {
            severity = .ok
        } else {
            severity = .warning
        }

        return DiagnosticEvent(
            category: .asr,
            severity: severity,
            title: credentials.statusTitle,
            detail: credentials.maskedAPIKey ?? credentials.storageDetail
        )
    }

    private static func transcriptEvent(_ transcript: TranscriptSnapshot) -> DiagnosticEvent {
        let latencyDetail = transcript.latencyMilliseconds.map { " · \($0) ms" } ?? ""
        return DiagnosticEvent(
            category: .asr,
            severity: .ok,
            title: "\(transcript.providerName) 转写",
            detail: "\(transcript.finalText.count) 字符 · \(transcript.partials.count) 个 partial\(latencyDetail)"
        )
    }

    private static func injectionEvent(_ injection: TextInjectionSnapshot?) -> DiagnosticEvent {
        guard let injection else {
            return DiagnosticEvent(
                category: .injection,
                severity: .warning,
                title: "无近期输入",
                detail: "完成一次转写后会显示最近文本插入状态。"
            )
        }

        let target = injection.targetAppName ?? "无目标 App"
        return DiagnosticEvent(
            category: .injection,
            severity: injection.succeeded ? .ok : .error,
            title: injection.strategy.title,
            detail: "\(target) · \(injection.detail)"
        )
    }

    private static func failureEvent(_ message: String?) -> DiagnosticEvent {
        guard let message, !message.isEmpty else {
            return DiagnosticEvent(
                category: .failure,
                severity: .ok,
                title: "无近期失败",
                detail: "当前运行时没有记录失败状态。"
            )
        }

        return DiagnosticEvent(
            category: .failure,
            severity: .error,
            title: "最近失败",
            detail: message
        )
    }
}
