---
title: Voco Settings Workbench Redesign
date: 2026-05-07
status: design-approved
target_platform: macOS 14+ native SwiftUI settings window
scope: Refactor the native settings window to match the approved A workbench prototype
prototype: docs/prototypes/voco-settings-redesign.html
---

# Voco Settings Workbench Redesign 设计文档

## 1. Goal

把当前设置窗口从“所有功能堆在一条滚动页里”重构成一个任务恢复控制台。用户打开设置后，第一眼要能判断：

1. Voco 当前能不能用；
2. 哪一步阻塞了真实语音输入链路；
3. 应该点击哪个按钮修复；
4. 修复后如何跑一次测试录音确认。

最终实现以 prototype A “工作台式”为准。B “偏好设置”和 C “修复向导”只作为探索方案，不进入本轮 native 实现。

## 2. Approved Visual Decisions

本轮视觉讨论已确认以下决策：

- 首屏定位：任务恢复控制台。
- 首屏右侧视觉：`Right Command -> HUD 胶囊 -> 当前输入框` 的语音输入链路预览。
- 左侧导航：保留 5 项任务分组。
- 左侧问题提示：使用状态点，不使用红色数字 badge。
- 左侧行尾：移除右侧小灰图标，让侧栏更像 macOS source list。
- 视觉风格：更 macOS 原生，减少强边框和重按钮。
- 下半部分：展示最近一次语音输入链路诊断，而不是权限 + HUD 预览。

## 3. Information Architecture

设置窗口使用固定的 sidebar-detail 结构。左侧导航是真正的 selection，不再只是静态目录。

左侧 5 项任务分组：

| 分组 | 内容 |
| --- | --- |
| 总览 | 当前状态、阻塞点、修复动作、语音输入链路预览、最近链路诊断 |
| 语音输入 | 快捷键、录音模式、音频输入、电平、HUD 预览 |
| 转写服务 | Doubao provider、凭证模式、Keychain 状态、连接测试入口 |
| 权限与输入 | 麦克风、辅助功能、文本插入策略、最近目标 App |
| 诊断与隐私 | 最近运行链路、导出诊断包、Keychain、转写保留、日志脱敏 |

旧的 8 个 `SettingsSection` 可以继续存在于 core 层用于底层分类和测试，但 native 设置窗口应该以新的 5 项任务分组渲染。

## 4. Overview Screen

总览页是默认选中页面。

顶部内容：

- eyebrow：`OVERVIEW`。
- 标题：`把设置页改成可恢复、可验证的控制台`。
- 描述：强调它直接回答“现在能不能用、哪里坏了、下一步点哪里”。
- 主动作：`开始测试录音`。
- 次动作：`导出诊断包`。

主状态卡左侧：

- 显示当前最高优先级阻塞点。
- 当前优先级顺序：
  1. 必需权限缺失；
  2. Doubao 凭证缺失或读取失败；
  3. ASR provider 失败；
  4. 最近输入失败；
  5. 无阻塞时显示就绪状态。
- 每个阻塞点必须有明确恢复动作，例如 `打开辅助功能设置`、`保存到 Keychain`、`重新检查`。

主状态卡右侧：

展示静态语音输入链路预览：

```text
Right Command
-> HUD 胶囊：语音输入 + 波形 + 第二行转写文本
-> 当前输入框
```

这块是视觉解释，不需要成为真实 HUD 渲染器。

下半部分：

展示最近一次语音输入链路诊断，四步固定为：

1. Command；
2. 录音；
3. Doubao；
4. 输入。

每一步显示状态、摘要和动作。失败步骤使用更高视觉权重，并提供恢复动作。

## 5. Sidebar Behavior

侧栏使用更接近 macOS source list 的轻量行。

每一行包含：

- 左侧状态点；
- 标题；
- 一行短说明。

不包含：

- 数字 badge；
- 行尾小灰图标；
- 多行 metadata；
- 卡片式复杂边框。

状态点含义：

| 状态 | 视觉 |
| --- | --- |
| 正常 | 绿色点 |
| 需要处理 | 红色点 |
| 需要注意或可选 | 黄色/灰色点 |
| 无近期失败 | 灰色点 |

