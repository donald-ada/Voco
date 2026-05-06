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
    private let session: URLSession

    init(session: URLSession = .shared) {
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
            try await sendHandshakePing(on: task)
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

    private func sendHandshakePing(on task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
