---
title: Voco — 终端可控的本地/云端 macOS 语音输入工具
date: 2026-05-01
status: design-approved-pending-final-review
target_platform: macOS (Apple Silicon, macOS 14+)
language: Rust (主) + Swift (HUD)
---

# Voco — 设计文档

## 0. 一句话定位

Voco 是一个常驻 macOS 后台、由终端 CLI 控制的语音输入工具。按一次全局热键开始录音，再按一次结束；本地或云端 ASR 流式识别后，文本被自动注入到当前焦点 app 的光标位置。对标产品：闪电说、Typeless。

## 1. 决策摘要

| 维度 | 决策 | 备注 |
|---|---|---|
| 形态 | STT 语音输入 | 不是 TTS |
| 平台 | macOS 14+，Apple Silicon | 暂不跨平台 |
| 主语言 | Rust | + Swift 仅写 HUD |
| 本地 ASR | sherpa-onnx + Paraformer-zh 流式 | **MVP 不实装**，trait 留接口 |
| 云端 ASR | 豆包 / 火山引擎流式 WebSocket | MVP 主后端 |
| 后端切换 | `AsrBackend` trait + 配置文件 | 工厂函数构造 |
| 运行模型 | 守护进程 .app bundle（LSUIElement=true）+ CLI 控制 | 类比 brew services / Hammerspoon |
| 热键 | 切换式：按一下开始，再按一下结束 | 默认 Right Command，可配 |
| 文本输出 | CGEvent 注入光标，失败降级到剪贴板 | 含 secure input 自动降级 |
| HUD | SwiftUI 胶囊（麦克风+声波+黄点+毛玻璃） | 屏幕底部居中，不抢焦点 |
| HUD 实现 | swift-bridge 与 Rust 通信 | 单进程 .app bundle |
| IPC | Unix domain socket + length-prefixed JSON | cli ↔ daemon |
| 配置 | `voco config` 交互式向导（inquire） | 不只是打开编辑器 |

---

## 2. 整体架构与代码组织

### 2.1 Cargo workspace 结构

```
voco/
├── Cargo.toml                      # workspace 根
├── crates/
│   ├── voco-cli/                   # bin: voco - 终端入口
│   ├── voco-daemon/                # bin: voco-daemon - 守护进程主体
│   ├── voco-config/                # lib: Config schema + load/save/validate
│   ├── voco-asr/                   # lib: AsrBackend trait + 实现
│   │   ├── doubao.rs               # 豆包 WebSocket 流式
│   │   └── sherpa.rs               # sherpa-onnx 本地流式（MVP 不实装）
│   ├── voco-audio/                 # lib: 麦克风采集 (cpal) + RMS amplitude
│   ├── voco-hotkey/                # lib: CGEventTap 全局热键
│   ├── voco-injector/              # lib: CGEvent 文本注入 + 剪贴板降级
│   └── voco-ipc/                   # lib: socket 协议 + 消息定义
├── hud/                            # Swift Package: SwiftUI 胶囊
│   ├── Package.swift
│   └── Sources/VocoHUD/Capsule.swift
├── bridge/                         # swift-bridge 自动生成 + 手写胶水
├── packaging/
│   └── Voco.app/                   # bundle 模板（Info.plist + Entitlements）
└── docs/superpowers/specs/2026-05-01-voco-design.md
```

**为什么拆这么多 crate**：voco-asr / voco-audio / voco-injector 各自有独立的副作用边界（网络、麦克风、键盘事件）。拆开后单元测试可以 mock trait，daemon crate 本身就是"纤薄的编排层"，不会膨胀。

### 2.2 进程拓扑

```
┌────────────────────────────┐         ┌──────────────────────────┐
│ 用户终端                   │         │  Voco.app（常驻）         │
│  $ voco daemon start       │ ──IPC──▶│  ┌─────────────────────┐ │
│  $ voco status             │  UDS    │  │ main thread:        │ │
│  $ voco config edit        │  JSON   │  │  NSApplication      │ │
└────────────────────────────┘         │  │  + SwiftUI HUD      │ │
                                       │  └─────────────────────┘ │
                                       │  ┌─────────────────────┐ │
                                       │  │ tokio runtime:      │ │
                                       │  │  hotkey listener    │ │
                                       │  │  audio capture      │ │
                                       │  │  ASR backend        │ │
                                       │  │  IPC server         │ │
                                       │  │  injector           │ │
                                       │  └─────────────────────┘ │
                                       └──────────────────────────┘
```

进程模型为**单进程**：`Voco.app` 同时运行 GUI 主线程（NSApplication runloop + SwiftUI HUD）和后端逻辑（tokio runtime 在 spawned thread）。Info.plist 设 `LSUIElement=true`，无 dock 图标、无 menu bar。

### 2.3 端到端时序（按一次热键的完整生命周期）

