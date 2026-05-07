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

public let volcengineTranscriptionProviderName = "火山引擎"
public let volcengineDefaultEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
public let volcengineSeedASRResourceID = "volc.seedasr.sauc.duration"
public let volcengineLegacyOpenSpeechResourceID = "volc.bigasr.sauc.duration"
public let volcengineDefaultResourceID = volcengineSeedASRResourceID
public let volcengineRealtimeGatewayModel = "bigmodel"
public let volcengineRealtimeGatewayEndpoint = "wss://ai-gateway.vei.volces.com/v1/realtime?model=bigmodel"
public let volcengineSingleAPIKeyUnsupportedMessage =
    "OpenSpeech 流式 ASR 需要 App ID 和 Access Token；单个 API Key 属于新网关协议，当前版本不会用它连接 wss://openspeech.bytedance.com。"

public enum VolcengineTranscriptionAuth: Equatable, Sendable {
    case apiKey(String)
    case appIDAccessToken(appID: String, accessToken: String)
}

public struct VolcengineTranscriptionRequest: Equatable, Sendable {
    public let endpoint: URL
    public let resourceID: String
    public let headers: [String: String]
    public let audio: CapturedAudioSnapshot
    public let safeDebugDescription: String

    public static func make(
        apiKey: String?,
        audio: CapturedAudioSnapshot,
        endpoint: String = volcengineDefaultEndpoint,
        resourceID: String = volcengineDefaultResourceID
    ) throws -> VolcengineTranscriptionRequest {
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAPIKey.isEmpty else {
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: "Keychain 中没有保存火山引擎 API Key。"
            )
        }

        return try make(
            auth: .apiKey(trimmedAPIKey),
            audio: audio,
            endpoint: endpoint,
            resourceID: resourceID
        )
    }

    public static func make(
        auth: VolcengineTranscriptionAuth,
        audio: CapturedAudioSnapshot,
        endpoint: String = volcengineDefaultEndpoint,
        resourceID: String = volcengineDefaultResourceID
    ) throws -> VolcengineTranscriptionRequest {
        let sessionRequest = try VolcengineTranscriptionSessionRequest.make(
            auth: auth,
            endpoint: endpoint,
            resourceID: resourceID
        )

        guard !audio.pcm16Samples.isEmpty else {
            throw TranscriptionProviderError.emptyAudio
        }

        let safeDebugDescription = [
            "endpoint=\(sessionRequest.endpoint.absoluteString)",
            "resourceID=\(resourceID)",
            "headers=\(sessionRequest.headers.keys.sorted().joined(separator: ","))",
            "samples=\(audio.pcm16Samples.count)"
        ].joined(separator: " ")

        return VolcengineTranscriptionRequest(
            endpoint: sessionRequest.endpoint,
            resourceID: resourceID,
            headers: sessionRequest.headers,
            audio: audio,
            safeDebugDescription: safeDebugDescription
        )
    }
}

public struct VolcengineTranscriptionSessionRequest: Equatable, Sendable {
    public let endpoint: URL
    public let resourceID: String
    public let headers: [String: String]
    public let safeDebugDescription: String

    public static func make(
        apiKey: String?,
        endpoint: String = volcengineDefaultEndpoint,
        resourceID: String = volcengineDefaultResourceID
    ) throws -> VolcengineTranscriptionSessionRequest {
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAPIKey.isEmpty else {
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: "Keychain 中没有保存火山引擎 API Key。"
            )
        }

