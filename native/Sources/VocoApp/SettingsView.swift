import AppKit
import SwiftUI
import VocoAppCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var transcriptionAPIKey = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases) { section in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                        Text(section.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: section.systemImage)
                }
            }
            .navigationTitle("Voco")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Voco 设置")
                        .font(.title2)
                        .fontWeight(.semibold)

                    statusRow

                    Text("当前版本包含 native macOS app shell：菜单栏状态、设置窗口、登录项开关和全局快捷键入口。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    launchAtLoginSection

                    hotkeySection

                    audioSettingsSection

                    transcriptionSection

                    injectionSettingsSection

                    hudSettingsSection

                    privacySettingsSection

                    recordingDiagnosticsSection

                    permissionsSection

                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            }
            .frame(minWidth: 480, minHeight: 360, alignment: .topLeading)
        }
        .onAppear {
            coordinator.prepareForSettingsPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: coordinator.snapshot.systemImage)
                .foregroundStyle(.yellow)
            Text(coordinator.snapshot.title)
                .font(.headline)
            if let message = coordinator.lastErrorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("登录时启动")
                    .font(.headline)
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { coordinator.launchAtLoginEnabled },
                        set: { enabled in
                            Task {
                                await coordinator.setLaunchAtLoginEnabled(enabled)
                            }
                        }
                    )
                )
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Image(systemName: coordinator.launchAtLoginState.systemImage)
                    .foregroundStyle(launchAtLoginTint(coordinator.launchAtLoginState))
                Text(coordinator.launchAtLoginState.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(coordinator.launchAtLoginState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if coordinator.launchAtLoginState == .requiresApproval {
                Text("请在 System Settings → General → Login Items 中批准 Voco。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var audioSettingsSection: some View {
        let snapshot = coordinator.audioSettingsSnapshot

        return settingsCard(section: .audio) {
            settingsStatusRow(
                title: snapshot.inputDevice.title,
                detail: snapshot.inputDevice.detail,
                systemImage: snapshot.inputDevice.systemImage
            )

            settingsStatusRow(
                title: snapshot.levelMeter.title,
                detail: snapshot.levelMeter.detail,
                systemImage: snapshot.levelMeter.systemImage,
                tint: statusTint(for: snapshot.levelMeter.systemImage)
            )

            settingsStatusRow(
                title: snapshot.sampleRate.title,
                detail: snapshot.sampleRate.detail,
                systemImage: snapshot.sampleRate.systemImage,
                tint: statusTint(for: snapshot.sampleRate.systemImage)
            )
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("权限")
                    .font(.headline)
                Spacer()
                Button {
                    coordinator.refreshPermissions()
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
            }

            ForEach(coordinator.permissions) { permission in
                permissionRow(permission)
            }
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("快捷键")
                    .font(.headline)
                Spacer()
                Label(coordinator.hotkeyRuntimeState.title, systemImage: coordinator.hotkeyRuntimeState.systemImage)
                    .font(.caption)
                    .foregroundStyle(hotkeyTint(coordinator.hotkeyRuntimeState))
            }

            HStack(spacing: 8) {
                Label(coordinator.hotkeyBinding.displayName, systemImage: "keyboard")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(coordinator.hotkeyMode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(coordinator.hotkeyRuntimeState.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var injectionSettingsSection: some View {
        let snapshot = coordinator.injectionSettingsSnapshot

        return settingsCard(section: .injection) {
            settingsStatusRow(
                title: snapshot.strategy.title,
                detail: snapshot.strategy.detail,
                systemImage: snapshot.strategy.systemImage,
                tint: statusTint(for: snapshot.strategy.systemImage)
            )

            settingsStatusRow(
                title: snapshot.focusedApp.title,
                detail: snapshot.focusedApp.detail,
                systemImage: snapshot.focusedApp.systemImage,
                tint: statusTint(for: snapshot.focusedApp.systemImage)
            )
        }
    }

    private var hudSettingsSection: some View {
        let snapshot = coordinator.hudSettingsSnapshot

        return settingsCard(section: .hud) {
            settingsStatusRow(
                title: snapshot.position.title,
                detail: snapshot.position.detail,
                systemImage: snapshot.position.systemImage
            )

            settingsStatusRow(
                title: snapshot.notchMode.title,
                detail: snapshot.notchMode.detail,
                systemImage: snapshot.notchMode.systemImage
            )

            settingsStatusRow(
                title: snapshot.transcriptPreview.title,
                detail: snapshot.transcriptPreview.detail,
                systemImage: snapshot.transcriptPreview.systemImage,
                tint: snapshot.transcriptPreview.isVisible ? .green : .secondary
            )
        }
    }

    private var privacySettingsSection: some View {
        let snapshot = coordinator.privacySettingsSnapshot

        return settingsCard(section: .privacy) {
            settingsStatusRow(
                title: snapshot.keychain.title,
                detail: snapshot.keychain.detail,
                systemImage: snapshot.keychain.systemImage,
                tint: statusTint(for: snapshot.keychain.systemImage)
            )

            settingsStatusRow(
                title: snapshot.transcriptRetention.title,
                detail: snapshot.transcriptRetention.detail,
                systemImage: snapshot.transcriptRetention.systemImage
            )

            settingsStatusRow(
                title: snapshot.logsPolicy.title,
                detail: snapshot.logsPolicy.detail,
                systemImage: snapshot.logsPolicy.systemImage
            )
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("转写")
                    .font(.headline)
                Spacer()
                Label(
                    coordinator.transcriptionProviderStatus.title,
                    systemImage: coordinator.transcriptionProviderStatus.systemImage
                )
                .font(.caption)
                .foregroundStyle(transcriptionTint(coordinator.transcriptionProviderStatus))
            }

            Text(coordinator.transcriptionProviderStatus.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: coordinator.transcriptionCredentials.hasAPIKey ? "key.fill" : "key")
                    .frame(width: 18)
                    .foregroundStyle(credentialTint(coordinator.transcriptionCredentials))

                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.transcriptionCredentials.statusTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(coordinator.transcriptionCredentials.maskedAPIKey ?? coordinator.transcriptionCredentials.storageDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var recordingDiagnosticsSection: some View {
        if coordinator.lastAudio != nil || coordinator.lastTranscript != nil || coordinator.lastInjection != nil || coordinator.lastErrorMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("录音诊断")
                    .font(.headline)

                if let audio = coordinator.lastAudio {
                    diagnosticRow(
                        title: "音频",
                        value: String(
                            format: "%.2fs · %.0f Hz · %d samples · peak %.2f",
                            audio.durationSeconds,
                            audio.sampleRate,
                            audio.pcm16Samples.count,
                            audio.peakAmplitude
                        ),
                        systemImage: "waveform"
                    )
                }

                if let transcript = coordinator.lastTranscript {
                    diagnosticRow(
                        title: "转写",
                        value: "\(transcript.providerName) · \(transcript.finalText.count) 字符",
                        systemImage: "text.bubble"
                    )
                }

                if let injection = coordinator.lastInjection {
                    diagnosticRow(
                        title: "输入",
                        value: "\(injection.targetAppName ?? "无目标 App") · \(injection.strategy.title)",
                        systemImage: "text.cursor"
                    )

                    Text(injection.detail)
                        .font(.caption)
                        .foregroundStyle(injection.succeeded ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = coordinator.lastErrorMessage {
                    diagnosticRow(title: "错误", value: message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func permissionRow(_ permission: PermissionSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.kind.systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(permission.kind.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Label(permission.state.title, systemImage: permission.state.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(permissionTint(permission.state))

                    Text(permission.isRequired ? "必需" : "可选")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(permission.kind.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !permission.state.isGranted {
                    HStack(spacing: 8) {
                        if permission.kind == .microphone {
                            Button {
                                Task {
                                    await coordinator.requestMicrophonePermission()
                                }
                            } label: {
                                Label("请求麦克风权限", systemImage: "mic.badge.plus")
                            }
                        }

                        Button {
                            openSettings(for: permission.kind)
                        } label: {
                            Label(permission.kind.recoveryActionTitle, systemImage: "gear")
                        }
                        .disabled(URL(string: permission.kind.settingsURLString) == nil)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func settingsCard<Content: View>(
        section: SettingsSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.title, systemImage: section.systemImage)
                .font(.headline)

            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func settingsStatusRow(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func diagnosticRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionTint(_ state: PermissionGrantState) -> Color {
        switch state {
        case .granted:
            .green
        case .notDetermined:
            .yellow
        case .denied, .restricted:
            .red
        case .unknown:
            .orange
        }
    }

    private func hotkeyTint(_ state: HotkeyRuntimeState) -> Color {
        switch state {
        case .listening:
            .green
        case .inactive:
            .secondary
        case .permissionNeeded:
            .yellow
        case .failed:
            .red
        }
    }

    private func launchAtLoginTint(_ state: LaunchAtLoginState) -> Color {
        switch state {
        case .enabled:
            .green
        case .disabled:
            .secondary
        case .requiresApproval:
            .yellow
        case .unavailable, .failed:
            .red
        }
    }

    private func transcriptionTint(_ state: TranscriptionProviderStatus) -> Color {
        switch state {
        case .ready:
            .green
        case .notConfigured, .authenticationRequired:
            .yellow
        case .offline, .failed:
            .red
        }
    }

    private func credentialTint(_ snapshot: TranscriptionCredentialSnapshot) -> Color {
        if snapshot.lastErrorMessage != nil {
            return .red
        }

        return snapshot.hasAPIKey ? .green : .secondary
    }

    private func statusTint(for systemImage: String) -> Color {
        if systemImage.contains("checkmark") || systemImage == "key.fill" {
            return .green
        }

        if systemImage.contains("xmark") || systemImage.contains("exclamationmark") {
            return .red
        }

        return .secondary
    }

    private func openSettings(for kind: PermissionKind) {
        guard let url = URL(string: kind.settingsURLString) else {
            coordinator.fail("无法打开系统设置：\(kind.title) 的链接无效")
            return
        }

        if !NSWorkspace.shared.open(url) {
            coordinator.fail("无法打开系统设置：\(kind.title)")
        }
    }
}
