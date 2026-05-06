import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    @StateObject private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            Button(coordinator.isRecording ? "停止录音" : "开始录音") {
                coordinator.toggleRecordingFromMenu()
            }
            .disabled(!coordinator.snapshot.isRecordingActionEnabled && !coordinator.isRecording)

            Divider()

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
        let credentialStore = MacKeychainCredentialStore()
        let transcriptionProvider = MacDoubaoTranscriptionProvider(credentialStore: credentialStore)
        let appCoordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            permissionProvider: MacPermissionProvider(),
            launchAtLoginProvider: MacLaunchAtLoginProvider(),
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: NativeRecordingWorkflow(
                audioCapture: MacAudioCaptureEngine(),
                transcription: transcriptionProvider,
                textInjection: MacTextInjectionProvider()
            ),
            hotkeyProvider: MacHotkeyProvider()
        )
        appCoordinator.finishLaunching()
        HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
        _coordinator = StateObject(wrappedValue: appCoordinator)
    }
}
