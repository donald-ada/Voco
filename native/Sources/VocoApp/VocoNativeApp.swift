import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    @StateObject private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            Button("显示 Voco") {
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
        SettingsWorkbenchFontRegistrar.registerBundledFonts()
        let permissionProvider = MacPermissionProvider()
        let credentialStore = MacKeychainCredentialStore()
        let transcriptionProvider = MacVolcengineTranscriptionProvider(credentialStore: credentialStore)
        let voiceInputPreferences = MacVoiceInputPreferenceStore()
        let audioCapture = MacAudioCaptureEngine()
        if let audioInputDevice = voiceInputPreferences.audioInputDevice {
            audioCapture.setInputDevice(audioInputDevice)
        }

        let appCoordinator = AppCoordinator(
            permissionProvider: permissionProvider,
            launchAtLoginProvider: MacLaunchAtLoginProvider(),
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: NativeRecordingWorkflow(
                audioCapture: audioCapture,
                transcription: transcriptionProvider,
                textInjection: MacTextInjectionProvider()
            ),
            hotkeyProvider: MacHotkeyProvider(),
            installLocationProvider: MacInstallLocationProvider(),
            legacyInstallProvider: MacLegacyInstallProvider(),
            voiceInputPreferenceStore: voiceInputPreferences,
            hotkeyBinding: voiceInputPreferences.hotkeyPreset?.binding ?? .default,
            hotkeyMode: voiceInputPreferences.hotkeyMode ?? .toggle
        )
        appCoordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
        _coordinator = StateObject(wrappedValue: appCoordinator)
    }
}