```
T=0ms     用户按 Right Command → CGEventTap 捕获
T+1ms     voco-hotkey 通过 channel 通知 daemon orchestrator
T+2ms     启动 cpal 采集 16kHz mono PCM
T+3ms     bridge::hud_show() 调用 → SwiftUI 胶囊淡入（150ms 动画）
T+5ms     PCM 帧（每 20ms 一块）开始进入 ASR backend
          - 云端（MVP 唯一路径）：通过已建立的 WebSocket 推送给豆包
          - 本地（v2 才有）：喂给已加载的 sherpa-onnx OnlineRecognizer
T+200ms   首批 partial 结果返回 → daemon 缓存（v1 不显示）
...       期间 amplitude 持续推给 HUD 驱动声波动画
T=N       用户再按 Right Command → stop_recording 信号
T=N+50    backend 返回 final 文本
T=N+60    injector 用 CGEvent 模拟键盘把文本注入到当前焦点 app
T=N+200   bridge::hud_hide() → 胶囊淡出
```

### 2.4 关键依赖

```toml
# Rust 侧
tokio                 = { version = "1", features = ["full"] }
cpal                  = "0.15"   # macOS 走 CoreAudio
core-foundation       = "0.10"
core-graphics         = "0.24"   # CGEvent / CGEventTap
objc2                 = "0.5"    # NSApplication 启动 + Pasteboard
swift-bridge          = "0.1"
# sherpa-rs           = "0.x"    # v2 才引；MVP 不打这个依赖
tokio-tungstenite     = "0.x"    # 豆包 WebSocket
serde / serde_json    = "1"
clap                  = { version = "4", features = ["derive"] }
inquire               = "0.7"    # 配置向导
crossterm             = "0.27"   # 自定义热键捕获
tracing / tracing-subscriber / tracing-appender
directories           = "5"
thiserror             = "1"
anyhow                = "1"      # 仅 binary 边界使用
```

```swift
// Swift 侧 (Package.swift)
SwiftUI / AppKit  // 系统自带
```

### 2.5 关键路径与权限

- 配置：`~/.config/voco/config.toml`
- socket：`~/Library/Application Support/voco/voco.sock`
- 日志：`~/Library/Logs/voco/voco.log`（rotate by size 10MB × 5）
- 模型（v2 sherpa）：`~/Library/Application Support/voco/models/paraformer-zh/`
- 必需的 macOS 权限：
  - **麦克风**（NSMicrophoneUsageDescription）
  - **辅助功能**（CGEvent 注入 + CGEventTap 全局热键）
  - **输入监控**（部分 macOS 版本下 CGEventTap 需要）

---

## 3. 模块职责与接口契约

### 3.1 voco-config

```rust
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Config {
    pub backend: BackendChoice,           // doubao | sherpa
    pub hotkey: HotkeyConfig,
    pub output: OutputConfig,
    pub hud: HudConfig,
    pub doubao: Option<DoubaoCreds>,
    pub sherpa: Option<SherpaPaths>,
    pub log_level: LogLevel,
    pub recording_max_duration_secs: u32, // 默认 60
}

pub enum BackendChoice { Doubao, Sherpa }

pub struct HotkeyConfig {
    pub keycode: u16,
    pub modifiers: u32,                   // CGEventFlags 位掩码
    pub display_name: String,
}

pub struct OutputConfig {
    pub mode: OutputMode,                 // InjectThenClipboard | ClipboardOnly
    pub trim_trailing_punct: bool,
    pub auto_capitalize: bool,            // v1 不实现，留 false
}

pub struct DoubaoCreds {
    pub app_id: String,
    pub access_token: String,             // v1 chmod 600 toml; v2 上 Keychain
    pub endpoint: String,
    pub model_id: String,
}

pub struct SherpaPaths {
    pub model_dir: PathBuf,
    pub num_threads: usize,
    pub provider: String,                 // "cpu" | "coreml"
}

impl Config {
    pub fn load() -> Result<Self>;        // 缺失返回 default
    pub fn save(&self) -> Result<()>;     // 原子写：temp + rename
    pub fn default() -> Self;
    pub fn validate(&self) -> Result<(), Vec<ValidationError>>;
}
```

**热重载边界**：
- 可热重载：hotkey、output、hud、log_level、creds
- 不可热重载（必须 `voco daemon restart`）：socket path、log path、`backend` 切换在 `state != Idle` 时延迟到下次 Idle

### 3.2 voco-cli

#### 命令面

```
voco                         # 默认提示用法
voco daemon start            # 启动守护进程（launchctl load）
voco daemon stop
voco daemon restart
voco daemon logs [-f]
voco status                  # IPC 查 daemon 状态
voco doctor                  # 自检
voco config                  # 交互式向导（无参数时）
voco config show
voco config set <k> <v>      # 脚本友好
voco config edit             # $EDITOR 兜底
voco config reset            # 二次确认
voco config validate
```

