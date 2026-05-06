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

public let doubaoTranscriptionProviderName = "Doubao"
public let doubaoDefaultEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
public let doubaoDefaultResourceID = "volc.seedasr.sauc.duration"

public struct DoubaoTranscriptionRequest: Equatable, Sendable {
    public let endpoint: URL
    public let resourceID: String
    public let headers: [String: String]
    public let audio: CapturedAudioSnapshot
    public let safeDebugDescription: String

    public static func make(
        apiKey: String?,
        audio: CapturedAudioSnapshot,
        endpoint: String = doubaoDefaultEndpoint,
        resourceID: String = doubaoDefaultResourceID
    ) throws -> DoubaoTranscriptionRequest {
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAPIKey.isEmpty else {
            throw TranscriptionProviderError.authentication(
                providerName: doubaoTranscriptionProviderName,
                message: "Keychain 中没有保存 Doubao API Key。"
            )
        }

        guard !audio.pcm16Samples.isEmpty else {
            throw TranscriptionProviderError.emptyAudio
        }

        guard let endpointURL = URL(string: endpoint), endpointURL.scheme?.hasPrefix("ws") == true else {
            throw TranscriptionProviderError.provider(
                providerName: doubaoTranscriptionProviderName,
                message: "Doubao WebSocket endpoint 无效：\(endpoint)"
            )
        }

        let headers = [
            "X-Api-Key": trimmedAPIKey,
            "X-Api-Resource-Id": resourceID,
            "X-Api-Request-Id": UUID().uuidString,
            "X-Api-Connect-Id": UUID().uuidString
        ]
        let safeDebugDescription = [
            "endpoint=\(endpointURL.absoluteString)",
            "resourceID=\(resourceID)",
            "headers=\(headers.keys.sorted().joined(separator: ","))",
            "samples=\(audio.pcm16Samples.count)"
        ].joined(separator: " ")

        return DoubaoTranscriptionRequest(
            endpoint: endpointURL,
            resourceID: resourceID,
            headers: headers,
            audio: audio,
            safeDebugDescription: safeDebugDescription
        )
    }
}

public enum DoubaoTranscriptionErrorMapper {
    public static func providerError(code: Int, message: String) -> TranscriptionProviderError {
        switch code {
        case 45000002:
            return .emptyAudio
        case 45000081:
            return .transport(
                providerName: doubaoTranscriptionProviderName,
                message: "server timeout (45000081): \(message)",
                retryable: true
            )
        case 55000031:
            return .transport(
                providerName: doubaoTranscriptionProviderName,
                message: "server busy (55000031): \(message)",
                retryable: true
            )
        case 45000001:
            return .provider(
                providerName: doubaoTranscriptionProviderName,
                message: "bad request (45000001): \(message)"
            )
        case 45000151:
            return .provider(
                providerName: doubaoTranscriptionProviderName,
                message: "audio format error (45000151): \(message)"
            )
        case 55000000..<56000000:
            return .transport(
                providerName: doubaoTranscriptionProviderName,
                message: "server internal (\(code)): \(message)",
                retryable: true
            )
        default:
            return .provider(
                providerName: doubaoTranscriptionProviderName,
                message: "server error (\(code)): \(message)"
            )
        }
    }

    public static func transportError(_ error: Error, endpoint: URL) -> TranscriptionProviderError {
        .transport(
            providerName: doubaoTranscriptionProviderName,
            message: "WebSocket connect to \(endpoint.absoluteString) failed: \(error.localizedDescription)",
            retryable: true
        )
    }
}

public enum DoubaoServerResponse {
    public static func parsePartial(_ data: Data) throws -> TranscriptPartialSnapshot? {
        let response = try decode(data)
        guard let result = response.result else {
            return nil
        }

        let utterances = result.utterances ?? []
        let sortedUtterances = utterances.sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
        let stableText = sortedUtterances
            .filter { $0.definite == true }
            .map(\.text)
            .joined()
        let pendingText = sortedUtterances
            .filter { $0.definite != true }
            .map(\.text)
            .joined()
        let partialText = pendingText.isEmpty ? (result.text ?? "") : stableText + pendingText
        let trimmedText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return TranscriptPartialSnapshot(
            text: trimmedText,
            stablePrefixLength: pendingText.isEmpty ? 0 : stableText.count,
            providerName: doubaoTranscriptionProviderName
        )
    }

    public static func parseFinalText(_ data: Data) throws -> String {
        let response = try decode(data)
        guard let result = response.result else {
            throw TranscriptionProviderError.provider(
                providerName: doubaoTranscriptionProviderName,
                message: "server response missing result"
            )
        }

        let directText = (result.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !directText.isEmpty {
            return directText
        }

        let stitchedText = (result.utterances ?? [])
            .filter { $0.definite == true }
            .sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stitchedText.isEmpty else {
            throw TranscriptionProviderError.provider(
                providerName: doubaoTranscriptionProviderName,
                message: "server response contains no final text"
            )
        }

        return stitchedText
    }

    private static func decode(_ data: Data) throws -> DoubaoServerResponsePayload {
        do {
            return try JSONDecoder().decode(DoubaoServerResponsePayload.self, from: data)
        } catch {
            throw TranscriptionProviderError.provider(
                providerName: doubaoTranscriptionProviderName,
                message: "server json: \(error.localizedDescription)"
            )
        }
    }
}

@MainActor
public protocol DoubaoTranscriptionTransporting {
    func transcribe(
        request: DoubaoTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot
}

private struct DoubaoServerResponsePayload: Decodable {
    let result: DoubaoServerResult?
}

private struct DoubaoServerResult: Decodable {
    let text: String?
    let utterances: [DoubaoServerUtterance]?
}

private struct DoubaoServerUtterance: Decodable {
    let text: String
    let startTime: Int?
    let endTime: Int?
    let definite: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case startTime = "start_time"
        case endTime = "end_time"
        case definite
    }
}

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
