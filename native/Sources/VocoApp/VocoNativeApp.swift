import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    @NSApplicationDelegateAdaptor(VocoAppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @State private var didPresentInitialSettingsWindow = false

    var body: some Scene {
        MenuBarExtra {
            Button(coordinator.strings.app.showSettingsMenuTitle) {
                coordinator.prepareForSettingsPresentation()
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Divider()

            Button(coordinator.strings.app.quitMenuTitle) {
                NSApp.terminate(nil)
            }
        } label: {
            MenuBarIcon(
                resourceName: coordinator.snapshot.templateIconResourceName,
                fallbackSystemImage: coordinator.snapshot.systemImage
            )
            .accessibilityLabel(Text("Voco \(coordinator.snapshot.title)"))
            .help("Voco \(coordinator.snapshot.title)")
            .onAppear {
                presentInitialSettingsWindowIfNeeded()
            }
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
        let voiceInputSessionStore = MacVoiceInputSessionStore.makeDefault()
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
            voiceInputSessionStore: voiceInputSessionStore,
            hotkeyBinding: voiceInputPreferences.hotkeyPreset?.binding ?? .default,
            hotkeyMode: voiceInputPreferences.hotkeyMode ?? .toggle
        )
        appCoordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
        _coordinator = StateObject(wrappedValue: appCoordinator)
        appDelegate.coordinator = appCoordinator
        appDelegate.coordinatorDidBecomeAvailable()
    }

    private func presentInitialSettingsWindowIfNeeded() {
        guard !didPresentInitialSettingsWindow,
              !coordinator.silentLaunchEnabled else {
            return
        }

        didPresentInitialSettingsWindow = true
        coordinator.prepareForSettingsPresentation()
        SettingsWindowPresenter.shared.show(coordinator: coordinator)
    }
}
