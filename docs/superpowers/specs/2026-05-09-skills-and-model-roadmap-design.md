# 技能模块与模型路线图设计

日期：2026-05-09

## 背景

Voco 当前是 native macOS SwiftUI 语音输入应用。现有流程是录音、调用
Volcengine ASR 转写，然后把最终转写文本插入到当前聚焦的 App。设置窗口已经
采用工作台结构，当前导航包含主页、模型、统计、设置。

下一阶段目标是增加 **技能** 模块，用于对转写文本做后处理。第一版先实现
“语气词清理”，同时为后续自定义模型、动态切换模型和本地模型下载保留架构
空间。

## 目标

1. 在设置工作台左侧新增 **技能** 导航。
2. 在 ASR 转写和文本插入之间引入 `TranscriptPostProcessingPipeline`。
3. 第一版实现一个技能：语气词清理。
4. 支持自定义语气词规则，并允许删除或替换为指定内容。
5. 第一版对用户保持简单：只暴露普通文本匹配；内部模型预留 regex 能力。
6. 第一版全局生效；内部模型预留按 App / 场景配置能力。
7. 历史列表默认显示处理后文本；详情保留原始转写、处理后文本和命中规则。
8. 给后续模型 provider registry、本地模型下载和动态切换定义阶段性路线。

## 非目标

1. 第一阶段不实现本地模型下载。
2. 第一阶段不实现本地 ASR 运行时。
3. 第一阶段不在 UI 暴露正则匹配。
4. 第一阶段不实现按 App / 场景单独配置规则。
5. 第一阶段不加入 LLM 改写。
6. 第一阶段不替换当前 Volcengine 生产转写路径。

## 产品形态

设置侧边栏新增 **技能**：

- 主页
- 模型
- 技能
- 统计
- 设置

技能页是一个配置页，不做插件市场。第一版展示：

1. 技能总开关。
2. 处理链路状态摘要。
3. “语气词清理”技能卡片。
4. 规则编辑列表。
5. 测试预览区：输入一段文本后展示原文、处理后文本和命中规则。

第一版技能顺序固定，但数据模型需要保留 `order` 或 `priority` 字段，后续可
以支持拖拽排序，不需要迁移已有规则。

## 第一版技能：语气词清理

语气词清理运行在最终 ASR 转写完成之后、文本插入之前。

默认内置候选语气词包括：

- 嗯
- 呃
- 啊
- 这个
- 那个
- 就是
- 然后

规则字段：

- 是否启用
- 显示名称
- 普通文本匹配值
- 动作：删除或替换
- 替换内容
- 作用域元数据：第一版全局，后续可扩展到 App / 场景
- 匹配类型：第一版只支持 `plainText`，内部预留 `regex`
- 顺序或优先级

替换行为：

- 删除等价于替换为空字符串
- 替换可以使用空字符串、单个空格或自定义字符串
- UI 必须把“空字符串”和“空格”显式做成可选项，避免用户猜测不可见字符

第一版 UI 只开放普通文本匹配。内部规则模型保留匹配类型：

- `plainText`：第一版支持并暴露
- `regex`：第一版不暴露，只预留

## 文本处理链路

目标链路：

1. 音频采集
2. ASR provider 返回原始最终转写
3. `TranscriptPostProcessingPipeline` 接收原始文本和上下文
4. 已启用技能按确定顺序执行
5. pipeline 返回处理后文本和诊断信息
6. 文本插入使用处理后文本
7. 最近会话列表默认展示处理后文本
8. 会话详情展示原始转写、处理后文本和命中规则

这个设计让用户日常看到的是干净文本，同时保留足够信息来追踪规则误删。

## 核心模型

核心行为放在 `VocoAppCore`，避免 SwiftUI 视图承担业务逻辑。

建议新增：

- `TranscriptPostProcessingPipeline`
- `TranscriptPostProcessingSkill`
- `TranscriptPostProcessingContext`
- `TranscriptPostProcessingResult`
- `TranscriptPostProcessingDiagnostic`
- `FillerCleanupRule`
- `FillerCleanupAction`
- `FillerCleanupMatchType`
- `FillerCleanupSettings`

`TranscriptPostProcessingResult` 包含：

- `originalText`
- `processedText`
- `diagnostics`
- 是否发生文本变化

`TranscriptPostProcessingDiagnostic` 包含：

- skill id
- rule id
- 规则显示名称
- 命中文本
- 替换文本
- 命中次数或变化摘要

第一版普通文本替换可以直接实现，但必须集中在技能模型后面，不要把字符串处理
散落在 UI、workflow 或插入逻辑里。这样以后加 regex、热词、标点整理时可以复
用同一条 pipeline。

