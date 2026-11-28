# Changelog

All notable changes to **Sonote（声记）** are documented in this file.

## [1.7.0] - 2026-11-28

### Added
- **Document-Flow Structured Minutes Editor (`MinutesEditorView`)**: Rebuilt the post-meeting editing experience with auto-wrapping multi-line inputs, numbered card-grouped Key Topics, full add/edit/delete across all 5 sections (Summary, Key Topics, Decisions, Action Items with Enter-to-add, and Open Questions), transactional draft snapshots with `⌘⏎` Save & `Esc` Cancel, automatic whitespace/blank cleanup (`SmartMinutes.sanitizedForSave()`), and automatic Obsidian Markdown folder sync on save.
- **Interactive Audio Waveform Scrubber (`AudioWaveformExtractor` + `AudioWaveformScrubber`)**: Extracts 88-bar normalized RMS waveforms off the main thread via fast `AVAudioFile` + universal `AVAssetReader` fallback (supporting `.m4a/.mp3/.wav/.mp4/.mov`), with click/drag scrubbing, hover timestamp badges, and automatic reload on `audioFilePath` updates.
- **Floating Desktop Live Subtitle Bar & Optional Bilingual Translation (`LiveSubtitlePanelController`)**: Draggable bottom-center translucent HUD displaying live speaker badges, real-time transcript text, and an optional second-line AI bilingual translation (`GPTClient.translateSubtitleLine`), toggleable from both the floating capsule and the live transcript toolbar.
- **Crash-Safe Recording Checkpoints & Recovery Banner**: Automatically persists in-progress meetings every 30 seconds during recording, detects interrupted sessions on next launch (`MeetingStore.detectInterruptedMeetingIDs()`), and displays a one-click Home recovery banner to review or generate AI minutes.
- **Open-Source Community & CI/CD Standards**: Added `CODE_OF_CONDUCT.md` (100% GitHub Community Profile), `.github/dependabot.yml`, explicit least-privilege `permissions: contents: read` in CI, and compiled build-product caching in both CI (`~2m 44s` warm runs) and Release workflows.

### Changed
- **App-Wide Input Field Craft**: Introduced crisp `AppTheme.inputBackground` / `inputBorder` / `inputHoverBorder` tokens with hover & brand focus rings, secret reveal eye toggles, legible disabled primary buttons, Settings window title localization, and eliminated all remaining system `.roundedBorder` text fields across the entire app.
- **100% Bilingual Core Errors & Tooltips**: Localized all remaining `SonoteCore` errors, search snippets, `TokenUsage.detailedSummary`, and `SpeakerSource` labels via `SonoteLocale`.
- **Workspace & Home Modularity**: Split `MainWindowView.swift` into `UI/Home/HomeComponents.swift` and split `MeetingWorkspaceView.swift` into `UI/Workspace/MinutesEditorView.swift` and `UI/Workspace/WorkspaceChromeAndCards.swift`.

### Fixed
- **macOS Traffic-Light Scroll Overlap**: Moved the top titlebar safe-area spacer outside the `ScrollView` in both `CompletedMeetingDocumentView` and `TranscriptPaneView` so scrolled meeting titles and transcripts never collide with the window traffic lights.
- **Accidental Overwrite Prevention During Editing**: Hid template switcher and Regenerate controls while actively editing minutes and folded `Quick Notes` into a clean collapsible section within the same save/cancel draft.

## [1.6.0] - 2026-11-27

### Added
- **Summary Output Language (`MinutesOutputLanguage`)**: Choose **Auto (Match Transcript)**, **Always Simplified Chinese**, or **Always English** in **Settings → Templates** (e.g., summarize English meetings directly into Chinese minutes or vice versa).
- **Live AI Streaming Preview**: Displays real-time token progress, character counter, reasoning-model (`<think>`) status badge, and collapsible live stream preview while generating minutes.
- **Obsidian / Local Markdown Folder Auto-Sync** (`MarkdownFolderSyncService`): Automatically exports completed meetings as YAML-frontmatter `.md` notes (`title`, `date`, `duration`, `tags`, `participants`, `meeting_id`), updating existing files in-place on regeneration without duplicates, plus one-click batch sync in **Settings → Sync & Backup**.
- **First-Launch 3-Step Setup Guide** (`OnboardingCardView`): Dismissible Home checklist covering Mic/System Audio permissions, local MLX Qwen3-ASR preload (with `hf-mirror.com` toggle), and AI provider / offline MLX selection (re-openable from General Settings).
- **Enhanced Playback & Transcript UX**: Added `±10s` skip controls, Spacebar play/pause shortcut, toggleable transcript auto-scroll following active playback, and in-transcript keyword search with match count & inline highlighting.
- **Fast Metadata Index & Lazy Hydration** (`MeetingStore` + `AppState`): Added `meetings_index.json` with O(1) instant startup rendering for large libraries (>25 meetings), on-demand single-session hydration (`loadMeeting(id:)`), background preloading, and resilient skipping of corrupted JSON files.
- **Official Homebrew Tap & Notarization-Ready Release Pipeline**: Published `eeachen4/homebrew-tap` enabling `brew install --cask eeachen4/tap/sonote`, plus optional Apple Developer ID signing & notarization in `.github/workflows/release.yml`.
- **Expanded Unit Tests**: Added 7 new offline test suites (24 tests total) covering `SonoteCore` bilingual i18n, summary output language prompts, Obsidian frontmatter sync, fast index & corrupted JSON resilience, settings backward compatibility, Webhook HMAC-SHA256 payloads, multi-provider SSE/thinking-tag parsers, and WAV/resampling.

### Changed
- **100% Full-Stack Live Bilingual EN/ZH Coverage**: Completed localization across both SwiftUI views and `SonoteCore` enums/status models (`SonoteLocale`) so switching to English leaves zero untranslated strings.
- **Modular Architecture**: Refactored `AppState.swift` (1,610 lines) into 5 domain files (`AppState`, `+Recording`, `+MinutesAI`, `+VoiceprintsAndImport`, `+Integrations`) and split `MeetingWorkspaceView.swift` (1,379 lines) into `MeetingWorkspaceView` + 3 focused `UI/Workspace/` modules.
- **CI/CD & Documentation**: Upgraded GitHub Actions runners to `macos-26` (Swift 6.3+ for `mlx-audio-swift`), upgraded `actions/checkout@v7` & `actions/cache@v6`, added 5 real 2× Retina UI screenshots to `README.md` / `README_EN.md`, added `AGENTS.md`, and improved `default.metallib` resolution in `scripts/build_app.sh`.

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
