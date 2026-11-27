# Sonote（声记 / 智会纪要）

<p align="center">
  <strong>原生 macOS 智能会议纪要 App · 100% 本地 Apple Silicon MLX 语音、降噪、声纹与大模型引擎</strong>
</p>

<p align="center">
  <a href="./README_EN.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0%2B-000000?logo=apple" alt="macOS 15+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-MLX-2468F2" alt="Apple Silicon MLX" />
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/License-MIT-22C55E" alt="MIT License" />
</p>

**Sonote（声记）** 是一款为 Apple Silicon Mac 打造的纯原生 SwiftUI 智能会议纪要工具（零 Electron、零虚拟声卡驱动、无需外部 Python/Ollama 进程）。

它在极简清新的浅色界面背后，集成了完整的本地 **Apple Silicon MLX** 语音与推理链路：**系统声音 + 麦克风双轨采集**、**DeepFilterNet3 神经降噪**、**Silero 流式 VAD**、**Qwen3-ASR 中英混说转写**、**Sortformer / ECAPA-TDNN 跨会议声纹认人**，以及**内置离线 Qwen2.5 MLX 大模型**与多云端模型（OpenAI / Claude / Gemini / Codex / Ollama），一键生成结构化会议纪要并推送至飞书、钉钉、Notion 与 Apple 提醒事项。

---

## 核心特性

### 1. 无侵入会议自动检测与日历联动
- **CoreAudio 进程级自动感知**：实时监控会议软件音频状态（无需辅助功能或完整录屏权限），自动识别 **腾讯会议、飞书、钉钉、企业微信、微信、Zoom、Microsoft Teams、FaceTime、Slack、Discord、Webex** 及 **Chrome / Safari / Arc / Edge** 网页会议。
- **忽略应用黑名单**：支持在桌面提醒弹窗一键「不再提醒」，或在设置中管理自定义忽略列表。
- **macOS 日历联动（EventKit）**：开会时自动匹配当前日程标题，并将参会人姓名注入语音识别热词。
- **开机自启 & 系统级全局快捷键**：支持 `SMAppService` 静默驻留菜单栏，内置无需辅助功能权限的 Carbon 全局快捷键（默认 `⌥⇧R` 启停录音、`⌥⇧M` 呼出/收起窗口，全屏开会同样生效）。

### 2. 双轨采集、设备热插拔与音文同步回放
- **系统远端声音 + 麦克风双轨分离**：基于 `CoreAudio Process Tap`（仅需「仅系统音频录制」权限，无需安装 BlackHole 等虚拟声卡）+ `AVAudioEngine` 独立采集，自动区分本机与远端发言并过滤外放回声。
- **耳机热切换自动重连**：会中切换 AirPods、蓝牙耳机或外接麦克风时自动重建音频管线。
- **轻量化混音备份与倍速回听**：录制自动保存 `.m4a`；会后支持 `1x / 1.25x / 1.5x / 2x` 倍速播放，点击任意逐字稿段落秒级跳转原声。
- **本地音视频离线导入**：拖拽或选择 `.m4a / .mp3 / .wav / .mp4 / .mov` 离线转写（视频自动提取轻量化音轨，不占磁盘）。

### 3. 全链路 Apple Silicon MLX 语音、降噪与声纹引擎
- **MLX Qwen3-ASR**：默认 `mlx-community/Qwen3-ASR-1.7B-8bit`（可选 1.7B / 0.6B 4-bit / 8-bit，支持国内 HuggingFace 镜像源），高精度中英混说与术语识别；自动融合本机姓名、团队词典、日程参会人与声纹库热词；会后自动释放显存。
- **Silero 逐帧流式 VAD**：512 采样点（32 ms）LSTM 流式断句，兼顾轻声捕捉与抗键盘/环境底噪。
- **DeepFilterNet3 v3 嘈杂环境人声降噪**：内置 `MLXAudioSTS` 神经降噪增强（M4 Pro 实测约 59x 实时速度），在开放办公区或咖啡馆有效抑制背景噪声。
- **Sortformer + ECAPA-TDNN 本地声纹库 & 跨会议自动认人**：
  - 本地 192 维 ECAPA-TDNN 声纹提取与持久化存储（100% 离线，不上传云端）。
  - 支持设置页 5 秒录音建档、音频导入建档，以及逐字稿点击改名一键「记住声纹」。
  - 同时提供 **Sortformer（≤4 人精准分离）** 与 **ECAPA 在线聚类（突破 4 人上限，支持 5~12 人大组会）**，支持会中实时分离与「AI 猜姓名」上下文推断。
- 同步保留 **Apple 本机语音识别**（`SpeechAnalyzer` / `SFSpeechRecognizer`）与 **OpenAI Audio Transcribe API** 作为备选。

