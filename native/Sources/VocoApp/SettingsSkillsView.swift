import SwiftUI
import VocoAppCore

enum FillerCleanupReplacementPreset: String, CaseIterable, Identifiable {
    case empty
    case space
    case custom

    var id: String {
        rawValue
    }

    func title(strings: VocoStrings) -> String {
        switch self {
        case .empty:
            strings.skills.replacementEmptyTitle
        case .space:
            strings.skills.replacementSpaceTitle
        case .custom:
            strings.language == .zhHans ? "自定义" : "Custom"
        }
    }

    func replacementText(customText: String) -> String {
        switch self {
        case .empty:
            ""
        case .space:
            " "
        case .custom:
            customText
        }
    }

    func action(customText: String) -> FillerCleanupAction {
        switch self {
        case .empty:
            .delete
        case .space, .custom:
            .replace(replacementText(customText: customText))
        }
    }
}

struct SettingsSkillsView: View {
    @ObservedObject var coordinator: AppCoordinator
    let strings: VocoStrings

    @State private var previewInput: String
    @State private var selectedDetailTab: FillerCleanupDetailTab = .overview
    @State private var isDetailPresented = false
    @State private var newMatchText = ""
    @State private var newReplacementText = ""
    @State private var replacementPreset: FillerCleanupReplacementPreset = .empty

    init(coordinator: AppCoordinator, strings: VocoStrings) {
        self.coordinator = coordinator
        self.strings = strings
        _previewInput = State(initialValue: strings.language == .zhHans ? "嗯这个语音输入需要清理" : "um this voice input needs cleanup")
    }

    var body: some View {
        let snapshot = coordinator.skillSettingsSnapshot(previewInput: previewInput)

        VStack(alignment: .leading, spacing: 16) {
            masterToggle(snapshot)
            skillLibrary(snapshot)
        }
        .sheet(isPresented: $isDetailPresented) {
            FillerCleanupDetailSheet(
                coordinator: coordinator,
                strings: strings,
                previewInput: $previewInput,
                selectedTab: $selectedDetailTab,
                newMatchText: $newMatchText,
                newReplacementText: $newReplacementText,
                replacementPreset: $replacementPreset,
                onClose: {
                    isDetailPresented = false
                }
            )
        }
    }

    private func localized(_ zhHans: String, _ en: String) -> String {
        strings.language == .zhHans ? zhHans : en
    }

    private func masterToggle(_ snapshot: SkillSettingsSnapshot) -> some View {
        HStack(spacing: 12) {
            Text(strings.skills.enabledTitle)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { snapshot.isEnabled },
                    set: { coordinator.setSkillsEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .pointingHandCursor()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .skillsPanel(cornerRadius: 18)
    }

    private func skillLibrary(_ snapshot: SkillSettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("技能库", "Skill Library"))
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            Divider()

            VStack(spacing: 0) {
                ForEach(snapshot.catalogItems) { item in
                    SkillCatalogRow(
                        item: item,
                        configureTitle: localized("配置", "Configure"),
                        onConfigure: {
                            selectedDetailTab = .overview
                            isDetailPresented = true
                        }
                    )
                    .disabled(!item.isConfigurable)

                    if item.id != snapshot.catalogItems.last?.id {
                        Divider()
                            .padding(.leading, 78)
                    }
                }
            }
        }
        .skillsPanel(cornerRadius: 18)
    }
}

private struct SkillCatalogRow: View {
    let item: SkillCatalogItemSnapshot
    let configureTitle: String
    let onConfigure: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(item.glyph)
                .font(SettingsWorkbenchVisual.monoBadgeFont)
                .foregroundStyle(item.statusTone == .active ? SettingsWorkbenchVisual.accent : SettingsWorkbenchVisual.primaryText)
                .frame(width: 38, height: 38)
                .background(
                    item.statusTone == .active ? SettingsWorkbenchVisual.accentSoft : SettingsWorkbenchVisual.smallCardBackground,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                )

            Text(item.title)
                .font(SettingsWorkbenchVisual.sectionTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)

            Spacer(minLength: 16)

            SkillPill(title: item.statusTitle, tone: item.statusTone)

            Button(configureTitle, action: onConfigure)
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    }
}

private struct FillerCleanupDetailSheet: View {
    @ObservedObject var coordinator: AppCoordinator
    let strings: VocoStrings
    @Binding var previewInput: String
    @Binding var selectedTab: FillerCleanupDetailTab
    @Binding var newMatchText: String
    @Binding var newReplacementText: String
    @Binding var replacementPreset: FillerCleanupReplacementPreset
    let onClose: () -> Void

