import AppKit
import SwiftUI
import VocoAppCore

struct OnboardingView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var transcriptionAPIKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let warningTitle = coordinator.installLocation.warningTitle,
                   let warningDetail = coordinator.installLocation.warningDetail {
                    warningBanner(title: warningTitle, detail: warningDetail)
                }

                ForEach(coordinator.onboarding.steps) { step in
                    stepRow(step)
                }

                if let message = coordinator.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button {
                        if coordinator.completeOnboardingIfReady() {
                            OnboardingWindowPresenter.shared.close()
                        }
                    } label: {
                        Label("完成首次设置", systemImage: "checkmark.circle")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!coordinator.onboarding.isComplete)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear {
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voco 首次设置")
                .font(.title2)
                .fontWeight(.semibold)

            Text("完成必要权限、ASR 凭证和快捷键测试后，Voco 会留在菜单栏中等待全局快捷键。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func warningBanner(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.yellow)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stepRow(_ step: OnboardingStepSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: step.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(step.title)
                            .font(.headline)

                        Label(step.status.title, systemImage: step.status.systemImage)
                            .font(.caption)
                            .foregroundStyle(statusTint(step.status))

                        Text(step.isRequired ? "必需" : "可选")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.statusDetail)
                        .font(.caption)
                        .foregroundStyle(statusTint(step.status))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            controls(for: step)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func controls(for step: OnboardingStepSnapshot) -> some View {
        switch step.id {
        case .microphone, .accessibility, .inputMonitoring:
            permissionControls(for: step)
        case .asrSetup:
            asrControls
        case .launchAtLogin:
            launchAtLoginControls
        case .hotkeyTest:
            hotkeyControls
        }
    }

    @ViewBuilder
    private func permissionControls(for step: OnboardingStepSnapshot) -> some View {
        if step.status != .complete {
            HStack(spacing: 8) {
                if let retryAction = step.retryAction {
                    Button {
                        retryPermissionStep(step.id)
                    } label: {
                        Label(retryAction.title, systemImage: retryAction.systemImage)
                    }
                }

                if let recoveryAction = step.recoveryAction {
                    Button {
                        openSettings(recoveryAction)
                    } label: {
                        Label(recoveryAction.title, systemImage: recoveryAction.systemImage)
                    }
                    .disabled(recoveryAction.settingsURLString.flatMap(URL.init(string:)) == nil)
                }
            }
            .controlSize(.small)
        }
    }

    private var asrControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Doubao API Key", text: $transcriptionAPIKey)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    let apiKey = transcriptionAPIKey
                    transcriptionAPIKey = ""
                    Task {
                        await coordinator.saveTranscriptionAPIKey(apiKey)
                    }
                } label: {
                    Label("保存到 Keychain", systemImage: "key")
                }
                .disabled(transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    Task {
                        await coordinator.clearTranscriptionCredentials()
                    }
                } label: {
                    Label("清除凭证", systemImage: "trash")
                }
                .disabled(!coordinator.transcriptionCredentials.hasAPIKey)
            }
            .controlSize(.small)
        }
    }

    private var launchAtLoginControls: some View {
        HStack(spacing: 12) {
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
            .disabled(!coordinator.installLocation.allowsLaunchAtLogin)

            Button {
                coordinator.markLaunchAtLoginSkippedForOnboarding()
            } label: {
                Label("暂时跳过", systemImage: "forward")
            }
            .controlSize(.small)
        }
    }

    private var hotkeyControls: some View {
        HStack(spacing: 8) {
            Label(coordinator.hotkeyBinding.displayName, systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                coordinator.markHotkeyVerifiedForOnboarding()
            } label: {
                Label("我已测试快捷键", systemImage: "checkmark")
            }
            .controlSize(.small)
            .disabled(coordinator.hotkeyRuntimeState != .listening)
        }
    }

    private func retryPermissionStep(_ id: OnboardingStepID) {
        if id == .microphone {
            Task {
                await coordinator.requestMicrophonePermission()
            }
        } else {
            coordinator.refreshPermissions()
        }
    }

    private func openSettings(_ action: OnboardingAction) {
        guard let urlString = action.settingsURLString, let url = URL(string: urlString) else {
            coordinator.fail("无法打开系统设置：\(action.title) 的链接无效")
            return
        }

        if !NSWorkspace.shared.open(url) {
            coordinator.fail("无法打开系统设置：\(action.title)")
        }
    }

    private func statusTint(_ status: OnboardingStepStatus) -> Color {
        switch status {
        case .complete:
            .green
        case .actionNeeded:
            .yellow
        case .blocked:
            .red
        case .skipped:
            .secondary
        }
    }
}