#### 交互式向导（`voco config` 无参数时）

依赖 [`inquire`](https://github.com/mikaelmello/inquire)。流程示例：

```
$ voco config
✓ Loaded config from ~/.config/voco/config.toml

? Default ASR backend
> doubao   (cloud, requires API key)
  sherpa   (local, requires model files)   ← v1 选了会提示 not yet supported

? Hotkey
> Right Command (current)
  Fn
  F19
  Caps Lock
  Custom...

? Text output mode
> Inject to focused app, fall back to clipboard (recommended)
  Clipboard only (manual paste)

? Configure Doubao credentials? [y/N] y
  ? App ID:        ____________
  ? Access Token:  •••••••••••• (masked)
  ? Endpoint:      [press Enter for default]
  ? Model:
  > bigmodel-streaming
    paraformer-realtime-v2

? HUD style
> Capsule (mic icon + waveform + dot, default)
  Minimal (single dot)
  Disabled

─── Summary of changes ───
backend:      sherpa → doubao
hotkey:       Fn → Right Command
doubao:       (added)
─────────────────────────
? Apply these changes? [Y/n] y
✓ Saved to ~/.config/voco/config.toml

? Daemon is running. Restart now to apply? [Y/n] y
✓ Daemon restarted (pid 41823)
```

实现要点：
- `inquire::Select` / `Text` / `Password` / `Confirm` 几个原语
- 自定义热键捕获走 `crossterm::event` raw mode
- 保存前 diff 当前 vs 修改后，给用户 review
- 保存后 IPC 调 `daemon.reload_config`，daemon 内部完成热重载；不可热重载字段提示 `daemon restart`

### 3.3 voco-asr

```rust
#[async_trait]
pub trait AsrBackend: Send + Sync {
    async fn start(&mut self) -> Result<(), AsrError>;       // 建连/加载模型
    async fn feed(&mut self, pcm: &[i16]) -> Result<Option<Partial>, AsrError>;
    async fn stop(&mut self) -> Result<Final, AsrError>;
    fn name(&self) -> &'static str;
}

pub struct Partial { pub text: String, pub stable_prefix_len: usize }
pub struct Final   { pub text: String, pub segments: Vec<Segment> }

pub fn build_backend(cfg: &Config) -> Result<Box<dyn AsrBackend>, AsrError>;
```

#### DoubaoBackend

- 维护单条长持 WebSocket（火山引擎流式 ASR endpoint）
- `start()` 鉴权握手；`feed(pcm)` 按豆包协议帧打包推送（PCM s16le 16kHz mono）；`stop()` 发送 last frame 并取最终结果
- 重连策略：连接断开后下次 `start()` 自动重连；中途断开把已收 partial 当 final 返回

#### SherpaBackend（v2，trait 已留位置）

- 包装 `sherpa_rs::OnlineRecognizer`
- `start()` 加载 ONNX 模型；`feed()` 流式喂帧；`stop()` 取最终 result + reset

### 3.4 voco-audio

```rust
pub struct AudioCapture;

impl AudioCapture {
    /// 启动一次采集会话，返回 PCM 帧流、amplitude 流、停止句柄
    pub fn start() -> Result<(PcmRx, AmplitudeRx, StopHandle), AudioError>;
}

pub type PcmRx = tokio::sync::mpsc::Receiver<Vec<i16>>;        // 20ms 320 samples 一块
pub type AmplitudeRx = tokio::sync::watch::Receiver<f32>;      // RMS [0.0, 1.0]，60Hz
```

实现要点：
- cpal 配置：16kHz / mono / i16
- bounded mpsc(64)：满了 drop 最老帧（避免 ASR 慢拖死采集 real-time thread）
- amplitude：每 320 sample 算 RMS，归一化到 [0, 1]
- v1 无 VAD

### 3.5 voco-hotkey

```rust
pub struct HotkeyManager { /* ... */ }

impl HotkeyManager {
    pub fn install(cfg: &HotkeyConfig, tx: mpsc::Sender<HotkeyEvent>)
        -> Result<Self, HotkeyError>;
    pub fn uninstall(self);
}

pub enum HotkeyEvent { Toggle }
```

实现：`CGEventTap` 注册在专用线程（线程跑 `CFRunLoopRun`），callback 里识别配置的 keycode/modifiers 后 `try_send` 进 mpsc。

### 3.6 voco-injector

```rust
pub struct Injector;

impl Injector {
    pub fn insert(text: &str, mode: OutputMode) -> Result<InjectionOutcome, InjectionError>;
}

pub enum InjectionOutcome {
    Injected,
    ClipboardFallback { reason: String },
}
```

策略链（按 mode `InjectThenClipboard`）：
1. 用 `CGEventKeyboardSetUnicodeString` 一次性 post 整段 unicode（避免逐字符在 secure input 下卡住）
2. 若失败（返回非 0）→ 写 NSPasteboard + 模拟 Cmd+V
3. 若再失败（剪贴板写入异常）→ 仅写剪贴板，HUD 提示 "Copied, paste manually"，日志 warn

### 3.7 voco-ipc

```rust
pub enum Request {
    Status,
    ReloadConfig,
    DaemonShutdown,
    RecordingStart,           // debug 用
    RecordingStop,
}

pub enum Response { Ok, Status(StatusInfo), Error(String) }

pub struct Envelope {
    pub protocol_version: u32,    // = 1
    pub kind: EnvelopeKind,       // request | response
    pub id: Uuid,
    pub payload: serde_json::Value,
}
```

- 协议：length-prefixed (u32 BE) JSON
- Server: `tokio::net::UnixListener` + per-connection task
- Client: 同步 `std::os::unix::net::UnixStream`（CLI 不需要 tokio runtime，启动更快）
- 协议版本不匹配 → cli 提示 `voco daemon restart`

### 3.8 voco-daemon

```rust
enum DaemonState { Idle, Recording, Transcribing, Injecting }

pub struct Orchestrator {
    config: Arc<RwLock<Config>>,
    backend: Box<dyn AsrBackend>,
    audio: Option<AudioCapture>,
    hud_handle: HudHandle,
    state: DaemonState,
    stats: Arc<Mutex<Stats>>,
}
```

主事件循环（tokio runtime 在 spawned thread）：
- `tokio::select!` 监听：hotkey_rx、ipc_rx、shutdown_signal、recording_timeout
- 状态机转移调用 swift-bridge 函数（HUD 函数线程安全，内部 `dispatch_async(main_queue)`）

main thread 上 `NSApplication.run()`（必需）。

### 3.9 hud（Swift Package）

```swift
public final class HudWindow: NSPanel { /* ... */ }
// styleMask: .nonactivatingPanel
// level: .floating
// ignoresMouseEvents: true
// 屏幕底部居中，y = bottomMargin (~120pt)

public struct CapsuleView: View {
    @ObservedObject var model: HudModel    // amplitude / state / isVoiced
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
            WaveformBars(amplitude: model.amplitude)   // 5-7 根竖条
            Circle()
                .fill(.yellow)
                .frame(width: 8, height: 8)
                .opacity(model.isVoiced ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.2), value: model.isVoiced)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

@_cdecl("voco_hud_show")        public func hud_show()
@_cdecl("voco_hud_hide")        public func hud_hide()
@_cdecl("voco_hud_set_amp")     public func hud_set_amp(_ amp: Float)
@_cdecl("voco_hud_set_state")   public func hud_set_state(_ state: Int32)
                                            // 0=idle 1=listening 2=transcribing 3=error
```

`HudModel` 内部 60Hz timer 把 amplitude 平滑到 `@Published` 属性，让 `WaveformBars` 用 `withAnimation` 自然过渡。HUD 是**纯被动 view**，所有状态由 daemon 推送。

---

## 4. 数据流与状态机

### 4.1 主状态机

```
                    ┌─────────────────────────────────────────────┐
                    │                                             │
                    │  ┌──── HotkeyEvent::Toggle ─────────┐       │
                    ▼  │                                  │       │
              ┌──────────┐                          ┌─────────────┐
        ┌───▶│   Idle   │── start_recording() ────▶│  Recording  │
        │     └──────────┘                          └─────────────┘
        │           ▲                                      │
        │           │                                      │ HotkeyEvent::Toggle
        │           │ on success                           │   或  recording_max_duration
        │           │                                      ▼
   ┌─────────┐      │                              ┌──────────────┐
   │Injecting│◀─────┴────── Final ─────────────────│ Transcribing │
   └─────────┘                                     └──────────────┘
        │                                                  │
        │ on inject error                                  │ on backend error
        └──── ClipboardFallback ──┐    ┌──────── Error ────┘
                                  ▼    ▼
                              ┌────────────┐
                              │   Idle     │
                              └────────────┘
```

**不变量**：
- `Recording` 收到第二个 Toggle → 转 `Transcribing`（自然路径）
- `Transcribing` 收到 Toggle → **忽略**，HUD 状态变灰，日志 warn
- `Injecting` 收到 Toggle → 忽略
- `start_recording()` 中 `audio.start()` 或 `backend.start()` 失败 → 不进 `Recording`，HUD 不显示，错误回 Idle

### 4.2 三条并发数据流（Recording 期间）

```
                 cpal callback (real-time audio thread)
                          │
                          │ Vec<i16> (320 samples / 20ms)
                          ▼
                 ┌────────────────┐
                 │  AudioCapture  │ ── tokio::watch<f32> ──▶ Swift HUD (amplitude @60Hz)
                 │   (compute     │
                 │     RMS)       │
                 └────────────────┘
                          │
                          │ tokio::mpsc<Vec<i16>> bounded(64)
                          ▼
                 ┌────────────────┐
                 │  AsrBackend    │
                 │   .feed()      │── Option<Partial> ──▶ (v2: 显示在 HUD)
                 └────────────────┘
                          │
                  on stop │ Final
                          ▼
                 ┌────────────────┐
                 │   Injector     │
                 └────────────────┘
                          │
                          ▼
                  CGEvent 注入 / 剪贴板
```

并发原则：
1. cpal real-time thread 不能被 ASR 阻塞 → bounded(64) channel + drop oldest
2. ASR 流是 tokio task，async loop 取帧 + `backend.feed().await`
3. HUD amplitude 流是独立 60Hz tick task，跟 ASR 解耦

### 4.3 跨线程边界

| 边界 | 机制 |
|---|---|
| cpal real-time thread → tokio runtime | `tokio::sync::mpsc`（lock-free） |
| tokio runtime → main thread (HUD) | swift-bridge 函数；Swift 侧 `DispatchQueue.main.async` |
| CLI 进程 → daemon 进程 | Unix domain socket，length-prefixed JSON |
| CGEventTap callback → tokio | 专用线程跑 `CFRunLoopRun`，callback 里 `try_send` 进 mpsc |

### 4.4 配置热重载流程

```
$ voco config           （cli 进程）
  ↓ 用户改完 → 保存 config.toml
  ↓ IPC → daemon: Request::ReloadConfig
                        ↓
            Orchestrator 收到 ReloadConfig:
              1. Config::load() 重新读
              2. validate() 失败 → 返回错误，旧 config 不变
              3. diff old vs new:
                 - hotkey 变了      → HotkeyManager.reinstall(new_hotkey)
                 - backend 变了     → 旧 backend.shutdown(); new = build_backend();
                                       state != Idle 时推迟到下次 Idle
                 - hud 样式变了     → bridge::hud_set_style(...)
                 - 凭据变了         → 下次 backend.start() 自然生效
              4. 写回 Arc<RwLock<Config>>
              5. 返回 Response::Ok
  ↓
  cli 显示 "✓ Daemon reloaded"
```

不可热重载字段（socket path / log path / 极少数 sherpa onnx provider 切换）→ cli 在 diff 阶段提示 `daemon restart`。

### 4.5 HUD 状态映射

| daemon 状态 | HUD 行为 |
|---|---|
| Idle | hud_hide() |
| Recording | hud_set_state(Listening) + hud_show()，amplitude 持续推 |
| Transcribing | hud_set_state(Transcribing)，声波冻结、麦克风变 spinner |
| Injecting | hud_hide() |
| Error | hud_set_state(Error) 显示 1s 红色 → hud_hide() |

### 4.6 边界场景

| 场景 | 行为 |
|---|---|
| 麦克风被其他 app 抢走 | 进 Error 态，HUD 红色 1s，日志 error，回 Idle |
| 豆包 WebSocket 中途断 | 缓冲 partial → 触发 stop → 把 partial 当 final 注入；下次 start 重连 |
| 录音超过 60s | 自动转 Transcribing，HUD 提示 "max duration reached" |
| daemon 没启动时按热键 | 无反应（hotkey 由 daemon 注册） |
| daemon 崩溃 | launchctl KeepAlive=true 自动拉起 |
| 拔掉麦克风 | 同"麦克风被抢走" |
| daemon 关闭时正在录音 | shutdown：stop_recording → **不注入** → HUD hide → 退出 |

### 4.7 资源生命周期

- `AudioCapture`：每次 start_recording 时新建，stop_recording 时 drop（cpal stream 自动 stop）
- `AsrBackend`：daemon 启动时构造一次并 `start()`（云端建 WebSocket、本地加载 onnx）→ 全程持有；每次录音 stop 后立刻 start 重新待命
- `HotkeyManager`：daemon 启动时 install，关闭时 uninstall
- HUD `NSPanel`：daemon 启动时创建（隐藏），生命周期等于 daemon

---

## 5. 错误处理、日志、可观测性

### 5.1 错误类型分层

```rust
#[derive(thiserror::Error, Debug)]
pub enum VocoError {
    #[error("config error: {0}")]              Config(#[from] ConfigError),
    #[error("audio capture failed: {0}")]      Audio(#[from] AudioError),
    #[error("asr backend error: {0}")]         Asr(#[from] AsrError),
    #[error("hotkey error: {0}")]              Hotkey(#[from] HotkeyError),
    #[error("text injection failed: {0}")]     Injection(#[from] InjectionError),
    #[error("ipc error: {0}")]                 Ipc(#[from] IpcError),
    #[error("permission denied: {0}")]         Permission(PermissionKind),
    #[error("io: {0}")]                        Io(#[from] std::io::Error),
}

pub enum PermissionKind { Microphone, Accessibility, InputMonitoring }
```

每个 crate 有自己的具体 error 枚举，最外层折叠到 `VocoError`。

### 5.2 三原则

1. **永不静默吞错**：`?` 链路终点必须有 `tracing::error!` 或 user-facing 输出
2. **网络/IO 失败带描述**：豆包 WebSocket 关闭码、cpal `StreamError` 变体、CGEvent post 返回值全进日志
3. **降级而非崩溃**：状态机定义了哪些错误降级到 Idle

### 5.3 关键失败路径

| 失败 | 策略 |
|---|---|
| 豆包 WebSocket 连不上（启动时） | daemon 不失败，进 BackendDegraded 状态；HUD 仍能起，按热键给红色错误 |
| 豆包返回 401/403 | 进 Idle，HUD 红色 "Auth failed"，日志附 endpoint + app_id（**绝不打 token**），引导 `voco config` |
| 豆包识别中断 | 把已收 partial 拼成 final 注入；自动 reconnect |
| sherpa 模型文件缺失（v2） | 启动 validate 阶段拒绝，doctor 给修复建议 |
| sherpa 运行时 panic | tokio task 被 catch_unwind 包；orchestrator 收到 fail → BackendDegraded |
| cpal 找不到默认输入设备 | 录音启动失败，HUD 红色"No microphone"，日志列设备 |
| TCC 麦克风未授权 | cpal Stream::play 错误码 → osascript display dialog 引导 |
| TCC 辅助功能未授权 | daemon 启动时 `AXIsProcessTrustedWithOptions(prompt=true)`；未授权 daemon 仍启动但 hotkey 不工作，状态在 doctor/status 可见 |
| CGEvent 注入失败（secure input） | 自动降级到剪贴板 + Cmd+V；再失败仅写剪贴板，HUD 提示 "Copied, paste manually" |
| daemon socket 残留 | 启动时检查：能连上 → 退出报错；连不上 → 删除残留并重新创建 |
| IPC 协议版本不匹配 | cli 提示 "daemon out-of-date, run `voco daemon restart`" |

### 5.4 日志（tracing）

```rust
tracing_subscriber::fmt()
    .with_env_filter(EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(&cfg.log_level)))
    .with_writer(non_blocking_file_writer)   // tracing-appender，rotate 10MB × 5
    .with_ansi(false)
    .json()
    .init();
```

文件：`~/Library/Logs/voco/voco.log` + `voco.log.1..5`

#### Span/event 命名约定

```
span: voco.session                       一次按热键到注入完成
  ├── event: voco.recording.started      { trigger: "hotkey" }
  ├── span:  voco.asr.feed               { backend: "doubao", frames: 47 }
  ├── event: voco.asr.partial            { chars: 12 }
  ├── event: voco.recording.stopped      { duration_ms: 2840 }
  ├── span:  voco.asr.finalize
  │   └── event: voco.asr.final          { chars: 24, latency_ms: 320 }
  ├── span:  voco.injection
  │   └── event: voco.injection.done     { mode: "cgevent", chars: 24, app: "Notes" }
```

**绝不打日志**：access_token、识别文本（隐私）
**默认打**：字符数、延迟、目标 app bundle id、错误堆栈
**`log_level=debug` 才打**：partial 文本前 N 字符（用户主动开调试模式）

### 5.5 内部度量（轻量级）

```rust
pub struct Stats {
    pub sessions_total: u64,
    pub sessions_succeeded: u64,
    pub sessions_failed: u64,
    pub last_session_latency_ms: Option<u64>,
    pub last_first_partial_ms: Option<u64>,
    pub backend_in_use: String,
    pub recent_errors: VecDeque<(SystemTime, String)>,   // 最近 10 条
}
```

`voco status` IPC 拿这个结构并人类可读地展示：

```
$ voco status
✓ daemon running (pid 41823, uptime 2h 14m)
  backend:           doubao (cloud)
  state:             idle
  total sessions:    47  (success 46, failed 1)
  last latency:      first partial 220ms, final 360ms, total 1840ms
  recent errors:
    2026-05-01 10:23  doubao ws close 1006, reconnected
```

### 5.6 voco doctor

```
$ voco doctor
Checking permissions...
  ✓ Microphone access (granted)
  ✗ Accessibility (NOT granted)
      → Open: System Settings → Privacy & Security → Accessibility → enable Voco
  ✓ Input Monitoring (granted)

Checking config...
  ✓ ~/.config/voco/config.toml exists
  ✓ Schema valid
  ✓ Backend = doubao (configured)
  - sherpa not configured (skip)

Checking backend...
  ✓ Doubao endpoint reachable (rtt 84ms)
  ✓ Doubao auth OK

Checking daemon...
  ✓ Daemon running (pid 41823)
  ✓ Socket /Users/.../voco.sock writable
  ✓ Hotkey installed (Right Command)

Checking model files...
  - sherpa skipped

Checking microphone...
  ✓ Default input device: MacBook Pro Microphone (16kHz/mono supported)

All checks passed except Accessibility. Fix above and rerun.
```

每一项独立函数，便于单元测试 mock。

### 5.7 用户可见反馈层级

按权重：
1. **HUD 视觉反馈**（≤2 秒红色 + 错误代码）—— 用户当下能看到
2. **结构化日志** —— 排查用
3. **`voco status` / `voco doctor`** —— 主动查问题用

**不**用系统通知（NSUserNotification）—— 太吵。**唯一例外**：第一次启动时 TCC 权限引导用 `osascript display dialog`。

---

## 6. 测试策略

### 6.1 第 1 层：单元测试（每 crate 自带）

| crate | 测试重点 |
|---|---|
| voco-config | schema 默认值、加载/保存原子性、validate 各分支、热重载 diff 算法 |
| voco-asr | DoubaoBackend 用 mock WebSocket server；SherpaBackend 用预录 WAV → 断言识别文本（v2） |
| voco-audio | RMS 计算、PCM frame 切分、watch 节流 |
| voco-hotkey | HotkeyConfig 解析（CGEventTap 难 mock，集成测试覆盖） |
| voco-injector | mock Injector trait；剪贴板路径可测；CGEvent 路径手动测 |
| voco-ipc | UnixListener+UnixStream 起在 tempdir 端到端 |
| voco-daemon | Orchestrator 用 mock backend / mock audio → 测状态机所有转移 |

覆盖目标：voco-config / voco-ipc / voco-daemon ≥80% 行覆盖。其他不强制。

### 6.2 第 2 层：集成测试（顶层 `tests/`）

跑真实 daemon 进程 + 真实 socket，backend 替换为 `MockBackend`（回固定文本）。

```
tests/integration/
├── cli_status.rs              # voco daemon start → voco status 返回 idle
├── cli_config_wizard.rs       # 用 expectrl 模拟 inquire 交互
├── ipc_protocol.rs            # 协议版本不匹配的拒绝行为
├── reload_config.rs           # 改 config → IPC reload → daemon 状态正确
└── orchestrator_e2e.rs        # mock hotkey + mock audio + mock backend 走完整流程
```

### 6.3 第 3 层：手动验收清单（每次 release 前）

```
□ daemon 冷启动 < 200ms（time voco daemon start）
□ 按热键到 HUD 显示 < 50ms（肉眼）
□ 按热键到首字识别返回 ≤ 300ms（豆包）
□ 中文长句（30 字）识别准确率主观满意
□ 中英混杂识别正确
□ 焦点在 Notes / Cursor / 微信 / 终端 / 浏览器地址栏 各注入一次
□ 焦点在终端 sudo 密码框 → 自动切剪贴板 + 提示
□ 录音时 Cmd+Tab 切换前台 → HUD 不跟着切（NSPanel 行为）
□ 录音中拔耳机 → 优雅降级
□ daemon 干掉（kill -9）→ launchctl 自动拉起
□ 配置向导每一项都能保存并生效
□ voco doctor 全绿
```

### 6.4 CI（GitHub Actions）

```yaml
matrix:
  os: [macos-14, macos-15]   # arm64 only
jobs:
  - cargo fmt --check
  - cargo clippy -- -D warnings
  - cargo test --workspace
  - swift build (in hud/)
  - cargo build --release    # 验证 swift-bridge 链接通过
```

不在 CI 跑"需要 TCC 授权"的测试（runner 没 GUI 没法授权）；这部分仅在本机 `cargo test --features manual-only`。

---

## 7. MVP 范围

### 7.1 MVP 必须有

1. `voco daemon start/stop/status` + launchctl plist 安装
2. `voco config`（交互向导）+ `show/set/edit/reset/validate`
3. `voco doctor` 全检查
4. **豆包 backend**（主，因为已有 API）
5. 配置驱动的全局热键（默认 Right Command，切换式）
6. 文本注入（CGEvent → 剪贴板降级）
7. SwiftUI 胶囊 HUD（麦克风 + 声波 + 黄点 + 毛玻璃）
8. 结构化日志 + `voco daemon logs -f`
9. 录音超时（默认 60s）
10. 配置热重载（hotkey 和大部分字段）

### 7.2 MVP 明确不做（v2+）

- sherpa-onnx 本地后端（架构留好，trait 已设计，**不实装**）
- HUD 实时显示 partial 文本（声波就够了）
- 多套 hotkey profile / 上下文感知
- 文本后处理（标点修正、首字大写、自定义替换词典）
- 命令模式（"删除上一句"等语音指令）
- 系统通知 / Menu Bar 图标
- Keychain 存 token（先 chmod 600）
- VAD 自动断句
- 多语言切换（先只中文 + 中英混杂）
- 自动更新 / 内置模型下载器
- Linux / Windows 移植

### 7.3 取舍说明

把 sherpa 留到 v2 是有意识的取舍。架构里 trait 已长好，第一版只接一个 backend 反而能更专注地把"daemon ↔ HUD ↔ 注入"主链路打磨好。等主链路稳了，补 sherpa 是几天的事；反过来同时做两个，第一版会拖到 5 周以上。

---

## 8. 里程碑（按周排，全职等价）

```
Week 1 — 脚手架 + 配置 + IPC（无 GUI、无录音、无识别）
  □ workspace 拆分、CI 跑通
  □ voco-config 默认值 + 加载/保存
  □ voco-ipc + UnixListener + 协议版本 + 集成测试
  □ voco-cli 框架（clap subcommands）
  □ voco daemon start/stop/status 走通（daemon 是空壳）
  ✦ 验证：voco daemon start && voco status 看到 idle

Week 2 — 配置向导 + doctor + 日志
  □ inquire 向导走通五个问题
  □ voco doctor 所有检查项
  □ tracing 接 file appender，daemon logs -f
  ✦ 验证：voco config 一遍走完能保存；doctor 全绿

Week 3 — 音频 + 豆包 backend（有声音 + 有识别，无 UI）
  □ cpal 采集 + RMS + bounded mpsc
  □ voco-asr trait + DoubaoBackend WebSocket 实现
  □ orchestrator 状态机 + mock hotkey 触发
  □ 命令行模式：voco _internal_record（debug）
  ✦ 验证：从命令行触发录音，能在终端打印识别结果

Week 4 — 全局热键 + 文本注入（端到端通了，但 UI 还没）
  □ CGEventTap 全局热键
  □ CGEvent 文本注入 + 剪贴板降级
  □ TCC 权限引导
  □ 录音超时
  ✦ 验证：按 Right Command 在 Notes 里能写出文字

Week 5 — SwiftUI HUD（最后给体验上花）
  □ Swift Package + NSPanel + CapsuleView
  □ swift-bridge FFI 5 个函数
  □ amplitude 60Hz 推送 + 声波动画
  □ 状态切换动画 (idle/listening/transcribing/error)
  ✦ 验证：手动验收清单全过

Week 6 — 打包 + 文档
  □ Voco.app bundle + Info.plist (LSUIElement, NSMicrophoneUsageDescription)
  □ launchctl plist 安装/卸载脚本
  □ README + Quickstart
  □ 自用 1 周 / 改 bug
  → v0.1 可发布
```

### 推迟到 v0.2 的明确事项

1. sherpa-onnx 本地后端
2. HUD partial 文本显示
3. Keychain 集成
4. 自动更新

---

## 9. 风险登记

| 风险 | 概率 | 缓解 |
|---|---|---|
| swift-bridge 在打 universal binary 时构建脚本踩坑 | 中 | Week 1 末就先做 hello world swift 函数串通，别拖到 Week 5 |
| 豆包 WebSocket 协议帧格式踩坑（鉴权、PCM 编码） | 中 | Week 3 第一天先按官方文档发最小可工作请求；不一上来就接 trait |
| CGEventTap 在 Apple Silicon 某些情况下需要 Input Monitoring 而非仅 Accessibility | 中 | doctor 把两个权限都检查；用户授权指南写清楚 |
| CGEvent 注入中文（Unicode）在某些 app 偶发丢字 | 低-中 | 用 `CGEventKeyboardSetUnicodeString` 一次注入整段；测试矩阵覆盖主流 app |
| LSUIElement bundle 想被 Spotlight 找到但又不显示 dock | 低 | Info.plist 标 `LSUIElement=true`；不上 App Store 不影响 |

---

## 10. 开放问题（实施期间需要决定）

1. **launchctl plist 的安装路径**：`~/Library/LaunchAgents/com.voco.daemon.plist` 还是 `/Library/LaunchAgents/`？前者用户级，无需 sudo；推荐前者。
2. **豆包流式 ASR 的具体 endpoint 与协议帧**：实施 Week 3 时按当前火山引擎文档确定，可能需要小改 DoubaoBackend 协议层。
3. **CapsuleView 的精确尺寸 / 颜色 / 动效曲线**：先按 SwiftUI 默认 `.ultraThinMaterial` 实现，Week 5 主观调优。
4. **CLI 默认热键的最终选择**：Right Command 与 Fn 各有取舍（Fn 更好按但部分键盘不易截获，Right Command 更通用）。Week 4 实测后定。

---

## 11. 参考

- 闪电说官网：https://shandianshuo.cn/
- Typeless: https://www.typeless.com/
- VoiceInk（开源近似实现，可参考其 macOS 集成方式）: https://tryvoiceink.com/
- swift-bridge: https://github.com/chinedufn/swift-bridge
- inquire: https://github.com/mikaelmello/inquire
- sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx
- cpal: https://github.com/RustAudio/cpal
