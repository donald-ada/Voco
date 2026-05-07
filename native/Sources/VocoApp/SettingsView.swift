import AppKit
import SwiftUI
import VocoAppCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var selectedSection: SettingsWorkbenchSection = .overview
    @State private var selectedDoubaoCredentialMode: DoubaoCredentialMode = .apiKey
    @State private var transcriptionAPIKey = ""
    @State private var doubaoAppID = ""
    @State private var doubaoAccessToken = ""
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
        .background(SettingsWorkbenchVisual.windowBackground)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            coordinator.prepareForSettingsPresentation()
            syncSelectedDoubaoCredentialMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshLegacyInstall()
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
            syncSelectedDoubaoCredentialMode()
        }
    }

    @ViewBuilder
    private func detailContent(for section: SettingsWorkbenchSection) -> some View {
        switch section {
        case .overview:
            overviewSection
        case .voiceInput:
            voiceInputSection
        case .transcription:
            transcriptionWorkbenchSection
        case .permissionsAndInput:
            permissionsAndInputSection
        case .diagnosticsAndPrivacy:
            diagnosticsAndPrivacySection
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

            statusRow

            legacyInstallSection

            launchAtLoginSection

            SettingsOverviewRecoveryCard(
                snapshot: workbench,
                primaryAction: performOverviewPrimaryAction,
                secondaryAction: {
                    coordinator.prepareForSettingsPresentation()
                    settingsFeedbackMessage = "已重新检查状态。"
                }
            )

            RecentVoiceInputChainPanel(
                steps: workbench.recentChain,
                stepAction: performVoiceInputChainAction
            )
        }
    }

    private var voiceInputSection: some View {
        let audio = coordinator.audioSettingsSnapshot
        let hud = coordinator.hudSettingsSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "VOICE INPUT",
                title: "语音输入体验",
                detail: "调整快捷键、录音提示和顶部 HUD 显示。"
            ) {
                Button {
                    startTestRecordingFromSettings()
                } label: {
                    Label("试录 3 秒", systemImage: "waveform")
                }
            }

            workbenchPanel(
                title: "快捷键、音频和 HUD",
                detail: "检查当前快捷键监听、录音输入和 HUD 预览。"
            ) {
                WorkbenchStatusPill(
                    coordinator.hotkeyRuntimeState.title,
                    systemImage: coordinator.hotkeyRuntimeState.systemImage,
                    color: hotkeyTint(coordinator.hotkeyRuntimeState)
                )
            } content: {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        voiceInputControls(audio: audio, hud: hud)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        SettingsHUDCompactPreview(snapshot: hud)
                            .frame(width: 270)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        voiceInputControls(audio: audio, hud: hud)
                        SettingsHUDCompactPreview(snapshot: hud)
                    }
                }
            }

            WorkbenchStatsGrid {
                WorkbenchStatCard(label: "采样率", value: audio.sampleRate.title)
                WorkbenchStatCard(label: "峰值电平", value: recentPeakDisplayTitle)
                WorkbenchStatCard(label: "HUD 预览", value: hud.transcriptPreview.isVisible ? "已开启" : "已关闭")
            }
        }
    }

    private var transcriptionWorkbenchSection: some View {
        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "TRANSCRIPTION",
                title: "Doubao 转写服务",
                detail: "选择凭证模式，并将 Doubao 凭证保存到 macOS Keychain。"
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    credentialPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    transcriptionProviderPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    credentialPanel
                    transcriptionProviderPanel
                }
            }
        }
    }

    private var permissionsAndInputSection: some View {
        let injection = coordinator.injectionSettingsSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "PERMISSIONS AND INPUT",
                title: "权限与文本输入",
                detail: "管理 macOS 授权，并查看最近一次文本输入方式。"
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    permissionsPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    injectionPanel(snapshot: injection)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    permissionsPanel
                    injectionPanel(snapshot: injection)
                }
            }
        }
    }

    private var diagnosticsAndPrivacySection: some View {
        let privacy = coordinator.privacySettingsSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "DIAGNOSTICS AND PRIVACY",
                title: "诊断与隐私",
                detail: "查看最近一次语音输入记录，导出已脱敏的诊断包。"
            )

            DiagnosticsRowsPanel(
                steps: coordinator.settingsWorkbenchSnapshot.recentChain,
                exportAction: exportDiagnosticsFromSettings
            )

            WorkbenchStatsGrid {
                WorkbenchStatCard(label: "Keychain", value: privacy.keychain.title)
                WorkbenchStatCard(label: "转写保留", value: privacy.transcriptRetention.title)
                WorkbenchStatCard(label: "日志策略", value: privacy.logsPolicy.title)
            }

            recordingDiagnosticsSection
        }
    }

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: coordinator.snapshot.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsWorkbenchVisual.warning)
                .frame(width: 18)

            Text(coordinator.snapshot.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            if let message = coordinator.lastErrorMessage ?? settingsFeedbackMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(coordinator.lastErrorMessage == nil ? SettingsWorkbenchVisual.secondaryText : SettingsWorkbenchVisual.danger)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SettingsWorkbenchVisual.warning.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.warning.opacity(0.16), lineWidth: 1)
        )
    }

    private func settingsPageHeader<Actions: View>(
        eyebrow: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(SettingsWorkbenchVisual.eyebrowFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)

                Text(title)
                    .font(SettingsWorkbenchVisual.pageTitleFont)
                    .fontWeight(.bold)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(2)

                Text(detail)
                    .font(SettingsWorkbenchVisual.bodyFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                settingsHeaderStatus

                HStack(spacing: 8) {
                    actions()
                }
                .controlSize(.small)
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }
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

        return HStack(alignment: .center, spacing: 8) {
            WorkbenchStatusPill(status.workbenchTitle, color: status.workbenchColor)

            Text(snapshot.statusTitle)
                .font(.caption)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.70),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                    Text(detail)
                        .font(.caption)
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

    private func voiceInputControls(audio: AudioSettingsSnapshot, hud: HUDSettingsSnapshot) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            WorkbenchFieldBlock(label: "快捷键") {
                WorkbenchReadout(
                    title: coordinator.hotkeyBinding.displayName,
                    detail: coordinator.hotkeyRuntimeState.detail,
                    systemImage: "keyboard",
                    color: hotkeyTint(coordinator.hotkeyRuntimeState)
                )
            }

            WorkbenchFieldBlock(label: "录音模式") {
                WorkbenchSegmentedReadout(activeTitle: coordinator.hotkeyMode.title, inactiveTitle: "按住录音")
            }

            WorkbenchFieldBlock(label: "输入设备") {
                WorkbenchReadout(
                    title: audio.inputDevice.title,
                    detail: audio.inputDevice.detail,
                    systemImage: audio.inputDevice.systemImage,
                    color: SettingsWorkbenchVisual.accent
                )
            }

            WorkbenchFieldBlock(label: "最近峰值 \(recentPeakDisplayTitle)") {
                VStack(alignment: .leading, spacing: 7) {
                    WorkbenchMeter(value: recentPeakFraction, color: statusTint(for: audio.levelMeter.systemImage))
                    Text(audio.levelMeter.detail)
                        .font(.caption2)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                        .lineLimit(2)
                }
            }

            WorkbenchFieldBlock(label: "HUD 位置") {
                WorkbenchReadout(
                    title: hud.position.title,
                    detail: hud.position.detail,
                    systemImage: hud.position.systemImage,
                    color: SettingsWorkbenchVisual.accent
                )
            }

            WorkbenchFieldBlock(label: "实时文本") {
                WorkbenchReadout(
                    title: hud.transcriptPreview.title,
                    detail: hud.transcriptPreview.detail,
                    systemImage: hud.transcriptPreview.systemImage,
                    color: hud.transcriptPreview.isVisible ? SettingsWorkbenchVisual.success : SettingsWorkbenchVisual.neutral
                )
            }
        }
    }

    private var credentialPanel: some View {
        workbenchPanel(
            title: "Doubao 凭证",
            detail: "凭证会保存到 macOS Keychain，不会在界面中显示完整密钥。"
        ) {
            WorkbenchStatusPill(
                coordinator.transcriptionCredentials.statusTitle,
                systemImage: coordinator.transcriptionCredentials.hasCredential ? "key.fill" : "key",
                color: credentialTint(coordinator.transcriptionCredentials)
            )
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Doubao 凭证模式", selection: $selectedDoubaoCredentialMode) {
                    ForEach(DoubaoCredentialMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                WorkbenchFieldBlock(label: selectedDoubaoCredentialMode.fieldLabel) {
                    credentialFields
                }

                Text(selectedDoubaoCredentialMode.detail)
                    .font(.caption)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        let mode = selectedDoubaoCredentialMode
                        let apiKey = transcriptionAPIKey
                        let appID = doubaoAppID
                        let accessToken = doubaoAccessToken
                        clearTranscriptionInputFields()
                        Task {
                            switch mode {
                            case .apiKey:
                                await coordinator.saveTranscriptionAPIKey(apiKey)
                            case .appIDAccessToken:
                                await coordinator.saveDoubaoAppIDAccessToken(
                                    appID: appID,
                                    accessToken: accessToken
                                )
                            }
                            if coordinator.lastErrorMessage == nil {
                                settingsFeedbackMessage = "已保存 Doubao 凭证。"
                            }
                        }
                    } label: {
                        Label("保存到 Keychain", systemImage: "key")
                    }
                    .buttonStyle(SettingsWorkbenchPrimaryButtonStyle())
                    .disabled(!canSaveSelectedCredential)

                    Button("刷新状态") {
                        coordinator.prepareForSettingsPresentation()
                        settingsFeedbackMessage = "已刷新 Doubao 状态。"
                    }
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())

                    Button(role: .destructive) {
                        Task {
                            await coordinator.clearTranscriptionCredentials()
                            if coordinator.lastErrorMessage == nil {
                                settingsFeedbackMessage = "已清除 Doubao 凭证。"
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

    private var transcriptionProviderPanel: some View {
        workbenchPanel(
            title: "服务状态",
            detail: "查看当前凭证模式对应的连接状态和参数。"
        ) {
            WorkbenchStatusPill(
                coordinator.transcriptionProviderStatus.title,
                systemImage: coordinator.transcriptionProviderStatus.systemImage,
                color: transcriptionTint(coordinator.transcriptionProviderStatus)
            )
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                WorkbenchInfoRow(
                    symbol: "ws",
                    title: "WebSocket endpoint",
                    detail: selectedDoubaoCredentialMode.endpointDetail,
                    color: SettingsWorkbenchVisual.success
                ) {
                    Button("复制") {
                        copyToPasteboard(selectedDoubaoCredentialMode.endpointDetail)
                    }
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                }

                WorkbenchInfoRow(
                    symbol: "res",
                    title: selectedDoubaoCredentialMode.routingParameterTitle,
                    detail: selectedDoubaoCredentialMode.routingParameterDetail,
                    color: SettingsWorkbenchVisual.success
                ) {
                    WorkbenchStatusPill(
                        selectedDoubaoCredentialMode.routingParameterBadgeTitle,
                        color: selectedDoubaoCredentialMode == .apiKey
                            ? SettingsWorkbenchVisual.neutral
                            : SettingsWorkbenchVisual.accent
                    )
                }

                WorkbenchInfoRow(
                    symbol: "hdr",
                    title: "认证方式",
                    detail: selectedDoubaoCredentialMode.authHeaderDetail,
                    color: SettingsWorkbenchVisual.accent
                ) {
                    WorkbenchStatusPill("随模式切换", color: SettingsWorkbenchVisual.accent)
                }

                WorkbenchInfoRow(
                    symbol: "log",
                    title: "日志脱敏",
                    detail: "不记录完整 App ID、Access Token 或转写正文",
                    color: SettingsWorkbenchVisual.accent
                ) {
                    WorkbenchStatusPill("开启", color: SettingsWorkbenchVisual.success)
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

    private func injectionPanel(snapshot: InjectionSettingsSnapshot) -> some View {
        workbenchPanel(
            title: "文本输入策略",
            detail: "查看最近目标 App 和文本插入方式。"
        ) {
            WorkbenchStatusPill(
                snapshot.strategy.title,
                systemImage: snapshot.strategy.systemImage,
                color: injectionStrategyTint(snapshot.strategy)
            )
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                WorkbenchInfoRow(
                    symbol: "app",
                    title: "最近目标 App",
                    detail: snapshot.focusedApp.detail,
                    color: snapshot.focusedApp.hasRecentTarget ? SettingsWorkbenchVisual.success : SettingsWorkbenchVisual.neutral
                ) {
                    WorkbenchStatusPill(snapshot.focusedApp.title, color: snapshot.focusedApp.hasRecentTarget ? SettingsWorkbenchVisual.success : SettingsWorkbenchVisual.neutral)
                }

                WorkbenchInfoRow(
                    symbol: "clip",
                    title: "首选策略",
                    detail: snapshot.strategy.detail,
                    color: injectionStrategyTint(snapshot.strategy)
                ) {
                    Button("查看诊断") {
                        selectedSection = .diagnosticsAndPrivacy
                    }
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                }

                WorkbenchInfoRow(
                    symbol: "ax",
                    title: "辅助功能",
                    detail: accessibilityDetail,
                    color: accessibilityColor
                ) {
                    if accessibilityPermission?.state.isGranted == true {
                        WorkbenchStatusPill("已授权", color: SettingsWorkbenchVisual.success)
                    } else {
                        Button("修复") {
                            openSettings(for: .accessibility)
                        }
                        .buttonStyle(SettingsWorkbenchPrimaryButtonStyle())
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

    private var recentPeakFraction: Double {
        guard let peakAmplitude = coordinator.lastAudio?.peakAmplitude else {
            return 0
        }

        return min(max(peakAmplitude, 0), 1)
    }

    private var recentPeakDisplayTitle: String {
        guard coordinator.lastAudio != nil else {
            return "等待采样"
        }

        return "\(Int((recentPeakFraction * 100).rounded()))%"
    }

    private var accessibilityPermission: PermissionSnapshot? {
        coordinator.permissions.first { permission in
            permission.kind == .accessibility
        }
    }

    private var accessibilityDetail: String {
        guard let accessibilityPermission else {
            return "辅助功能权限状态暂不可用。"
        }

        return accessibilityPermission.state.isGranted
            ? "已允许 Voco 控制前台输入框，文本插入链路可用。"
            : "缺失时无法监听全局快捷键，也不能保证输入成功。"
    }

    private var accessibilityColor: Color {
        accessibilityPermission.map { permissionTint($0.state) } ?? SettingsWorkbenchVisual.neutral
    }

    private func injectionStrategyTint(_ snapshot: InjectionStrategySettingsSnapshot) -> Color {
        switch snapshot.succeeded {
        case .some(true):
            SettingsWorkbenchVisual.success
        case .some(false):
            SettingsWorkbenchVisual.danger
        case .none:
            SettingsWorkbenchVisual.neutral
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        settingsFeedbackMessage = "已复制到剪贴板。"
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("登录时启动")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                Text(coordinator.launchAtLoginState.detail)
                    .font(.caption)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if coordinator.launchAtLoginState == .requiresApproval {
                Text("请在 System Settings → General → Login Items 中批准 Voco。")
                    .font(.caption)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            }
        }
        .padding(12)
        .workbenchPanel(cornerRadius: 12)
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
                    .font(.headline)
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
                    .font(.caption)
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
        switch selectedDoubaoCredentialMode {
        case .apiKey:
            SecureField("Doubao API Key", text: $transcriptionAPIKey)
                .textFieldStyle(.roundedBorder)
        case .appIDAccessToken:
            TextField("Doubao App ID", text: $doubaoAppID)
                .textFieldStyle(.roundedBorder)

            SecureField("Doubao Access Token", text: $doubaoAccessToken)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var canSaveSelectedCredential: Bool {
        switch selectedDoubaoCredentialMode {
        case .apiKey:
            !transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appIDAccessToken:
            !doubaoAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !doubaoAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private var recordingDiagnosticsSection: some View {
        if coordinator.lastAudio != nil || coordinator.lastTranscript != nil || coordinator.lastInjection != nil || coordinator.lastErrorMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("录音诊断")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

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
                        .foregroundStyle(injection.succeeded ? SettingsWorkbenchVisual.secondaryText : SettingsWorkbenchVisual.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = coordinator.lastErrorMessage {
                    diagnosticRow(title: "错误", value: message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SettingsWorkbenchVisual.danger)
                }
            }
            .padding(12)
            .workbenchPanel(cornerRadius: 12)
        }
    }

    private func diagnosticRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .background(
                    SettingsWorkbenchVisual.neutral.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            Text(value)
                .font(.caption)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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

    private func transcriptionTint(_ state: TranscriptionProviderStatus) -> Color {
        switch state {
        case .ready:
            SettingsWorkbenchVisual.success
        case .notConfigured, .authenticationRequired:
            SettingsWorkbenchVisual.warning
        case .offline, .failed:
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

    private func syncSelectedDoubaoCredentialMode() {
        guard let mode = coordinator.transcriptionCredentials.mode else {
            return
        }

        selectedDoubaoCredentialMode = mode
    }

    private func clearTranscriptionInputFields() {
        transcriptionAPIKey = ""
        doubaoAppID = ""
        doubaoAccessToken = ""
    }

    private func statusTint(for systemImage: String) -> Color {
        if systemImage.contains("checkmark") || systemImage == "key.fill" {
            return SettingsWorkbenchVisual.success
        }

        if systemImage.contains("xmark") || systemImage.contains("exclamationmark") {
            return SettingsWorkbenchVisual.danger
        }

        return SettingsWorkbenchVisual.neutral
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
        } else if title == "前往权限与输入" ||
            title.contains("输入") {
            selectedSection = .permissionsAndInput
        } else if title == "前往转写服务" ||
            title.contains("转写") ||
            title.contains("Keychain") {
            selectedSection = .transcription
        } else if title.contains("诊断") {
            selectedSection = .diagnosticsAndPrivacy
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
            selectedSection = .permissionsAndInput
            settingsFeedbackMessage = "请先处理权限后再测试录音。"
            return
        }

        settingsFeedbackMessage = "当前状态不能开始录音：\(coordinator.snapshot.title)"
    }

    private func exportDiagnosticsFromSettings() {
        do {
            let url = try coordinator.exportDiagnosticBundleToTemporaryDirectory()
            settingsFeedbackMessage = "诊断包已导出：\(url.lastPathComponent)"
        } catch {
            coordinator.fail(error.localizedDescription)
        }
    }

    private func performVoiceInputChainAction(_ action: VoiceInputChainStepAction) {
        switch action {
        case .viewDetails:
            selectedSection = .diagnosticsAndPrivacy
        case .checkHotkey:
            selectedSection = .voiceInput
        case .startTestRecording:
            startTestRecordingFromSettings()
        case .testTranscription:
            selectedSection = .transcription
            coordinator.prepareForSettingsPresentation()
            settingsFeedbackMessage = "已刷新 Doubao 状态。"
        case .openTranscription:
            selectedSection = .transcription
        case .openPermissionsAndInput:
            selectedSection = .permissionsAndInput
        }
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
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary.opacity(0.84)
    static let tertiaryText = Color.secondary.opacity(0.64)
    static let accent = Color(red: 0.15, green: 0.39, blue: 0.92)
    static let success = Color(red: 0.10, green: 0.58, blue: 0.28)
    static let warning = Color(red: 0.86, green: 0.47, blue: 0.08)
    static let danger = Color(red: 0.86, green: 0.15, blue: 0.15)
    static let neutral = Color.secondary.opacity(0.62)
    static let border = Color(nsColor: .separatorColor).opacity(0.34)
    static let subtleBorder = Color(nsColor: .separatorColor).opacity(0.20)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let detailBackground = LinearGradient(
        colors: [
            Color(nsColor: .windowBackgroundColor),
            Color(nsColor: .controlBackgroundColor).opacity(0.82)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sidebarBackground = LinearGradient(
        colors: [
            Color(nsColor: .controlBackgroundColor).opacity(0.94),
            Color(nsColor: .windowBackgroundColor).opacity(0.88)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let eyebrowFont = Font.system(size: 11, weight: .bold, design: .default)
    static let pageTitleFont = Font.system(size: 30, weight: .bold, design: .default)
    static let bodyFont = Font.system(size: 14, weight: .regular, design: .default)
}

private extension View {
    func workbenchPanel(cornerRadius: CGFloat = 14) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
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

private extension DoubaoCredentialMode {
    var fieldLabel: String {
        switch self {
        case .apiKey:
            "新网关 API Key"
        case .appIDAccessToken:
            "Doubao App ID + Access Token"
        }
    }

    var endpointDetail: String {
        switch self {
        case .apiKey:
            doubaoRealtimeGatewayEndpoint
        case .appIDAccessToken:
            doubaoDefaultEndpoint
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
            doubaoRealtimeGatewayModel
        case .appIDAccessToken:
            "\(doubaoDefaultResourceID) / \(doubaoLegacyOpenSpeechResourceID)"
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.58))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                SettingsWorkbenchVisual.accent.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.36),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsWorkbenchSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? SettingsWorkbenchVisual.primaryText : SettingsWorkbenchVisual.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(configuration.isPressed ? 0.72 : 0.94),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 10, weight: .bold))
            }

            Text(title)
                .font(.system(size: 11, weight: .bold))
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.60),
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WorkbenchSegmentedReadout: View {
    let activeTitle: String
    let inactiveTitle: String

    var body: some View {
        HStack(spacing: 4) {
            Text(activeTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(SettingsWorkbenchVisual.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(inactiveTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Color(nsColor: .windowBackgroundColor).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .padding(3)
        .background(
            Color(nsColor: .separatorColor).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct WorkbenchMeter: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SettingsWorkbenchVisual.neutral.opacity(0.14))

                Capsule()
                    .fill(color)
                    .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 9)
    }
}

private struct WorkbenchStatsGrid<Content: View>: View {
    private let content: Content
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            content
        }
    }
}

private struct WorkbenchStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .workbenchPanel(cornerRadius: 13)
    }
}

private struct WorkbenchSymbolBox: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .heavy))
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
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
            Color(nsColor: .controlBackgroundColor).opacity(0.62),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }
}

private struct SettingsHUDCompactPreview: View {
    let snapshot: HUDSettingsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HUD 预览")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Spacer()

                WorkbenchStatusPill(snapshot.notchMode.title, color: SettingsWorkbenchVisual.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("语音输入")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.yellow)
                    Spacer()
                    MiniWaveform()
                }

                Text("第二行实时显示你正在说的内容")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettingsWorkbenchVisual.success)
                    .lineLimit(2)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)

            WorkbenchInfoRow(
                symbol: "hud",
                title: snapshot.position.title,
                detail: snapshot.position.detail,
                color: SettingsWorkbenchVisual.accent
            ) {
                WorkbenchStatusPill(snapshot.transcriptPreview.isVisible ? "显示文本" : "隐藏文本", color: snapshot.transcriptPreview.isVisible ? SettingsWorkbenchVisual.success : SettingsWorkbenchVisual.neutral)
            }
        }
        .padding(12)
        .workbenchPanel(cornerRadius: 14)
    }
}

private struct DiagnosticsRowsPanel: View {
    let steps: [VoiceInputChainStepSnapshot]
    let exportAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近一次语音输入")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    Text("查看按键、录音、转写和输入是否正常。")
                        .font(.caption)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                }

                Spacer()

                Button("导出诊断包", action: exportAction)
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    WorkbenchInfoRow(
                        symbol: step.id == "command" ? "cmd" : String(step.title.prefix(3)),
                        title: step.title,
                        detail: step.detail,
                        color: step.status.workbenchColor
                    ) {
                        WorkbenchStatusPill(step.status.workbenchTitle, color: step.status.workbenchColor)
                    }
                }
            }
        }
        .padding(14)
        .workbenchPanel(cornerRadius: 15)
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
                    Color(nsColor: .controlBackgroundColor).opacity(0.82)
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
                .font(.system(size: 24, weight: .bold))
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    Text("Right Command -> HUD 胶囊 -> 当前输入框")
                        .font(.caption2)
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SettingsWorkbenchVisual.accent)
                .frame(width: 30, height: 30)
                .background(SettingsWorkbenchVisual.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }

    private var connector: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.65))
            .frame(width: 1, height: 10)
    }

    private var notchPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("语音输入")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.yellow)
                Spacer()
                MiniWaveform()
            }

            Text("第二行实时显示你正在说的内容")
                .font(.caption2)
                .fontWeight(.semibold)
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
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                Text("Voco")
                    .font(.system(size: 23, weight: .bold))
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
                Circle()
                    .fill(status.workbenchColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                        .lineLimit(1)

                    Text(section.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(
                isSelected ? Color(nsColor: .controlBackgroundColor).opacity(0.95) : Color.clear,
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

private struct RecentVoiceInputChainPanel: View {
    let steps: [VoiceInputChainStepSnapshot]
    let stepAction: (VoiceInputChainStepAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近一次语音输入")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    Text("检查 Right Command、录音、Doubao 和文本输入。")
                        .font(.caption)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                }

                Spacer()
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(steps) { step in
                    RecentVoiceInputChainStepCard(
                        step: step,
                        action: {
                            stepAction(step.action)
                        }
                    )
                }
            }
        }
        .padding(14)
        .workbenchPanel(cornerRadius: 15)
    }
}

private struct RecentVoiceInputChainStepCard: View {
    let step: VoiceInputChainStepSnapshot
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                SettingsWorkbenchStepSymbol(id: step.id, color: step.status.workbenchColor)

                Spacer(minLength: 0)

                WorkbenchStatusPill(step.status.workbenchTitle, color: step.status.workbenchColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(step.actionTitle, action: action)
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.78),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
        )
    }
}

private struct SettingsWorkbenchStepSymbol: View {
    let id: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.16), lineWidth: 1)
            )
    }

    private var systemImage: String {
        switch id {
        case "command":
            "command"
        case "audio":
            "waveform"
        case "doubao":
            "text.bubble"
        case "input":
            "text.cursor"
        default:
            "circle"
        }
    }
}
