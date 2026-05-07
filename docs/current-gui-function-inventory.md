# Voco 当前 GUI 功能与菜单说明

盘点日期：2026-05-07

盘点范围：当前工作区里的 native macOS GUI，包括菜单栏入口、首次设置窗口、设置窗口、诊断窗口、HUD 灵动岛胶囊，以及这些界面背后的状态模型。本文档用于下一步通过 `prototype-design` 技能重新设计设置界面和相关 GUI。

## 1. 当前 GUI 总览

Voco 当前是一个菜单栏 App。启动后使用 `.accessory` activation policy，不显示 Dock 图标，菜单栏图标是主入口。

当前 GUI 由四类界面组成：

| 界面 | 当前作用 | 入口 |
| --- | --- | --- |
| 菜单栏菜单 | 启停录音、打开窗口、切换登录项、退出 | macOS 菜单栏图标 |
| 首次设置窗口 | 引导用户完成权限、ASR 凭证、登录项、快捷键测试 | 首次启动自动弹出；菜单栏“打开首次设置” |
| 设置窗口 | 展示状态、凭证、权限、快捷键、音频、输入、HUD、隐私、录音诊断 | 菜单栏“打开设置”或“检查权限” |
| 诊断窗口 | 展示分类诊断事件，并导出诊断 JSON | 菜单栏“打开诊断” |
| HUD 灵动岛胶囊 | 录音、转写、插入、成功、错误状态反馈 | 全局快捷键或菜单栏录音动作触发 |

当前没有自定义主菜单、偏好设置菜单命令或 Dock 菜单；显式 GUI 菜单只有 `MenuBarExtra` 菜单。

## 2. 菜单栏状态与图标

菜单栏图标优先读取 bundle 里的 `VocoMenuBarIconTemplate`，可接受 `svg`、`pdf`、`png`，并设置为 template image。资源缺失时使用当前状态对应的 SF Symbol fallback。

菜单栏图标的可访问性标签和 hover help 文案都是：

```text
Voco <当前状态标题>
```

当前状态标题与 fallback 图标如下：

| Runtime 状态 | 菜单栏标题 | fallback system image | 说明 |
| --- | --- | --- | --- |
| `launching` | 启动中 | `hourglass` | App 初始化中 |
| `needsOnboarding` | 需要设置 | `exclamationmark.triangle` | 首次设置未完成 |
| `ready` | 就绪 | `waveform` | 可开始录音 |
| `recording` | 录音中 | `record.circle` | 正在采集音频 |
| `transcribing` | 转写中 | `ellipsis.bubble` | 正在等待 ASR 结果 |
| `injecting` | 插入中 | `text.cursor` | 正在把转写文本输入到当前 App |
| `permissionNeeded` | 需要权限 | `lock.shield` | 必需权限缺失 |
| `providerOffline` | 服务离线 | `wifi.slash` | ASR provider 连接或服务异常 |
| `error` | 错误 | `xmark.octagon` | 最近动作失败 |

## 3. 菜单栏菜单逐项说明

| 顺序 | 菜单项 | 当前启用条件 | 点击后的行为 | 设计备注 |
| --- | --- | --- | --- | --- |
| 1 | `开始录音` / `停止录音` | `ready` 或 `recording` | `ready` 时启动录音；`recording` 时停止录音并进入转写/输入流程 | label 由 `coordinator.isRecording` 决定；非录音状态但不可用时显示“开始录音”且置灰 |
| 2 | 分隔线 | - | 分隔录音动作和窗口入口 | - |
| 3 | `打开首次设置` | 始终可点 | 刷新 onboarding 状态并打开“Voco 首次设置”窗口 | 即使已完成首次设置，也允许重新打开 |
| 4 | `打开设置` | 始终可点 | 刷新设置相关状态并打开“Voco 设置”窗口 | 会刷新旧版启动项、凭证、权限 |
| 5 | `检查权限` | 始终可点 | 当前行为与“打开设置”一致：刷新状态并打开设置窗口 | 当前没有 deep link 到权限区块，适合在重设计中改成聚焦权限页 |
| 6 | `打开诊断` | 始终可点 | 刷新设置相关状态并打开“Voco 诊断”窗口 | 诊断窗口可导出 JSON 诊断包 |
| 7 | `登录时启动` | Toggle 始终显示，实际结果受安装位置和系统状态影响 | 调用登录项 provider 开启/关闭登录时启动 | 如果从磁盘映像运行，开启会失败并提示移动到 `/Applications` |
| 8 | 分隔线 | - | 分隔常用动作和退出 | - |
| 9 | `退出 Voco` | 始终可点 | 调用 `NSApp.terminate(nil)` 退出 App | - |

