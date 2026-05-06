import Foundation
import VocoAppCore

@MainActor
final class MacDoubaoTranscriptionProvider: TranscriptionProviding {
    private let credentialStore: any TranscriptionCredentialStoring
    private let transport: any DoubaoTranscriptionTransporting
    private let legacyConfigURL: URL?

    init(
        credentialStore: any TranscriptionCredentialStoring,
        transport: any DoubaoTranscriptionTransporting = URLSessionDoubaoTranscriptionTransport(),
        legacyConfigURL: URL? = LegacyDoubaoConfig.defaultURL()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.legacyConfigURL = legacyConfigURL
    }

    var status: TranscriptionProviderStatus {
        if (try? LegacyDoubaoConfig.load(from: legacyConfigURL)) != nil {
            return .ready(providerName: doubaoTranscriptionProviderName)
        }

        let snapshot = credentialStore.currentSnapshot()
        if snapshot.hasAPIKey {
            return .ready(providerName: doubaoTranscriptionProviderName)
        }
        if let message = snapshot.lastErrorMessage {
            return .failed(providerName: doubaoTranscriptionProviderName, message: message)
        }
        return .authenticationRequired(providerName: doubaoTranscriptionProviderName)
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        if let legacyConfig = try LegacyDoubaoConfig.load(from: legacyConfigURL) {
            let request = try DoubaoTranscriptionRequest.make(
                auth: .appIDAccessToken(
                    appID: legacyConfig.appID,
                    accessToken: legacyConfig.accessToken
                ),
                audio: audio,
                resourceID: legacyConfig.resourceID
            )
            return try await transport.transcribe(request: request, progress: progress)
        }

        let apiKey: String?
        do {
            apiKey = try await credentialStore.apiKey(for: .doubao)
        } catch {
            throw TranscriptionProviderError.authentication(
                providerName: doubaoTranscriptionProviderName,
                message: error.localizedDescription
            )
        }

        let request = try DoubaoTranscriptionRequest.make(apiKey: apiKey, audio: audio)
        return try await transport.transcribe(request: request, progress: progress)
    }
}

@MainActor
final class URLSessionDoubaoTranscriptionTransport: DoubaoTranscriptionTransporting {
    private let frameSamples = 3_200
    private let session: any DoubaoWebSocketSessioning

    init(session: any DoubaoWebSocketSessioning = URLSession.shared) {
        self.session = session
    }

    func transcribe(
        request: DoubaoTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        var urlRequest = URLRequest(url: request.endpoint)
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let task = session.webSocketTask(with: urlRequest)
        task.resume()

        do {
            let start = Date()
            try await task.send(.data(try DoubaoWireProtocol.buildFullClientRequestFrame()))

            let samples = request.audio.pcm16Samples
            var cursor = 0
            while cursor < samples.count {
                let end = min(cursor + frameSamples, samples.count)
                let isLast = end == samples.count
                try await task.send(
                    .data(
                        try DoubaoWireProtocol.buildAudioFrame(
                            pcm16Samples: Array(samples[cursor..<end]),
                            last: isLast
                        )
                    )
                )
                cursor = end
            }

            let transcript = try await receiveTranscript(
                from: task,
                progress: progress,
                startedAt: start
            )
            task.cancel(with: .goingAway, reason: nil)
            return transcript
        } catch let providerError as TranscriptionProviderError {
            task.cancel(with: .goingAway, reason: nil)
            throw providerError
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw DoubaoTranscriptionErrorMapper.transportError(error, endpoint: request.endpoint)
        }
    }

    private func receiveTranscript(
        from task: any DoubaoWebSocketTasking,
        progress: TranscriptionProgressHandler?,
        startedAt: Date
    ) async throws -> TranscriptSnapshot {
        var partials: [String] = []
        var finalText: String?

        while true {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .data(let frameData):
                data = frameData
            case .string:
                continue
            @unknown default:
                continue
            }

            switch try DoubaoWireProtocol.parseServerFrame(data) {
            case .error(let code, let message):
                throw DoubaoTranscriptionErrorMapper.providerError(code: code, message: message)
            case .response(let flags, let payload):
                if let partial = try DoubaoServerResponse.parsePartial(payload) {
                    partials.append(partial.text)
                    progress?(partial)
                }

                if flags.isLast {
                    finalText = try DoubaoServerResponse.parseFinalText(payload)
                    let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    return TranscriptSnapshot(
                        finalText: finalText ?? "",
                        partials: partials,
                        providerName: doubaoTranscriptionProviderName,
                        latencyMilliseconds: latency
                    )
                }
            }
        }
    }
}

@MainActor
protocol DoubaoWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any DoubaoWebSocketTasking
}

@MainActor
protocol DoubaoWebSocketTasking: AnyObject {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSession: DoubaoWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any DoubaoWebSocketTasking {
        webSocketTask(with: request) as URLSessionWebSocketTask
    }
}

extension URLSessionWebSocketTask: DoubaoWebSocketTasking {
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(message) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            receive { result in
                continuation.resume(with: result)
            }
        }
    }
}

private struct LegacyDoubaoConfig {
    let appID: String
    let accessToken: String
    let resourceID: String

    static func defaultURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/voco/config.toml")
    }

    static func load(from url: URL?) throws -> LegacyDoubaoConfig? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw TranscriptionProviderError.authentication(
                providerName: doubaoTranscriptionProviderName,
                message: "读取旧 Doubao 配置失败：\(url.path): \(error.localizedDescription)"
            )
        }

        var inDoubaoSection = false
        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                inDoubaoSection = line == "[doubao]"
                continue
            }

            guard inDoubaoSection, let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: equalsIndex)
            let value = unquotedValue(String(line[valueStart...]))
            values[key] = value
        }

        let appID = values["app_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accessToken = values["access_token"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !appID.isEmpty, !accessToken.isEmpty else {
            return nil
        }

        let resourceID = values["resource_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LegacyDoubaoConfig(
            appID: appID,
            accessToken: accessToken,
            resourceID: resourceID?.isEmpty == false ? resourceID! : doubaoDefaultResourceID
        )
    }

    private static func unquotedValue(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
    }
}
