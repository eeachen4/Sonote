# Contributing to Sonote

Thank you for your interest in contributing to **Sonote（声记）**!

## Development Requirements

- **macOS 15.0 (Sequoia)** or later on **Apple Silicon** (`arm64`)
- **Xcode 16+** with `MetalToolchain` installed (`xcodebuild -downloadComponent MetalToolchain`)

> **Important:** Because Sonote compiles `mlx-swift` Metal GPU shaders, always build and test using `xcodebuild` (or `./scripts/build_app.sh`) instead of plain `swift build`.

## Local Workflow

```bash
# 1. Run fast offline unit tests (~1s incremental)
xcodebuild test \
  -scheme Sonote-Package \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -derivedDataPath .build/xcode-release

# 2. Build signed app bundle (dist/Sonote.app)
./scripts/build_app.sh

# 3. Install to /Applications/Sonote.app and launch
./scripts/install_app.sh
```

### Opt-in Live Apple Silicon MLX Hardware Tests

Live integration tests download HuggingFace models on first run and verify real GPU inference:

```bash
# DeepFilterNet3 v3 + ECAPA-TDNN + Sortformer + cross-meeting auto-ID
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

## Project Layout

- `Sources/SonoteCore/`: Pure Swift library (models, audio capture, MLX ASR/VAD/denoiser/voiceprint/LLM engines, multi-provider AI client, Keychain & archive backup, webhooks, CJK Markdown parser).
- `Sources/Sonote/`: Native SwiftUI macOS application shell, adaptive Light/Dark theme engine (`Theme.swift`), modular Settings tabs (`UI/Settings/`), workspace & floating HUD panels.
- `Tests/SonoteTests/`: Fast offline unit tests + opt-in hardware tests.
- `scripts/`: App icon generator, `xcodebuild` bundler, `.dmg` packager, and `/Applications` installer.

## Pull Request Guidelines

- Follow conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`).
- Ensure any UI change looks crisp in **both Light and Dark mode** and supports `L("中文", "English")` live localization.
- Never hardcode API keys, personal names, or signing Team IDs.
- Add unit tests in `Tests/SonoteTests/SonoteTests.swift` for new parsers, storage, or provider logic.
