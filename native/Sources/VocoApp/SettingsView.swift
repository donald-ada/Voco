import AppKit
import SwiftUI
import VocoAppCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var selectedSection: SettingsWorkbenchSection = .overview
    @State private var selectedVolcengineCredentialMode: VolcengineCredentialMode = .apiKey
    @State private var transcriptionAPIKey = ""
    @State private var volcengineAppID = ""
    @State private var volcengineAccessToken = ""
    @State private var settingsFeedbackMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            SettingsWorkbenchSidebar(
                selectedSection: $selectedSection,
                snapshot: coordinator.settingsWorkbenchSnapshot
            )

            Divider()

            ScrollView {
                detailContent(for: selectedSection)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 30)
                    .frame(maxWidth: 900, minHeight: 560, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .background(SettingsWorkbenchVisual.detailBackground)
        }
        .frame(minWidth: 900, minHeight: 600)
        .font(SettingsWorkbenchVisual.bodyFont)
        .background(SettingsWorkbenchVisual.pageBackground)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            coordinator.prepareForSettingsPresentation()
            syncSelectedVolcengineCredentialMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshLegacyInstall()
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
            syncSelectedVolcengineCredentialMode()
        }
    }

    @ViewBuilder
    private func detailContent(for section: SettingsWorkbenchSection) -> some View {
        switch section {
        case .overview:
            overviewSection
        case .settings:
            settingsSection
        case .model:
            modelWorkbenchSection
        }
    }

    private var overviewSection: some View {
        let workbench = coordinator.settingsWorkbenchSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "OVERVIEW",
                title: "Voco 设置",
                detail: "查看语音输入是否可用，并处理影响录音、转写或文本输入的问题。"
            )

            legacyInstallSection

            SettingsOverviewRecoveryCard(
                snapshot: workbench,
                primaryAction: performOverviewPrimaryAction,
                secondaryAction: {
                    coordinator.prepareForSettingsPresentation()
                    settingsFeedbackMessage = "已重新检查状态。"
                }
            )

        }
    }

    private var settingsSection: some View {
        let audio = coordinator.audioSettingsSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "SETTINGS",
                title: "语音输入体验",
                detail: "配置开始录音的按键、触发方式、麦克风输入和 macOS 权限。"
            ) {
                Button {
                    startTestRecordingFromSettings()
                } label: {
                    Label("试录 3 秒", systemImage: "waveform")
                }
            }

            workbenchPanel(
                title: "录音控制",
                detail: "选择快捷键、录音方式和输入设备。"
            ) {
                WorkbenchStatusPill(
                    coordinator.hotkeyRuntimeState.title,
                    systemImage: coordinator.hotkeyRuntimeState.systemImage,
                    color: hotkeyTint(coordinator.hotkeyRuntimeState)
                )
            } content: {
                voiceInputControls(audio: audio)
            }

            systemPanel

            permissionsPanel
        }
    }

    private var modelWorkbenchSection: some View {
        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "MODEL",
                title: "火山引擎模型",
                detail: "选择凭证模式，并将火山引擎凭证保存到 macOS Keychain。"
            )

            credentialPanel
        }
    }

    private func settingsPageHeader<Actions: View>(
        eyebrow: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(eyebrow)
                .font(SettingsWorkbenchVisual.eyebrowFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)

            Spacer()

            HStack(spacing: 8) {
                actions()
            }
            .controlSize(.small)
            .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())

            settingsHeaderStatus
        }
        .padding(.bottom, 4)
    }

    private func settingsPageHeader(
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        settingsPageHeader(eyebrow: eyebrow, title: title, detail: detail) {
            EmptyView()
        }
    }

    private var settingsHeaderStatus: some View {
        let snapshot = coordinator.settingsWorkbenchSnapshot
        let status = snapshot.status(for: .overview)

        return HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(status.workbenchColor)
                .frame(width: 7, height: 7)

            Text(status.workbenchTitle)
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(status.workbenchColor)
                .lineLimit(1)

            Text(snapshot.statusTitle)
                .font(SettingsWorkbenchVisual.caption2Font)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .lineLimit(1)
        }
    }

    private func workbenchPanel<Accessory: View, Content: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SettingsWorkbenchVisual.panelTitleFont)
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                    Text(detail)
                        .font(SettingsWorkbenchVisual.captionFont)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                accessory()
            }

            content()
        }
        .padding(14)
        .workbenchPanel(cornerRadius: 15)
    }

    private func voiceInputControls(audio: AudioSettingsSnapshot) -> some View {
        VStack(spacing: 10) {
            VoiceInputSettingRow(
                label: "快捷键",
                title: coordinator.hotkeyBinding.displayName,
                detail: coordinator.hotkeyRuntimeState.detail,
                systemImage: "keyboard",
                color: hotkeyTint(coordinator.hotkeyRuntimeState)
            ) {
                WorkbenchMenuControl(
                    title: selectedHotkeyPresetBinding.wrappedValue.title,
                    width: 156
                ) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Button {
                            selectedHotkeyPresetBinding.wrappedValue = preset
                        } label: {
                            WorkbenchMenuItemLabel(
                                title: preset.title,
                                isSelected: selectedHotkeyPresetBinding.wrappedValue == preset
                            )
                        }
                    }
                }
            }

            VoiceInputSettingRow(
                label: "录音模式",
                title: coordinator.hotkeyMode.title,
                detail: coordinator.hotkeyMode == .toggle ? "按一次开始，再按一次提交。" : "按住开始录音，松开后提交。",
                systemImage: "record.circle",
                color: SettingsWorkbenchVisual.accent
            ) {
                WorkbenchSegmentedControl(
                    options: HotkeyMode.allCases,
                    selected: selectedHotkeyModeBinding.wrappedValue,
                    width: 190,
                    title: \.title
                ) { mode in
                    selectedHotkeyModeBinding.wrappedValue = mode
                }
            }

            VoiceInputSettingRow(
                label: "输入设备",
                title: audio.inputDevice.title,
                detail: audio.inputDevice.detail,
                systemImage: audio.inputDevice.systemImage,
                color: SettingsWorkbenchVisual.accent
            ) {
                HStack(spacing: 8) {
                    WorkbenchMenuControl(
                        title: selectedAudioInputDeviceBinding.wrappedValue.title,
                        width: 168
                    ) {
                        ForEach(audioInputDevicesForPicker) { device in
                            Button {
                                selectedAudioInputDeviceBinding.wrappedValue = device
                            } label: {
                                WorkbenchMenuItemLabel(
                                    title: device.title,
                                    isSelected: selectedAudioInputDeviceBinding.wrappedValue == device
                                )
                            }
                        }
                    }

                    Button {
                        openSoundInputSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                    .help("打开 macOS 声音输入设置")
                }
            }
        }
    }

    private var credentialPanel: some View {
        workbenchPanel(
            title: "火山引擎凭证",
            detail: "凭证会保存到 macOS Keychain，不会在界面中显示完整密钥。"
        ) {
            WorkbenchStatusPill(
                coordinator.transcriptionCredentials.statusTitle,
                systemImage: coordinator.transcriptionCredentials.hasCredential ? "key.fill" : "key",
                color: credentialTint(coordinator.transcriptionCredentials)
            )
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                WorkbenchSegmentedControl(
                    options: VolcengineCredentialMode.allCases,
                    selected: selectedVolcengineCredentialMode,
                    width: 360,
                    title: \.title
                ) { mode in
                    selectedVolcengineCredentialMode = mode
                }

                WorkbenchFieldBlock(label: selectedVolcengineCredentialMode.fieldLabel) {
                    credentialFields
                }

                Text(selectedVolcengineCredentialMode.detail)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        let mode = selectedVolcengineCredentialMode
                        let apiKey = transcriptionAPIKey
                        let appID = volcengineAppID
                        let accessToken = volcengineAccessToken
                        clearTranscriptionInputFields()
                        Task {
                            switch mode {
                            case .apiKey:
                                await coordinator.saveTranscriptionAPIKey(apiKey)
                            case .appIDAccessToken:
                                await coordinator.saveVolcengineAppIDAccessToken(
                                    appID: appID,
                                    accessToken: accessToken
                                )
                            }
                            if coordinator.lastErrorMessage == nil {
                                settingsFeedbackMessage = "已保存火山引擎凭证。"
                            }
                        }
                    } label: {
                        Label("保存到 Keychain", systemImage: "key")
                    }
                    .buttonStyle(SettingsWorkbenchPrimaryButtonStyle())
                    .disabled(!canSaveSelectedCredential)

                    Button("刷新状态") {
                        coordinator.prepareForSettingsPresentation()
                        settingsFeedbackMessage = "已刷新火山引擎状态。"
                    }
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())

                    Button(role: .destructive) {
                        Task {
                            await coordinator.clearTranscriptionCredentials()
                            if coordinator.lastErrorMessage == nil {
                                settingsFeedbackMessage = "已清除火山引擎凭证。"
                            }
                        }
                    } label: {
                        Label("清除凭证", systemImage: "trash")
                    }
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                    .disabled(!coordinator.transcriptionCredentials.hasCredential)
                }
            }
        }
    }

    private var permissionsPanel: some View {
        workbenchPanel(
            title: "权限",
            detail: "允许麦克风和辅助功能。"
        ) {
            Button {
                coordinator.refreshPermissions()
                settingsFeedbackMessage = "已重新检查权限。"
            } label: {
                Label("重新检查", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(coordinator.permissions) { permission in
                    WorkbenchInfoRow(
                        symbol: String(permission.kind.title.prefix(2)),
                        title: permission.kind.title,
                        detail: permission.kind.description,
                        color: permissionTint(permission.state)
                    ) {
                        HStack(spacing: 8) {
                            WorkbenchStatusPill(permission.state.title, color: permissionTint(permission.state))
                            permissionActions(permission)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func permissionActions(_ permission: PermissionSnapshot) -> some View {
        if permission.state.isGranted {
            EmptyView()
        } else {
            if permission.kind == .microphone {
                Button("请求") {
                    Task {
                        await coordinator.requestMicrophonePermission()
                    }
                }
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }

            Button(permission.kind.recoveryActionTitle) {
                openSettings(for: permission.kind)
            }
            .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            .disabled(URL(string: permission.kind.settingsURLString) == nil)
        }
    }

    private var systemPanel: some View {
        workbenchPanel(
            title: "系统",
            detail: "配置 Voco 的启动方式。"
        ) {
            WorkbenchStatusPill(
                coordinator.silentLaunchEnabled ? "静默启动" : "启动显示窗口",
                systemImage: coordinator.silentLaunchEnabled ? "menubar.rectangle" : "macwindow",
                color: SettingsWorkbenchVisual.neutral
            )
        } content: {
            VStack(spacing: 10) {
                VoiceInputSettingRow(
                    label: "开机自启动",
                    title: coordinator.launchAtLoginEnabled ? "已开启" : coordinator.launchAtLoginState.title,
                    detail: "启用后，Voco将在系统启动时自动运行。可在系统设置 > 通用 > 登录项中管理。",
                    systemImage: coordinator.launchAtLoginState.systemImage,
                    color: launchAtLoginTint(coordinator.launchAtLoginState)
                ) {
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
                    .toggleStyle(.switch)
                }

                if coordinator.launchAtLoginState == .requiresApproval {
                    Text("请在系统设置 > 通用 > 登录项中批准 Voco。")
                        .font(SettingsWorkbenchVisual.captionFont)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VoiceInputSettingRow(
                    label: "静默启动",
                    title: coordinator.silentLaunchEnabled ? "仅在系统托盘运行" : "启动时显示主窗口",
                    detail: "启用后，应用启动时不显示主窗口，仅在系统托盘运行。可随时通过托盘图标打开主窗口。",
                    systemImage: coordinator.silentLaunchEnabled ? "menubar.rectangle" : "macwindow",
                    color: SettingsWorkbenchVisual.neutral
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { coordinator.silentLaunchEnabled },
                            set: { enabled in
                                coordinator.setSilentLaunchEnabled(enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    @ViewBuilder
    private var legacyInstallSection: some View {
        if coordinator.legacyInstall.requiresUserAction {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        coordinator.legacyInstall.title,
                        systemImage: coordinator.legacyInstall.systemImage
                    )
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(legacyInstallTint(coordinator.legacyInstall.status))

                    Spacer()

                    Button {
                        coordinator.refreshLegacyInstall()
                    } label: {
                        Label("重新检查", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                }

                Text(coordinator.legacyInstall.detail)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    Task {
                        await coordinator.removeLegacyLaunchAgentFromUserAction()
                    }
                } label: {
                    Label(
                        coordinator.isRemovingLegacyLaunchAgent ? "正在移除..." : "移除旧版启动项",
                        systemImage: coordinator.isRemovingLegacyLaunchAgent ? "hourglass" : "trash"
                    )
                }
                .controlSize(.small)
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                .disabled(coordinator.isRemovingLegacyLaunchAgent)
            }
            .padding(12)
            .workbenchPanel(cornerRadius: 12)
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        switch selectedVolcengineCredentialMode {
        case .apiKey:
            SecureField("火山引擎 API Key", text: $transcriptionAPIKey)
                .workbenchCredentialField()
        case .appIDAccessToken:
            TextField("火山引擎 App ID", text: $volcengineAppID)
                .workbenchCredentialField()

            SecureField("火山引擎 Access Token", text: $volcengineAccessToken)
                .workbenchCredentialField()
        }
    }

    private var canSaveSelectedCredential: Bool {
        switch selectedVolcengineCredentialMode {
        case .apiKey:
            !transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appIDAccessToken:
            !volcengineAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !volcengineAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func permissionTint(_ state: PermissionGrantState) -> Color {
        switch state {
        case .granted:
            SettingsWorkbenchVisual.success
        case .notDetermined:
            SettingsWorkbenchVisual.warning
        case .denied, .restricted:
            SettingsWorkbenchVisual.danger
        case .unknown:
            SettingsWorkbenchVisual.warning
        }
    }

    private func hotkeyTint(_ state: HotkeyRuntimeState) -> Color {
        switch state {
        case .listening:
            SettingsWorkbenchVisual.success
        case .inactive:
            SettingsWorkbenchVisual.neutral
        case .permissionNeeded:
            SettingsWorkbenchVisual.warning
        case .failed:
            SettingsWorkbenchVisual.danger
        }
    }

    private func launchAtLoginTint(_ state: LaunchAtLoginState) -> Color {
        switch state {
        case .enabled:
            SettingsWorkbenchVisual.success
        case .disabled:
            SettingsWorkbenchVisual.neutral
        case .requiresApproval:
            SettingsWorkbenchVisual.warning
        case .unavailable, .failed:
            SettingsWorkbenchVisual.danger
        }
    }

    private func credentialTint(_ snapshot: TranscriptionCredentialSnapshot) -> Color {
        if snapshot.lastErrorMessage != nil {
            return SettingsWorkbenchVisual.danger
        }
        if snapshot.mode == .apiKey {
            return SettingsWorkbenchVisual.warning
        }

        return snapshot.hasCredential ? SettingsWorkbenchVisual.success : SettingsWorkbenchVisual.neutral
    }

    private func syncSelectedVolcengineCredentialMode() {
        guard let mode = coordinator.transcriptionCredentials.mode else {
            return
        }

        selectedVolcengineCredentialMode = mode
    }

    private func clearTranscriptionInputFields() {
        transcriptionAPIKey = ""
        volcengineAppID = ""
        volcengineAccessToken = ""
    }

    private func legacyInstallTint(_ status: LegacyInstallStatus) -> Color {
        switch status {
        case .notFound:
            SettingsWorkbenchVisual.neutral
        case .detected:
            SettingsWorkbenchVisual.warning
        case .removalFailed:
            SettingsWorkbenchVisual.danger
        }
    }

    private func performOverviewPrimaryAction() {
        let title = coordinator.settingsWorkbenchSnapshot.overview.primaryActionTitle

        if title == PermissionKind.microphone.recoveryActionTitle {
            openSettings(for: .microphone)
        } else if title == PermissionKind.accessibility.recoveryActionTitle {
            openSettings(for: .accessibility)
        } else if title == "前往设置" ||
            title.contains("输入") {
            selectedSection = .settings
        } else if title == "前往模型" ||
            title.contains("模型") ||
            title.contains("Keychain") {
            selectedSection = .model
        } else if title == "重新检查" {
            coordinator.prepareForSettingsPresentation()
            settingsFeedbackMessage = "已重新检查状态。"
        } else {
            startTestRecordingFromSettings()
        }
    }

    private func startTestRecordingFromSettings() {
        if coordinator.snapshot.isRecordingActionEnabled || coordinator.isRecording {
            settingsFeedbackMessage = nil
            coordinator.toggleRecordingFromMenu()
            return
        }

        if !coordinator.permissionSummary.allRequiredGranted {
            selectedSection = .settings
            settingsFeedbackMessage = "请先处理权限后再测试录音。"
            return
        }

        settingsFeedbackMessage = "当前状态不能开始录音：\(coordinator.snapshot.title)"
    }

    private var selectedHotkeyPresetBinding: Binding<HotkeyPreset> {
        Binding(
            get: {
                HotkeyPreset.matching(coordinator.hotkeyBinding) ?? .rightCommand
            },
            set: { preset in
                coordinator.setHotkeyPreset(preset)
                settingsFeedbackMessage = "快捷键已切换为 \(preset.title)。"
            }
        )
    }

    private var selectedHotkeyModeBinding: Binding<HotkeyMode> {
        Binding(
            get: {
                coordinator.hotkeyMode
            },
            set: { mode in
                coordinator.setHotkeyMode(mode)
                settingsFeedbackMessage = "录音模式已切换为 \(mode.title)。"
            }
        )
    }

    private var selectedAudioInputDeviceBinding: Binding<AudioInputDeviceSelection> {
        Binding(
            get: {
                coordinator.selectedAudioInputDevice
            },
            set: { device in
                coordinator.setAudioInputDevice(device)
                settingsFeedbackMessage = "输入设备已切换为 \(device.title)。"
            }
        )
    }

    private var audioInputDevicesForPicker: [AudioInputDeviceSelection] {
        let devices = coordinator.availableAudioInputDevices
        if devices.contains(coordinator.selectedAudioInputDevice) {
            return devices
        }

        return devices + [coordinator.selectedAudioInputDevice]
    }

    private func openSoundInputSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension?Input",
            "x-apple.systempreferences:com.apple.preference.sound?Input"
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }

        coordinator.fail("无法打开 macOS 声音输入设置")
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

private enum SettingsWorkbenchVisual {
    static let primaryText = rgb(0x16, 0x17, 0x16)
    static let secondaryText = rgb(0x66, 0x6a, 0x64)
    static let tertiaryText = rgb(0x8a, 0x8e, 0x87)
    static let accent = rgb(0x21, 0xb6, 0x6f)
    static let success = accent
    static let warning = rgb(0xb7, 0x79, 0x1f)
    static let danger = rgb(0xc7, 0x35, 0x2e)
    static let neutral = tertiaryText
    static let blue = rgb(0x2c, 0x6d, 0xd2)
    static let accentInk = rgb(0x05, 0x39, 0x1f)
    static let accentSoft = rgb(0xdf, 0xf7, 0xeb)
    static let warningSoft = rgb(0xff, 0xf0, 0xd1)
    static let dangerSoft = rgb(0xff, 0xe2, 0xdf)
    static let blueSoft = rgb(0xe4, 0xee, 0xfc)
    static let border = primaryText.opacity(0.11)
    static let subtleBorder = primaryText.opacity(0.11)
    static let strongBorder = primaryText.opacity(0.18)
    static let controlBorder = primaryText
    static let pageBackground = rgb(0xec, 0xeb, 0xea)
    static let windowBackground = rgb(0xf8, 0xf8, 0xf6)
    static let detailBackground = windowBackground
    static let sidebarBackground = rgb(0xef, 0xef, 0xec)
    static let panelBackground = Color.white
    static let smallCardBackground = rgb(0xf1, 0xf1, 0xee)
    static let softPreviewBackground = rgb(0xf6, 0xf6, 0xf3)
    static let buttonBackground = Color.white.opacity(0.72)
    static let selectedRowBackground = Color.white.opacity(0.82)

    static let eyebrowFont = SettingsWorkbenchTypography.body(size: 11, weight: .heavy)
    static let pageTitleFont = SettingsWorkbenchTypography.body(size: 30, weight: .bold)
    static let overviewTitleFont = SettingsWorkbenchTypography.body(size: 24, weight: .bold)
    static let sidebarTitleFont = SettingsWorkbenchTypography.body(size: 23, weight: .bold)
    static let bodyFont = SettingsWorkbenchTypography.body(size: 14)
    static let controlFont = SettingsWorkbenchTypography.body(size: 13, weight: .semibold)
    static let panelTitleFont = SettingsWorkbenchTypography.body(size: 17, weight: .bold)
    static let sectionTitleFont = SettingsWorkbenchTypography.body(size: 15, weight: .bold)
    static let cardTitleFont = SettingsWorkbenchTypography.body(size: 13, weight: .bold)
    static let captionFont = SettingsWorkbenchTypography.body(size: 12)
    static let captionSemiboldFont = SettingsWorkbenchTypography.body(size: 12, weight: .semibold)
    static let captionBoldFont = SettingsWorkbenchTypography.body(size: 12, weight: .bold)
    static let caption2Font = SettingsWorkbenchTypography.body(size: 11)
    static let caption2SemiboldFont = SettingsWorkbenchTypography.body(size: 11, weight: .semibold)
    static let caption2BoldFont = SettingsWorkbenchTypography.body(size: 11, weight: .bold)
    static let tinyBoldFont = SettingsWorkbenchTypography.body(size: 10, weight: .bold)
    static let monoSymbolFont = SettingsWorkbenchTypography.mono(size: 11, weight: .semibold)
    static let monoBadgeFont = SettingsWorkbenchTypography.mono(size: 13, weight: .semibold)

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}

private extension View {
    func workbenchPanel(cornerRadius: CGFloat = 14) -> some View {
        background(
            SettingsWorkbenchVisual.panelBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.border, lineWidth: 1)
            )
    }

    func workbenchCredentialField() -> some View {
        textFieldStyle(.plain)
            .font(SettingsWorkbenchVisual.bodyFont)
            .foregroundStyle(SettingsWorkbenchVisual.primaryText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                SettingsWorkbenchVisual.panelBackground,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.strongBorder, lineWidth: 1)
            )
    }
}

private extension SettingsWorkbenchSectionStatus {
    var workbenchColor: Color {
        switch self {
        case .ok:
            SettingsWorkbenchVisual.success
        case .needsAttention:
            SettingsWorkbenchVisual.danger
        case .warning:
            SettingsWorkbenchVisual.warning
        case .neutral:
            SettingsWorkbenchVisual.neutral
        }
    }

    var workbenchTitle: String {
        switch self {
        case .ok:
            "正常"
        case .needsAttention:
            "阻塞"
        case .warning:
            "注意"
        case .neutral:
            "等待"
        }
    }
}

private extension VolcengineCredentialMode {
    var fieldLabel: String {
        switch self {
        case .apiKey:
            "新网关 API Key"
        case .appIDAccessToken:
            "火山引擎 App ID + Access Token"
        }
    }

    var endpointDetail: String {
        switch self {
        case .apiKey:
            volcengineRealtimeGatewayEndpoint
        case .appIDAccessToken:
            volcengineDefaultEndpoint
        }
    }

    var routingParameterTitle: String {
        switch self {
        case .apiKey:
            "Model"
        case .appIDAccessToken:
            "Resource ID"
        }
    }

    var routingParameterDetail: String {
        switch self {
        case .apiKey:
            volcengineRealtimeGatewayModel
        case .appIDAccessToken:
            "\(volcengineDefaultResourceID) / \(volcengineLegacyOpenSpeechResourceID)"
        }
    }

    var routingParameterBadgeTitle: String {
        switch self {
        case .apiKey:
            "固定"
        case .appIDAccessToken:
            "自动重试"
        }
    }

    var authHeaderDetail: String {
        switch self {
        case .apiKey:
            "Authorization: Bearer"
        case .appIDAccessToken:
            "X-Api-App-Key + X-Api-Access-Key"
        }
    }
}

private struct SettingsWorkbenchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsWorkbenchVisual.captionSemiboldFont)
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.58))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                SettingsWorkbenchVisual.primaryText.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.36),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsWorkbenchSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsWorkbenchVisual.captionSemiboldFont)
            .foregroundStyle(isEnabled ? SettingsWorkbenchVisual.primaryText : SettingsWorkbenchVisual.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                SettingsWorkbenchVisual.buttonBackground
                    .opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkbenchMenuControl<MenuContent: View>: View {
    let title: String
    let width: CGFloat
    private let menuContent: MenuContent

    init(
        title: String,
        width: CGFloat,
        @ViewBuilder content: () -> MenuContent
    ) {
        self.title = title
        self.width = width
        self.menuContent = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(SettingsWorkbenchVisual.panelBackground)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.controlBorder, lineWidth: 2)

            Menu {
                menuContent
            } label: {
                WorkbenchMenuControlLabel(title: title)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }
        .frame(width: width, height: 38)
        .shadow(color: SettingsWorkbenchVisual.primaryText.opacity(0.14), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct WorkbenchMenuControlLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Image(systemName: "chevron.up.chevron.down")
                .font(SettingsWorkbenchVisual.tinyBoldFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkbenchMenuItemLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSelected {
                Image(systemName: "checkmark")
                    .frame(width: 12)
            } else {
                Color.clear
                    .frame(width: 12, height: 1)
            }

            Text(title)
        }
    }
}

private struct WorkbenchSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let selected: Option
    let width: CGFloat
    let title: (Option) -> String
    let action: (Option) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option == selected

                Button {
                    action(option)
                } label: {
                    Text(title(option))
                        .font(SettingsWorkbenchVisual.captionSemiboldFont)
                        .foregroundStyle(isSelected ? Color.white : SettingsWorkbenchVisual.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .padding(.horizontal, 8)
                        .background(
                            isSelected ? SettingsWorkbenchVisual.primaryText : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(width: width)
        .frame(minHeight: 34)
        .background(
            SettingsWorkbenchVisual.smallCardBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.strongBorder, lineWidth: 1)
        )
    }
}

private struct WorkbenchStatusPill: View {
    let title: String
    let systemImage: String?
    let color: Color

    init(_ title: String, systemImage: String? = nil, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(SettingsWorkbenchVisual.tinyBoldFont)
            }

            Text(title)
                .font(SettingsWorkbenchVisual.caption2BoldFont)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 1))
    }
}

private struct WorkbenchFieldBlock<Content: View>: View {
    let label: String
    private let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            SettingsWorkbenchVisual.smallCardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }
}

private struct WorkbenchReadout: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsWorkbenchVisual.cardTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(SettingsWorkbenchVisual.caption2Font)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WorkbenchSymbolBox: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(SettingsWorkbenchVisual.monoSymbolFont)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct WorkbenchInfoRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let color: Color
    private let accessory: Accessory

    init(
        symbol: String,
        title: String,
        detail: String,
        color: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.color = color
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            WorkbenchSymbolBox(label: symbol, color: color)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsWorkbenchVisual.cardTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            accessory
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            SettingsWorkbenchVisual.smallCardBackground,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }
}

private struct VoiceInputSettingRow<Accessory: View>: View {
    let label: String
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    private let accessory: Accessory

    init(
        label: String,
        title: String,
        detail: String,
        systemImage: String,
        color: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.color = color
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(SettingsWorkbenchVisual.caption2BoldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                Text(title)
                    .font(SettingsWorkbenchVisual.cardTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(SettingsWorkbenchVisual.caption2Font)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            accessory
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(
            SettingsWorkbenchVisual.smallCardBackground,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }
}

private struct SettingsOverviewRecoveryCard: View {
    let snapshot: SettingsWorkbenchSnapshot
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                statusContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                VoiceInputFlowPreview()
                    .frame(width: 310)
            }

            VStack(alignment: .leading, spacing: 18) {
                statusContent
                VoiceInputFlowPreview()
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    statusColor.opacity(0.09),
                    SettingsWorkbenchVisual.panelBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(statusColor.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 22, y: 12)
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            WorkbenchStatusPill(statusLabel, systemImage: statusSystemImage, color: statusColor)

            Text(snapshot.overview.title)
                .font(SettingsWorkbenchVisual.overviewTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(2)

            Text(snapshot.overview.detail)
                .font(SettingsWorkbenchVisual.bodyFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(snapshot.overview.primaryActionTitle, action: primaryAction)
                    .buttonStyle(SettingsWorkbenchPrimaryButtonStyle())

                Button(snapshot.overview.secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }
            .padding(.top, 2)
        }
    }

    private var statusLabel: String {
        switch snapshot.status(for: .overview) {
        case .ok:
            "已就绪"
        case .needsAttention:
            "需要处理 1 项"
        case .warning:
            "需要确认"
        case .neutral:
            "等待检查"
        }
    }

    private var statusSystemImage: String {
        switch snapshot.status(for: .overview) {
        case .ok:
            "checkmark.circle.fill"
        case .needsAttention:
            "exclamationmark.triangle.fill"
        case .warning:
            "exclamationmark.circle.fill"
        case .neutral:
            "circle.fill"
        }
    }

    private var statusColor: Color {
        snapshot.status(for: .overview).workbenchColor
    }
}

private struct VoiceInputFlowPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("语音输入流程")
                        .font(SettingsWorkbenchVisual.captionBoldFont)
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    Text("Right Command -> HUD 胶囊 -> 当前输入框")
                        .font(SettingsWorkbenchVisual.caption2Font)
                        .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                }

                Spacer()

                WorkbenchStatusPill("实时路径", color: SettingsWorkbenchVisual.accent)
            }

            VStack(spacing: 8) {
                flowBox(systemImage: "command", title: "Right Command", detail: "长按开始，松开提交")
                connector
                notchPreview
                connector
                flowBox(systemImage: "text.cursor", title: "当前输入框", detail: "完成后插入前台应用")
            }
        }
        .padding(12)
        .workbenchPanel(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.border, lineWidth: 1)
        )
    }

    private func flowBox(systemImage: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(SettingsWorkbenchVisual.cardTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.accent)
                .frame(width: 30, height: 30)
                .background(SettingsWorkbenchVisual.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SettingsWorkbenchVisual.captionBoldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Text(detail)
                    .font(SettingsWorkbenchVisual.caption2Font)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            SettingsWorkbenchVisual.panelBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }

    private var connector: some View {
        Rectangle()
            .fill(SettingsWorkbenchVisual.strongBorder)
            .frame(width: 1, height: 10)
    }

    private var notchPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("语音输入")
                    .font(SettingsWorkbenchVisual.caption2SemiboldFont)
                    .foregroundStyle(Color.yellow)
                Spacer()
                MiniWaveform()
            }

            Text("第二行实时显示你正在说的内容")
                .font(SettingsWorkbenchVisual.caption2SemiboldFont)
                .foregroundStyle(Color.green)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }
}