## 4. 首次设置窗口

窗口标题：`Voco 首次设置`

窗口尺寸：创建时 `760 x 680`，内容最小 `640 x 560`，可关闭、最小化、缩放。

窗口目的：让用户完成必要权限、ASR 凭证和快捷键测试。完成后 Voco 留在菜单栏中等待全局快捷键。

### 4.1 顶部区域

| 元素 | 文案/行为 |
| --- | --- |
| 标题 | `Voco 首次设置` |
| 说明 | `完成必要权限、ASR 凭证和快捷键测试后，Voco 会留在菜单栏中等待全局快捷键。` |
| 安装位置警告 | 如果检测到 App 从 `/Volumes/...` 等磁盘映像运行，显示“从磁盘映像运行”警告，提示移动到 `/Applications` 后再开启登录时启动 |

### 4.2 Step 卡片通用结构

每个步骤都是一个圆角卡片，包含：

| 元素 | 说明 |
| --- | --- |
| 图标 | 每个步骤对应一个 SF Symbol |
| 标题 | 步骤名称 |
| 状态 label | `已完成`、`需要设置`、`需要处理`、`已跳过` |
| 必需/可选 | 必需步骤会阻止“完成首次设置”；可选步骤可以跳过 |
| 详情 | 解释这个步骤为什么需要 |
| 状态详情 | 当前状态的具体原因 |
| 操作区 | 根据步骤显示按钮、Toggle、Picker、输入框 |

### 4.3 当前实际显示的首次设置步骤

首次设置窗口已移除，当前通过设置窗口完成权限、凭证和录音链路检查。

| 步骤 | 必需 | 当前控件 | 完成条件 |
| --- | --- | --- | --- |
| 麦克风权限 | 是 | `请求麦克风权限`、`打开麦克风设置` | macOS 麦克风权限为 `已允许` |
| 辅助功能权限 | 是 | `重新检查权限`、`打开辅助功能设置` | macOS 辅助功能权限为 `已允许` |
| ASR 凭证 | 是 | Doubao 凭证模式 Picker、凭证输入框、`保存到 Keychain`、`清除凭证` | Keychain 中保存有效 Doubao 凭证 |
| 登录时启动 | 否 | `登录时启动` Toggle、`暂时跳过` | 开启成功，或用户选择跳过 |
| 快捷键测试 | 是 | 显示快捷键 `Right Command`，按钮 `我已测试快捷键` | 辅助功能权限已允许、监听状态为 `监听中`，并点击“我已测试快捷键” |

### 4.4 ASR 凭证模式

首次设置和设置窗口共用同一套 Doubao 凭证逻辑。

| 模式 | UI 文案 | 输入项 | 保存后的请求头 |
| --- | --- | --- | --- |
| 新网关 API Key | `新网关 API Key` | `Doubao API Key` SecureField | `Authorization: Bearer`，连接 `wss://ai-gateway.vei.volces.com/v1/realtime?model=bigmodel` |
| 旧控制台 App ID + Token | `旧控制台 App ID + Token` | `Doubao App ID` TextField、`Doubao Access Token` SecureField | `X-Api-App-Key`、`X-Api-Access-Key`，连接 OpenSpeech 时先使用 `volc.seedasr.sauc.duration`，握手拒绝后自动回退 `volc.bigasr.sauc.duration` |

保存按钮只在对应模式的必填字段非空时启用。保存位置是 Keychain。当前 native provider 不再从旧配置文件读取 TOKEN。

### 4.5 完成按钮

底部按钮：`完成首次设置`

启用条件：所有必需步骤完成，所有可选步骤完成或跳过。

点击行为：

1. 再次刷新 onboarding 状态。
2. 如果未完成，显示错误 `首次设置尚未完成。`
3. 如果完成，持久化 `hasCompletedOnboarding = true`，根据权限状态进入 `ready` 或 `permissionNeeded`，关闭首次设置窗口。

## 5. 设置窗口

窗口标题：`Voco 设置`

窗口尺寸：创建时 `760 x 520`，detail 内容最小 `480 x 360`，可关闭、最小化、缩放。

当前结构是 `NavigationSplitView`：

