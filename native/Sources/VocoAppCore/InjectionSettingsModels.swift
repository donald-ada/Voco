import Foundation

public struct InjectionSettingsSnapshot: Equatable, Sendable {
    public let strategy: InjectionStrategySettingsSnapshot
    public let focusedApp: FocusedAppSettingsSnapshot

    public init(lastInjection: TextInjectionSnapshot?) {
        self.strategy = InjectionStrategySettingsSnapshot(lastInjection: lastInjection)
        self.focusedApp = FocusedAppSettingsSnapshot(lastInjection: lastInjection)
    }
}

public struct InjectionStrategySettingsSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let succeeded: Bool?

    public init(lastInjection: TextInjectionSnapshot?) {
        guard let lastInjection else {
            self.title = "等待插入"
            self.detail = "完成一次转写后会显示采用的文本插入方式。"
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

    public init(lastInjection: TextInjectionSnapshot?) {
        guard let lastInjection else {
            self.title = "无近期目标"
            self.detail = "尚未完成文本插入，无法显示最近聚焦 App。"
            self.systemImage = "app.dashed"
            self.hasRecentTarget = false
            return
        }

        if let targetAppName = lastInjection.targetAppName, !targetAppName.isEmpty {
            self.title = targetAppName
            self.detail = lastInjection.succeeded ? "最近插入目标 App。" : lastInjection.detail
            self.systemImage = lastInjection.succeeded ? "app.connected.to.app.below.fill" : "app.badge"
            self.hasRecentTarget = true
        } else {
            self.title = "无目标 App"
            self.detail = lastInjection.detail
            self.systemImage = "app.dashed"
            self.hasRecentTarget = false
        }
    }
}