private struct MiniWaveform: View {
    private let heights: [CGFloat] = [9, 16, 22, 15, 11, 18, 13]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SettingsWorkbenchVisual.success)
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(height: 24)
    }
}

private struct SettingsWorkbenchSidebar: View {
    @Binding var selectedSection: SettingsWorkbenchSection
    let snapshot: SettingsWorkbenchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VOCAL INPUT")
                    .font(SettingsWorkbenchVisual.eyebrowFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                Text("Voco")
                    .font(SettingsWorkbenchVisual.sidebarTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 52)

            VStack(spacing: 5) {
                ForEach(SettingsWorkbenchSection.allCases) { section in
                    SettingsWorkbenchSidebarRow(
                        section: section,
                        status: snapshot.status(for: section),
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .frame(width: 220)
        .background(SettingsWorkbenchVisual.sidebarBackground)
    }
}

private struct SettingsWorkbenchSidebarRow: View {
    let section: SettingsWorkbenchSection
    let status: SettingsWorkbenchSectionStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.sidebarSystemImage)
                    .font(SettingsWorkbenchVisual.captionSemiboldFont)
                    .foregroundStyle(isSelected ? SettingsWorkbenchVisual.primaryText : SettingsWorkbenchVisual.tertiaryText)
                    .frame(width: 18, height: 18)

                Text(section.title)
                    .font(SettingsWorkbenchVisual.controlFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Circle()
                    .fill(status.workbenchColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isSelected ? SettingsWorkbenchVisual.selectedRowBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? SettingsWorkbenchVisual.subtleBorder : Color.clear, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension SettingsWorkbenchSection {
    var sidebarSystemImage: String {
        switch self {
        case .overview:
            "house"
        case .settings:
            "gearshape"
        case .model:
            "cpu"
        }
    }
}
