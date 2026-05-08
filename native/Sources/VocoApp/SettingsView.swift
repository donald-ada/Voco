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
    @State private var voiceInputSessionPage = 1
    @State private var selectedVoiceInputSession: VoiceInputSessionSnapshot?

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
                    .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
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
        .sheet(item: $selectedVoiceInputSession) { session in
            VoiceInputSessionDetailSheet(session: session)
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
                eyebrow: "HOME",
                title: "主页",
                detail: "查看语音输入是否可用，并浏览最近会话。"
            )

            legacyInstallSection

            SettingsHomeHeroCard(
                snapshot: workbench,
                primaryAction: performOverviewPrimaryAction,
                secondaryAction: {
                    coordinator.prepareForSettingsPresentation()
                    settingsFeedbackMessage = "已重新检查状态。"
                }
            )

            homeMetricsRow

            VoiceInputSessionsPanel(
                sessions: coordinator.recentVoiceInputSessions,
                currentPage: $voiceInputSessionPage,
                selectedSession: $selectedVoiceInputSession
            )
        }
    }

    private var homeMetricsRow: some View {
        let sessions = coordinator.recentVoiceInputSessions
        let todaySessions = sessions.filter { Calendar.current.isDateInToday($0.createdAt) }
        let totalWords = todaySessions.reduce(0) { $0 + $1.wordCount }
        let latestSession = sessions.first

        return HStack(spacing: 12) {
            HomeMetricCard(label: "TODAY", value: "\(todaySessions.count) 次会话")
            HomeMetricCard(label: "WORDS", value: "\(totalWords) 字")
            HomeMetricCard(label: "LAST", value: latestSession?.timeTitle ?? "--")
        }
    }

    private var settingsSection: some View {
        let audio = coordinator.audioSettingsSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "SETTINGS",
                title: "语音输入体验",
                detail: "配置开始录音的按键、触发方式、麦克风输入和 macOS 权限。"
            )

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
                    width: 156,
                    options: Array(HotkeyPreset.allCases),
                    selected: selectedHotkeyPresetBinding.wrappedValue,
                    titleForOption: \.title
                ) { preset in
                    selectedHotkeyPresetBinding.wrappedValue = preset
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
                        width: 168,
                        options: audioInputDevicesForPicker,
                        selected: selectedAudioInputDeviceBinding.wrappedValue,
                        titleForOption: \.title
                    ) { device in
                        selectedAudioInputDeviceBinding.wrappedValue = device
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
                        systemImage: permission.kind.systemImage,
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
                    .pointingHandCursor()
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
                    .pointingHandCursor()
                }

                VoiceInputSettingRow(
                    label: "在 Dock 中显示",
                    title: coordinator.displayInDockEnabled ? "已显示" : "已隐藏",
                    detail: "启用后，Voco 会出现在 Dock 和应用切换器中。",
                    systemImage: coordinator.displayInDockEnabled ? "dock.rectangle" : "dock.rectangle",
                    color: SettingsWorkbenchVisual.neutral
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { coordinator.displayInDockEnabled },
                            set: { enabled in
                                coordinator.setDisplayInDockEnabled(enabled)
                                MacDockPresentationController.apply(displayInDockEnabled: enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .pointingHandCursor()
                }

                VoiceInputSettingRow(
                    label: "保存会话记录",
                    title: coordinator.voiceInputSessionHistoryEnabled ? "已保存" : "不保存",
                    detail: coordinator.voiceInputSessionHistoryEnabled
                        ? "成功录音后写入本机 SQLite，会话列表下次启动仍可查看。"
                        : "关闭后不再写入 SQLite，只保留当前运行中的临时列表。",
                    systemImage: coordinator.voiceInputSessionHistoryEnabled ? "tray.full" : "tray",
                    color: coordinator.voiceInputSessionHistoryEnabled
                        ? SettingsWorkbenchVisual.accent
                        : SettingsWorkbenchVisual.neutral
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { coordinator.voiceInputSessionHistoryEnabled },
                            set: { enabled in
                                coordinator.setVoiceInputSessionHistoryEnabled(enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .pointingHandCursor()
                }

                if coordinator.voiceInputSessionHistoryEnabled {
                    VoiceInputSettingRow(
                        label: "保留策略",
                        title: coordinator.voiceInputSessionRetentionPolicy.title,
                        detail: coordinator.voiceInputSessionRetentionPolicy.detail,
                        systemImage: "clock.arrow.circlepath",
                        color: SettingsWorkbenchVisual.neutral
                    ) {
                        WorkbenchMenuControl(
                            title: coordinator.voiceInputSessionRetentionPolicy.title,
                            width: 132,
                            options: Array(VoiceInputSessionRetentionPolicy.allCases),
                            selected: coordinator.voiceInputSessionRetentionPolicy,
                            titleForOption: \.title
                        ) { policy in
                            coordinator.setVoiceInputSessionRetentionPolicy(policy)
                        }
                    }
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
            SecureField("输入火山引擎 API Key", text: $transcriptionAPIKey)
                .workbenchCredentialField()
        case .appIDAccessToken:
            TextField("输入火山引擎 App ID", text: $volcengineAppID)
                .workbenchCredentialField()

            SecureField("输入火山引擎 Access Token", text: $volcengineAccessToken)
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

        switch SettingsOverviewPrimaryActionResolver.resolve(title: title) {
        case .requestMicrophonePermission:
            Task {
                await coordinator.requestMicrophonePermission()
            }
        case .openAccessibilitySettings:
            openSettings(for: .accessibility)
        case .selectSettings:
            selectedSection = .settings
        case .selectModel:
            selectedSection = .model
        case .refresh:
            coordinator.prepareForSettingsPresentation()
            settingsFeedbackMessage = "已重新检查状态。"
        case .startTestRecording:
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
    static let homeTitleFont = SettingsWorkbenchTypography.body(size: 34, weight: .bold)
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
    static let monoTinyFont = SettingsWorkbenchTypography.mono(size: 11, weight: .medium)
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
            "新控制台 API Key"
        case .appIDAccessToken:
            "火山引擎 App ID + Access Token"
        }
    }

    var endpointDetail: String {
        volcengineDefaultEndpoint
    }

    var routingParameterTitle: String {
        "Resource ID"
    }

    var routingParameterDetail: String {
        "\(volcengineDefaultResourceID) / \(volcengineLegacyOpenSpeechResourceID)"
    }

    var routingParameterBadgeTitle: String {
        "自动重试"
    }

    var authHeaderDetail: String {
        switch self {
        case .apiKey:
            "X-Api-Key"
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
            .pointingHandCursor()
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
            .pointingHandCursor()
    }
}

private struct WorkbenchMenuControl<Option: Identifiable>: View {
    let title: String
    let width: CGFloat
    let options: [Option]
    let selected: Option
    let titleForOption: (Option) -> String
    let onSelect: (Option) -> Void

    init(
        title: String,
        width: CGFloat,
        options: [Option],
        selected: Option,
        titleForOption: @escaping (Option) -> String,
        onSelect: @escaping (Option) -> Void
    ) {
        self.title = title
        self.width = width
        self.options = options
        self.selected = selected
        self.titleForOption = titleForOption
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            WorkbenchMenuControlLabel(title: title)
                .frame(width: width, height: 38)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            WorkbenchPopUpButton(
                options: options,
                selectedID: selected.id,
                titleForOption: titleForOption,
                onSelect: onSelect
            )
            .frame(width: width, height: 38)
        }
        .frame(width: width, height: 38)
        .background(
            SettingsWorkbenchVisual.panelBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.controlBorder, lineWidth: 2)
        )
        .shadow(color: SettingsWorkbenchVisual.primaryText.opacity(0.14), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .pointingHandCursor()
        .accessibilityLabel(Text(title))
    }
}

private struct WorkbenchPopUpButton<Option: Identifiable>: NSViewRepresentable {
    let options: [Option]
    let selectedID: Option.ID
    let titleForOption: (Option) -> String
    let onSelect: (Option) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(options: options, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectOption(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.options = options
        context.coordinator.onSelect = onSelect

        button.removeAllItems()
        options.forEach { option in
            button.addItem(withTitle: titleForOption(option))
        }

        if let selectedIndex = options.firstIndex(where: { $0.id == selectedID }) {
            button.selectItem(at: selectedIndex)
        } else {
            button.selectItem(at: -1)
        }
    }

    final class Coordinator: NSObject {
        var options: [Option]
        var onSelect: (Option) -> Void

        init(options: [Option], onSelect: @escaping (Option) -> Void) {
            self.options = options
            self.onSelect = onSelect
        }

        @MainActor
        @objc
        func selectOption(_ sender: NSPopUpButton) {
            let selectedIndex = sender.indexOfSelectedItem
            guard options.indices.contains(selectedIndex) else {
                return
            }

            onSelect(options[selectedIndex])
        }
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

            Image(systemName: "chevron.down")
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(SettingsWorkbenchVisual.primaryText, in: Circle())
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .pointingHandCursor()
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

private struct WorkbenchIconBox: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(SettingsWorkbenchVisual.captionSemiboldFont)
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct WorkbenchInfoRow<Accessory: View>: View {
    let systemImage: String
    let title: String
    let detail: String
    let color: Color
    private let accessory: Accessory

    init(
        systemImage: String,
        title: String,
        detail: String,
        color: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.color = color
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            WorkbenchIconBox(systemImage: systemImage, color: color)

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

private struct SettingsHomeHeroCard: View {
    let snapshot: SettingsWorkbenchSnapshot
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                statusContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                VoiceInputFlowPreview()
                    .frame(width: 510)
            }

            VStack(alignment: .leading, spacing: 18) {
                statusContent
                VoiceInputFlowPreview()
            }
        }
        .padding(25)
        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(statusColor.opacity(0.20), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 22, y: 12)
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.homeIssueItems.isEmpty ? "Welcome" : "需要解决")
                .font(SettingsWorkbenchVisual.homeTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)

            if snapshot.homeIssueItems.isEmpty {
                Text(snapshot.overview.detail)
                    .font(SettingsWorkbenchVisual.bodyFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.homeIssueItems) { item in
                        HomeIssueRow(item: item, color: statusColor)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(snapshot.overview.primaryActionTitle, action: primaryAction)
                    .buttonStyle(SettingsWorkbenchPrimaryButtonStyle())

                Button(snapshot.overview.secondaryActionTitle, action: secondaryAction)
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }
            .padding(.top, 2)
        }
    }

    private var statusColor: Color {
        snapshot.status(for: .overview).workbenchColor
    }
}

private struct HomeIssueRow: View {
    let item: SettingsWorkbenchIssueItem
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(SettingsWorkbenchVisual.captionSemiboldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Text(item.detail)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(2)
            }
        }
    }
}

private struct HomeMetricCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(SettingsWorkbenchVisual.monoTinyFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            Text(value)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .workbenchPanel(cornerRadius: 18)
    }
}

private struct VoiceInputSessionsPanel: View {
    let sessions: [VoiceInputSessionSnapshot]
    @Binding var currentPage: Int
    @Binding var selectedSession: VoiceInputSessionSnapshot?

    private var sessionPage: VoiceInputSessionPage {
        VoiceInputSessionPage(sessions: sessions, page: currentPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("会话记录")
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Spacer()

                Text("内容预览 / 字数 / 时间 / 时长")
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) {
                Divider()
            }

            if sessionPage.entries.isEmpty {
                emptyState
            } else {
                ForEach(sessionPage.entries) { session in
                    VoiceInputSessionRow(session: session) {
                        selectedSession = session
                    }
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
            }

            paginationFooter
        }
        .workbenchPanel(cornerRadius: 20)
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 10)
        .onChange(of: sessions.count) { _, _ in
            currentPage = VoiceInputSessionPage(sessions: sessions, page: currentPage).page
        }
    }

    private var emptyState: some View {
        Text("暂无会话记录")
            .font(SettingsWorkbenchVisual.bodyFont)
            .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 82)
    }

    private var paginationFooter: some View {
        HStack(spacing: 10) {
            Text(sessionPage.visibleRangeTitle)
                .font(SettingsWorkbenchVisual.monoTinyFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)

            Spacer()

            Button("上一页") {
                currentPage = max(1, sessionPage.page - 1)
            }
            .buttonStyle(SettingsWorkbenchPaginationButtonStyle())
            .disabled(sessionPage.page <= 1)

            ForEach(1...sessionPage.totalPages, id: \.self) { page in
                Button("\(page)") {
                    currentPage = page
                }
                .buttonStyle(SettingsWorkbenchPaginationButtonStyle(isActive: page == sessionPage.page))
                .disabled(page == sessionPage.page)
            }

            Button("下一页") {
                currentPage = min(sessionPage.totalPages, sessionPage.page + 1)
            }
            .buttonStyle(SettingsWorkbenchPaginationButtonStyle())
            .disabled(sessionPage.page >= sessionPage.totalPages)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(SettingsWorkbenchVisual.softPreviewBackground)
    }
}

