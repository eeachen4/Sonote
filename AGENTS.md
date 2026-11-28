# AGENTS.md

Guidance for AI coding agents working on **Sonote（声记）** — a native macOS 15+ (Apple Silicon) SwiftUI AI meeting minutes app powered by on-device MLX audio and LLM engines.

---

## 1. Environment & Critical Build Rules

- **Platform**: macOS 15.0 (Sequoia)+ on Apple Silicon (`arm64`), Xcode 16+ with `MetalToolchain` (`xcodebuild -downloadComponent MetalToolchain`).
- **Swift Package**: `swift-tools-version: 6.0` with targets compiled under `.swiftLanguageMode(.v5)` in [Package.swift](Package.swift).
- **CRITICAL — Always use `xcodebuild`, NOT plain `swift build`**:
  `mlx-swift` compiles Metal GPU shaders (`default.metallib`) that plain SwiftPM cannot build into the bundle. Reuse `-derivedDataPath .build/xcode-release` for fast (~1–4s) incremental builds and tests.

### Standard Commands

```bash
# Fast offline unit tests (run after every code change)
xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -derivedDataPath .build/xcode-release

# Build signed native app bundle (dist/Sonote.app with Metal shaders)
./scripts/build_app.sh

# Install to /Applications/Sonote.app and relaunch
./scripts/install_app.sh

# Package distributable arm64 .dmg
./scripts/package_dmg.sh
```

### Opt-In Live Apple Silicon MLX Hardware Tests

These download HuggingFace models on first run and validate real Metal GPU inference (skipped in CI and default offline runs):

```bash
# DeepFilterNet3 v3 denoising + ECAPA-TDNN voiceprints + Sortformer diarization
TEST_RUNNER_SONOTE_LIVE_V15=1 xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -derivedDataPath .build/xcode-release

# Qwen3-ASR bilingual transcription
TEST_RUNNER_SONOTE_LIVE_MLX=1 xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -derivedDataPath .build/xcode-release
```

---

## 2. Architecture & Repository Map

