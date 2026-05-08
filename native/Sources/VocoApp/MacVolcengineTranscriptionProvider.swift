import Foundation
import VocoAppCore

@MainActor
final class MacVolcengineTranscriptionProvider: TranscriptionProviding, RealtimeTranscriptionProviding {
    private let credentialStore: any TranscriptionCredentialStoring
    private let openSpeechTransport: any VolcengineTranscriptionTransporting

    init(
        credentialStore: any TranscriptionCredentialStoring,
        transport: any VolcengineTranscriptionTransporting = URLSessionVolcengineTranscriptionTransport()
    ) {
        self.credentialStore = credentialStore
        self.openSpeechTransport = transport
    }

    var status: TranscriptionProviderStatus {
        let snapshot = credentialStore.currentSnapshot()
        if snapshot.hasCredential {
            return .ready(providerName: volcengineTranscriptionProviderName)
        }
        if let message = snapshot.lastErrorMessage {
            return .failed(providerName: volcengineTranscriptionProviderName, message: message)
        }
        return .authenticationRequired(providerName: volcengineTranscriptionProviderName)
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        let credential = try await volcengineCredential()
        return try await transcribeUsingOpenSpeechCredential(
            credential,
            audio: audio,
            progress: progress
        )
    }

    func startStreaming(progress: TranscriptionProgressHandler?) async throws -> any RealtimeTranscriptionSession {
        let credential = try await volcengineCredential()
        return try await startOpenSpeechStreaming(
            credential: credential,
            progress: progress
        )
    }

    private func transcribeUsingOpenSpeechCredential(
        _ credential: TranscriptionCredential,
        audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        try await withOpenSpeechResourceFallback { resourceID in
            let request = try VolcengineTranscriptionRequest.make(
                auth: credential.openSpeechAuth,
                audio: audio,
                resourceID: resourceID
            )
            return try await openSpeechTransport.transcribe(request: request, progress: progress)
        }
    }

    private func startOpenSpeechStreaming(
        credential: TranscriptionCredential,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession {
        try await withOpenSpeechResourceFallback { resourceID in
            let request = try VolcengineTranscriptionSessionRequest.make(
                auth: credential.openSpeechAuth,
                resourceID: resourceID
            )
            return try await openSpeechTransport.startStreaming(request: request, progress: progress)
        }
    }

    private func withOpenSpeechResourceFallback<T>(
        operation: (String) async throws -> T
    ) async throws -> T {
        let resourceIDs = Self.openSpeechResourceIDs
        var lastError: Error?

        for (index, resourceID) in resourceIDs.enumerated() {
            do {
                return try await operation(resourceID)
            } catch {
                lastError = error
                let hasFallback = index + 1 < resourceIDs.count
                guard hasFallback, Self.shouldRetryOpenSpeechResource(after: error) else {
                    throw error
                }
            }
        }

        throw lastError ?? TranscriptionProviderError.notConfigured
    }

    private static var openSpeechResourceIDs: [String] {
        var resourceIDs = [volcengineDefaultResourceID]
        if !resourceIDs.contains(volcengineLegacyOpenSpeechResourceID) {
            resourceIDs.append(volcengineLegacyOpenSpeechResourceID)
        }
        return resourceIDs
    }

    private static func shouldRetryOpenSpeechResource(after error: Error) -> Bool {
        guard case .transport(let providerName, let message, let retryable) = error as? TranscriptionProviderError else {
            return false
        }

        return providerName == volcengineTranscriptionProviderName
            && retryable
            && message.contains("OpenSpeech WebSocket 握手被服务端拒绝")
    }

    private func volcengineCredential() async throws -> TranscriptionCredential {
        let credential: TranscriptionCredential?
        do {
            credential = try await credentialStore.credential(for: .volcengine)
        } catch {
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: error.localizedDescription
            )
        }

        guard let credential else {
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: "Keychain 中没有保存火山引擎凭证。"
            )
        }

        let normalizedCredential: TranscriptionCredential
        do {
            normalizedCredential = try credential.normalized()
        } catch {
            throw TranscriptionProviderError.authentication(
                providerName: volcengineTranscriptionProviderName,
                message: error.localizedDescription
            )
        }

        return normalizedCredential
    }
}

private extension TranscriptionCredential {
    var openSpeechAuth: VolcengineTranscriptionAuth {
        switch mode {
        case .apiKey:
            .apiKey(apiKey ?? "")
        case .appIDAccessToken:
            .appIDAccessToken(appID: appID ?? "", accessToken: accessToken ?? "")
        }
    }
}

@MainActor
final class URLSessionVolcengineTranscriptionTransport: VolcengineTranscriptionTransporting {
    private let frameSamples = 3_200
    private let session: any VolcengineWebSocketSessioning

    init(session: any VolcengineWebSocketSessioning = URLSession.shared) {
        self.session = session
    }

