# Sonote (声记)

<p align="center">
  <strong>Native macOS AI Meeting Minutes powered 100% on-device by Apple Silicon MLX</strong>
</p>

<p align="center">
  <strong>English</strong> · <a href="./README.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0%2B-000000?logo=apple" alt="macOS 15+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-MLX-2468F2" alt="Apple Silicon MLX" />
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/License-MIT-22C55E" alt="MIT License" />
</p>

**Sonote** is a native SwiftUI meeting minutes app built for Apple Silicon Macs — no Electron, no virtual audio drivers (no BlackHole), and no external Python/Ollama server required.

Behind a calm, minimalist light UI, Sonote runs an end-to-end on-device **MLX** audio & intelligence pipeline: **CoreAudio system audio + mic dual capture**, **DeepFilterNet3 neural speech denoising**, **streaming Silero VAD**, **Qwen3-ASR bilingual transcription**, **Sortformer & ECAPA-TDNN cross-meeting voiceprint recognition**, and a **built-in quantized Qwen2.5 MLX LLM** alongside cloud providers (OpenAI, Claude, Gemini, Ollama, Codex).

---

## Highlights

- **Zero-Friction Meeting Detection & Calendar Sync**: Detects active calls across Zoom, Teams, Feishu, DingTalk, Tencent Meeting, WeCom, Slack, Discord, Webex, FaceTime, and browser meetings via CoreAudio (no Accessibility or full Screen Recording permission needed). Automatically pulls meeting titles & attendee names from macOS Calendar (EventKit).
- **Dual-Track Audio Capture & Synced Playback**: Captures system audio via macOS 15 `CoreAudio Process Tap` + microphone via `AVAudioEngine`, handles AirPods/headset hot-swapping automatically, saves lightweight `.m4a` recordings, and supports variable-speed playback (`1x`–`2x`) synced to transcript timestamps.
- **Full On-Device Apple Silicon MLX Audio Stack**:
  - **Qwen3-ASR (`mlx-audio-swift`)**: High-accuracy bilingual Chinese/English transcription with team glossary & calendar attendee hotwords; automatically unloads GPU memory after meetings.
  - **Streaming Silero VAD**: 512-sample (32 ms) frame-by-frame LSTM endpointing.
  - **DeepFilterNet3 v3 Denoiser**: Neural speech enhancement (~59x real-time on M4 Pro) for noisy offices and cafés.
  - **Local ECAPA-TDNN Voiceprint Library & Diarization**: 192-dim speaker embeddings persisted 100% offline. Supports **Sortformer** (≤4 speakers) and **ECAPA online clustering** (5–12+ speakers) to automatically identify real names across meetings.
- **Built-In Offline MLX LLM + Multi-Provider Cloud AI (Global & Chinese LLMs)**:
  - Run quantized `Qwen2.5-Instruct` (`1.5B` / `3B` / `7B` 4-bit) directly inside the app via Metal GPU with zero external servers or token fees.
  - First-class support for **DeepSeek** (`deepseek-chat` / `deepseek-reasoner` with cache-hit & `<think>` handling), **Alibaba Qwen / DashScope** (`qwen-plus` / `qwen-max` / `qwen3-max` / `qwen-long`), and one-click presets for **Kimi (Moonshot)**, **Zhipu GLM**, **Doubao (Volcengine Ark)**, **SiliconFlow**, **MiniMax**, and **Tencent Hunyuan**.
  - Also supports **OpenAI / Ollama / MLX Server**, **Anthropic Claude**, **Google Gemini**, and local **Codex Auth** — all API keys stored in macOS Keychain.
- **Minimalist Productivity & Team Workflows**:
  - Compact floating recording capsule (`316×108`), collapsible live manual notes, custom summary prompt templates, meeting tags, global action-item tracker synced to **Apple Reminders**, and **Cross-Meeting AI Q&A**.
  - One-click **Feishu / DingTalk / Custom JSON (Notion, n8n) Webhook** push with official HMAC-SHA256 signing, rich-text HTML/RTF copy, paginated A4 PDF export, Mermaid mind maps, and portable `.zip` full-library backup & merge restore (API keys stripped).

---

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Apple Silicon Mac** (M1 / M2 / M3 / M4, 16 GB+ unified memory recommended for local MLX models)
- **Xcode 16+** with `MetalToolchain` installed

---

## Build, Test & Install

> Because Sonote compiles `mlx-swift` Metal GPU shaders, build using `xcodebuild` (via the included scripts) rather than plain `swift build`.

```bash
git clone https://github.com/eeachen4/Sonote.git
cd Sonote

# Install Metal Toolchain once if prompted on first build
xcodebuild -downloadComponent MetalToolchain

# Run offline unit tests
xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release

# Build signed native app bundle (dist/Sonote.app)
chmod +x scripts/build_app.sh scripts/install_app.sh scripts/package_dmg.sh
./scripts/build_app.sh

# Install to /Applications/Sonote.app and launch
./scripts/install_app.sh

# Package distributable .dmg (dist/Sonote-1.5.0-arm64.dmg)
./scripts/package_dmg.sh
```

---

## Privacy First

- All transcripts, minutes, `.m4a` audio backups, and 192-dim voiceprint profiles stay locally in `~/Library/Application Support/Sonote/`.
- All API keys and Webhook signing secrets are stored strictly in macOS Keychain (`com.sonote.app`) and excluded from exported `.zip` backups.
- With **MLX Qwen3-ASR + Built-in Local MLX LLM**, the entire meeting pipeline runs **100% offline on your Mac**.

---

## License

Released under the [MIT License](./LICENSE).