| 区域 | 当前行为 |
| --- | --- |
| 左侧列表 | 展示全部 `SettingsSection`，有图标、标题、摘要 |
| 右侧详情 | 一个纵向 `ScrollView`，固定显示所有设置内容 |

重要现状：左侧列表当前只是信息架构提示，没有绑定 selection，也不会切换右侧内容。这是设置界面“太简单”的主要原因之一。

### 5.1 左侧设置菜单/栏目

| 栏目 | 图标 | 摘要 |
| --- | --- | --- |
| 通用 | `gearshape` | 启动和基础状态 |
| 快捷键 | `keyboard` | 快捷键监听和触发模式 |
| 音频 | `mic` | 输入设备、电平和采样率 |
| 转写 | `text.bubble` | ASR provider 和凭证 |
| 输入 | `text.cursor` | 插入策略和聚焦 App 诊断 |
| HUD | `rectangle.inset.filled` | 位置、刘海模式和转写预览 |
| 隐私 | `lock` | Keychain、转写保留和日志策略 |
| 诊断 | `stethoscope` | 最近录音、转写和错误 |

### 5.2 右侧顶部状态

| 元素 | 说明 |
| --- | --- |
| 页面标题 | `Voco 设置` |
| 状态行 | 显示当前菜单栏状态图标和状态标题 |
| 最近错误 | 如果 `lastErrorMessage` 存在，用红色显示在状态行旁 |
| 当前版本说明 | `当前版本包含 native macOS app shell：菜单栏状态、设置窗口、登录项开关和全局快捷键入口。` |

### 5.3 旧版启动项提示

仅当检测到旧版 LaunchAgent 或移除失败时显示。

| 控件 | 行为 |
| --- | --- |
| `重新检查` | 刷新旧版启动项检测状态 |
| `移除旧版启动项` | 移除用户目录下的 `~/Library/LaunchAgents/com.voco.daemon.plist` |

移除过程不使用 `sudo`，不触碰系统级 LaunchAgents。

### 5.4 登录时启动

| 元素 | 当前功能 |
| --- | --- |
| `登录时启动` Toggle | 开启/关闭 macOS 登录项 |
| 状态 label | `已关闭`、`已开启`、`需要批准`、`不可用`、`出错` |
| 详情文案 | 解释当前登录项状态 |
| 额外提示 | `requiresApproval` 时提示去 `System Settings -> General -> Login Items` 批准 Voco |

如果 App 从磁盘映像运行，开启登录项会进入不可用/失败路径，并提示先移动到 `/Applications`。

### 5.5 快捷键

| 元素 | 当前功能 |
| --- | --- |
| 状态 label | `未监听`、`监听中`、`需要权限`、`出错` |
| 当前绑定 | `Right Command` |
| 当前模式 | `切换录音` |
| 详情 | 展示监听状态说明，例如 `Voco 正在监听全局快捷键。` |

当前设置窗口没有快捷键编辑器，也没有模式切换控件。底层模型支持 `toggle` 和 `pressAndHold` 两种模式，但当前 coordinator 默认使用 `toggle`。

### 5.6 音频

| 行 | 当前显示 |
| --- | --- |
| 输入设备 | `系统默认输入`；说明真实设备选择会在后续偏好设置中接入 |
| 电平 | 没有近期录音时显示 `无近期采样`；录音后显示峰值，过低或接近削波会提示 |
| 采样率 | 没有近期录音时显示目标转写采样率 `16,000 Hz`；录音后检查是否匹配目标采样率 |

当前没有设备选择下拉框、输入增益、噪声门或实时电平条。

### 5.7 转写

| 元素 | 当前功能 |
| --- | --- |
| provider 状态 | 显示 `ready`、`notConfigured`、`authenticationRequired`、`offline`、`failed` 的标题和详情 |
| 凭证状态 | 显示是否保存 Doubao 凭证，以及脱敏后的凭证摘要 |
| Doubao 凭证模式 Picker | 在“新网关 API Key”和“旧控制台 App ID + Token”之间切换 |
| 凭证输入框 | 根据模式显示 API Key，或 App ID + Access Token |
| `保存到 Keychain` | 保存当前模式的凭证 |
| `清除凭证` | 删除 Keychain 中的 Doubao 凭证 |
| 服务状态参数 | 随凭证模式显示 Realtime 网关 Model，或 OpenSpeech Resource ID 自动重试队列 |

当前没有 provider 选择列表，只有 Doubao。也没有“测试连接”按钮；用户只能通过一次真实录音确认 ASR 是否可用。

