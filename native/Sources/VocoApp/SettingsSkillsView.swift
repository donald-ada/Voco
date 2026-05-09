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
            header(snapshot)
            masterTogglePanel(snapshot)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    fillerCleanupPanel(snapshot)
                    ruleListPanel(snapshot)
                    addRulePanel
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                previewPanel(snapshot.preview)
                    .frame(width: 300, alignment: .topLeading)
            }
        }
    }

    private var trimmedNewMatchText: String {
        newMatchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddRule: Bool {
        !trimmedNewMatchText.isEmpty && (replacementPreset != .custom || !newReplacementText.isEmpty)
    }

    private func localized(_ zhHans: String, _ en: String) -> String {
        strings.language == .zhHans ? zhHans : en
    }

    private func header(_ snapshot: SkillSettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SKILLS")
                .font(SettingsWorkbenchVisual.eyebrowFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)

            Text(snapshot.title)
                .font(SettingsWorkbenchVisual.pageTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(snapshot.detail)
                .font(SettingsWorkbenchVisual.bodyFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func masterTogglePanel(_ snapshot: SkillSettingsSnapshot) -> some View {
        Toggle(
            isOn: Binding(
                get: { snapshot.isEnabled },
                set: { coordinator.setSkillsEnabled($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(strings.skills.enabledTitle)
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Text(snapshot.detail)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            }
        }
        .toggleStyle(.switch)
        .padding(18)
        .settingsSkillsPanel(cornerRadius: 16)
    }

    private func fillerCleanupPanel(_ snapshot: SkillSettingsSnapshot) -> some View {
        Toggle(
            isOn: Binding(
                get: { snapshot.isFillerCleanupEnabled },
                set: { coordinator.setFillerCleanupEnabled($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.fillerCleanupTitle)
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Text(snapshot.fillerCleanupDetail)
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(18)
        .settingsSkillsPanel(cornerRadius: 16)
    }

    private func ruleListPanel(_ snapshot: SkillSettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.skills.rulesTitle)
                    .font(SettingsWorkbenchVisual.panelTitleFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)

                Spacer()

                Text(localized("\(snapshot.rules.count) 条", "\(snapshot.rules.count) rules"))
                    .font(SettingsWorkbenchVisual.monoTinyFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Divider()
            }

            if snapshot.rules.isEmpty {
                Text(localized("暂无规则", "No rules"))
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                ForEach(snapshot.rules) { rule in
                    SettingsSkillRuleRow(
                        rule: rule,
                        actionLabel: actionLabel(for: rule.action),
                        strings: strings,
                        onEnabledChange: { updateRule(rule, isEnabled: $0) },
                        onDelete: { coordinator.removeFillerCleanupRule(id: rule.id) }
                    )
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
            }
        }
        .settingsSkillsPanel(cornerRadius: 16)
    }

    private var addRulePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("添加自定义规则", "Add Custom Rule"))
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("匹配文本", "Match Text"))
                    .font(SettingsWorkbenchVisual.caption2BoldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                TextField(localized("输入要清理的语气词", "Text to clean up"), text: $newMatchText)
                    .settingsSkillsField()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("动作", "Action"))
                    .font(SettingsWorkbenchVisual.caption2BoldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                Picker(localized("动作", "Action"), selection: $replacementPreset) {
                    ForEach(FillerCleanupReplacementPreset.allCases) { preset in
                        Text(preset.title(strings: strings)).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if replacementPreset == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("替换文本", "Replacement Text"))
                        .font(SettingsWorkbenchVisual.caption2BoldFont)
                        .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                    TextField(localized("输入替换后的文本", "Replacement text"), text: $newReplacementText)
                        .settingsSkillsField()
                }
            }

            HStack {
                Text(actionLabel(for: replacementPreset.action(customText: newReplacementText)))
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                    .lineLimit(1)

                Spacer()

                Button(strings.skills.addRuleButton) {
                    addRule()
                }
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
                .disabled(!canAddRule)
            }
        }
        .padding(18)
        .settingsSkillsPanel(cornerRadius: 16)
    }

    private func previewPanel(_ preview: SkillPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.skills.previewTitle)
                .font(SettingsWorkbenchVisual.panelTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)

            TextEditor(text: $previewInput)
                .font(SettingsWorkbenchVisual.bodyFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 104)
                .background(
                    SettingsWorkbenchVisual.softPreviewBackground,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                )

            SettingsSkillPreviewTextBlock(title: strings.skills.originalTextTitle, text: preview.originalText)
            SettingsSkillPreviewTextBlock(title: strings.skills.processedTextTitle, text: preview.processedText)

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.skills.matchedRulesTitle)
                    .font(SettingsWorkbenchVisual.caption2BoldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

                if preview.matchedRuleTitles.isEmpty {
                    Text(strings.skills.noMatchedRulesTitle)
                        .font(SettingsWorkbenchVisual.captionFont)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(preview.matchedRuleTitles.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(SettingsWorkbenchVisual.captionSemiboldFont)
                                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(18)
        .settingsSkillsPanel(cornerRadius: 16)
    }

    private func updateRule(_ rule: FillerCleanupRule, isEnabled: Bool) {
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
            displayName: displayName(for: matchText),
            matchText: matchText,
            action: replacementPreset.action(customText: newReplacementText)
        )
        newMatchText = ""
        newReplacementText = ""
        replacementPreset = .empty
    }

    private func displayName(for matchText: String) -> String {
        switch replacementPreset {
        case .empty:
            "\(strings.skills.deleteActionTitle) \(matchText)"
        case .space, .custom:
            "\(strings.skills.replaceActionTitle) \(matchText)"
        }
    }

    private func actionLabel(for action: FillerCleanupAction) -> String {
        switch action {
        case .delete:
            return strings.skills.deleteActionTitle
        case .replace(let text):
            if text == " " {
                return "\(strings.skills.replaceActionTitle): \(strings.skills.replacementSpaceTitle)"
            }
            if text.isEmpty {
                return "\(strings.skills.replaceActionTitle): \(strings.skills.replacementEmptyTitle)"
            }
            return "\(strings.skills.replaceActionTitle): \(text)"
        }
    }
}

private struct SettingsSkillRuleRow: View {
    let rule: FillerCleanupRule
    let actionLabel: String
    let strings: VocoStrings
    let onEnabledChange: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { isEnabled in onEnabledChange(isEnabled) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text(rule.displayName)
                    .font(SettingsWorkbenchVisual.captionSemiboldFont)
                    .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(rule.matchText)
                        .font(SettingsWorkbenchVisual.monoTinyFont)
                        .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            SettingsWorkbenchVisual.softPreviewBackground,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )

                    Text(actionLabel)
                        .font(SettingsWorkbenchVisual.caption2Font)
                        .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(strings.skills.deleteActionTitle, action: onDelete)
                .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

private struct SettingsSkillPreviewTextBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SettingsWorkbenchVisual.caption2BoldFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)

            Text(text.isEmpty ? " " : text)
                .font(SettingsWorkbenchVisual.captionFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .padding(10)
                .background(
                    SettingsWorkbenchVisual.softPreviewBackground,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsWorkbenchVisual.subtleBorder, lineWidth: 1)
                )
        }
    }
}

private extension View {
    func settingsSkillsPanel(cornerRadius: CGFloat) -> some View {
        background(
            SettingsWorkbenchVisual.panelBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(SettingsWorkbenchVisual.border, lineWidth: 1)
        )
    }

    func settingsSkillsField() -> some View {
        textFieldStyle(.plain)
            .font(SettingsWorkbenchVisual.bodyFont)
            .foregroundStyle(SettingsWorkbenchVisual.primaryText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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
