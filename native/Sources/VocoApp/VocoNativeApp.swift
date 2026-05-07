import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    static let showSettingsMenuTitle = "显示 Voco"
    static let quitMenuTitle = "退出"

    @StateObject private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            Button(Self.showSettingsMenuTitle) {
                coordinator.prepareForSettingsPresentation()
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Divider()

            Button(Self.quitMenuTitle) {
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
        SettingsWorkbenchFontRegistrar.registerBundledFonts()
        let permissionProvider = MacPermissionProvider()
        let credentialStore = MacKeychainCredentialStore()
        let transcriptionProvider = MacVolcengineTranscriptionProvider(credentialStore: credentialStore)
        let voiceInputPreferences = MacVoiceInputPreferenceStore()
        let appPreferences = MacAppPreferenceStore()
        MacDockPresentationController.apply(displayInDockEnabled: appPreferences.displayInDockEnabled)
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
            appPreferenceStore: appPreferences,
            hotkeyBinding: voiceInputPreferences.hotkeyPreset?.binding ?? .default,
            hotkeyMode: voiceInputPreferences.hotkeyMode ?? .toggle
        )
        appCoordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
        _coordinator = StateObject(wrappedValue: appCoordinator)

        if AppLaunchPresentationPolicy(silentLaunchEnabled: appPreferences.silentLaunchEnabled).action == .showSettingsWindow {
            DispatchQueue.main.async {
                appCoordinator.prepareForSettingsPresentation()
                SettingsWindowPresenter.shared.show(coordinator: appCoordinator)
            }
        }
    }
}