### 5.8 输入

| 行 | 当前显示 |
| --- | --- |
| 插入策略 | 没有近期插入时显示 `等待插入`；插入后显示实际策略 |
| 聚焦 App | 没有近期目标时显示 `无近期目标`；插入后显示最近目标 App 或错误原因 |

底层支持的文本输入策略：

| 策略 | 说明 |
| --- | --- |
| `辅助功能直接插入` | 通过 Accessibility 设置选中文本属性 |
| `Unicode 事件` | 逐字符发送 Unicode keyboard event |
| `剪贴板回退` | 写入剪贴板、发送 Command+V、再恢复剪贴板 |
| `不可用` | 当前没有可用插入方式 |
| `空文本跳过` | final transcript 为空时不插入 |

当前优先策略是剪贴板回退，其次 Unicode 事件，再其次辅助功能直接插入。

### 5.9 HUD

设置窗口里的 HUD 区域目前只展示状态，不提供可调控件。

| 行 | 当前显示 |
| --- | --- |
| 位置 | `顶部居中`，HUD 固定显示在屏幕顶部中央 |
| 刘海模式 | `刘海避让`，带刘海屏幕贴近 Dynamic Island 区域 |
| 转写预览 | `显示转写预览`，最多显示 80 个字符 |

当前没有 HUD 预览、位置切换、尺寸调节、动画速度、颜色主题或关闭预览的 UI。

### 5.10 隐私

| 行 | 当前显示 |
| --- | --- |
| Keychain | 显示凭证是否保存，或 Keychain 访问错误 |
| 转写保留 | `不保留转写文本`，仅用于本次插入和当前运行时诊断 |
| 日志策略 | `日志默认脱敏`，不记录完整 API Key 或完整转写正文 |

当前没有更细的隐私开关，比如“允许保存最近 N 条转写”或“清除运行时诊断”。

### 5.11 录音诊断

该区块是条件显示：只有最近有音频、转写、输入或错误时才出现。

| 行 | 当前显示 |
| --- | --- |
| 音频 | 时长、采样率、样本数、peak |
| 转写 | provider 名称、final text 字符数 |
| 输入 | 目标 App、插入策略、插入详情 |
| 错误 | 最近错误消息 |

当前没有“复制诊断摘要”或“清空最近诊断”按钮。

### 5.12 权限

| 权限 | 必需 | 说明 | 当前动作 |
| --- | --- | --- | --- |
| 麦克风 | 是 | 用于录制语音并生成转写文本 | `请求麦克风权限`、`打开麦克风设置` |
| 辅助功能 | 是 | 用于把转写文本插入当前正在输入的 App，也用于全局快捷键监听 | `打开辅助功能设置` |

权限区顶部有 `重新检查` 按钮。权限状态包括 `未决定`、`已允许`、`已拒绝`、`受限制`、`未知`。

## 6. 诊断窗口

窗口标题：`Voco 诊断`

窗口尺寸：创建时 `820 x 560`，内容最小 `640 x 420`，可关闭、最小化、缩放。

### 6.1 诊断窗口顶部

| 元素 | 当前功能 |
| --- | --- |
| 标题 | `Voco 诊断` |
| overall severity | `正常`、`需要注意`、`错误`，由所有诊断事件的最高等级决定 |
| App 状态 | 当前菜单栏状态标题 |
| 生成时间 | 本地格式化日期时间 |
| `导出诊断包` | 写入临时目录 JSON 文件，并显示完整路径 |

导出的 JSON 会脱敏 secret 和完整转写正文。目标文件已存在时会报错，不覆盖旧文件。

### 6.2 诊断分类

诊断窗口按分类显示非空事件。

| 分类 | 图标 | 当前事件来源 |
| --- | --- | --- |
| 权限 | `lock.shield` | 麦克风、辅助功能的状态 |
| 安装位置 | `externaldrive` | 仅从磁盘映像运行时显示警告 |
| 旧版迁移 | `arrow.triangle.2.circlepath` | 检测到旧版 LaunchAgent 或移除失败时显示 |
| 音频 | `waveform` | 最近音频指标，或无近期采样 |
| 快捷键 | `keyboard` | 快捷键监听状态、绑定、模式 |
| ASR | `text.bubble` | provider 状态、凭证状态、最近转写统计 |
| 输入 | `text.cursor` | 最近文本插入策略和目标 App |
| 最近失败 | `exclamationmark.triangle` | 最近错误消息，或无近期失败 |