```text
Sonote/
├── Package.swift                           # SPM manifest (SonoteCore, Sonote, SonoteTests)
├── Resources/Info.plist                    # Bundle metadata, permissions & version
├── scripts/
│   ├── build_app.sh                        # Icon gen + xcodebuild + Metal shader bundle + codesign
│   ├── install_app.sh                      # Stops running app, copies to /Applications, relaunches
│   ├── package_dmg.sh                      # Builds release .dmg + SHA256
│   └── generate_icon.swift                 # Programmatic AppIcon.icns generator
├── Casks/sonote.rb                         # Homebrew Cask formula
├── .github/workflows/                      # ci.yml (build + test) & release.yml (tag -> DMG)
├── Sources/
│   ├── SonoteCore/                         # Core Swift library (business logic, audio, MLX, AI, storage)
│   │   ├── Models/
│   │   │   ├── AppSettings.swift           # Settings, LLM/ASR providers, themes, backward-safe Codable
│   │   │   ├── MeetingModels.swift         # MeetingSession, TranscriptSegment, SmartMinutes, TokenUsage
│   │   │   └── VoiceprintModels.swift      # 192-dim ECAPA-TDNN VoiceprintProfile
│   │   └── Services/
│   │       ├── AI/
│   │       │   ├── GPTClient.swift         # Public AI orchestration, live incremental & Map-Reduce summary
│   │       │   ├── GPTClient+Backends.swift# DeepSeek, Qwen, OpenAI/Domestic, Claude, Gemini, Codex, MLX
│   │       │   ├── GPTClient+Parsers.swift # JSON extraction, <think> stripping, usage/cache token parsing
│   │       │   └── LocalMLXLLMEngine.swift # Built-in on-device Qwen2.5 MLX LLM (no Ollama needed)
│   │       ├── Audio/
│   │       │   ├── DualAudioCaptureManager.swift # Dual-track orchestrator, hot-swap reconnect, .m4a mix
│   │       │   ├── SystemAudioTapCapture.swift   # macOS 15 CoreAudio Process Tap (no virtual driver)
│   │       │   ├── MicrophoneCapture.swift       # AVAudioEngine mic capture
│   │       │   ├── SpeechEnhancementService.swift# MLX DeepFilterNet3 v3 neural denoiser
│   │       │   ├── AudioWaveformExtractor.swift  # AVAudioFile + AVAssetReader RMS waveform bins
│   │       │   └── WAVEncoder.swift
│   │       ├── Transcription/
│   │       │   ├── TranscriptionCoordinator.swift # Silero streaming VAD + ASR + live diarization
│   │       │   ├── MLXQwen3ASREngine.swift        # MLX Qwen3-ASR bilingual STT + hf-mirror support
│   │       │   ├── SpeechTranscriberEngines.swift # Apple Speech & OpenAI Transcribe fallbacks
│   │       │   ├── SpeakerDiarizerService.swift   # Sortformer (<=4) & ECAPA online clustering (5–12+)
│   │       │   ├── VoiceprintService.swift        # Local ECAPA-TDNN enrollment & cosine matching
│   │       │   └── AudioFileImporter.swift        # Offline audio/video import & audio track extraction
│   │       ├── Auth/
│   │       │   ├── AuthManager.swift              # Credential resolution across all providers
│   │       │   └── KeychainStore.swift            # macOS Keychain (com.sonote.app + legacy fallback)
│   │       ├── Storage/
│   │       │   ├── MeetingStore.swift             # JSON persistence + meetings_index.json + TTMinutes migration
│   │       │   └── ArchiveBackupService.swift     # .zip full-library backup & merge restore
│   │       ├── Detection/MeetingDetector.swift    # CoreAudio process-level meeting auto-detection
│   │       ├── Calendar/CalendarContextService.swift # EventKit title & attendee hotwords
│   │       ├── Export/
│   │       │   ├── WebhookPushService.swift       # Feishu / DingTalk / custom JSON HMAC-SHA256 webhooks
│   │       │   └── MarkdownFolderSyncService.swift# Obsidian / Logseq YAML frontmatter .md auto-sync
│   │       ├── Markdown/MarkdownParser.swift      # CJK-safe inline/block GFM Markdown parser
│   │       └── System/                            # GlobalHotKeyService (Carbon), LaunchAtLogin, UpdateChecker
│   └── Sonote/                             # Native macOS SwiftUI application target
│       ├── App/
│       │   ├── SonoteApp.swift             # App entry, Window/MenuBarExtra/Settings scenes, AppDelegate
│       │   ├── AppState.swift              # Core @MainActor state, detector & storage mutations
│       │   ├── AppState+Recording.swift    # Recording lifecycle, timers & floating capsule controls
│       │   ├── AppState+MinutesAI.swift    # Live/final AI summary, Obsidian auto-sync & Ask AI
│       │   ├── AppState+VoiceprintsAndImport.swift # Media import, diarization & voiceprint enrollment
│       │   ├── AppState+Integrations.swift # Tags, Reminders, Webhooks, Obsidian sync, Backup & MLX
│       │   ├── MeetingAudioPlayer.swift    # Variable-speed playback synced to transcript timestamps
│       │   └── MeetingPDFExporter.swift    # Paginated A4 PDF renderer
│       └── UI/
│           ├── Theme.swift                 # ThemeManager + adaptive Light/Dark AppTheme + L("zh", "en")
│           ├── MainWindowView.swift        # Home dashboard & navigation shell
│           ├── Home/HomeComponents.swift   # Action cards, meeting rows, paste sheet & window accessor
│           ├── OnboardingCardView.swift    # Dismissible 3-step first-launch setup checklist
│           ├── MeetingWorkspaceView.swift  # Post-meeting document + live 2-column split workspace
│           ├── Workspace/                  # Modular sections (Chrome/Cards, MinutesEditor, Transcript, AskAI, Audio)
│           ├── SmartMinutesPaneView.swift  # Summary, Mind-Map, Action Items, Ask AI
│           ├── TranscriptPaneView.swift    # Dual-track speaker transcript + inline speaker rename
│           ├── FloatingPanels.swift        # Non-activating HUD prompts & compact floating recording capsule
│           ├── MenuBarView.swift           # MenuBarExtra popover
│           ├── MarkdownContentView.swift   # Native SwiftUI renderer for MarkdownParser AST
│           ├── ProductivitySheetsView.swift# Global action items, cross-meeting Q&A, text-to-minutes
│           └── Settings/                   # Modular 2-column Settings window (1 file per tab)
│               ├── SettingsView.swift
│               ├── SettingsComponents.swift
│               ├── SettingsGeneralPage.swift
│               ├── SettingsAIModelPage.swift
│               ├── SettingsAudioPage.swift
│               ├── SettingsVoiceprintPage.swift
│               ├── SettingsTemplatesPage.swift
│               ├── SettingsDetectionPage.swift
│               └── SettingsSyncBackupPage.swift
└── Tests/SonoteTests/SonoteTests.swift     # Offline unit tests + opt-in hardware tests
```

---

## 3. Core Engineering Invariants & Pitfalls

