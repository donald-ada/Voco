---
title: Voco Notch Live Transcript Island
date: 2026-05-05
scope: Add a top-center Dynamic Island style live transcript HUD for streaming ASR partials
---

# Voco 刘海实时字幕灵动岛设计文档

## 1. Problem

Voco 现在的 HUD 只能展示录音状态、波形和转写状态，不能实时展示用户正在说的话。用户希望在 Mac 屏幕顶部中间、接近刘海的位置增加一个灵动岛，用于展示 Doubao 流式 ASR 的实时 partial transcript。

现有 Doubao 链路已经使用 `bigmodel_async` 双向流式接口，并且 `voco-asr` 已经能从服务端响应中生成 `Partial { text, stable_prefix_len }`。当前缺口在 Voco 内部事件链路：`RecordingSession` 收到 partial 后只更新 session payload，不会把 partial 发送给 Swift HUD。

## 2. External Capability

火山引擎大模型流式语音识别文档说明该接口支持流式识别场景，能够在说话过程中持续返回识别结果。`bigmodel_async` 优化版的行为是当结果发生变化时返回新数据包。

参考文档：

- https://www.volcengine.com/docs/6561/1354869?lang=zh
- https://www.volcengine.com/docs/6561/1354871?lang=zh

设计结论：不用新增 ASR provider，也不用改 Doubao 协议层；应复用现有 `Partial`，把 partial 转成 HUD event。

## 3. Goals

- 新增一个顶部中间、贴近 Mac 刘海/菜单栏区域的 Dynamic Island style transcript island。
- 选择 visual option B：识别到文字后展开为两行字幕岛。
- 录音开始时先显示紧凑 island：黄色 `语音输入` + 绿色细 waveform。
- 收到 partial transcript 后展开 island，展示最近实时识别文字。
- 稳定文本使用暖白色，正在变化的 partial suffix 使用绿色。
- 录音停止、注入完成或失败后，顶部 island 按现有 HUD 生命周期隐藏或进入错误态。
- 保留现有底部 HUD，不把本功能做成底部 HUD 的替代品。

## 4. Non-Goals

- 不做完整历史字幕记录。
- 不新增设置 UI。
- 不新增 ASR provider。
- 不改 hotkey 行为。
- 不改变最终文本注入逻辑。
- 不把长文本撑成大窗口；超过两行只显示最近内容或尾部内容。
- 不在 Doubao 没有返回 partial 时伪造实时字幕。

## 5. UX Design

采用 option B：展开字幕岛。

```text
位置：屏幕顶部中间，贴近刘海/菜单栏。
空闲录音态：黑色小胶囊，左侧黄色“语音输入”，右侧绿色细 waveform。
实时字幕态：胶囊向下展开到两行字幕高度。
稳定文本：暖白色。
正在变化文本：绿色。
隐藏：录音结束并完成注入后隐藏。
```

建议尺寸：

```text
Collapsed width:    220-260 px
Collapsed height:   42-46 px
Expanded width:     480-560 px
Expanded height:    76-92 px
Top offset:         visibleFrame.maxY - islandHeight - 6 to 12 px
Text lines:         max 2
Transcript font:    16-18 px semibold
Status font:        13-14 px semibold
```

视觉规则：

- 黑色 island 必须完全透明背景外框，不能出现矩形残影。
- 边缘只保留很弱的亮边和贴近阴影，避免像浮动卡片。
- 展开动画使用宽高、opacity、scale 的短动画，首帧就开始动。
- 绿色 waveform 继续用于表达“正在听”，绿色 transcript suffix 用于表达“正在变化”。

## 6. Data Flow

当前链路：

```text
Doubao WS response
  -> DoubaoBackend::ingest_response
  -> AsrBackend::feed returns Option<Partial>
  -> RecordingSession::record_partial
  -> final RecordingPayload
```

新增链路：

```text
RecordingSession::record_partial
  -> HudEvent::Transcript { text, stable_prefix_len }
  -> voco-hud stdin JSONL
  -> Swift HudEvent.transcript
  -> HudModel.transcriptText + stablePrefixLen
  -> top transcript island render
```

关键点：

- `include_partials` 只控制最终 IPC response 是否包含 partial history；不应阻止 HUD 实时展示 partial。
- hotkey 录音路径当前传入 `include_partials=false`，但仍应把 partial 发送给 HUD。
- transcript event 只承载当前完整 partial 文本和 stable prefix 长度，不传历史数组。

## 7. Rust Design

`crates/voco-daemon/src/hud.rs`:

- 新增 `HudEvent::Transcript { text: String, stable_prefix_len: usize }`。
- 新增 constructor，例如 `HudEvent::transcript(text, stable_prefix_len)`。
- JSONL shape:

```json
{"type":"transcript","text":"把这个函数改成异步","stable_prefix_len":18}
```

