# Changelog

All notable changes to **Sonote（声记）** are documented in this file.

## [1.5.1] - 2026-11-27

### Added
- **General Settings (`通用 / General`)**: Live interface language switching (`Follow System` / `简体中文` / `English`), adaptive `Light` / `Dark` / `Auto` appearance with miniature window previews, 6 curated global accent themes (`Cobalt`, `Indigo`, `Emerald`, `Amber`, `Rose`, `Graphite`), reading font scale (`Compact` / `Standard` / `Large`), startup/menu-bar window behavior controls, and built-in GitHub release update checker.
- **First-Class Chinese Domestic LLMs**: Dedicated Keychain-backed configuration cards for **DeepSeek** (`deepseek-chat` / `deepseek-reasoner` with `prompt_cache_hit_tokens` accounting, `reasoning_content` separation, and `<think>` tag stripping), **Alibaba Qwen / DashScope** (Beijing & Singapore regions, `qwen-plus` / `qwen-max` / `qwen3-max` / `qwq-plus` / `qwen-long`), and one-click presets for **Kimi (Moonshot)**, **Zhipu GLM**, **Doubao (Volcengine Ark)**, **SiliconFlow**, **MiniMax**, and **Tencent Hunyuan**.
- **Open-Source Infrastructure**: Pinned `mlx-audio-swift` revision in `Package.swift`, GitHub Actions CI & Release DMG workflows, Issue/PR templates, `CONTRIBUTING.md`, `SECURITY.md`, Homebrew Cask manifest (`Casks/sonote.rb`), Mermaid architecture diagram, and Apple Silicon RAM selection guide.

### Changed
- Refactored `SettingsView` into modular per-tab Swift files under `Sources/Sonote/UI/Settings/` with full bilingual ZH/EN UI coverage.
- Refactored `GPTClient` into `GPTClient.swift`, `GPTClient+Backends.swift`, and `GPTClient+Parsers.swift`.

### Fixed
- Fixed floating recording capsule expand button failing to bring the main workspace window to front when Settings was open or main window had been closed/minimized; added `AcceptsFirstMouseHostingView` for immediate single-click response while another app is active.

## [1.5.0] - 2026-11-27

### Added
- Initial open-source release of **Sonote（声记）** for macOS 15+ Apple Silicon.
- End-to-end on-device Apple Silicon MLX audio pipeline: CoreAudio Process Tap + Mic dual capture, DeepFilterNet3 v3 neural denoising, streaming Silero VAD, Qwen3-ASR bilingual transcription, Sortformer + 192-dim ECAPA-TDNN local voiceprint library with cross-meeting speaker auto-identification.
- Built-in offline MLX LLM (`MLXAudioCore.Qwen2Model`) for zero-cost local summarization.
- Multi-provider cloud AI (`Codex Auth`, `OpenAI / Ollama / MLX Server`, `Anthropic Claude`, `Google Gemini`).
- Feishu Interactive Card, DingTalk Markdown, and Custom JSON (Notion / n8n) Webhooks with official HMAC-SHA256 signing, Apple Reminders todo sync, Cross-Meeting AI Q&A, paginated A4 PDF export, and `.zip` full-library backup & non-destructive merge restore.