        return try make(
            auth: .apiKey(trimmedAPIKey),
            endpoint: endpoint,
            resourceID: resourceID
        )
    }

    public static func make(
        auth: VolcengineTranscriptionAuth,
        endpoint: String = volcengineDefaultEndpoint,
        resourceID: String = volcengineDefaultResourceID
    ) throws -> VolcengineTranscriptionSessionRequest {
        let headers: [String: String]
        switch auth {
        case .apiKey(let apiKey):
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAPIKey.isEmpty else {
                throw TranscriptionProviderError.authentication(
                    providerName: volcengineTranscriptionProviderName,
                    message: "Keychain 中没有保存火山引擎 API Key。"
                )
            }
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: volcengineSingleAPIKeyUnsupportedMessage
            )
        case .appIDAccessToken(let appID, let accessToken):
            let trimmedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAppID.isEmpty, !trimmedAccessToken.isEmpty else {
                throw TranscriptionProviderError.authentication(
                    providerName: volcengineTranscriptionProviderName,
                    message: "火山引擎旧控制台凭证缺少 App ID 或 Access Token。"
                )
            }
            headers = [
                "X-Api-App-Key": trimmedAppID,
                "X-Api-Access-Key": trimmedAccessToken,
                "X-Api-Resource-Id": resourceID,
                "X-Api-Request-Id": UUID().uuidString,
                "X-Api-Connect-Id": UUID().uuidString
            ]
        }

        guard let endpointURL = URL(string: endpoint), endpointURL.scheme?.hasPrefix("ws") == true else {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "火山引擎 WebSocket endpoint 无效：\(endpoint)"
            )
        }

        let safeDebugDescription = [
            "endpoint=\(endpointURL.absoluteString)",
            "resourceID=\(resourceID)",
            "headers=\(headers.keys.sorted().joined(separator: ","))"
        ].joined(separator: " ")

        return VolcengineTranscriptionSessionRequest(
            endpoint: endpointURL,
            resourceID: resourceID,
            headers: headers,
            safeDebugDescription: safeDebugDescription
        )
    }
}

public struct VolcengineRealtimeGatewayTranscriptionRequest: Equatable, Sendable {
    public let endpoint: URL
    public let model: String
    public let headers: [String: String]
    public let audio: CapturedAudioSnapshot
    public let safeDebugDescription: String

    public static func make(
        apiKey: String?,
        audio: CapturedAudioSnapshot,
        endpoint: String = volcengineRealtimeGatewayEndpoint,
        model: String = volcengineRealtimeGatewayModel
    ) throws -> VolcengineRealtimeGatewayTranscriptionRequest {
        let sessionRequest = try VolcengineRealtimeGatewaySessionRequest.make(
            apiKey: apiKey,
            endpoint: endpoint,
            model: model
        )

        guard !audio.pcm16Samples.isEmpty else {
            throw TranscriptionProviderError.emptyAudio
        }

        let safeDebugDescription = [
            sessionRequest.safeDebugDescription,
            "samples=\(audio.pcm16Samples.count)"
        ].joined(separator: " ")

        return VolcengineRealtimeGatewayTranscriptionRequest(
            endpoint: sessionRequest.endpoint,
            model: sessionRequest.model,
            headers: sessionRequest.headers,
            audio: audio,
            safeDebugDescription: safeDebugDescription
        )
    }
}

public struct VolcengineRealtimeGatewaySessionRequest: Equatable, Sendable {
    public let endpoint: URL
    public let model: String
    public let headers: [String: String]
    public let safeDebugDescription: String

    public static func make(
        apiKey: String?,
        endpoint: String = volcengineRealtimeGatewayEndpoint,
        model: String = volcengineRealtimeGatewayModel
    ) throws -> VolcengineRealtimeGatewaySessionRequest {
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAPIKey.isEmpty else {
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: "Keychain 中没有保存火山引擎 API Key。"
            )
        }

        guard let endpointURL = URL(string: endpoint), endpointURL.scheme?.hasPrefix("ws") == true else {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "火山引擎 Realtime endpoint 无效：\(endpoint)"
            )
        }

        let headers = [
            "Authorization": "Bearer \(trimmedAPIKey)"
        ]
        let safeDebugDescription = [
            "endpoint=\(endpointURL.absoluteString)",
            "model=\(model)",
            "headers=\(headers.keys.sorted().joined(separator: ","))"
        ].joined(separator: " ")

        return VolcengineRealtimeGatewaySessionRequest(
            endpoint: endpointURL,
            model: model,
            headers: headers,
            safeDebugDescription: safeDebugDescription
        )
    }
}

public enum VolcengineRealtimeGatewayServerEvent: Equatable, Sendable {
    case sessionUpdated
    case partial(TranscriptPartialSnapshot)
    case final(String)
    case error(String)
    case ignored
}

