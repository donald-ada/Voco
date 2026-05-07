import ApplicationServices
import AVFoundation
import Foundation
import VocoAppCore

struct MacPermissionProvider: PermissionProviding {
    func currentSnapshots() -> [PermissionSnapshot] {
        [
            .microphone(microphoneState()),
            .accessibility(accessibilityState())
        ]
    }

    func requestMicrophoneAccess() async -> [PermissionSnapshot] {
        _ = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        return currentSnapshots()
    }

    private func microphoneState() -> PermissionGrantState {
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
    }

    private func accessibilityState() -> PermissionGrantState {
        AXIsProcessTrusted() ? .granted : .denied
    }
}
