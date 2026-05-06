import Foundation
import VocoAppCore

@MainActor
final class MacDoubaoTranscriptionProvider: TranscriptionProviding {
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
            try await task.sendPing()
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw DoubaoTranscriptionErrorMapper.transportError(error, endpoint: request.endpoint)
        }

        task.cancel(with: .goingAway, reason: nil)
        throw TranscriptionProviderError.provider(
            providerName: doubaoTranscriptionProviderName,
            message: "Native Doubao WebSocket handshake succeeded, but binary audio streaming is not enabled in this build."
        )
    }

}

@MainActor
protocol DoubaoWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any DoubaoWebSocketTasking
}

@MainActor
protocol DoubaoWebSocketTasking: AnyObject {
    func resume()
    func sendPing() async throws
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSession: DoubaoWebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> any DoubaoWebSocketTasking {
        webSocketTask(with: request) as URLSessionWebSocketTask
    }
}

extension URLSessionWebSocketTask: DoubaoWebSocketTasking {
    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
