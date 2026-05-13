import ApplicationServices
import AVFoundation
import Foundation
import VocoAppCore

struct MacPermissionProvider: PermissionProviding {
    typealias MicrophoneAccessRequester = @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
    typealias PermissionStateReader = @Sendable () -> PermissionGrantState

    private let microphoneAccessRequester: MicrophoneAccessRequester
    private let microphoneStateReader: PermissionStateReader
    private let accessibilityStateReader: PermissionStateReader

    init(
        microphoneAccessRequester: @escaping MicrophoneAccessRequester = { completion in
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        },
        microphoneStateReader: @escaping PermissionStateReader = {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                .notDetermined
            case .restricted:
                .restricted
            case .denied:
                .denied
            case .authorized:
                .granted
            @unknown default:
                .unknown
            }
        },
        accessibilityStateReader: @escaping PermissionStateReader = {
            AXIsProcessTrusted() ? .granted : .denied
        }
    ) {
        self.microphoneAccessRequester = microphoneAccessRequester
        self.microphoneStateReader = microphoneStateReader
        self.accessibilityStateReader = accessibilityStateReader
    }

    func currentSnapshots() -> [PermissionSnapshot] {
        [
            .microphone(microphoneStateReader()),
            .accessibility(accessibilityStateReader())
        ]
    }

    func requestMicrophoneAccess() async -> [PermissionSnapshot] {
        _ = await withCheckedContinuation { continuation in
            microphoneAccessRequester { granted in
                Task { @MainActor in
                    continuation.resume(returning: granted)
                }
            }
        }
        return currentSnapshots()
    }
}
