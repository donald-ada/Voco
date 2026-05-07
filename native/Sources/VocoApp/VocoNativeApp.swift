import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    @StateObject private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            Button("设置...") {
                coordinator.prepareForSettingsPresentation()
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Divider()

            Button("退出 Voco") {
                NSApp.terminate(nil)
            }
        } label: {
            MenuBarIcon(
                resourceName: coordinator.snapshot.templateIconResourceName,
                fallbackSystemImage: coordinator.snapshot.systemImage
            )
            .accessibilityLabel(Text("Voco \(coordinator.snapshot.title)"))
            .help("Voco \(coordinator.snapshot.title)")
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let permissionProvider = MacPermissionProvider()
        let credentialStore = MacKeychainCredentialStore()
        let transcriptionProvider = MacDoubaoTranscriptionProvider(credentialStore: credentialStore)
        let appCoordinator = AppCoordinator(
            permissionProvider: permissionProvider,
            launchAtLoginProvider: MacLaunchAtLoginProvider(),
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: NativeRecordingWorkflow(
                audioCapture: MacAudioCaptureEngine(),
                transcription: transcriptionProvider,
                textInjection: MacTextInjectionProvider()
            ),
            hotkeyProvider: MacHotkeyProvider(),
            installLocationProvider: MacInstallLocationProvider(),
            legacyInstallProvider: MacLegacyInstallProvider()
        )
        appCoordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
        _coordinator = StateObject(wrappedValue: appCoordinator)
    }
}
