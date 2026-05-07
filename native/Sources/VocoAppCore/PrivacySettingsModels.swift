import Foundation

public struct PrivacySettingsSnapshot: Equatable, Sendable {
    public let keychain: KeychainPrivacyStatusSnapshot
    public let transcriptRetention: TranscriptRetentionPolicySnapshot
    public let logsPolicy: DiagnosticLogsPolicySnapshot

    public init(transcriptionCredentials: TranscriptionCredentialSnapshot) {
        self.keychain = KeychainPrivacyStatusSnapshot(credentials: transcriptionCredentials)
        self.transcriptRetention = .notRetained
        self.logsPolicy = .redacted
    }
}

public struct KeychainPrivacyStatusSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public init(credentials: TranscriptionCredentialSnapshot) {
        if credentials.lastErrorMessage != nil {
            self.title = "Keychain 访问失败"
            self.detail = credentials.storageDetail
            self.systemImage = "exclamationmark.triangle.fill"
        } else if credentials.hasCredential {
            self.title = "Keychain 已保存凭证"
            self.detail = credentials.maskedCredential ?? credentials.storageDetail
            self.systemImage = "key.fill"
        } else {
            self.title = "Keychain 未保存凭证"
            self.detail = credentials.storageDetail
            self.systemImage = "key"
        }
    }
}

public struct TranscriptRetentionPolicySnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var notRetained: TranscriptRetentionPolicySnapshot {
        TranscriptRetentionPolicySnapshot(
            title: "不保留转写文本",
            detail: "转写文本仅用于本次插入和当前运行时诊断。",
            systemImage: "text.badge.checkmark"
        )
    }
}

public struct DiagnosticLogsPolicySnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var redacted: DiagnosticLogsPolicySnapshot {
        DiagnosticLogsPolicySnapshot(
            title: "日志默认脱敏",
            detail: "诊断信息不记录完整 Doubao 凭证或完整转写正文。",
            systemImage: "doc.text.magnifyingglass"
        )
    }
}