### Security, Privacy & Keychain
- **Never write secrets to disk or git**: API keys (`deepSeekAPIKey`, `qwenAPIKey`, `openAIAPIKey`, `claudeAPIKey`, `geminiAPIKey`, `webhookSecret`, etc.) are persisted exclusively in **macOS Keychain** (`com.sonote.app`, with read fallback to legacy `com.ttminutes.app`). `settings.json` must never store plaintext credentials.
- **Be careful with `AppState.settings` mutations**: `AppState.settings.didSet` invokes `MeetingStore.shared.saveSettings(settings)`, which updates Keychain and **deletes** keys if saved as empty strings. Never mutate `AppState.shared.settings` with mock or blank settings in tests, previews, or helper code.
- **Never commit user data or secrets**: Do not commit personal transcripts, recordings, signing Team IDs, `.DS_Store`, or `default.profraw`.

### Backward-Compatible Persistence
- Data lives in `~/Library/Application Support/Sonote/` (auto-migrated non-destructively from legacy `~/Library/Application Support/TTMinutes/`).
- When adding new fields to `AppSettings`, `MeetingSession`, `SmartMinutes`, or `VoiceprintProfile`, **always provide fallback defaults in `init(from decoder:)`** using `decodeIfPresent` so existing users' JSON files never fail to decode.

### Adaptive Theming & Live Bilingual UI
- **Light & Dark Mode**: Use `AppTheme.*` tokens from [Sources/Sonote/UI/Theme.swift](Sources/Sonote/UI/Theme.swift) (backed by dynamic `NSColor(name:dynamicProvider:)` synced through `ThemeManager.shared`). Avoid hardcoded `Color.white` or `Color.black` on surfaces/text.
- **Live Localization**: Wrap all user-facing strings in `L("简体中文", "English")` so switching language in General Settings updates every view immediately without restarting the app.
- **Settings Modularity**: Keep [SettingsView.swift](Sources/Sonote/UI/Settings/SettingsView.swift) lean. Put tab-specific controls in the matching `Sources/Sonote/UI/Settings/Settings*Page.swift` file and shared cards/buttons in `SettingsComponents.swift`.

### macOS Windowing & Floating Panels
- Floating HUD panels (`FloatingHUDPanel` in [FloatingPanels.swift](Sources/Sonote/UI/FloatingPanels.swift)) must use `AcceptsFirstMouseHostingView` so buttons (such as expanding the floating capsule) respond on the first click even when Sonote is not the active app.
- The main window is tracked via `MainWindowAccessor` using identifier `"sonote-main-window"` with a SwiftUI `openWindow(id: "main")` fallback. Never rely on loose window matching that could select `Settings`, `MenuBarExtra`, or `FloatingHUDPanel`.

### AI Providers & Parsers
- All providers (DeepSeek V3/R1, Alibaba Qwen/DashScope, domestic OpenAI-compatible presets, OpenAI/Ollama, Claude, Gemini, Codex Auth, and Built-in Offline MLX) route through `GPTClient` (`GPTClient.swift`, `GPTClient+Backends.swift`, `GPTClient+Parsers.swift`).
- Preserve `<think>...</think>` stripping before JSON decoding and accurate `prompt_cache_hit_tokens` / `reasoning_tokens` parsing for reasoning models (DeepSeek R1, QwQ, OpenAI reasoning models).

### Audio, MLX & Dependencies
- **Audio thread safety**: CoreAudio / `AVAudioEngine` tap callbacks run on real-time audio threads. Never block, perform disk I/O, or synchronously hop to `@MainActor` inside audio callbacks.
- **Memory discipline**: Preserve automatic MLX weight unloading after meetings so idle background memory remains ~50–90 MB.
- **Dependency pinning**: `mlx-audio-swift` is pinned to an exact commit revision in [Package.swift](Package.swift) because upstream `main` occasionally introduces breaking API changes. Always verify both unit tests and opt-in MLX live tests before updating the revision.

---

## 4. Coding Style & Workflow Checklist

1. **Design aesthetic**: Maintain the minimalist, airy Light/Dark editorial UI (clean spacing, hairline borders, clear visual hierarchy, CJK-friendly Markdown typography).
2. **Test coverage**: Add or update unit tests in [Tests/SonoteTests/SonoteTests.swift](Tests/SonoteTests/SonoteTests.swift) for any changes to models, parsers, auth resolution, providers, backup/storage, or Markdown rendering.
3. **Verify before finishing**:
   - Run `xcodebuild test -scheme Sonote-Package -destination 'platform=macOS,arch=arm64' -configuration Release -derivedDataPath .build/xcode-release` and ensure 0 failures.
   - If UI or bundle resources changed, run `./scripts/build_app.sh` to verify clean app bundling and signing.
4. **Commit & release conventions**:
   - Use Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`).
   - When bumping versions, keep `Resources/Info.plist`, `CHANGELOG.md`, and `Casks/sonote.rb` aligned.