## 7. HUD 灵动岛胶囊

HUD 是一个独立 overlay panel，贴近屏幕顶部中央和刘海区域。

### 7.1 尺寸和位置

| 状态 | 宽度 | 高度 | 说明 |
| --- | --- | --- | --- |
| 折叠 | `320` | `44` | 没有可显示转写文本时 |
| 展开 | `520` | `86` | 有可显示转写文本时 |
| panel 总尺寸 | `568 x 134` | - | 包含 shadow padding |

位置计算：以 visible frame 中心为水平中心，顶部贴近 screen frame 顶部，当前 `notchTopOffset = -1`。

### 7.2 视觉结构

| 区域 | 当前内容 |
| --- | --- |
| 背景 | 黑色连续圆角胶囊，阴影半径 `12` |
| 第一行左侧 | 状态文字。正常为 `语音输入`，错误为 `输入失败` |
| 第一行右侧 | 7 条迷你波形柱，30fps 刷新 |
| 第二行 | 转写预览文本，最多 2 行 |

当前 `HUDSnapshot` 里有 `title`、`detail`、`systemImage`，但 `HUDOverlayView` 实际视觉只使用 `phase` 和 `transcriptPreview`。因此录音、转写、插入、成功阶段第一行都显示 `语音输入`，错误阶段显示 `输入失败`。

### 7.3 HUD 显示规则

| App 状态 | HUD phase | 当前显示 |
| --- | --- | --- |
| `launching` | hidden | 不显示 |
| `needsOnboarding` | hidden | 不显示 |
| `permissionNeeded` | hidden | 不显示 |
| `ready` 且没有成功插入结果 | hidden | 不显示 |
| `recording` | recording | 显示胶囊、波形、可能显示 partial 文本 |
| `transcribing` | transcribing | 显示胶囊、波形、可能显示 partial/final 文本 |
| `injecting` | injecting | 显示胶囊、波形、显示转写文本 |
| `ready` 且最近成功插入 | success | 显示成功后的转写预览，`1.4s` 后自动隐藏 |
| `providerOffline` | error | 显示红色 `输入失败`，不显示转写文本 |
| `error` | error | 显示红色 `输入失败`，不显示转写文本 |

转写预览来源：优先 final text；如果 final text 为空，则使用最后一个 partial。文本去掉首尾空白后，最多保留 80 个字符。

## 8. 语音输入主流程

当前核心用户路径如下：

1. 用户按 `Right Command`，或从菜单栏点 `开始录音`。
2. App 必须处于 `ready`，否则不会开始录音。
3. 开始录音后清空上次音频、转写、输入和错误，HUD 显示录音状态。
4. 如果 provider 支持实时流式转写，录音期间会发布 partial，并在 HUD 第二行显示。
5. 用户再次按快捷键，或菜单栏点 `停止录音`。
6. App 停止采集音频，进入 `transcribing`。
7. 音频少于 `0.25s`、样本为空或 peak 低于 `0.003` 时，视为空文本并跳过输入。
8. ASR 返回 final text 后，App 进入输入流程。
9. 输入成功后回到 `ready`，HUD 成功态自动隐藏。
10. ASR 或输入失败时进入 `providerOffline` 或 `error`，错误展示在设置/诊断/HUD 中。

## 9. 当前 GUI 的主要设计欠缺

这些是给下一步原型重设计用的明确问题点。

| 问题 | 影响 |
| --- | --- |
| 设置窗口左侧菜单不能切换内容 | 用户以为是导航，但右侧永远是长滚动页 |
| 设置内容全部堆成浅灰卡片 | 层级弱，重点动作不突出 |
| “检查权限”菜单只打开设置窗口 | 没有把用户带到权限问题本身 |
| 转写凭证没有测试连接动作 | 用户保存凭证后不知道是否可用 |
| HUD 设置只有说明没有可控项 | 用户无法预览或调节顶部刘海胶囊 |
| 音频设置只有诊断，没有输入设备选择 | 看起来像半成品设置页 |
| 快捷键不能编辑，也不能切换按住/切换模式 | 与用户对语音输入工具的预期不一致 |
| 诊断混在设置里又有独立诊断窗口 | 信息架构重复 |
| 首次设置和设置窗口重复凭证表单 | 维护和体验都重复 |
| 错误恢复路径不集中 | 用户遇到 ASR、权限、输入失败时要自己找对应位置 |
| HUD visual 没有使用 snapshot title/detail | 录音、转写、插入阶段的状态语义没有完整呈现 |