    func transcribe(
        request: VolcengineTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        let urlRequest = Self.urlRequest(endpoint: request.endpoint, headers: request.headers)
        let task = session.webSocketTask(with: urlRequest)
        task.resume()

        do {
            let start = Date()
            try await task.send(.data(try VolcengineWireProtocol.buildFullClientRequestFrame()))

            let samples = request.audio.pcm16Samples
            var cursor = 0
            while cursor < samples.count {
                let end = min(cursor + frameSamples, samples.count)
                let isLast = end == samples.count
                try await task.send(
                    .data(
                        try VolcengineWireProtocol.buildAudioFrame(
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
            throw VolcengineTranscriptionErrorMapper.transportError(
                error,
                endpoint: request.endpoint,
                resourceID: request.resourceID
            )
        }
    }

    func startStreaming(
        request: VolcengineTranscriptionSessionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> any RealtimeTranscriptionSession {
        let urlRequest = Self.urlRequest(endpoint: request.endpoint, headers: request.headers)
        let task = session.webSocketTask(with: urlRequest)
        task.resume()

        do {
            try await task.send(.data(try VolcengineWireProtocol.buildFullClientRequestFrame()))
            return URLSessionVolcengineStreamingTranscriptionSession(
                task: task,
                endpoint: request.endpoint,
                progress: progress,
                startedAt: Date()
            )
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw VolcengineTranscriptionErrorMapper.transportError(
                error,
                endpoint: request.endpoint,
                resourceID: request.resourceID
            )
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
        from task: any VolcengineWebSocketTasking,
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

            switch try VolcengineWireProtocol.parseServerFrame(data) {
            case .error(let code, let message):
                throw VolcengineTranscriptionErrorMapper.providerError(code: code, message: message)
            case .response(let flags, let payload):
                if flags.isLast {
                    finalText = try VolcengineFinalTextResolver.resolve(payload: payload, partials: partials)
                    let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    return TranscriptSnapshot(
                        finalText: finalText ?? "",
                        partials: partials,
                        providerName: volcengineTranscriptionProviderName,
                        latencyMilliseconds: latency
                    )
                }

                if let partial = try VolcengineServerResponse.parsePartial(payload) {
                    partials.append(partial.text)
                    progress?(partial)
                }
            }
        }
    }
}

private actor URLSessionVolcengineStreamingTranscriptionSession: RealtimeTranscriptionSession {
    private static let frameSampleCount = 3_200

    private let task: any VolcengineWebSocketTasking
    private let endpoint: URL
    private let receiveTask: Task<TranscriptSnapshot, Error>
    private var pendingError: TranscriptionProviderError?
    private var isFinished = false
    private var sentAnyAudio = false
    private var sentAudioSampleCount = 0
    private var pendingAudioSamples: [Int16] = []

    init(
        task: any VolcengineWebSocketTasking,
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
                        try VolcengineWireProtocol.buildAudioFrame(
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
            pendingError = VolcengineTranscriptionErrorMapper.transportError(error, endpoint: endpoint)
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
                        try VolcengineWireProtocol.buildAudioFrame(
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
            throw VolcengineTranscriptionErrorMapper.transportError(error, endpoint: endpoint)
        }
    }

    private func sendFinalAudioSamples(_ samples: [Int16]) async throws {
        var cursor = 0
        while cursor < samples.count {
            let end = min(cursor + Self.frameSampleCount, samples.count)
            let isLast = end == samples.count
            try await task.send(
                .data(
                    try VolcengineWireProtocol.buildAudioFrame(
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
        from task: any VolcengineWebSocketTasking,
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

            switch try VolcengineWireProtocol.parseServerFrame(data) {
            case .error(let code, let message):
                throw VolcengineTranscriptionErrorMapper.providerError(code: code, message: message)
            case .response(let flags, let payload):
                if flags.isLast {
                    let finalText = try VolcengineFinalTextResolver.resolve(payload: payload, partials: partials)
                    let latency = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    return TranscriptSnapshot(
                        finalText: finalText,
                        partials: partials,
                        providerName: volcengineTranscriptionProviderName,
                        latencyMilliseconds: latency
                    )
                }

                if let partial = try VolcengineServerResponse.parsePartial(payload) {
                    partials.append(partial.text)
                    await progress?(partial)
                }
            }
        }
    }
}

private enum VolcengineFinalTextResolver {
    static func resolve(payload: Data, partials: [String]) throws -> String {
        do {
            return try VolcengineServerResponse.parseFinalText(payload)
        } catch let error as TranscriptionProviderError where canRecoverFromEmptyFinal(error) {
            if let finalFramePartial = try VolcengineServerResponse.parsePartial(payload)?.text,
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

        return providerName == volcengineTranscriptionProviderName
            && (message == "server response missing result" || message == "server response contains no final text")
    }
}

@MainActor
protocol VolcengineWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any VolcengineWebSocketTasking
}

@MainActor
protocol VolcengineWebSocketTasking: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSession: VolcengineWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any VolcengineWebSocketTasking {
        webSocketTask(with: request) as URLSessionWebSocketTask
    }
}

extension URLSessionWebSocketTask: @unchecked Sendable {}

extension URLSessionWebSocketTask: VolcengineWebSocketTasking {
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
