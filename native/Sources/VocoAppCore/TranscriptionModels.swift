import Foundation

public struct TranscriptPartialSnapshot: Equatable, Sendable {
    public let text: String
    public let stablePrefixLength: Int
    public let providerName: String

    public init(text: String, stablePrefixLength: Int, providerName: String) {
        self.text = text
        self.stablePrefixLength = max(0, stablePrefixLength)
        self.providerName = providerName
    }
}

public typealias TranscriptionProgressHandler = @MainActor @Sendable (TranscriptPartialSnapshot) -> Void

public enum TranscriptionProviderStatus: Equatable, Sendable {
    case notConfigured
    case ready(providerName: String)
    case authenticationRequired(providerName: String)
    case offline(providerName: String)
    case failed(providerName: String, message: String)

    public var title: String {
        switch self {
        case .notConfigured:
            "未配置"
        case .ready(let providerName):
            providerName
        case .authenticationRequired(let providerName):
            "\(providerName) 需要认证"
        case .offline(let providerName):
            "\(providerName) 离线"
        case .failed(let providerName, _):
            "\(providerName) 错误"
        }
    }

    public var detail: String {
        switch self {
        case .notConfigured:
            "请先配置 ASR provider。"
        case .ready:
            "转写服务已配置"
        case .authenticationRequired:
            "请检查 provider 凭证。"
        case .offline:
            "转写服务暂不可用，稍后可重试。"
        case .failed(_, let message):
            message
        }
    }

    public var systemImage: String {
        switch self {
        case .notConfigured, .authenticationRequired:
            "exclamationmark.triangle"
        case .ready:
            "text.bubble"
        case .offline:
            "wifi.slash"
        case .failed:
            "xmark.octagon"
        }
    }

    public var isUsable: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

public enum TranscriptionProviderError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case emptyAudio
    case authentication(providerName: String, message: String)
    case transport(providerName: String, message: String, retryable: Bool)
    case provider(providerName: String, message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "转写服务未配置：请先在设置中配置 ASR provider。"
        case .emptyAudio:
            "转写失败：没有可用音频。"
        case .authentication(let providerName, let message):
            "\(providerName) 认证失败：\(message)"
        case .transport(let providerName, let message, _):
            "\(providerName) 网络错误：\(message)"
        case .provider(let providerName, let message):
            "\(providerName) 转写失败：\(message)"
        case .cancelled:
            "转写已取消。"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .transport(_, _, let retryable):
            retryable
        case .emptyAudio, .provider:
            true
        case .notConfigured, .authentication, .cancelled:
            false
        }
    }
}
