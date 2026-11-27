# Security & Privacy Policy

## Privacy Architecture

Sonote is built **local-first**:

- **On-device storage**: All transcripts, summaries, `.m4a` audio backups, and 192-dim ECAPA-TDNN voiceprint vectors live strictly under `~/Library/Application Support/Sonote/`.
- **Keychain isolation**: All AI API keys (`OpenAI`, `DeepSeek`, `DashScope/Qwen`, `Claude`, `Gemini`, domestic cloud providers) and Webhook signing secrets are stored exclusively in **macOS Keychain** (`com.sonote.app`) and are never written in plaintext to `settings.json` or exported `.zip` backup archives.
- **100% offline mode**: When configured with **MLX Qwen3-ASR** + **Built-in Offline MLX LLM**, zero meeting audio or transcript data leaves your Mac.
- **Minimal macOS permissions**: System audio capture uses macOS 15 `CoreAudio Process Tap` (Audio Capture permission only — no Accessibility permission and no full Screen Recording permission required).

## Reporting a Vulnerability

If you discover a security vulnerability (such as secret leakage, unsafe file handling, or webhook/signing issues):

1. **Do not** open a public GitHub issue with exploit details.
2. Please use GitHub's **Security → Advisories → Report a vulnerability** feature on [eeachen4/Sonote](https://github.com/eeachen4/Sonote/security/advisories), or contact the maintainer privately.
3. We will acknowledge reports within 48 hours and coordinate a fix before public disclosure.
