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
    @State private var selectedStatisticsPeriod: VoiceInputSessionStatisticsPeriod = .last7Days
    @State private var selectedStatisticsMetric: VoiceInputSessionStatisticsMetric = .words
    @State private var selectedStatisticsAppName = VoiceInputSessionStatisticsDashboardSnapshot.allAppsTitle
    @State private var statisticsDashboardSnapshot = VoiceInputSessionStatisticsDashboardSnapshot.empty(period: .last7Days)

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
        .onChange(of: selectedSection) { _, section in
            if section == .statistics {
                refreshStatisticsDashboardSnapshot()
            }
        }
        .onChange(of: selectedStatisticsPeriod) { _, _ in
            refreshStatisticsDashboardSnapshot()
        }
        .onChange(of: selectedStatisticsAppName) { _, _ in
            refreshStatisticsDashboardSnapshot()
        }
        .onChange(of: coordinator.recentVoiceInputSessions) { _, _ in
            if selectedSection == .statistics {
                refreshStatisticsDashboardSnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshLegacyInstall()
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
            syncSelectedVolcengineCredentialMode()
            if selectedSection == .statistics {
                refreshStatisticsDashboardSnapshot()
            }
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
        case .model:
            modelWorkbenchSection
        case .statistics:
            statisticsSection
        case .settings:
            settingsSection
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

    private var statisticsSection: some View {
        let dashboard = statisticsDashboardSnapshot
        let baseSnapshot = dashboard.baseSnapshot
        let snapshot = dashboard.scopedSnapshot
        let appOptions = dashboard.appOptions
        let selectedApp = dashboard.selectedAppName
        let layoutPolicy = StatisticsDashboardLayoutPolicy.resizeOptimized

        return LazyVStack(alignment: .leading, spacing: layoutPolicy.verticalSpacing) {
            settingsPageHeader(
                eyebrow: "STATISTICS",
                title: "统计",
                detail: "查看语音输入使用趋势、应用分布和活跃时段。"
            ) {
                WorkbenchSegmentedControl(
                    options: VoiceInputSessionStatisticsPeriod.allCases,
                    selected: selectedStatisticsPeriod,
                    width: 248,
                    title: \.title
                ) { period in
                    selectedStatisticsPeriod = period
                }
            }

            StatisticsAppFilter(
                options: appOptions,
                selectedApp: selectedApp
            ) { app in
                selectedStatisticsAppName = app
            }

            StatisticsMetricSummaryRow(
                snapshot: snapshot,
                selectedApp: selectedApp
            )

            StatisticsDashboardColumnsView(
                layoutPolicy: layoutPolicy,
                snapshot: snapshot,
                baseSnapshot: baseSnapshot,
                period: selectedStatisticsPeriod,
                metric: selectedStatisticsMetric,
                selectedApp: selectedApp
            ) { metric in
                selectedStatisticsMetric = metric
            } onSelectApp: { app in
                selectedStatisticsAppName = app
            }
        }
    }

    private func refreshStatisticsDashboardSnapshot() {
        statisticsDashboardSnapshot = VoiceInputSessionStatisticsDashboardSnapshot.make(
            sessions: coordinator.recentVoiceInputSessions,
            period: selectedStatisticsPeriod,
            selectedAppName: selectedStatisticsAppName
        )
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
        let actionID = coordinator.settingsWorkbenchSnapshot.overview.primaryActionID

        switch SettingsOverviewPrimaryActionResolver.resolve(actionID: actionID) {
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
        case .unknown:
            coordinator.fail("Unknown settings action: \(actionID)")
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
                Button(snapshot.overview.primaryActionDisplayTitle, action: primaryAction)
                    .buttonStyle(SettingsWorkbenchPrimaryButtonStyle())

                Button(snapshot.overview.secondaryActionDisplayTitle, action: secondaryAction)
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

private struct StatisticsAppFilter: View {
    let options: [String]
    let selectedApp: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("目标 App")
                .font(SettingsWorkbenchVisual.monoTinyFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                .lineLimit(1)

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = option == selectedApp

                        Button {
                            onSelect(option)
                        } label: {
                            Text(option)
                                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                                .foregroundStyle(isSelected ? Color.white : SettingsWorkbenchVisual.primaryText)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(
                                    isSelected ? SettingsWorkbenchVisual.primaryText : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SettingsWorkbenchVisual.softPreviewBackground,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .workbenchPanel(cornerRadius: 16)
    }
}

private struct StatisticsMetricSummaryRow: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let selectedApp: String

    var body: some View {
        HStack(spacing: 12) {
            StatisticsMetricCard(
                label: "TOTAL",
                value: "\(snapshot.totalSessions) 次",
                note: "\(StatisticsFormat.integer(snapshot.totalWords)) 字"
            )
            StatisticsMetricCard(
                label: "EFFICIENCY",
                value: "\(snapshot.wordsPerMinute) 字/分",
                note: "字数 / 时长"
            )
            StatisticsMetricCard(
                label: "APPS",
                value: "\(snapshot.activeAppCount) 个",
                note: selectedApp == VoiceInputSessionStatisticsDashboardSnapshot.allAppsTitle ? "应用去重" : "当前筛选"
            )
            StatisticsMetricCard(
                label: "AVG TIME",
                value: StatisticsFormat.duration(snapshot.averageDurationSeconds),
                note: "平均时长"
            )
        }
    }
}

private struct StatisticsMetricCard: View {
    let label: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(SettingsWorkbenchVisual.monoTinyFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                .lineLimit(1)

            Text(value)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(note)
                .font(SettingsWorkbenchVisual.captionFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .workbenchPanel(cornerRadius: 18)
    }
}

private struct StatisticsDashboardColumnsView: View {
    let layoutPolicy: StatisticsDashboardLayoutPolicy
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let baseSnapshot: VoiceInputSessionStatisticsSnapshot
    let period: VoiceInputSessionStatisticsPeriod
    let metric: VoiceInputSessionStatisticsMetric
    let selectedApp: String
    let onSelectMetric: (VoiceInputSessionStatisticsMetric) -> Void
    let onSelectApp: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: layoutPolicy.horizontalSpacing) {
            LazyVStack(spacing: layoutPolicy.verticalSpacing) {
                ForEach(layoutPolicy.leadingPanels) { panel in
                    StatisticsDashboardLeadingPanelView(
                        panel: panel,
                        layoutPolicy: layoutPolicy,
                        snapshot: snapshot,
                        baseSnapshot: baseSnapshot,
                        period: period,
                        metric: metric,
                        selectedApp: selectedApp,
                        onSelectMetric: onSelectMetric,
                        onSelectApp: onSelectApp
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            LazyVStack(spacing: layoutPolicy.verticalSpacing) {
                ForEach(layoutPolicy.trailingPanels) { panel in
                    StatisticsDashboardTrailingPanelView(
                        panel: panel,
                        snapshot: snapshot,
                        period: period,
                        selectedApp: selectedApp
                    )
                }
            }
            .frame(width: layoutPolicy.trailingColumnWidth, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StatisticsDashboardLeadingPanelView: View {
    let panel: StatisticsDashboardPanel
    let layoutPolicy: StatisticsDashboardLayoutPolicy
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let baseSnapshot: VoiceInputSessionStatisticsSnapshot
    let period: VoiceInputSessionStatisticsPeriod
    let metric: VoiceInputSessionStatisticsMetric
    let selectedApp: String
    let onSelectMetric: (VoiceInputSessionStatisticsMetric) -> Void
    let onSelectApp: (String) -> Void

    var body: some View {
        switch panel {
        case .trend:
            StatisticsTrendPanel(
                snapshot: snapshot,
                metric: metric,
                onSelectMetric: onSelectMetric
            )
        case .heatmapAndLengthDistribution:
            StatisticsHeatmapAndLengthDistributionRow(
                snapshot: snapshot,
                period: period,
                layoutPolicy: layoutPolicy
            )
        case .appContribution:
            StatisticsAppContributionPanel(
                contributions: baseSnapshot.appContributions,
                metric: metric,
                selectedApp: selectedApp,
                onSelectApp: onSelectApp
            )
        case .insight, .hourRange, .provider, .rhythm:
            EmptyView()
        }
    }
}

private struct StatisticsDashboardTrailingPanelView: View {
    let panel: StatisticsDashboardPanel
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let period: VoiceInputSessionStatisticsPeriod
    let selectedApp: String

    var body: some View {
        switch panel {
        case .insight:
            StatisticsInsightPanel(
                snapshot: snapshot,
                selectedApp: selectedApp,
                period: period
            )
        case .hourRange:
            StatisticsHourRangePanel(snapshot: snapshot)
        case .provider:
            StatisticsProviderPanel(snapshot: snapshot)
        case .rhythm:
            StatisticsRhythmPanel(snapshot: snapshot)
        case .trend, .heatmapAndLengthDistribution, .appContribution:
            EmptyView()
        }
    }
}

private struct StatisticsPanel<Accessory: View, Content: View>: View {
    let title: String
    private let accessory: Accessory
    private let content: Content

    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                accessory
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .workbenchPanel(cornerRadius: 18)
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 10)
    }
}

private extension StatisticsPanel where Accessory == EmptyView {
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title) {
            EmptyView()
        } content: {
            content()
        }
    }
}

private struct StatisticsCompactPanel<Content: View>: View {
    let title: String
    let minHeight: CGFloat?
    private let content: Content

    init(
        title: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .workbenchPanel(cornerRadius: 18)
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 8)
    }
}

private struct StatisticsTrendPanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let metric: VoiceInputSessionStatisticsMetric
    let onSelectMetric: (VoiceInputSessionStatisticsMetric) -> Void

    var body: some View {
        StatisticsPanel(title: "\(metric.title)趋势") {
            WorkbenchSegmentedControl(
                options: VoiceInputSessionStatisticsMetric.allCases,
                selected: metric,
                width: 178,
                title: \.title,
                action: onSelectMetric
            )
        } content: {
            StatisticsTrendChart(
                points: snapshot.dailyPoints,
                metric: metric
            )
            .frame(height: 238)
        }
    }
}

private struct StatisticsTrendChart: View {
    let points: [VoiceInputSessionStatisticsDailyPoint]
    let metric: VoiceInputSessionStatisticsMetric

    private var maxValue: Double {
        max(1, points.map { metric.value(in: $0) }.max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let count = max(points.count, 1)
                let spacing: CGFloat = 8
                let availableWidth = max(0, size.width - spacing * CGFloat(count - 1))
                let slotWidth = availableWidth / CGFloat(count)
                let barWidth = min(24, max(3, slotWidth * 0.54))

                for (index, point) in points.enumerated() {
                    let value = metric.value(in: point)
                    let ratio = value / maxValue
                    let barHeight = value > 0
                        ? max(5, size.height * CGFloat(ratio))
                        : 2
                    let x = CGFloat(index) * (slotWidth + spacing) + (slotWidth - barWidth) / 2
                    let rect = CGRect(
                        x: x,
                        y: size.height - barHeight,
                        width: barWidth,
                        height: barHeight
                    )
                    let path = Path(
                        roundedRect: rect,
                        cornerSize: CGSize(width: 4, height: 4)
                    )
                    context.fill(
                        path,
                        with: .color(value > 0 ? metric.chartColor : SettingsWorkbenchVisual.smallCardBackground)
                    )
                }
            }
            .frame(height: 206)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SettingsWorkbenchVisual.strongBorder)
                    .frame(height: 1)
            }

            HStack(spacing: 8) {
                ForEach(points) { point in
                    Text(point.label)
                        .font(SettingsWorkbenchVisual.monoTinyFont)
                        .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 16)
        }
    }
}

private struct StatisticsHeatmapAndLengthDistributionRow: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let period: VoiceInputSessionStatisticsPeriod
    let layoutPolicy: StatisticsDashboardLayoutPolicy

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: layoutPolicy.horizontalSpacing) {
                heatmapPanel(minHeight: layoutPolicy.compactCombinedPanelHorizontalHeight)
                    .frame(minWidth: layoutPolicy.compactCombinedPanelMinimumWidth, maxWidth: .infinity)
                    .layoutPriority(1)

                lengthDistributionPanel(minHeight: layoutPolicy.compactCombinedPanelHorizontalHeight)
                    .frame(minWidth: layoutPolicy.compactCombinedPanelMinimumWidth, maxWidth: .infinity)
            }

            VStack(spacing: layoutPolicy.verticalSpacing) {
                heatmapPanel()
                lengthDistributionPanel()
            }
        }
    }

    private func heatmapPanel(minHeight: CGFloat? = nil) -> some View {
        StatisticsCompactPanel(
            title: period == .last7Days ? "周内热力" : "使用节律",
            minHeight: minHeight
        ) {
            StatisticsHeatmapView(
                rows: snapshot.heatmapRows,
                cellHeight: layoutPolicy.compactHeatmapCellHeight,
                rowSpacing: 4,
                columnSpacing: 5,
                labelWidth: 30,
                cellCornerRadius: 6
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func lengthDistributionPanel(minHeight: CGFloat? = nil) -> some View {
        StatisticsCompactPanel(
            title: "输入长度分布",
            minHeight: minHeight
        ) {
            StatisticsCompactLengthDistributionView(
                snapshot: snapshot,
                donutSize: layoutPolicy.compactLengthDonutSize
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatisticsHeatmapPanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let period: VoiceInputSessionStatisticsPeriod

    var body: some View {
        StatisticsPanel(title: period == .last7Days ? "周内热力" : "使用节律") {
            StatisticsHeatmapView(rows: snapshot.heatmapRows)
        }
    }
}

private struct StatisticsHeatmapView: View {
    let rows: [VoiceInputSessionStatisticsHeatmapRow]
    let cellHeight: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let labelWidth: CGFloat
    let cellCornerRadius: CGFloat

    init(
        rows: [VoiceInputSessionStatisticsHeatmapRow],
        cellHeight: CGFloat = 28,
        rowSpacing: CGFloat = 6,
        columnSpacing: CGFloat = 6,
        labelWidth: CGFloat = 38,
        cellCornerRadius: CGFloat = 8
    ) {
        self.rows = rows
        self.cellHeight = cellHeight
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.labelWidth = labelWidth
        self.cellCornerRadius = cellCornerRadius
    }

    private var maxSessions: Int {
        max(1, rows.flatMap(\.cells).map(\.sessions).max() ?? 0)
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            if let firstRow = rows.first {
                HStack(spacing: columnSpacing) {
                    Color.clear
                        .frame(width: labelWidth)

                    ForEach(firstRow.cells) { cell in
                        Text(cell.hourRangeLabel)
                            .font(SettingsWorkbenchVisual.monoTinyFont)
                            .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            ForEach(rows) { row in
                HStack(spacing: columnSpacing) {
                    Text(row.weekdayTitle)
                        .font(SettingsWorkbenchVisual.monoTinyFont)
                        .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)

                    ForEach(row.cells) { cell in
                        RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                            .fill(cellColor(cell))
                            .overlay(
                                RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight)
                    }
                }
            }
        }
    }

    private func cellColor(_ cell: VoiceInputSessionStatisticsHeatmapCell) -> Color {
        guard cell.sessions > 0 else {
            return SettingsWorkbenchVisual.smallCardBackground
        }

        let opacity = 0.18 + 0.64 * (Double(cell.sessions) / Double(maxSessions))
        return SettingsWorkbenchVisual.accent.opacity(opacity)
    }
}

private struct StatisticsCompactLengthDistributionView: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let donutSize: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StatisticsLengthDonutChart(
                buckets: snapshot.lengthBuckets,
                size: donutSize,
                lineWidth: 18,
                centerSize: 50
            )

            StatisticsLengthLegend(
                buckets: snapshot.lengthBuckets,
                isCompact: true
            )
        }
        .frame(maxWidth: .infinity, minHeight: 154)
    }
}

private struct StatisticsLengthDistributionPanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot

    var body: some View {
        StatisticsPanel(title: "输入长度分布") {
            HStack(alignment: .center, spacing: 18) {
                StatisticsLengthDonutChart(buckets: snapshot.lengthBuckets)
                StatisticsLengthLegend(buckets: snapshot.lengthBuckets)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StatisticsLengthDonutChart: View {
    let buckets: [VoiceInputSessionStatisticsLengthBucket]
    let size: CGFloat
    let lineWidth: CGFloat
    let centerSize: CGFloat

    init(
        buckets: [VoiceInputSessionStatisticsLengthBucket],
        size: CGFloat = 132,
        lineWidth: CGFloat = 26,
        centerSize: CGFloat = 68
    ) {
        self.buckets = buckets
        self.size = size
        self.lineWidth = lineWidth
        self.centerSize = centerSize
    }

    private var total: Int {
        buckets.reduce(0) { $0 + $1.sessions }
    }

    private var segments: [StatisticsDonutSegment] {
        guard total > 0 else {
            return []
        }

        var cursor = 0.0
        return buckets.enumerated().compactMap { index, bucket in
            guard bucket.sessions > 0 else {
                return nil
            }

            let start = cursor
            cursor += Double(bucket.sessions) / Double(total)
            return StatisticsDonutSegment(
                id: bucket.id,
                start: start,
                end: cursor,
                color: StatisticsLengthColor.color(for: index)
            )
        }
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = max(1, (min(size.width, size.height) - lineWidth) / 2)
                let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)

                if total == 0 {
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(SettingsWorkbenchVisual.smallCardBackground),
                        style: strokeStyle
                    )
                } else {
                    for segment in segments {
                        var path = Path()
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(segment.start * 360 - 90),
                            endAngle: .degrees(segment.end * 360 - 90),
                            clockwise: false
                        )
                        context.stroke(path, with: .color(segment.color), style: strokeStyle)
                    }
                }
            }

            Circle()
                .fill(SettingsWorkbenchVisual.panelBackground)
                .frame(width: centerSize, height: centerSize)
                .overlay(
                    Circle()
                        .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                )

            Text("\(total) 次")
                .font(SettingsWorkbenchVisual.monoBadgeFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: size, height: size)
    }
}

private struct StatisticsDonutSegment: Identifiable {
    let id: String
    let start: Double
    let end: Double
    let color: Color
}

private struct StatisticsLengthLegend: View {
    let buckets: [VoiceInputSessionStatisticsLengthBucket]
    var isCompact = false

    private var total: Int {
        buckets.reduce(0) { $0 + $1.sessions }
    }

    var body: some View {
        VStack(spacing: isCompact ? 7 : 9) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                let percent = total > 0
                    ? Int((Double(bucket.sessions) / Double(total) * 100).rounded())
                    : 0

                HStack(spacing: isCompact ? 7 : 9) {
                    Circle()
                        .fill(StatisticsLengthColor.color(for: index))
                        .frame(width: isCompact ? 8 : 10, height: isCompact ? 8 : 10)

                    VStack(alignment: .leading, spacing: isCompact ? 1 : 2) {
                        Text(bucket.title)
                            .font(SettingsWorkbenchVisual.captionBoldFont)
                            .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                            .lineLimit(1)

                        Text(bucket.detail)
                            .font(SettingsWorkbenchVisual.captionFont)
                            .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(percent)% · \(bucket.sessions)")
                        .font(SettingsWorkbenchVisual.monoTinyFont)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private enum StatisticsLengthColor {
    static func color(for index: Int) -> Color {
        switch index {
        case 0:
            SettingsWorkbenchVisual.accent
        case 1:
            SettingsWorkbenchVisual.blue
        default:
            SettingsWorkbenchVisual.warning
        }
    }
}

private struct StatisticsAppContributionPanel: View {
    let contributions: [VoiceInputSessionStatisticsContribution]
    let metric: VoiceInputSessionStatisticsMetric
    let selectedApp: String
    let onSelectApp: (String) -> Void

    var body: some View {
        StatisticsPanel(title: "应用贡献") {
            StatisticsContributionBarList(
                contributions: contributions,
                metric: metric,
                selectedName: selectedApp == VoiceInputSessionStatisticsDashboardSnapshot.allAppsTitle ? nil : selectedApp,
                color: SettingsWorkbenchVisual.accent,
                onSelect: onSelectApp
            )
        }
    }
}

private struct StatisticsHourRangePanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot

    var body: some View {
        StatisticsPanel(title: "活跃时段") {
            let hourRanges = Array(snapshot.hourRanges.sorted { lhs, rhs in
                if lhs.sessions != rhs.sessions {
                    return lhs.sessions > rhs.sessions
                }
                return lhs.startHour < rhs.startHour
            }.prefix(4))

            StatisticsHourRangeBarList(hourRanges: hourRanges)
        }
    }
}

private struct StatisticsProviderPanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot

    var body: some View {
        StatisticsPanel(title: "模型来源") {
            StatisticsContributionBarList(
                contributions: Array(snapshot.providerContributions.prefix(4)),
                metric: .sessions,
                selectedName: nil,
                color: SettingsWorkbenchVisual.blue,
                onSelect: nil
            )
        }
    }
}

private struct StatisticsRhythmPanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot

    var body: some View {
        StatisticsPanel(title: "使用节奏") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                StatisticsDetailCard(
                    value: "\(snapshot.rhythm.activeDayCount)",
                    label: "活跃天数"
                )
                StatisticsDetailCard(
                    value: snapshot.rhythm.busiestDayTitle,
                    label: "最高单日"
                )
                StatisticsDetailCard(
                    value: "\(snapshot.rhythm.peakHourSharePercent)%",
                    label: "高峰占比"
                )
                StatisticsDetailCard(
                    value: "\(snapshot.rhythm.appConcentrationPercent)%",
                    label: "应用集中度"
                )
            }
        }
    }
}

private struct StatisticsInsightPanel: View {
    let snapshot: VoiceInputSessionStatisticsSnapshot
    let selectedApp: String
    let period: VoiceInputSessionStatisticsPeriod

    private var topHour: VoiceInputSessionStatisticsHourRange? {
        snapshot.hourRanges.sorted { lhs, rhs in
            if lhs.sessions != rhs.sessions {
                return lhs.sessions > rhs.sessions
            }
            return lhs.startHour < rhs.startHour
        }
        .first
    }

    var body: some View {
        StatisticsPanel(title: "本期观察") {
            WorkbenchStatusPill(
                selectedApp == VoiceInputSessionStatisticsDashboardSnapshot.allAppsTitle ? period.title : selectedApp,
                color: SettingsWorkbenchVisual.neutral
            )
        } content: {
            VStack(spacing: 0) {
                StatisticsInsightRow(
                    value: snapshot.appContributions.first?.name ?? "--",
                    label: selectedApp == VoiceInputSessionStatisticsDashboardSnapshot.allAppsTitle ? "最常用目标应用" : "当前目标应用",
                    badge: "\(snapshot.appContributions.first?.words ?? 0) 字"
                )
                StatisticsInsightRow(
                    value: topHour?.label ?? "--",
                    label: "最高频时段",
                    badge: "\(topHour?.sessions ?? 0) 次"
                )
                StatisticsInsightRow(
                    value: snapshot.providerContributions.first?.name ?? "--",
                    label: "主要模型来源",
                    badge: "\(snapshot.providerContributions.first?.sessions ?? 0) 次"
                )
            }
        }
    }
}

private struct StatisticsInsightRow: View {
    let value: String
    let label: String
    let badge: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(label)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            WorkbenchStatusPill(badge, color: SettingsWorkbenchVisual.neutral)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct StatisticsContributionBarList: View {
    let contributions: [VoiceInputSessionStatisticsContribution]
    let metric: VoiceInputSessionStatisticsMetric
    let selectedName: String?
    let color: Color
    let onSelect: ((String) -> Void)?
    private let barTrackWidth = StatisticsDashboardLayoutPolicy.resizeOptimized.barTrackWidth

    private var maxValue: Double {
        max(1, contributions.map { metric.value(in: $0) }.max() ?? 0)
    }

    var body: some View {
        if contributions.isEmpty {
            StatisticsEmptyText()
        } else {
            VStack(spacing: 12) {
                ForEach(Array(contributions.prefix(6))) { contribution in
                    let isSelected = contribution.name == selectedName
                    if let onSelect {
                        Button {
                            onSelect(contribution.name)
                        } label: {
                            row(contribution, isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    } else {
                        row(contribution, isSelected: isSelected)
                    }
                }
            }
        }
    }

    private func row(
        _ contribution: VoiceInputSessionStatisticsContribution,
        isSelected: Bool
    ) -> some View {
        let value = metric.value(in: contribution)
        let ratio = value / maxValue

        return HStack(spacing: 10) {
            Text(contribution.name)
                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                .foregroundStyle(isSelected ? SettingsWorkbenchVisual.accentInk : SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isSelected ? SettingsWorkbenchVisual.accentSoft : SettingsWorkbenchVisual.smallCardBackground)

                Capsule()
                    .fill(color)
                    .frame(width: value > 0 ? max(5, barTrackWidth * CGFloat(ratio)) : 0)
            }
            .frame(width: barTrackWidth, height: 8)

            Text(metric.valueTitle(for: contribution))
                .font(SettingsWorkbenchVisual.monoTinyFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .lineLimit(1)
                .frame(width: 58, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}

private struct StatisticsHourRangeBarList: View {
    let hourRanges: [VoiceInputSessionStatisticsHourRange]
    private let barTrackWidth = StatisticsDashboardLayoutPolicy.resizeOptimized.barTrackWidth

    private var maxSessions: Double {
        max(1, Double(hourRanges.map(\.sessions).max() ?? 0))
    }

    var body: some View {
        if hourRanges.isEmpty {
            StatisticsEmptyText()
        } else {
            VStack(spacing: 12) {
                ForEach(hourRanges) { hourRange in
                    let ratio = Double(hourRange.sessions) / maxSessions

                    HStack(spacing: 10) {
                        Text(hourRange.label)
                            .font(SettingsWorkbenchVisual.captionSemiboldFont)
                            .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                            .lineLimit(1)
                            .frame(width: 54, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SettingsWorkbenchVisual.smallCardBackground)

                            Capsule()
                                .fill(SettingsWorkbenchVisual.warning)
                                .frame(
                                    width: hourRange.sessions > 0
                                        ? max(5, barTrackWidth * CGFloat(ratio))
                                        : 0
                                )
                        }
                        .frame(width: barTrackWidth, height: 8)

                        Text("\(hourRange.sessions) 次")
                            .font(SettingsWorkbenchVisual.monoTinyFont)
                            .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                            .lineLimit(1)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct StatisticsDetailCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(SettingsWorkbenchVisual.captionFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            SettingsWorkbenchVisual.softPreviewBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }
}

private struct StatisticsEmptyText: View {
    var body: some View {
        Text("暂无记录")
            .font(SettingsWorkbenchVisual.captionFont)
            .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 46)
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
        case .model:
            "cpu"
        case .statistics:
            "chart.bar"
        case .settings:
            "gearshape"
        }
    }
}

private extension VoiceInputSessionStatisticsMetric {
    var chartColor: Color {
        switch self {
        case .sessions:
            SettingsWorkbenchVisual.blue
        case .words:
            SettingsWorkbenchVisual.accent
        case .duration:
            SettingsWorkbenchVisual.warning
        }
    }

    func value(in point: VoiceInputSessionStatisticsDailyPoint) -> Double {
        switch self {
        case .sessions:
            Double(point.sessions)
        case .words:
            Double(point.words)
        case .duration:
            point.durationSeconds
        }
    }

    func value(in contribution: VoiceInputSessionStatisticsContribution) -> Double {
        switch self {
        case .sessions:
            Double(contribution.sessions)
        case .words:
            Double(contribution.words)
        case .duration:
            contribution.durationSeconds
        }
    }

    func valueTitle(for contribution: VoiceInputSessionStatisticsContribution) -> String {
        switch self {
        case .sessions:
            "\(contribution.sessions) 次"
        case .words:
            "\(StatisticsFormat.integer(contribution.words)) 字"
        case .duration:
            StatisticsFormat.duration(contribution.durationSeconds)
        }
    }
}

private enum StatisticsFormat {
    static func integer(_ value: Int) -> String {
        guard value >= 1000 else {
            return "\(value)"
        }

        return NumberFormatter.localizedString(
            from: NSNumber(value: value),
            number: .decimal
        )
    }

    static func duration(_ seconds: Double) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        guard roundedSeconds >= 60 else {
            return "\(roundedSeconds) 秒"
        }

        let minutes = roundedSeconds / 60
        let remainingSeconds = roundedSeconds % 60
        if remainingSeconds == 0 {
            return "\(minutes) 分"
        }

        return "\(minutes)分\(remainingSeconds)秒"
    }
}