`crates/voco-daemon/src/session.rs`:

- `run_with_hud` 需要让 `record_partial` 能访问 HUD sink。
- `record_partial` 在收到 partial 时立即发送 transcript HUD event。
- HUD send 失败不应中断录音，但必须保留现有 fail-loud style：记录 warning，不 silent catch。
- amplitude forwarder 保持不变。

`crates/voco-daemon/src/orchestrator.rs`:

- hotkey recording start/stop 流程保持不变。
- 现有 state event 顺序保持：`recording -> transcribing -> hidden/error`。
- transcript event 插入在 recording 期间，不新增 daemon state。

## 8. Swift HUD Design

`hud/Sources/VocoHUDCore/HudEvent.swift`:

- 新增 `case transcript(text: String, stablePrefixLen: Int)`。
- decoder 支持 `type = "transcript"` 和 `stable_prefix_len`。

`hud/Sources/VocoHUDCore/HudModel.swift`:

- 新增 `transcriptText` 和 `stablePrefixLen`。
- 收到 `transcript` 时更新文本，不改变 `presentationEpoch`。
- 收到 `.state(.hidden)` 时清空 transcript。
- 收到 `.state(.error)` 时可保留 message，但 transcript 应停止更新或在隐藏时清空。

`hud/Sources/VocoHUDCore/CapsuleView.swift`:

- 将现有 capsule 扩展为顶部 transcript island 的可复用视图，或者新增 `TranscriptIslandView`。
- collapsed state：无 transcript 时显示 `语音输入` + waveform。
- expanded state：有 transcript 时显示标题行和两行 transcript。
- stable prefix 使用暖白色，suffix 使用绿色。
- Swift 的 `stablePrefixLen` 当前是 UTF-8 byte length；渲染前必须安全地映射到 Swift `String.Index`。不能直接当作 character count。

`hud/Sources/VocoHUD/main.swift`:

- 新增顶部 panel 或将现有 panel 定位从底部改为顶部并支持 expanded size。
- 本设计倾向新增顶部 transcript panel，保留现有底部 HUD 行为，降低回归风险。
- 顶部 panel 使用 `.nonactivatingPanel`、`isOpaque=false`、`backgroundColor=.clear`、`hasShadow=false`。
- 顶部定位基于 `screen.visibleFrame`，水平居中，贴近 `visibleFrame.maxY`。

## 9. Error Handling

- Doubao 没有 partial：顶部 island 只显示 collapsed listening 状态，不显示假字幕。
- HUD helper pipe broken：沿用现有 respawn/retry 逻辑；transcript event 和 amplitude event 一样可被丢弃，但要有 warning。
- partial 文本过长：UI 截断到两行，不影响最终注入。
- stable prefix byte index 非法或落在 UTF-8 中间：Swift fallback 为全量 live text 或最近合法 boundary，不能 crash。
- 多屏：初版只定位到 `NSScreen.main`；没有 main screen 时 fallback 到 first screen。

## 10. Testing Plan

Rust tests:

- `HudEvent::transcript` JSON serialization shape。
- `RecordingSession` 收到 partial 时即使 `include_partials=false` 也会发送 transcript HUD event。
- HUD send error 不会导致 recording session failed，并产生 warning 路径。
- 现有 amplitude/state tests 保持通过。

Swift tests:

- `HudEvent.decodeLine` 支持 transcript event。
- `HudModel` 收到 transcript 后更新文本，不重启 entry animation。
- `.state(.hidden)` 清空 transcript。
- UTF-8 stable prefix splitting 覆盖中文字符串。
- layout tokens 覆盖顶部 expanded/collapsed 尺寸。

Full verification:

```bash
cd hud && swift test && swift build
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Manual verification:

```bash
./packaging/build_app_bundle.sh
./target/debug/voco app install --app-bundle ./target/Voco.app
/Users/zhangxiaolong/Applications/Voco.app/Contents/MacOS/voco daemon restart
```

Then press Right Command and speak:

- 顶部中间出现贴近刘海的 collapsed island。
- 说话时 partial transcript 实时出现并展开为两行。
- 稳定文本暖白，正在变化 suffix 绿色。
- 底部 HUD 仍显示录音波形。
- 说长句时 HUD 不自动消失，字幕不会撑破两行。
- 停止录音后文本正常注入，两个 HUD 都隐藏。

## 11. Scope Risks

- 当前用户机器是否有实体刘海不可从代码可靠判断；初版使用顶部居中定位，不读取硬件 notch geometry。
- SwiftUI rich text 按 UTF-8 stable prefix 分段需要谨慎处理中文边界。
- 顶部 panel 和底部 panel 并存时要避免两个 panel 生命周期互相影响。
- Doubao partial 频率可能较高；Swift model 更新应轻量，不为每个 partial 重启动画。