public enum VolcengineRealtimeGatewayProtocol {
    public static func buildSessionUpdateEvent(model: String = volcengineRealtimeGatewayModel) throws -> String {
        try encodeJSONString(
            VolcengineRealtimeGatewaySessionUpdateEvent(
                session: .init(
                    inputAudioFormat: "pcm16",
                    inputAudioSampleRate: 16_000,
                    inputAudioChannels: 1,
                    inputAudioTranscription: .init(model: model)
                )
            )
        )
    }

    public static func buildAudioAppendEvent(pcm16Samples: [Int16]) throws -> String {
        try encodeJSONString(
            VolcengineRealtimeGatewayAudioAppendEvent(
                audio: Data(pcm16LittleEndianBytes: pcm16Samples).base64EncodedString()
            )
        )
    }

    public static func buildAudioCommitEvent() throws -> String {
        try encodeJSONString(VolcengineRealtimeGatewayTypedEvent(type: "input_audio_buffer.commit"))
    }

    public static func parseServerEvent(_ text: String) throws -> VolcengineRealtimeGatewayServerEvent {
        guard let data = text.data(using: .utf8) else {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "Realtime event is not UTF-8 text"
            )
        }

        let payload: VolcengineRealtimeGatewayServerPayload
        do {
            payload = try JSONDecoder().decode(VolcengineRealtimeGatewayServerPayload.self, from: data)
        } catch {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "Realtime event json: \(error.localizedDescription)"
            )
        }

        switch payload.type {
        case "transcription_session.updated", "session.updated":
            return .sessionUpdated
        case "conversation.item.input_audio_transcription.result",
             "conversation.item.input_audio_transcription.delta":
            guard let text = payload.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return .ignored
            }
            return .partial(
                TranscriptPartialSnapshot(
                    text: text,
                    stablePrefixLength: 0,
                    providerName: volcengineTranscriptionProviderName
                )
            )
        case "conversation.item.input_audio_transcription.completed":
            return .final(payload.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        case "error":
            return .error(payload.error?.message ?? payload.message ?? "Realtime gateway error")
        default:
            return .ignored
        }
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "Realtime event encode failed"
            )
        }
        return string
    }
}

public enum VolcengineTranscriptionErrorMapper {
    public static func providerError(code: Int, message: String) -> TranscriptionProviderError {
        switch code {
        case 45000002:
            return .emptyAudio
        case 45000081:
            return .transport(
                providerName: volcengineTranscriptionProviderName,
                message: "server timeout (45000081): \(message)",
                retryable: true
            )
        case 55000031:
            return .transport(
                providerName: volcengineTranscriptionProviderName,
                message: "server busy (55000031): \(message)",
                retryable: true
            )
        case 45000001:
            return .provider(
                providerName: volcengineTranscriptionProviderName,
                message: "bad request (45000001): \(message)"
            )
        case 45000151:
            return .provider(
                providerName: volcengineTranscriptionProviderName,
                message: "audio format error (45000151): \(message)"
            )
        case 55000000..<56000000:
            return .transport(
                providerName: volcengineTranscriptionProviderName,
                message: "server internal (\(code)): \(message)",
                retryable: true
            )
        default:
            return .provider(
                providerName: volcengineTranscriptionProviderName,
                message: "server error (\(code)): \(message)"
            )
        }
    }

    public static func transportError(
        _ error: Error,
        endpoint: URL,
        resourceID: String? = nil
    ) -> TranscriptionProviderError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == URLError.badServerResponse.rawValue {
            if endpoint.host?.contains("ai-gateway.vei.volces.com") == true {
                return .transport(
                    providerName: volcengineTranscriptionProviderName,
                    message: "Realtime 网关 WebSocket 握手被服务端拒绝。请检查新网关 API Key 是否有效，并确认模型访问权限已开通。endpoint=\(endpoint.absoluteString)",
                    retryable: true
                )
            }

            let resourceDetail = resourceID.map { " resourceID=\($0)" } ?? ""
            return .transport(
                providerName: volcengineTranscriptionProviderName,
                message: "OpenSpeech WebSocket 握手被服务端拒绝。请在模型中保存旧控制台 App ID + Access Token，并确认 Resource ID 已开通。endpoint=\(endpoint.absoluteString)\(resourceDetail)",
                retryable: true
            )
        }

        return .transport(
            providerName: volcengineTranscriptionProviderName,
            message: "WebSocket connect to \(endpoint.absoluteString) failed: \(error.localizedDescription)",
            retryable: true
        )
    }
}