private struct VoiceInputSessionRow: View {
    let session: VoiceInputSessionSnapshot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                Text(session.previewText(maxLength: 58))
                    .font(SettingsWorkbenchVisual.captionSemiboldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(session.wordCount) 字")
                    .frame(width: 58, alignment: .leading)

                Text(session.timeTitle)
                    .frame(width: 54, alignment: .leading)

                Text(session.durationTitle)
                    .frame(width: 44, alignment: .leading)

                Text("详情")
                    .font(SettingsWorkbenchVisual.caption2BoldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        SettingsWorkbenchVisual.softPreviewBackground,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                    )
            }
            .font(SettingsWorkbenchVisual.caption2Font)
            .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

private struct VoiceInputSessionDetailSheet: View {
    let session: VoiceInputSessionSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("会话详情")
                        .font(SettingsWorkbenchVisual.panelTitleFont)
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                    Text(session.detailTimestampTitle)
                        .font(SettingsWorkbenchVisual.captionFont)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }
            .padding(22)

            Divider()

            HStack(spacing: 8) {
                WorkbenchStatusPill("\(session.wordCount) 字", color: SettingsWorkbenchVisual.neutral)
                WorkbenchStatusPill(session.durationTitle, color: SettingsWorkbenchVisual.neutral)
                if let targetAppName = session.targetAppName {
                    WorkbenchStatusPill(targetAppName, color: SettingsWorkbenchVisual.neutral)
                }
                WorkbenchStatusPill(session.providerName, color: SettingsWorkbenchVisual.neutral)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            ScrollView {
                Text(session.transcriptText)
                    .font(SettingsWorkbenchVisual.bodyFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
        }
        .frame(width: 680, height: 460)
        .background(SettingsWorkbenchVisual.panelBackground)
    }
}

private struct SettingsWorkbenchPaginationButtonStyle: ButtonStyle {
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsWorkbenchVisual.caption2BoldFont)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 11)
            .frame(minWidth: 36, minHeight: 34)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? SettingsWorkbenchVisual.primaryText : SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
            )
            .pointingHandCursor()
    }

    private var foregroundColor: Color {
        if isActive {
            return Color.white
        }

        return isEnabled ? SettingsWorkbenchVisual.primaryText : SettingsWorkbenchVisual.tertiaryText
    }

    private var backgroundColor: Color {
        if isActive {
            return SettingsWorkbenchVisual.primaryText
        }

        return isEnabled ? SettingsWorkbenchVisual.panelBackground : SettingsWorkbenchVisual.smallCardBackground
    }
}

