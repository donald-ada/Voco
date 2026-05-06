import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    private static let onboardingCompletionDefaultsKey = "hasCompletedOnboarding"

    @StateObject private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            Button(coordinator.isRecording ? "停止录音" : "开始录音") {
                coordinator.toggleRecordingFromMenu()
            }
            .disabled(!coordinator.snapshot.isRecordingActionEnabled && !coordinator.isRecording)

            Divider()

            Button("打开首次设置") {
                coordinator.refreshOnboardingState()
                OnboardingWindowPresenter.shared.show(coordinator: coordinator)
            }

            Button("打开设置") {
                coordinator.prepareForSettingsPresentation()
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Button("检查权限") {
                coordinator.prepareForSettingsPresentation()
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Button("打开诊断") {
                coordinator.prepareForSettingsPresentation()
                DiagnosticsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Toggle(
                "登录时启动",
                isOn: Binding(
                    get: { coordinator.launchAtLoginEnabled },
                    set: { enabled in
                        Task {
                            await coordinator.setLaunchAtLoginEnabled(enabled)
                        }
                    }
                )
            )

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
        let defaults = UserDefaults.standard
        let storedOnboardingCompletion = defaults.object(forKey: Self.onboardingCompletionDefaultsKey) as? Bool
        let hasCompletedOnboarding = OnboardingCompletionMigration.resolvedCompletion(
            storedValue: storedOnboardingCompletion,
            permissions: permissionProvider.currentSnapshots(),
            transcriptionCredentials: credentialStore.currentSnapshot()
        )
        let appCoordinator = AppCoordinator(
            hasCompletedOnboarding: hasCompletedOnboarding,
            setHasCompletedOnboarding: { completed in
                defaults.set(completed, forKey: Self.onboardingCompletionDefaultsKey)
            },
            permissionProvider: permissionProvider,
            launchAtLoginProvider: MacLaunchAtLoginProvider(),
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: NativeRecordingWorkflow(
                audioCapture: MacAudioCaptureEngine(),
                transcription: transcriptionProvider,
                textInjection: MacTextInjectionProvider()
            ),
            hotkeyProvider: MacHotkeyProvider(),
            installLocationProvider: MacInstallLocationProvider()
        )
        appCoordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
        if appCoordinator.status == .needsOnboarding {
            OnboardingWindowPresenter.shared.show(coordinator: appCoordinator)
        }
        _coordinator = StateObject(wrappedValue: appCoordinator)
    }
}
