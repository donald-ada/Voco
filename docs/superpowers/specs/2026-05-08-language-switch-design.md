# Voco 全应用语言切换设计

## 目标

在设置模块中新增语言切换能力。应用默认使用中文，用户可切换为英文。切换后，全应用用户可见文案应立即使用所选语言，包括设置窗口、菜单栏、HUD、状态摘要、权限说明、模型凭证状态、统计页、会话列表、用户操作反馈和应用生成的错误提示。

用户转写内容、目标 App 名称、Keychain/macOS/网络库返回的底层错误原文不做翻译；应用包裹这些错误时，包裹文案按当前语言显示。

## 推荐方案

采用项目内 typed localization catalog，而不是直接引入零散字符串 key 或只依赖 `.strings` 文件。

核心理由：

- 当前大量文案来自 `VocoAppCore` 的模型属性和 snapshot，而不是 SwiftUI view 中的静态 `Text`。
- 应用需要在设置窗口内运行时切换语言，并让现有 `@Published` 状态驱动 SwiftUI/AppKit/HUD 刷新。
- 类型化 API 能让测试覆盖动态文案、插值、状态分支和默认偏好，避免 key 拼写错误在运行时才暴露。

## 范围

第一版覆盖全应用用户可见文案：

- `VocoAppCore` 中的状态、权限、热键、模型凭证、转写、注入、音频、HUD、安装位置、旧版启动项、会话统计和设置工作台模型文案。
- `VocoApp` 中的设置窗口、菜单栏、窗口标题、HUD chrome、用户操作反馈、打开系统设置失败提示和 AppKit 适配层生成的错误提示。
- 现有中文测试要迁移为语言感知测试，新增英文断言。

不在第一版范围：

- 用户历史转写文本的翻译。
- Provider 名称本身的产品命名重写，除非它是应用自带的固定显示名。
- 从系统 API、Keychain、SQLite、URLSession 或第三方服务直接返回的底层错误原文翻译。
- 依赖 macOS 系统语言自动切换；默认始终中文，用户偏好优先。

## 数据模型

新增 `AppLanguage`：

- `zhHans`：默认语言，显示名为 `中文`。
- `en`：英文，显示名为 `English`。
- `rawValue` 可持久化到 `UserDefaults`。

扩展 `AppPreferenceStoring`：

- `var appLanguage: AppLanguage { get }`
- `func saveAppLanguage(_ language: AppLanguage)`

`MacAppPreferenceStore` 使用新 key，例如 `app.language`。没有已存值或 raw value 无效时返回 `.zhHans`。

`NoOpAppPreferenceStore` 默认返回 `.zhHans`，保持测试和预览行为稳定。

## 文案层

新增一个类型化文案入口，命名为 `VocoStrings`。它按 `AppLanguage` 初始化，并提供面向业务概念的 API，而不是让调用点传字符串 key。

示例形态：

```swift
public struct VocoStrings: Sendable {
    public let language: AppLanguage

    public var settings: SettingsStrings { ... }
    public var permissions: PermissionStrings { ... }
    public var transcription: TranscriptionStrings { ... }
    public var statistics: StatisticsStrings { ... }
}
```

动态文案通过方法表达：

```swift
strings.permissions.missingTitle(kind: .microphone)
strings.transcription.authenticationFailed(providerName: providerName, message: message)
strings.sessions.wordCount(session.wordCount)
```

优先把文案映射放在 `VocoAppCore`，因为 core models 已经承载大部分 app-facing copy。`VocoApp` 层只保留窗口、菜单、HUD chrome 和视图布局相关文案。

## 状态来源和数据流

`AppCoordinator` 成为当前语言的单一状态来源：

1. 初始化时从 `AppPreferenceStoring.appLanguage` 读取语言。
2. 暴露 `@Published public private(set) var appLanguage: AppLanguage`。
3. 暴露 `public var strings: VocoStrings`，由该属性按 `appLanguage` 生成文案 catalog。
4. 新增 `setAppLanguage(_:)`，更新 `appLanguage` 并持久化。
5. `settingsWorkbenchSnapshot`、`hudSnapshot`、`snapshot`、`audioSettingsSnapshot` 等由 coordinator 生成的 snapshot 使用当前语言生成文案。

