# Changelog

All notable changes to **Sonote（声记）** are documented in this file.

## [1.9.0] - 2026-11-28

### Added
- **Today's Upcoming Schedule on Home & Menu Bar**: Displays upcoming macOS Calendar meetings directly on Home (with live `"Now"` indicator, attendee chips, and one-click `"Record Now"`) and in the Menu Bar popover, pre-filling meeting titles and attendee ASR hotwords automatically.
- **Transcript Bulk Find & Replace + Adjacent Segment Merge**: Added an inline Find & Replace bar across the full transcript (with automatic self-learning ASR glossary suggestions for replaced terms) plus one-click merging of consecutive short segments (<12s gap) from the same speaker.
- **Interactive Speaker Talk-Share Analytics Bar**: Added a proportional color-coded speaker talk-share bar (`MeetingSession.speakerShareStats`) above the transcript showing each speaker's speaking percentage; clicking any speaker segment or legend pill filters the transcript instantly.
- **Cross-Meeting Ask AI Date-Range Quick Selectors & Archive to Minutes**: Added one-click `This Week`, `Last 7d`, and `Last 30d` meeting selection pills in Cross-Meeting Q&A, plus **Save as Minutes** to archive cross-meeting weekly reports or blocker digests as standalone completed meetings.
- **Original Audio Export & Reveal in Finder**: Added **Export Original Audio...** and **Reveal Audio in Finder** directly in the workspace Export menu whenever a recording audio file exists.
- **Live 20s Silence / Muted-Mic Warning Banner**: Monitors combined mic & system audio levels during active recordings and surfaces a dismissible warning banner after 20 consecutive seconds of silence to prevent accidental muted recordings.
- **Re-transcribe Audio, Queued Multi-File Import with Cancel, Smart Live Highlight & Interactive Mind-Map PNG Export**:
  - Re-transcribe saved meeting audio with your latest ASR model/denoiser/glossary (with optional minutes regeneration).
  - Queue multiple audio/video files on drop or picker with a live cancel button.
  - One-click `⭐ Highlight` (`标星`) during live recording (from workspace or floating capsule) prioritized in AI summarization prompts.
  - Collapsible mind-map branches with `Expand/Collapse All`, clickable `▶ MM:SS` citations, `Copy Mermaid`, and crisp **2× Retina PNG export**.
  - Native macOS workspace keyboard shortcuts (`⌘1–4`, `⌘E`, `⌘F`, `⌘[`), Global Todos live search + **Copy Markdown**, and floating subtitle bar position persistence + `A- / A+` font size controls.

### Changed
- **Architecture, Performance & Thread-Safety Overhaul**:
  - Isolated 25Hz audio level meters into `AudioMeterState` so high-frequency waveform updates no longer invalidate the entire `AppState` view hierarchy.
  - Introduced thread-safe pause-aware `RecordingClock` shared with `TranscriptionCoordinator` so pause durations never drift transcript timestamps.
  - Replaced `AppState.settings` full-Keychain rewrites with field-diff Keychain saves + 250ms debounced async `settings.json` persistence, serial `MeetingStore` `ioQueue` with `flushPendingWrites()` on app termination, and O(1) index-based crash-recovery detection (`MeetingIndexEntry.status`).
  - Offloaded PCM resampling & copy off real-time audio callbacks in `DualAudioCaptureManager`, added subtitle translation cancellation + generation guards, cached `MinutesTimestampMatcher` lookups & `DateFormatter`s, and added explicit user alerts on export failures.

### Fixed
- **English Search Placeholder Clipping**: Widened English search inputs on Home (`215pt`) and Global Action Items (`205pt`) so placeholders never clip on the right edge.
- **Clean Timestamp Citation Stripping**: Added `MinutesTimestampMatcher.strippingExplicitCitations(in:)` so static Mind-Map 2× PNG exports, non-interactive views, and Overview sections cleanly strip or link explicit `[MM:SS]` markers with `.onAppear` cache pre-warming.

## [1.8.0] - 2026-11-28

### Added
- **Clickable Timestamp Citations in Minutes (`MinutesTimestampMatcher`)**: AI-generated key topic points, decisions, and action items now include clickable `▶ MM:SS` timestamp pills (parsing explicit `[MM:SS]` citations from AI or auto-matching the closest transcript segment locally for existing meetings). Clicking jumps straight to the transcript line and plays the synced recording from that second.
- **Self-Learning ASR Glossary (`GlossarySuggestionExtractor`)**: When manually fixing a typo or proper noun in the transcript, Sonote detects the corrected term and offers a one-click banner to add it to your ASR glossary for higher accuracy in future meetings.
- **Subtitle Export (`.srt` & `.vtt`)**: Export timestamped, speaker-labeled transcripts as standard SubRip (`.srt`) or WebVTT (`.vtt`) subtitle files directly from the Export menu (`MeetingStore.exportSRT` / `exportVTT`).
- **Meeting Pinning & Batch Management**: Pin important meetings to a dedicated **Pinned** section at the top of Home (`MeetingSession.isPinned` + `MeetingIndexEntry.isPinned`), and use Home **Select / Batch Mode** to multi-select meetings for batch tagging, batch Markdown folder export, or batch deletion.
- **Custom Ask AI Quick Prompts**: Save and reuse custom one-click Ask AI instructions (e.g., *“Write a 3-line Slack update”*, *“Draft client email”*) persisted in `AppSettings.customAskAIPrompts`.
- **PDF With Transcript Option & Menu Bar Subtitle Toggle**: Added **Export .pdf (With Transcript)** alongside minutes-only PDF export, localized PDF page footers & error messages for EN/ZH, and added a quick Live Subtitle Bar toggle inside the Menu Bar recording dock.

### Changed
- **GitHub & Release Pipeline**: Merged Dependabot `softprops/action-gh-release` v3 update and generated `docs/assets/social-preview.png` (`1280×640`) for GitHub social cards.

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
