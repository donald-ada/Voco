# Voco

中文 | [English](#english)

Voco 是一款 macOS 语音输入工具。它运行在菜单栏中，按下热键即可录音、转写，并把文本输入到当前应用。

## 功能

- 菜单栏常驻，主窗口按需打开。
- 支持按住说话和切换录音两种热键模式。
- 使用 macOS Keychain 保存模型凭证。
- 支持火山引擎新控制台 API Key，以及 App ID + Access Token 凭证。
- 录音、转写和错误状态会显示在顶部 HUD。
- 支持将转写文本插入当前应用。
- 支持开机登录、静默启动和 Dock 图标显示设置。
- 内置会话记录和统计页，可查看输入趋势、目标 App、活跃时段、输入长度分布和模型来源。

## 使用

1. 启动 `Voco.app`。
2. 在菜单栏点击 Voco 图标，选择 `显示 Voco`。
3. 在 `模型` 页面保存模型凭证。
4. 在 `设置` 页面配置热键、录音模式和麦克风。
5. 授予麦克风和辅助功能权限。

完成配置后，在任意可输入文本的应用中按下热键即可开始语音输入。

## 权限

Voco 需要以下 macOS 权限：

- 麦克风：用于录音。
- 辅助功能：用于把转写文本输入到当前应用。

如果之前拒绝过麦克风权限，需要到系统设置中手动重新开启。

## 安装

本地调试安装可以先构建 DMG：

```bash
packaging/build_native_dmg.sh --profile debug --signing-style adhoc
open dist/Voco.dmg
```

打开 DMG 后，将 `Voco.app` 拖入 `/Applications`，再从应用程序中启动。

## 开发

构建和测试应用：

```bash
swift build --package-path native
swift test --package-path native
```

构建本地 app bundle：

```bash
packaging/build_native_app_bundle.sh --profile debug
open target/native/Voco.app
```

运行 bundle smoke test：

```bash
packaging/tests/native_app_bundle_smoke.sh
```

构建 Developer ID 版本：

```bash
VOCO_DEVELOPER_ID_APPLICATION="Developer ID Application: Example Team (TEAMID)" \
packaging/build_native_dmg.sh --profile release --signing-style developer-id
```

## 项目结构

- `native/`：macOS 应用和测试。
- `packaging/`：app bundle、DMG 和 smoke test 脚本。
- `prototypes/`：界面原型文件。

## English

Voco is a macOS voice input app. It lives in the menu bar, records speech through a hotkey, transcribes it, and inserts the resulting text into the active app.

## Features

- Menu bar app with an on-demand main window.
- Press-and-hold and toggle recording modes.
- macOS Keychain storage for model credentials.
- Volcengine API Key and App ID + Access Token credential modes.
- Top HUD for recording, transcription, and error states.
- Text insertion into the current app.
- Launch at login, silent launch, and optional Dock visibility.
- Session history and statistics for input trends, target apps, active time ranges, input length distribution, and model sources.

## Usage

1. Launch `Voco.app`.
2. Click the Voco icon in the menu bar and choose `显示 Voco`.
3. Save model credentials on the `模型` page.
4. Configure the hotkey, recording mode, and microphone on the `设置` page.
5. Grant microphone and accessibility permissions.

After setup, press the configured hotkey in any text input app to start voice input.

## Permissions

Voco requires these macOS permissions:

- Microphone: records audio.
- Accessibility: inserts transcribed text into the active app.

If microphone permission was denied before, re-enable it manually in System Settings.

## Install

Build a local DMG for testing:

```bash
packaging/build_native_dmg.sh --profile debug --signing-style adhoc
open dist/Voco.dmg
```

Open the DMG, drag `Voco.app` into `/Applications`, then launch it from Applications.

## Development

Build and test the app:

```bash
swift build --package-path native
swift test --package-path native
```

Build a local app bundle:

```bash
packaging/build_native_app_bundle.sh --profile debug
open target/native/Voco.app
```

Run the bundle smoke test:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Build a Developer ID release:

```bash
VOCO_DEVELOPER_ID_APPLICATION="Developer ID Application: Example Team (TEAMID)" \
packaging/build_native_dmg.sh --profile release --signing-style developer-id
```

## Project Structure

- `native/`: macOS app and tests.
- `packaging/`: app bundle, DMG, and smoke test scripts.
- `prototypes/`: UI prototype files.

## License

MIT