private struct VoiceInputFlowPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("语音输入流程")
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Spacer()

                Text("R Cmd / HUD / Input")
                    .font(SettingsWorkbenchVisual.monoTinyFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                    .lineLimit(1)
            }

            HStack(spacing: 9) {
                flowNode(systemImage: "command")
                flowConnector
                notchPreview
                flowConnector
                flowNode(label: "A|")
            }
        }
        .padding(16)
        .workbenchPanel(cornerRadius: 18)
    }

    private func flowNode(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(SettingsWorkbenchVisual.panelTitleFont)
            .foregroundStyle(SettingsWorkbenchVisual.accent)
            .frame(width: 46, height: 46)
            .background(SettingsWorkbenchVisual.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.accent.opacity(0.16), lineWidth: 1)
            )
    }

    private func flowNode(label: String) -> some View {
        Text(label)
            .font(SettingsWorkbenchVisual.monoBadgeFont)
            .foregroundStyle(SettingsWorkbenchVisual.accent)
            .frame(width: 46, height: 46)
            .background(SettingsWorkbenchVisual.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.accent.opacity(0.16), lineWidth: 1)
            )
    }

    private var flowConnector: some View {
        Rectangle()
            .fill(SettingsWorkbenchVisual.strongBorder)
            .frame(width: 22, height: 1)
    }

    private var notchPreview: some View {
        HStack(spacing: 12) {
            Text("语音输入")
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(SettingsWorkbenchVisual.warning)
                .lineLimit(1)

            Spacer(minLength: 4)

            MiniWaveform()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.black, in: Capsule())
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    }
}

private extension VoiceInputSessionSnapshot {
    var timeTitle: String {
        createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var detailTimestampTitle: String {
        createdAt.formatted(date: .numeric, time: .shortened)
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
        .pointingHandCursor()
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