SwiftUI 设置页观察 `coordinator.appLanguage`，切换后 body 重新计算，当前窗口立即刷新。AppKit 层窗口标题和菜单标题在展示或状态变化时重新读取当前语言。

## 设置界面

在 `设置 > 系统` 面板新增一行：

- label：中文为 `语言`，英文为 `Language`。
- title：当前语言显示名。
- detail：中文说明为 `切换 Voco 界面语言。`；英文说明为 `Switch the Voco interface language.`
- control：复用 `WorkbenchMenuControl`，选项为 `中文` 和 `English`。

切换行为：

- 默认中文。
- 选择英文后立即刷新设置窗口、菜单栏 snapshot、HUD snapshot 和后续错误提示。
- 现有中文历史会话文本保持原样；会话列表的时间、字数、按钮和空状态文案切换语言。

## 行为边界

语言切换不改变：

- 热键绑定、录音模式、权限状态、凭证、会话记录、登录项、Dock 显示状态。
- 当前录音或转写流程。
- 存量会话的 `providerName` 和 `transcriptText`。

语言切换会影响：

- 后续由应用生成的 `lastErrorMessage` 外层文案。
- 切换后重新计算的 snapshot 文案。
- 设置页即时可见文案和菜单/HUD 状态文案。

## 错误处理

偏好读取：

- 无存储值：使用中文。
- 无效 raw value：使用中文，不抛错。

底层错误包装：

- 应用包裹文案本地化，例如中文 `无法加载会话记录：...`，英文 `Unable to load session history: ...`。
- 底层 `error.localizedDescription` 原文保留，避免误译系统或服务返回内容。

网络、Keychain、SQLite 和文件 IO 错误仍需 fail loud：已有 `lastErrorMessage` 和 `NSLog` 路径继续保留，但包裹文案跟随语言。

## 测试计划

按 TDD 实施，先写失败测试再改实现：

1. `AppPreferenceModelsTests`

   验证 `AppLanguage` 顺序、默认中文、显示名和 `NoOpAppPreferenceStore` 默认语言。

2. `MacAppPreferenceStoreTests`

   验证语言偏好 round-trip，验证无效 raw value 回退中文。

3. Core model 文案测试

   先覆盖 `PermissionKind`、`HotkeyRuntimeState`、`TranscriptionProviderStatus`、`SettingsWorkbenchSnapshot`、`VoiceInputSessionRetentionPolicy` 和 `AppRuntimeStatus` 的中英文输出。

4. `AppCoordinatorTests`

   验证初始化读取语言，`setAppLanguage(_:)` 持久化语言，并让 menu bar snapshot、HUD snapshot、settings snapshot 使用新语言。

5. App 层测试

   更新 `VocoNativeAppTests`、`HUDOverlayChromeTests`、`SettingsOverviewPrimaryActionResolverTests` 和窗口标题相关测试，覆盖中英文行为。

最终验证命令：

```bash
swift test --package-path native
packaging/build_native_app_bundle.sh --profile debug
packaging/tests/native_app_bundle_smoke.sh
git diff --check
```

## 迁移顺序

1. 引入 `AppLanguage`、偏好存储和基础 tests。
2. 引入 typed strings catalog，先迁移小而稳定的 model：permission、hotkey、runtime status。
3. 迁移 `SettingsWorkbenchSnapshot` 和 overview routing，避免依赖中文按钮标题判断行为。
4. 迁移设置 UI 直接写死的文案，并加入语言选择控件。
5. 迁移 HUD、菜单、窗口标题、统计和会话列表文案。
6. 扫描剩余中文 user-facing literals，判断是否迁移、保留为测试数据，或保留为底层服务/用户内容。

## 验收标准

- 新安装或无偏好时默认中文。
- 设置里可选择 `中文` 或 `English`。
- 切换英文后，全应用可见的应用生成文案不再混中文。
- 切回中文后恢复中文界面。
- 语言偏好重启后保留。
- 所有新增和既有测试通过。
- app bundle 和 smoke test 通过。
