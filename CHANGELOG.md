# Changelog

All notable changes to **Sonote（声记）** are documented in this file.

## [Unreleased]

### Added
- **Obsidian / Local Markdown Folder Auto-Sync** (`MarkdownFolderSyncService`): Automatically exports completed meetings as YAML-frontmatter `.md` notes (`title`, `date`, `duration`, `tags`, `participants`, `meeting_id`), updating existing files in-place on regeneration without duplicates, plus one-click batch sync in **Settings → Sync & Backup**.
- **First-Launch 3-Step Setup Guide** (`OnboardingCardView`): Dismissible Home checklist covering Mic/System Audio permissions, local MLX Qwen3-ASR preload (with `hf-mirror.com` toggle), and AI provider / offline MLX selection (re-openable from General Settings).
- **Enhanced Playback & Transcript UX**: Added `±10s` skip controls, Spacebar play/pause shortcut, toggleable transcript auto-scroll following active playback, and in-transcript keyword search with match count & inline highlighting.
- **Fast Meeting Metadata Index** (`MeetingStore`): Added `meetings_index.json` for fast startup/search across large libraries, on-demand single-session loading (`loadMeeting(id:)`), and resilient skipping of corrupted JSON files.
- **Official Homebrew Tap**: Published `eeachen4/homebrew-tap` enabling `brew install --cask eeachen4/tap/sonote`, plus optional Apple Developer ID signing & notarization in `.github/workflows/release.yml`.
- **Expanded Unit Tests**: Added 6 new offline test suites covering Obsidian frontmatter sync, fast index & corrupted JSON resilience, settings backward compatibility, Webhook HMAC-SHA256 payloads, multi-provider SSE/thinking-tag parsers, and WAV/resampling.

### Changed
- **100% Live Bilingual EN/ZH Coverage**: Localized all remaining views across Main Window, Meeting Workspace, Live Summary, Transcript Pane, Floating HUD Panels, Global Action Items, Cross-Meeting AI Q&A, and AppState status notices.
- **Modular Architecture**: Refactored `AppState.swift` (1,610 lines) into 5 domain files (`AppState`, `+Recording`, `+MinutesAI`, `+VoiceprintsAndImport`, `+Integrations`) and split `MeetingWorkspaceView.swift` (1,379 lines) into `MeetingWorkspaceView` + 3 focused `UI/Workspace/` modules.
- **CI/CD Upgrade**: Upgraded GitHub Actions runners to `macos-26` (Swift 6.3+ for `mlx-audio-swift`), upgraded `actions/checkout@v7` & `actions/cache@v6`, and improved `default.metallib` resolution in `scripts/build_app.sh`.

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