## 持久化

新增独立的技能偏好存储，不和现有 app preference、voice input preference 混
在一起。

建议接口：

- `SkillPreferenceStoring`
- native 实现使用 `UserDefaults`
- 不在这里存任何凭证

持久化内容：

- 技能总开关
- 语气词清理开关
- 自定义规则
- 规则顺序

内置规则应是稳定默认值。自定义规则不应该覆盖内置规则，除非后续 UI 明确支持
编辑或禁用内置规则。

## UI 行为

技能页沿用当前设置工作台的紧凑 macOS 风格：

- 克制的面板和控件
- 沿用现有字体、颜色、间距
- 不放营销文案
- 不嵌套卡片
- 规则行和控件尺寸稳定，避免内容变化导致布局跳动

语气词清理 UI：

- 总开关
- 内置规则区
- 自定义规则区
- 新增规则按钮
- 规则行包含：匹配文本、动作菜单、替换输入、启用开关、删除按钮
- 预览区展示原文和处理后文本
- 命中规则摘要

预览第一版本地同步执行即可。未来如果出现不支持的规则类型，应通过诊断信息明
确失败，不要静默跳过。

## 历史记录行为

最近会话列表：

- 默认展示处理后文本
- 保持当前列表密度
- 不在列表里加入笨重的调试字段

会话详情：

- 处理后文本作为主文本
- 原始转写放在次级区域
- 展示命中规则和替换结果

如果没有任何技能修改文本，详情可以显示中性提示，例如“没有技能修改这次转写”，
并支持中英文切换。

## 错误处理

普通文本语气词清理通常不应该失败，但 pipeline 仍需要显式处理技能错误：

- 为失败技能记录 diagnostic error
- 保留原始转写
- 如果某个技能失败，使用 pipeline 中最近一次成功文本；如果第一个技能失败则
  使用原始文本
- 如果技能失败影响插入，应显示本地化运行时警告

后续用户规则会更强，因此不能使用静默 `catch`。

## 本地化

所有用户可见的技能 UI、诊断和错误都通过 `VocoStrings` 输出，默认中文，切换
到英文时显示英文。

第一版内置语气词主要面向中文。英文界面下，规则说明应解释这些中文语气词的作
用，不应假装它们是英文 filler。

## 测试要求

实现前先补测试：

1. `FillerCleanupRule` 可以删除普通文本语气词。
2. 替换值支持空字符串、空格和自定义字符串。
3. 禁用规则不会修改文本。
4. 多条规则按确定顺序执行。
5. pipeline 保留原始文本和处理后文本。
6. pipeline 输出命中规则诊断。
7. 会话列表快照使用处理后文本。
8. 会话详情数据包含原始转写和诊断。
9. 技能偏好可以 round-trip 自定义规则和启用状态。
10. 技能导航和文案支持英文。

实现完成前需要验证：

```bash
swift test --package-path native
packaging/build_native_app_bundle.sh --profile debug
packaging/tests/native_app_bundle_smoke.sh
git diff --check
```

## 模型管理路线图

模型管理是技能第一阶段之后的独立大阶段。方向是把当前硬编码的 Volcengine 提
供方升级为 provider registry：

- Volcengine cloud provider
- custom cloud API provider
- local model provider

未来 Model 页能力：

- 当前启用 provider 选择
- provider 状态
- 每个 provider 自己的凭证和设置表单
- 在已配置 provider 之间动态切换
- 本地模型库
- 下载进度
- checksum 或签名校验
- 磁盘占用展示
- 删除已下载模型
- 清除错误状态

本地模型不能轻率加入，需要单独设计：

- 模型格式
- runtime engine
- 硬件要求
- 磁盘空间和下载源
- 离线行为
- 隐私提示
- 失败和 fallback 行为

## 分期

第一阶段：

- 技能导航
- post-processing pipeline
- 语气词清理技能
- 全局规则设置
- 预览
- 历史详情可追溯

第二阶段：

- 标点整理
- 中英数字空格规范
- 术语热词表
- 技能排序
- 按 App / 场景配置

第三阶段：

- provider registry
- 自定义云端 provider
- 动态 provider 切换

第四阶段：

- 本地模型目录
- 下载和管理本地模型
- 本地 ASR runtime 集成

## 实现注意事项

当前 `SettingsView.swift` 很大。新增技能 UI 时，应拆出独立子视图或新文件，不
要继续把完整页面塞进 `SettingsView.swift`。核心行为放在 `VocoAppCore`；SwiftUI
只绑定 coordinator 暴露的 snapshot 和 action。