状态点由当前 coordinator snapshot 推导，不需要引入新的持久化状态。

## 6. Detail Screens

### 6.1 语音输入

展示：

- 当前快捷键：`Right Command`；
- 录音模式：当前为 `切换录音`；
- 输入设备：系统默认输入；
- 最近峰值电平和采样率；
- HUD 胶囊预览。

本轮不实现真实快捷键编辑器或设备选择器，但 UI 要为后续接入留出稳定位置。

### 6.2 转写服务

展示：

- Doubao provider 状态；
- Keychain 凭证状态；
- 凭证模式 segmented picker：
  - 新控制台 API Key；
  - 旧控制台 App ID + Token；
- 当前模式对应输入字段；
- 保存到 Keychain；
- 清除凭证；
- 测试连接入口。

本轮不恢复从配置文件读取 TOKEN 的旧路径。凭证来源只能是设置界面写入 Keychain。

### 6.3 权限与输入

展示：

- 麦克风：必需；
- 辅助功能：必需；
- 文本输入策略；
- 最近目标 App；
- 当前插入失败原因和恢复动作。

这里不再展示输入监控，避免用户误以为 Voco 默认需要键入监控授权。

### 6.4 诊断与隐私

展示：

- 最近一次语音输入链路；
- 导出诊断包；
- Keychain 状态；
- 转写保留策略；
- 日志脱敏策略。

导出的诊断包继续保持 secret 和完整转写正文脱敏。

## 7. Implementation Shape

推荐新增 core 模型，避免 SwiftUI 里硬编码新导航：

- `SettingsWorkbenchSection`
- `SettingsWorkbenchSectionStatus`
- `SettingsWorkbenchSnapshot`
- `VoiceInputChainStepSnapshot`

`SettingsWorkbenchSnapshot` 从现有 `AppCoordinator` 状态组合得出：

- runtime status；
- permissions；
- hotkey runtime state；
- transcription provider status；
- transcription credentials；
- last audio；
- last transcript；
- last injection；
- last error message。

`SettingsView` 重构为小组件：

- `SettingsWorkbenchSidebar`
- `SettingsWorkbenchOverview`
- `VoiceInputFlowPreview`
- `RecentVoiceInputChainPanel`
- `SettingsPanel`
- 复用或迁移现有 credential、permission、diagnostic 行组件。

`SettingsView` 应保留现有刷新行为：

- `onAppear` 调用 `prepareForSettingsPresentation()`；
- app 回到 active 时刷新旧版启动项、权限和凭证；
- Doubao 凭证模式跟随 Keychain snapshot 同步。

## 8. Testing

先补 core 模型测试，再改 SwiftUI。

必须覆盖：

- 新 5 项分组的顺序、标题、摘要和图标/状态语义。
- 权限缺失时，总览最高优先级阻塞点指向权限恢复。
- Doubao 凭证缺失时，总览阻塞点指向转写服务。
- 最近链路包含 `Command / 录音 / Doubao / 输入` 四步。
- 权限页只展示麦克风和辅助功能，不出现输入监控。

验证命令：

```text
swift test --package-path native
packaging/build_native_app_bundle.sh --profile debug
git diff --check
```

## 9. Out Of Scope

本轮不做：

- 真实快捷键编辑器；
- 真实音频设备选择器；
- provider 多选；
- HUD 设置持久化；
- 完整诊断历史列表；
- 完整菜单栏视觉重设计；
- B/C 原型方案实现。

## 10. Completion Criteria

完成时应满足：

- 打开设置窗口默认显示总览控制台；
- 左侧 5 项导航可切换右侧内容；
- 总览页有语音输入链路预览；
- 总览页下半部分是最近一次链路诊断；
- 侧栏使用状态点，没有数字 badge 和行尾小灰图标；
- Doubao 新旧凭证模式仍可保存和清除；
- 权限修复按钮仍可打开对应 System Settings；
- 所有 native 测试通过；
- debug app bundle 构建通过。
