import Foundation

public struct InjectionSettingsSnapshot: Equatable, Sendable {
    public let strategy: InjectionStrategySettingsSnapshot
    public let focusedApp: FocusedAppSettingsSnapshot

    public init(lastInjection: TextInjectionSnapshot?, strings: VocoStrings = VocoStrings()) {
        self.strategy = InjectionStrategySettingsSnapshot(lastInjection: lastInjection, strings: strings)
        self.focusedApp = FocusedAppSettingsSnapshot(lastInjection: lastInjection, strings: strings)
    }
}

public struct InjectionStrategySettingsSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let succeeded: Bool?

    public init(lastInjection: TextInjectionSnapshot?, strings: VocoStrings = VocoStrings()) {
        guard let lastInjection else {
            self.title = strings.injection.waitingToInsertTitle
            self.detail = strings.injection.waitingToInsertDetail
            self.systemImage = "text.cursor"
            self.succeeded = nil
            return
        }

        self.title = lastInjection.strategy.title
        self.detail = lastInjection.detail
        self.systemImage = lastInjection.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
        self.succeeded = lastInjection.succeeded
    }
}

public struct FocusedAppSettingsSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let hasRecentTarget: Bool

    public init(lastInjection: TextInjectionSnapshot?, strings: VocoStrings = VocoStrings()) {
        guard let lastInjection else {
            self.title = strings.injection.noRecentTargetTitle
            self.detail = strings.injection.noRecentTargetDetail
            self.systemImage = "app.dashed"
            self.hasRecentTarget = false
            return
        }

        if let targetAppName = lastInjection.targetAppName, !targetAppName.isEmpty {
            self.title = targetAppName
            self.detail = lastInjection.succeeded ? strings.injection.recentTargetDetail : lastInjection.detail
            self.systemImage = lastInjection.succeeded ? "app.connected.to.app.below.fill" : "app.badge"
            self.hasRecentTarget = true
        } else {
            self.title = strings.injection.noTargetAppTitle
            self.detail = lastInjection.detail
            self.systemImage = "app.dashed"
            self.hasRecentTarget = false
        }
    }
}