    private var snapshot: SkillSettingsSnapshot {
        coordinator.skillSettingsSnapshot(previewInput: previewInput)
    }

    private var trimmedNewMatchText: String {
        newMatchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddRule: Bool {
        !trimmedNewMatchText.isEmpty && (replacementPreset != .custom || !newReplacementText.isEmpty)
    }

    var body: some View {
        let snapshot = snapshot

        VStack(spacing: 0) {
            header(snapshot)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SkillsTabBar(tabs: snapshot.fillerCleanupDetail.tabs, selectedTab: $selectedTab)

                    switch selectedTab {
                    case .overview:
                        overviewContent(snapshot)
                    case .words:
                        wordsContent(snapshot)
                    case .hits:
                        hitsContent(snapshot)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .background(SettingsWorkbenchVisual.windowBackground)
        }
        .frame(width: 780)
        .frame(minHeight: 620)
        .font(SettingsWorkbenchVisual.bodyFont)
        .background(SettingsWorkbenchVisual.windowBackground)
    }

    private func localized(_ zhHans: String, _ en: String) -> String {
        strings.language == .zhHans ? zhHans : en
    }

    private func header(_ snapshot: SkillSettingsSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            SkillPill(
                title: snapshot.catalogItems.first?.statusTitle ?? "",
                tone: snapshot.isFillerCleanupEnabled ? .active : .neutral
            )

            Text(snapshot.fillerCleanupTitle)
                .font(SettingsWorkbenchVisual.pageTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button(localized("关闭", "Close"), action: onClose)
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(SettingsWorkbenchVisual.panelBackground)
    }

    private func overviewContent(_ snapshot: SkillSettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            previewSection(snapshot.preview)
            baseSettingsSection(snapshot)
            summarySection(snapshot)
        }
    }

    private func previewSection(_ preview: SkillPreviewSnapshot) -> some View {
        SkillSection(title: localized("处理预览", "Preview")) {
            HStack(alignment: .top, spacing: 14) {
                SkillPreviewEditor(
                    title: strings.skills.originalTextTitle,
                    text: $previewInput
                )

                SkillPreviewDiffText(
                    title: localized("变化预览", "Diff Preview"),
                    segments: preview.changeSegments,
                    strings: strings
                )
            }
        }
    }

    private func baseSettingsSection(_ snapshot: SkillSettingsSnapshot) -> some View {
        SkillSection(title: localized("基础设置", "Settings")) {
            VStack(spacing: 0) {
                SkillValueRow(title: localized("状态", "Status")) {
                    SkillPill(
                        title: snapshot.isFillerCleanupEnabled ? localized("已开启", "Enabled") : localized("已关闭", "Disabled"),
                        tone: snapshot.isFillerCleanupEnabled ? .active : .neutral
                    )

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { snapshot.isFillerCleanupEnabled },
                            set: { coordinator.setFillerCleanupEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .pointingHandCursor()
                }

                Divider()

                SkillValueRow(title: localized("启用规则", "Enabled Rules")) {
                    SkillPill(
                        title: localized("\(snapshot.fillerCleanupDetail.enabledRuleCount) 条", "\(snapshot.fillerCleanupDetail.enabledRuleCount) rules"),
                        tone: .neutral
                    )
                }
            }
        }
    }

    private func summarySection(_ snapshot: SkillSettingsSnapshot) -> some View {
        SkillSection(title: localized("词库 / 命中", "Words / Hits")) {
            HStack(alignment: .top, spacing: 12) {
                SkillSummaryButton(
                    title: localized("默认词库", "Default Words"),
                    value: localized("\(snapshot.fillerCleanupDetail.defaultWords.count) 个", "\(snapshot.fillerCleanupDetail.defaultWords.count) words")
                ) {
                    selectedTab = .words
                }

                SkillSummaryButton(
                    title: localized("自定义词", "Custom Words"),
                    value: localized("\(snapshot.fillerCleanupDetail.customWords.count) 个", "\(snapshot.fillerCleanupDetail.customWords.count) words")
                ) {
                    selectedTab = .words
                }

                SkillSummaryButton(
                    title: localized("累计命中", "Total Hits"),
                    value: localized("\(snapshot.fillerCleanupDetail.totalHitCount) 处", "\(snapshot.fillerCleanupDetail.totalHitCount) hits")
                ) {
                    selectedTab = .hits
                }
            }
        }
    }

    private func wordsContent(_ snapshot: SkillSettingsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            wordBlock(
                title: localized("默认词库", "Default Words"),
                words: snapshot.fillerCleanupDetail.defaultWords,
                allowsDelete: false
            )

            VStack(alignment: .leading, spacing: 16) {
                wordBlock(
                    title: localized("自定义词", "Custom Words"),
                    words: snapshot.fillerCleanupDetail.customWords,
                    allowsDelete: true
                )

                addWordSection
            }
        }
    }

    private func wordBlock(
        title: String,
        words: [FillerCleanupWordSnapshot],
        allowsDelete: Bool
    ) -> some View {
        SkillSection(title: title) {
            if words.isEmpty {
                Text(localized("暂无", "None"))
                    .font(SettingsWorkbenchVisual.sectionTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(words) { word in
                        WordManageRow(
                            word: word,
                            enabledTitle: localized("启用", "On"),
                            disabledTitle: localized("停用", "Off"),
                            deleteTitle: localized("删除", "Delete"),
                            allowsDelete: allowsDelete,
                            onEnabledChange: { isEnabled in
                                updateRule(id: word.id, isEnabled: isEnabled)
                            },
                            onDelete: {
                                coordinator.removeFillerCleanupRule(id: word.id)
                            }
                        )

                        if word.id != words.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var addWordSection: some View {
        SkillSection(title: localized("新增", "Add")) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(localized("例如：那个啥", "Example: you know"), text: $newMatchText)
                    .skillsField()

                SkillsReplacementPicker(
                    strings: strings,
                    selection: $replacementPreset
                )

                if replacementPreset == .custom {
                    TextField(localized("替换字符", "Replacement"), text: $newReplacementText)
                        .skillsField()
                }

                HStack {
                    SkillPill(
                        title: FillerCleanupDetailSnapshot.actionTitle(
                            for: replacementPreset.action(customText: newReplacementText),
                            strings: strings
                        ),
                        tone: replacementPreset == .empty ? .active : .neutral
                    )

                    Spacer()

                    Button(localized("新增", "Add")) {
                        addRule()
                    }
                    .buttonStyle(SkillsPrimaryButtonStyle())
                    .disabled(!canAddRule)
                }
            }
        }
    }

    private func hitsContent(_ snapshot: SkillSettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SkillSection(title: localized("累计命中", "Total Hits")) {
                if snapshot.fillerCleanupDetail.hitRows.isEmpty {
                    Text(localized("暂无历史命中", "No Historical Hits"))
                        .font(SettingsWorkbenchVisual.sectionTitleFont)
                        .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.fillerCleanupDetail.hitRows) { hit in
                            HitRow(hit: hit, countTitle: localized("\(hit.matchCount) 次", "\(hit.matchCount)x"))

                            if hit.id != snapshot.fillerCleanupDetail.hitRows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateRule(id: UUID, isEnabled: Bool) {
        guard let rule = coordinator.skillSettings.fillerCleanup.rules.first(where: { $0.id == id }) else {
            return
        }

        coordinator.updateFillerCleanupRule(
            FillerCleanupRule(
                id: rule.id,
                displayName: rule.displayName,
                matchText: rule.matchText,
                matchType: rule.matchType,
                action: rule.action,
                isEnabled: isEnabled,
                order: rule.order
            )
        )
    }

    private func addRule() {
        let matchText = trimmedNewMatchText
        guard canAddRule else {
            return
        }

        coordinator.addFillerCleanupRule(
            displayName: matchText,
            matchText: matchText,
            action: replacementPreset.action(customText: newReplacementText)
        )
        newMatchText = ""
        newReplacementText = ""
        replacementPreset = .empty
    }
}

private struct SkillsTabBar: View {
    let tabs: [FillerCleanupDetailTabSnapshot]
    @Binding var selectedTab: FillerCleanupDetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let isSelected = tab.id == selectedTab

                Button {
                    selectedTab = tab.id
                } label: {
                    Text(tab.title)
                        .font(SettingsWorkbenchVisual.captionSemiboldFont)
                        .foregroundStyle(isSelected ? Color.white : SettingsWorkbenchVisual.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            isSelected ? SettingsWorkbenchVisual.primaryText : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .pointingHandCursor()
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(
            SettingsWorkbenchVisual.smallCardBackground,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.strongBorder, lineWidth: 1)
        )
    }
}

private struct SkillSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            content
        }
        .padding(18)
        .skillsPanel(cornerRadius: 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SkillValueRow<Accessory: View>: View {
    let title: String
    private let accessory: Accessory

    init(title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SettingsWorkbenchVisual.sectionTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            Spacer()

            HStack(spacing: 8) {
                accessory
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct SkillSummaryButton: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(SettingsWorkbenchVisual.sectionTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                SkillPill(title: value, tone: .neutral)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                SettingsWorkbenchVisual.smallCardBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

private struct SkillPreviewEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            TextEditor(text: $text)
                .font(SettingsWorkbenchVisual.bodyFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .background(
                    SettingsWorkbenchVisual.softPreviewBackground,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

enum SkillPreviewChangeSegmentDisplay {
    static func text(for segment: SkillPreviewChangeSegment, strings: VocoStrings) -> String {
        if segment.kind == .inserted && segment.text == " " {
            return strings.skills.replacementSpaceTitle
        }

        return segment.text
    }
}

private struct SkillPreviewDiffText: View {
    let title: String
    let segments: [SkillPreviewChangeSegment]
    let strings: VocoStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            diffText
                .font(SettingsWorkbenchVisual.bodyFont)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .padding(12)
                .background(
                    SettingsWorkbenchVisual.softPreviewBackground,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var diffText: Text {
        guard !segments.isEmpty else {
            return Text(" ")
        }

        return segments.reduce(Text("")) { partialText, segment in
            partialText + styledText(for: segment)
        }
    }

    private func styledText(for segment: SkillPreviewChangeSegment) -> Text {
        let text = SkillPreviewChangeSegmentDisplay.text(for: segment, strings: strings)
        switch segment.kind {
        case .unchanged:
            return Text(text)
                .foregroundColor(SettingsWorkbenchVisual.primaryText)
        case .removed:
            return Text(text)
                .foregroundColor(SettingsWorkbenchVisual.danger)
                .strikethrough(true, color: SettingsWorkbenchVisual.danger)
        case .inserted:
            return Text(text)
                .foregroundColor(SettingsWorkbenchVisual.accent)
                .bold()
        }
    }
}

private struct WordManageRow: View {
    let word: FillerCleanupWordSnapshot
    let enabledTitle: String
    let disabledTitle: String
    let deleteTitle: String
    let allowsDelete: Bool
    let onEnabledChange: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            WordToken(text: word.text)

            Text(word.actionTitle)
                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            SkillPill(
                title: word.isEnabled ? enabledTitle : disabledTitle,
                tone: word.isEnabled ? .active : .neutral
            )

            Toggle(
                "",
                isOn: Binding(
                    get: { word.isEnabled },
                    set: { onEnabledChange($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .pointingHandCursor()

            if allowsDelete {
                Button(deleteTitle, action: onDelete)
                    .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
            }
        }
        .padding(.vertical, 10)
    }
}

private struct HitRow: View {
    let hit: FillerCleanupHitSnapshot
    let countTitle: String

    var body: some View {
        HStack(spacing: 12) {
            WordToken(text: hit.matchedText)

            Text(hit.actionTitle)
                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)

            Spacer()

            SkillPill(title: countTitle, tone: .neutral)
        }
        .padding(.vertical, 11)
    }
}

private struct SkillsReplacementPicker: View {
    let strings: VocoStrings
    @Binding var selection: FillerCleanupReplacementPreset

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FillerCleanupReplacementPreset.allCases) { preset in
                let isSelected = preset == selection

                Button {
                    selection = preset
                } label: {
                    Text(preset.title(strings: strings))
                        .font(SettingsWorkbenchVisual.captionSemiboldFont)
                        .foregroundStyle(isSelected ? Color.white : SettingsWorkbenchVisual.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            isSelected ? SettingsWorkbenchVisual.primaryText : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(4)
        .background(
            SettingsWorkbenchVisual.smallCardBackground,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.strongBorder, lineWidth: 1)
        )
    }
}

private struct WordToken: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsWorkbenchVisual.captionSemiboldFont)
            .foregroundStyle(SettingsWorkbenchVisual.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                SettingsWorkbenchVisual.smallCardBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
            )
    }
}

private struct SkillPill: View {
    let title: String
    let tone: SkillCatalogStatusTone

    var body: some View {
        let color = tone == .active ? SettingsWorkbenchVisual.accent : SettingsWorkbenchVisual.tertiaryText

        Text(title)
            .font(SettingsWorkbenchVisual.caption2BoldFont)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 1))
    }
}

private struct SkillsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SettingsWorkbenchVisual.captionSemiboldFont)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.58))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                SettingsWorkbenchVisual.primaryText.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.36),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .pointingHandCursor()
    }
}

private extension View {
    func skillsPanel(cornerRadius: CGFloat) -> some View {
        background(
            SettingsWorkbenchVisual.panelBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.border, lineWidth: 1)
        )
    }

    func skillsField() -> some View {
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