## 10. 给 `prototype-design` 的重设计输入

下一步原型不应该做营销页，而应该做一个真正可操作的 macOS 设置体验。建议至少覆盖 3 个设计变体，每个变体都包含设置主界面，并能切换到关键子页。

### 10.1 必须覆盖的屏幕

| 屏幕 | 需要展示的内容 |
| --- | --- |
| 菜单栏菜单 | 当前状态、开始/停止录音、设置、诊断、登录项、退出 |
| 设置总览 | 当前可用性、最近错误、下一步建议、一次测试录音入口 |
| 权限页 | 麦克风、辅助功能的状态、解释和修复动作 |
| 转写页 | Doubao 新旧凭证模式、Keychain 状态、测试连接、清除凭证 |
| 快捷键与输入页 | Right Command、切换/按住模式、输入策略、最近目标 App |
| 音频页 | 默认麦克风、采样率、峰值、电平反馈、未来设备选择位置 |
| HUD 页 | 顶部刘海胶囊预览、转写预览开关、位置/动画/尺寸调节位 |
| 诊断页 | 最近一轮录音全链路、错误解释、导出诊断包 |
| 首次设置流程 | 已删除；首次启动直接进入设置控制台 |

### 10.2 建议的信息架构

| 一级导航 | 主要内容 |
| --- | --- |
| 总览 | 状态、下一步动作、最近错误、快速测试 |
| 语音输入 | 快捷键、录音、音频、HUD |
| 转写服务 | Doubao provider、凭证模式、连接测试 |
| 权限与输入 | macOS 权限、文本插入策略、目标 App 诊断 |
| 诊断与隐私 | 最近运行记录、导出、Keychain、日志脱敏、转写保留 |

### 10.3 设计约束

| 约束 | 说明 |
| --- | --- |
| macOS 原生感 | 应该像生产力工具设置页，不做 landing page |
| 操作优先 | 每个错误状态都要有明确下一步按钮 |
| 权限解释要轻 | 只解释麦克风和辅助功能两个实际需要的权限 |
| 凭证模式要明确 | 新网关 API Key 走 Realtime 网关；旧控制台 App ID + Token 走 OpenSpeech，并在旧资源握手被拒时自动重试兼容资源 |
| HUD 要可预览 | 设置页里要能看到当前顶部刘海胶囊效果 |
| 诊断要围绕一次录音链路 | Command -> 录音 -> 识别 -> 展示 -> 插入输入框 |
| 不读配置文件 TOKEN | 凭证来源只通过设置界面进入 Keychain |

## 11. 代码来源

本文档基于以下当前源码盘点：

| 功能 | 主要文件 |
| --- | --- |
| App shell / 菜单栏 | `native/Sources/VocoApp/VocoNativeApp.swift` |
| 菜单栏图标 | `native/Sources/VocoApp/MenuBarIcon.swift` |
| 首次设置窗口 | `native/Sources/VocoApp/OnboardingView.swift`、`native/Sources/VocoAppCore/OnboardingModels.swift` |
| 设置窗口 | `native/Sources/VocoApp/SettingsView.swift`、`native/Sources/VocoAppCore/SettingsSection.swift` |
| 诊断窗口 | `native/Sources/VocoApp/DiagnosticsView.swift`、`native/Sources/VocoAppCore/DiagnosticsModels.swift` |
| HUD 胶囊 | `native/Sources/VocoApp/HUDOverlayView.swift`、`native/Sources/VocoApp/HUDOverlayChrome.swift`、`native/Sources/VocoAppCore/HUDModels.swift` |
| 权限 | `native/Sources/VocoApp/MacPermissionProvider.swift`、`native/Sources/VocoAppCore/PermissionModels.swift` |
| 快捷键 | `native/Sources/VocoApp/MacHotkeyProvider.swift`、`native/Sources/VocoAppCore/HotkeyModels.swift` |
| Doubao 凭证 | `native/Sources/VocoAppCore/TranscriptionCredentialModels.swift`、`native/Sources/VocoApp/MacKeychainCredentialStore.swift` |
| 录音/转写/输入流程 | `native/Sources/VocoAppCore/AppCoordinator.swift`、`native/Sources/VocoAppCore/RecordingWorkflowModels.swift`、`native/Sources/VocoAppCore/TextInjectionModels.swift` |