### 4. 多模型提供方 & 内置 100% 离线 MLX 大模型
所有 API 密钥与 Webhook 签名密钥均加密存储于 **macOS Keychain**，绝不落盘明文：
- **App 内置离线 MLX LLM**：直接基于 `MLXAudioCore.Qwen2Model` 在本机 Metal GPU 上流式运行量化 `Qwen2.5-Instruct`（`1.5B` / `3B` / `7B` 4-bit），**零外部 Ollama 进程、100% 离线、零 Token 费用**。
- **OpenAI / 兼容 API / 本地服务**：支持 OpenAI、DeepSeek、自定义中转及本地 **Ollama (`localhost:11434/v1`) / MLX Server (`localhost:8080/v1`)**。
- **Anthropic Claude & Google Gemini**：原生接入 Claude Messages SSE 与 Gemini Stream SSE。
- **本机 Codex Auth**：自动识别 `~/.codex/auth.json`（OAuth 自动刷新 + 模型目录发现）。

### 5. 极简工作台、协作推送与数据迁移
- **极简浅色 UI & 左上角悬浮小窗**：录制中可自动收起为 `316×108` 悬浮胶囊，支持一键展开双栏视图与底部「会中随手记」；主页支持标题、逐字稿与待办全文搜索。
- **省 Token 增量提炼 & 超长会议 Map-Reduce**：会中仅增量发送新发言片段（省 60%–80% Token），超长会议自动两阶段分段汇总，并按日精准统计 Token 账本。
- **自定义模板、标签、全局待办 & 跨会议 AI 问答**：内置 5 套纪要模板 + 自定义 Prompt 模板；支持会议标签筛选、全局待办一键同步到 macOS「提醒事项」、多场会议交叉汇总与追问。
- **中文友好原生 GFM Markdown 渲染**：自研行内解析器彻底解决中文标点紧邻加粗/斜体/代码时的渲染错位问题，完整支持表格、代码块与流式「问 AI」。
- **多渠道导出 & 全库安全迁移**：
  - 一键推送至 **飞书交互卡片 / 钉钉 Markdown / Notion & n8n 自定义 JSON Webhook**（内置官方 HMAC-SHA256 验签）。
  - 一键复制富文本（HTML/RTF）、导出分页 A4 PDF、复制 Markdown / Mermaid 导图。
  - `.zip` 全库备份与换机无损合并恢复（自动剔除 Keychain 密钥，安全分享与迁移）。

---

## 环境要求

- **系统**：macOS 15.0 (Sequoia) 及以上
- **芯片**：Apple Silicon（M1 / M2 / M3 / M4 系列，推荐 ≥16 GB 统一内存以获得最佳本地 MLX 体验）
- **工具链**：Xcode 16+（含 `MetalToolchain`，用于编译 MLX Metal GPU 着色器）

---

## 构建、测试与安装

> 由于项目集成了 `mlx-swift` Metal GPU 着色器，请使用 `xcodebuild`（或提供的构建脚本）打包完整 `.app`，而非纯 `swift build`。

```bash
# 1. 克隆仓库
git clone https://github.com/eeachen4/Sonote.git
cd Sonote

# 2. 若首次编译提示缺少 Metal Toolchain，先安装一次
xcodebuild -downloadComponent MetalToolchain

# 3. 运行离线单元测试
xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release

# 4. 构建并打包原生 macOS 应用 (dist/Sonote.app)
chmod +x scripts/build_app.sh scripts/install_app.sh scripts/package_dmg.sh
./scripts/build_app.sh

# 5. 一键安装到 /Applications/Sonote.app 并启动（推荐）
./scripts/install_app.sh

# 6. 打包可分发的 .dmg 安装镜像 (dist/Sonote-1.5.0-arm64.dmg)
./scripts/package_dmg.sh
```

### 可选：Apple Silicon 实机 MLX 集成验证

```bash
# 验证 DeepFilterNet3 v3 降噪 + ECAPA-TDNN 声纹 + Sortformer 分离 + 跨会议自动认人
TEST_RUNNER_SONOTE_LIVE_V15=1 xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release

# 验证本地 MLX Qwen3-ASR 中英混说识别
TEST_RUNNER_SONOTE_LIVE_MLX=1 xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release
```

---

## 隐私与本地数据

- 所有会议纪要、逐字稿、录音 `.m4a` 与 192 维 ECAPA 声纹库均保存在本机 `~/Library/Application Support/Sonote/`。
- 所有云端 API Key 与 Webhook 签名密钥均加密存储于本机 macOS Keychain（`com.sonote.app`），导出备份包时自动排除密钥。
- 开启 **MLX Qwen3-ASR + 内置离线 MLX LLM** 后，从录音、降噪、声纹认人到生成会议纪要全程 **100% 离线运行**，无任何会议音频或文本离开你的 Mac。

---

## 开源协议

本项目基于 [MIT License](./LICENSE) 开源。