public enum VolcengineServerResponse {
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
            providerName: volcengineTranscriptionProviderName
        )
    }

    public static func parseFinalText(_ data: Data) throws -> String {
        let response = try decode(data)
        guard let result = response.result else {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
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
                providerName: volcengineTranscriptionProviderName,
                message: "server response contains no final text"
            )
        }

        return stitchedText
    }

    private static func decode(_ data: Data) throws -> VolcengineServerResponsePayload {
        do {
            return try JSONDecoder().decode(VolcengineServerResponsePayload.self, from: data)
        } catch {
            throw TranscriptionProviderError.provider(
                providerName: volcengineTranscriptionProviderName,
                message: "server json: \(error.localizedDescription)"
            )
        }
    }
}

@MainActor
public protocol VolcengineTranscriptionTransporting {
    func transcribe(
        request: VolcengineTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot

    func startStreaming(
        request: VolcengineTranscriptionSessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession
}

@MainActor
public protocol VolcengineRealtimeGatewayTranscriptionTransporting {
    func transcribe(
        request: VolcengineRealtimeGatewayTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot

    func startStreaming(
        request: VolcengineRealtimeGatewaySessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession
}

private struct VolcengineRealtimeGatewaySessionUpdateEvent: Encodable {
    let type = "transcription_session.update"
    let session: Session

    struct Session: Encodable {
        let inputAudioFormat: String
        let inputAudioSampleRate: Int
        let inputAudioChannels: Int
        let inputAudioTranscription: Transcription

        enum CodingKeys: String, CodingKey {
            case inputAudioFormat = "input_audio_format"
            case inputAudioSampleRate = "input_audio_sample_rate"
            case inputAudioChannels = "input_audio_channels"
            case inputAudioTranscription = "input_audio_transcription"
        }
    }

    struct Transcription: Encodable {
        let model: String
    }
}

private struct VolcengineRealtimeGatewayAudioAppendEvent: Encodable {
    let type = "input_audio_buffer.append"
    let audio: String
}

private struct VolcengineRealtimeGatewayTypedEvent: Encodable {
    let type: String
}

private struct VolcengineRealtimeGatewayServerPayload: Decodable {
    let type: String
    let transcript: String?
    let delta: String?
    let text: String?
    let message: String?
    let error: VolcengineRealtimeGatewayServerError?

    var transcriptText: String? {
        transcript ?? delta ?? text
    }
}

private struct VolcengineRealtimeGatewayServerError: Decodable {
    let message: String?
}

private extension Data {
    init(pcm16LittleEndianBytes samples: [Int16]) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            bytes.append(UInt8(truncatingIfNeeded: sample))
            bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        self.init(bytes)
    }
}

private struct VolcengineServerResponsePayload: Decodable {
    let result: VolcengineServerResult?
}

private struct VolcengineServerResult: Decodable {
    let text: String?
    let utterances: [VolcengineServerUtterance]?
}

private struct VolcengineServerUtterance: Decodable {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        startTime = try container.decodeIfPresent(Int.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Int.self, forKey: .endTime)
        definite = try container.decodeIfPresent(Bool.self, forKey: .definite)
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
            "\(providerName)需要认证"
        case .offline(let providerName):
            "\(providerName)离线"
        case .failed(let providerName, _):
            "\(providerName)错误"
        }
    }

    public var detail: String {
        switch self {
        case .notConfigured:
            "请先配置火山引擎凭证。"
        case .ready:
            "模型已配置"
        case .authenticationRequired:
            "请检查火山引擎凭证。"
        case .offline:
            "模型暂不可用，稍后可重试。"
        case .failed(_, let message):
            message
        }
    }

    public var systemImage: String {
        switch self {
        case .notConfigured, .authenticationRequired:
            "exclamationmark.triangle"
        case .ready:
            "cpu"
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
            "模型未配置：请先在设置中配置火山引擎凭证。"
        case .emptyAudio:
            "转写失败：没有可用音频。"
        case .authentication(let providerName, let message):
            "\(providerName)认证失败：\(message)"
        case .transport(let providerName, let message, _):
            "\(providerName)网络错误：\(message)"
        case .provider(let providerName, let message):
            "\(providerName)转写失败：\(message)"
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
