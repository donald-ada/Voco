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
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Toggle(
                "登录时启动",
                isOn: Binding(
                    get: { coordinator.launchAtLoginEnabled },
                    set: { coordinator.setLaunchAtLoginEnabled($0) }
                )
            )

            Divider()

            Button("退出 Voco") {
                NSApp.terminate(nil)
            }
        } label: {
            Label(coordinator.snapshot.title, systemImage: coordinator.snapshot.systemImage)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let appCoordinator = AppCoordinator()
        appCoordinator.finishLaunching()
        _coordinator = StateObject(wrappedValue: appCoordinator)
    }
}
