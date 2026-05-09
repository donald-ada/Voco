import AppKit
import SwiftUI
import VocoAppCore

@MainActor
struct VocoNativeAppDependencies {
    let coordinator: AppCoordinator
    let skillPreferenceStore: any SkillPreferenceStoring
    let displayInDockEnabled: Bool

    static func make() -> VocoNativeAppDependencies {
        let permissionProvider = MacPermissionProvider()
        let credentialStore = MacKeychainCredentialStore()
        let voiceInputPreferences = MacVoiceInputPreferenceStore()
        let appPreferences = MacAppPreferenceStore()
        let skillPreferenceStore = MacSkillPreferenceStore()
        let voiceInputSessionStore = MacVoiceInputSessionStore.makeDefault()
        let transcriptionProvider = MacVolcengineTranscriptionProvider(credentialStore: credentialStore)
        let audioCapture = MacAudioCaptureEngine()
        if let audioInputDevice = voiceInputPreferences.audioInputDevice {
            audioCapture.setInputDevice(audioInputDevice)
        }

        let coordinator = AppCoordinator(
            permissionProvider: permissionProvider,
            launchAtLoginProvider: MacLaunchAtLoginProvider(),
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: NativeRecordingWorkflow(
                audioCapture: audioCapture,
                transcription: transcriptionProvider,
                textInjection: MacTextInjectionProvider(),
                postProcessingSettingsProvider: { skillPreferenceStore.skillSettings }
            ),
            hotkeyProvider: MacHotkeyProvider(),
            installLocationProvider: MacInstallLocationProvider(),
            legacyInstallProvider: MacLegacyInstallProvider(),
            voiceInputPreferenceStore: voiceInputPreferences,
            appPreferenceStore: appPreferences,
            voiceInputSessionStore: voiceInputSessionStore,
            skillPreferenceStore: skillPreferenceStore,
            hotkeyBinding: voiceInputPreferences.hotkeyPreset?.binding ?? .default,
            hotkeyMode: voiceInputPreferences.hotkeyMode ?? .toggle
        )

        return VocoNativeAppDependencies(
            coordinator: coordinator,
            skillPreferenceStore: skillPreferenceStore,
            displayInDockEnabled: appPreferences.displayInDockEnabled
        )
    }
}

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
        let dependencies = VocoNativeAppDependencies.make()
        MacDockPresentationController.apply(displayInDockEnabled: dependencies.displayInDockEnabled)
        dependencies.coordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: dependencies.coordinator)
        _coordinator = StateObject(wrappedValue: dependencies.coordinator)
        appDelegate.coordinator = dependencies.coordinator
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
