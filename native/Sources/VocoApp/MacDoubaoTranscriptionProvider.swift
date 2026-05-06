import Foundation
import VocoAppCore

@MainActor
final class MacDoubaoTranscriptionProvider: TranscriptionProviding, RealtimeTranscriptionProviding {
    private let credentialStore: any TranscriptionCredentialStoring
    private let transport: any DoubaoTranscriptionTransporting

    init(
        credentialStore: any TranscriptionCredentialStoring,
        transport: any DoubaoTranscriptionTransporting = URLSessionDoubaoTranscriptionTransport()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    var status: TranscriptionProviderStatus {
        let snapshot = credentialStore.currentSnapshot()
        if snapshot.hasCredential {
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
        let request = try DoubaoTranscriptionRequest.make(
            auth: try await doubaoAuth(),
            audio: audio
        )
        return try await transport.transcribe(request: request, progress: progress)
    }

    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession {
        let request = try DoubaoTranscriptionSessionRequest.make(auth: try await doubaoAuth())
        return try await transport.startStreaming(request: request, progress: progress)
    }

    private func doubaoAuth() async throws -> DoubaoTranscriptionAuth {
        let credential: TranscriptionCredential?
        do {
            credential = try await credentialStore.credential(for: .doubao)
        } catch {
            throw TranscriptionProviderError.authentication(
                providerName: doubaoTranscriptionProviderName,
                message: error.localizedDescription
            )
        }

        guard let credential else {
            throw TranscriptionProviderError.authentication(
                providerName: doubaoTranscriptionProviderName,
                message: "Keychain 中没有保存 Doubao 凭证。"
            )
        }

        let normalizedCredential: TranscriptionCredential
        do {
            normalizedCredential = try credential.normalized()
        } catch {
            throw TranscriptionProviderError.authentication(
                providerName: doubaoTranscriptionProviderName,
                message: error.localizedDescription
            )
        }

        switch normalizedCredential.mode {
        case .apiKey:
            return .apiKey(normalizedCredential.apiKey ?? "")
        case .appIDAccessToken:
            return .appIDAccessToken(
                appID: normalizedCredential.appID ?? "",
                accessToken: normalizedCredential.accessToken ?? ""
            )
        }
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
        let urlRequest = Self.urlRequest(endpoint: request.endpoint, headers: request.headers)
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

    func startStreaming(
        request: DoubaoTranscriptionSessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession {
        let urlRequest = Self.urlRequest(endpoint: request.endpoint, headers: request.headers)
        let task = session.webSocketTask(with: urlRequest)
        task.resume()

        do {
            try await task.send(.data(try DoubaoWireProtocol.buildFullClientRequestFrame()))
            return URLSessionDoubaoStreamingTranscriptionSession(
                task: task,
                endpoint: request.endpoint,
                progress: progress,
                startedAt: Date()
            )
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw DoubaoTranscriptionErrorMapper.transportError(error, endpoint: request.endpoint)
        }
    }

    private static func urlRequest(endpoint: URL, headers: [String: String]) -> URLRequest {
        var urlRequest = URLRequest(url: endpoint)
        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
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
                if flags.isLast {
                    finalText = try DoubaoFinalTextResolver.resolve(payload: payload, partials: partials)
                    let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    return TranscriptSnapshot(
                        finalText: finalText ?? "",
                        partials: partials,
                        providerName: doubaoTranscriptionProviderName,
                        latencyMilliseconds: latency
                    )
                }

                if let partial = try DoubaoServerResponse.parsePartial(payload) {
                    partials.append(partial.text)
                    progress?(partial)
                }
            }
        }
    }
}

private actor URLSessionDoubaoStreamingTranscriptionSession: RealtimeTranscriptionSession {
    private static let frameSampleCount = 3_200

    private let task: any DoubaoWebSocketTasking
    private let endpoint: URL
    private let receiveTask: Task<TranscriptSnapshot, Error>
    private var pendingError: TranscriptionProviderError?
    private var isFinished = false
    private var sentAnyAudio = false
    private var sentAudioSampleCount = 0
    private var pendingAudioSamples: [Int16] = []

    init(
        task: any DoubaoWebSocketTasking,
        endpoint: URL,
        progress: TranscriptionProgressHandler?,
        startedAt: Date
    ) {
        self.task = task
        self.endpoint = endpoint
        self.receiveTask = Task {
            try await Self.receiveTranscript(
                from: task,
                progress: progress,
                startedAt: startedAt
            )
        }
    }

    func acceptAudioChunk(_ pcm16Samples: [Int16]) async {
        guard !isFinished, !pcm16Samples.isEmpty, pendingError == nil else {
            return
        }

        pendingAudioSamples.append(contentsOf: pcm16Samples)

        do {
            while pendingAudioSamples.count >= Self.frameSampleCount {
                let frameSamples = Array(pendingAudioSamples.prefix(Self.frameSampleCount))
                pendingAudioSamples.removeFirst(Self.frameSampleCount)
                try await task.send(
                    .data(
                        try DoubaoWireProtocol.buildAudioFrame(
                            pcm16Samples: frameSamples,
                            last: false
                        )
                    )
                )
                sentAnyAudio = true
                sentAudioSampleCount += frameSamples.count
            }
        } catch let providerError as TranscriptionProviderError {
            pendingError = providerError
            receiveTask.cancel()
            await cancelTask()
        } catch {
            pendingError = DoubaoTranscriptionErrorMapper.transportError(error, endpoint: endpoint)
            receiveTask.cancel()
            await cancelTask()
        }
    }

    func finish(audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        if let pendingError {
            throw pendingError
        }

        isFinished = true

        do {
            var finalSamples = pendingAudioSamples
            pendingAudioSamples.removeAll(keepingCapacity: false)

            let accountedSampleCount = min(sentAudioSampleCount + finalSamples.count, audio.pcm16Samples.count)
            if audio.pcm16Samples.count > accountedSampleCount {
                finalSamples.append(contentsOf: audio.pcm16Samples[accountedSampleCount...])
            }

            if !finalSamples.isEmpty {
                try await sendFinalAudioSamples(finalSamples)
            } else {
                try await task.send(
                    .data(
                        try DoubaoWireProtocol.buildAudioFrame(
                            pcm16Samples: [],
                            last: true
                        )
                    )
                )
            }

            let transcript = try await receiveTask.value
            await cancelTask()
            return transcript
        } catch let providerError as TranscriptionProviderError {
            await cancelTask()
            throw providerError
        } catch {
            await cancelTask()
            throw DoubaoTranscriptionErrorMapper.transportError(error, endpoint: endpoint)
        }
    }

    private func sendFinalAudioSamples(_ samples: [Int16]) async throws {
        var cursor = 0
        while cursor < samples.count {
            let end = min(cursor + Self.frameSampleCount, samples.count)
            let isLast = end == samples.count
            try await task.send(
                .data(
                    try DoubaoWireProtocol.buildAudioFrame(
                        pcm16Samples: Array(samples[cursor..<end]),
                        last: isLast
                    )
                )
            )
            sentAnyAudio = true
            sentAudioSampleCount += end - cursor
            cursor = end
        }
    }

    func cancel() async {
        isFinished = true
        receiveTask.cancel()
        await cancelTask()
    }

    private func cancelTask() async {
        await MainActor.run {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    private static func receiveTranscript(
        from task: any DoubaoWebSocketTasking,
        progress: TranscriptionProgressHandler?,
        startedAt: Date
    ) async throws -> TranscriptSnapshot {
        var partials: [String] = []

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
                if flags.isLast {
                    let finalText = try DoubaoFinalTextResolver.resolve(payload: payload, partials: partials)
                    let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    return TranscriptSnapshot(
                        finalText: finalText,
                        partials: partials,
                        providerName: doubaoTranscriptionProviderName,
                        latencyMilliseconds: latency
                    )
                }

                if let partial = try DoubaoServerResponse.parsePartial(payload) {
                    partials.append(partial.text)
                    await progress?(partial)
                }
            }
        }
    }
}

private enum DoubaoFinalTextResolver {
    static func resolve(payload: Data, partials: [String]) throws -> String {
        do {
            return try DoubaoServerResponse.parseFinalText(payload)
        } catch let error as TranscriptionProviderError where canRecoverFromEmptyFinal(error) {
            if let finalFramePartial = try DoubaoServerResponse.parsePartial(payload)?.text,
               !finalFramePartial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return finalFramePartial
            }

            if let latestPartial = partials.last?.trimmingCharacters(in: .whitespacesAndNewlines),
               !latestPartial.isEmpty {
                return latestPartial
            }

            return ""
        }
    }

    private static func canRecoverFromEmptyFinal(_ error: TranscriptionProviderError) -> Bool {
        guard case .provider(let providerName, let message) = error else {
            return false
        }

        return providerName == doubaoTranscriptionProviderName
            && (message == "server response missing result" || message == "server response contains no final text")
    }
}

@MainActor
protocol DoubaoWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any DoubaoWebSocketTasking
}

@MainActor
protocol DoubaoWebSocketTasking: AnyObject, Sendable {
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

extension URLSessionWebSocketTask: @unchecked Sendable {}

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
