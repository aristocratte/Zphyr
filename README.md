# Zphyr

Zphyr is a macOS voice dictation app built for developer workflows.
It captures audio locally, runs on-device ASR, post-processes the transcript, and inserts the final text into the active app.

The app is SwiftUI-first and shipped as a native macOS project (`.xcodeproj`).

## Highlights

- Local-first voice pipeline (no cloud transcription in the dictation flow)
- **WhisperKit** (Whisper Large v3 Turbo) as the default ASR backend — 30+ languages, ~600 MB, fully on-device
- Pluggable ASR backend architecture (`Whisper Large v3 Turbo`, `Apple Speech Analyzer`)
- Hardware-aware routing with performance tiers (`Eco`, `Balanced`, `Pro`)
- Hold-to-dictate global shortcut (default: right `Option`)
- Real-time dictation and offline audio file transcription
- Context-aware post-processing pipeline:
  - VAD-based audio trimming before ASR
  - deterministic formatter for explicit code triggers
  - optional advanced local LLM formatter with integrity fallback
  - filler-word cleanup, TODO extraction, spoken-list formatting
  - contextual snippets (LinkedIn, social, contact email)
  - tone-aware output per target app (email, messaging, code editors, …)
- Spoken meta-command detection (`CommandInterpreter`)
- Local-only performance metrics (`LocalMetrics`) — nothing leaves the device
- Custom dictionary + learning suggestions from user corrections
- Menu bar popover with model disk usage, RAM/CPU telemetry, and quick actions
- Multi-language UI and dictation language support

## Pipeline Architecture

```
Microphone
    │
    ▼
AudioCaptureService          (16 kHz mono Float32 buffer)
    │
    ▼
ASROrchestrator
    ├── VoiceActivityDetector  (VAD trim)
    └── WhisperKitBackend      (primary) / AppleSpeechAnalyzerBackend (fallback)
    │
    ▼
CommandInterpreter             (spoken meta-commands — cancel, copy, …)
    │
    ▼
TranscriptStabilizer           (filler removal → tone formatting → dictionary → snippets)
    │
    ▼
TextFormatter stack
    ├── EcoTextFormatter       (deterministic, always available)
    ├── ProTextFormatter       (LLM-based, Pro tier)
    └── TextIntegrityVerifier  (guards LLM output quality)
    │
    ▼
InsertionEngine                (CGEvent key simulation → clipboard fallback)
```

`DictationEngine` orchestrates the full session lifecycle and is observed by the UI.  
`ModelManager` handles model selection, download, and lifecycle transitions.  
`LocalMetrics` records per-session timings (ASR, stabilizer, formatter, insertion) locally.

## ASR Backends

| Backend | Model | Size | Notes |
|---|---|---|---|
| **Whisper Large v3 Turbo** *(default)* | `openai_whisper-large-v3-v20240930_turbo_632MB` | ~600 MB | WhisperKit · Apple Silicon · 30+ languages |
| Apple Speech Analyzer | built-in Speech framework | — | No download · used as fallback on Eco tier |

WhisperKit downloads once to `~/.cache/huggingface/hub/` and runs entirely on-device.

### Supported Languages (Whisper)

30 languages across two quality tiers:

**Excellent** — zh · en · ar · de · fr · es · pt · it · ko · ru · ja · nl · pl  
**Good** — id · th · vi · tr · hi · ms · sv · da · fi · cs · tl · fa · el · hu · ro · mk · yue

## Performance Tiers

Zphyr auto-detects machine profile from physical memory:

| Tier | RAM | ASR backend | LLM formatter |
|---|---|---|---|
| `Eco` | ≤ 8 GB | Apple Speech Analyzer (forced) | ✗ deterministic only |
| `Balanced` | 8–15 GB | configurable | ✓ |
| `Pro` | ≥ 16 GB | configurable | ✓ advanced mode |

## Tech Stack

- Swift 5 (MainActor-first, Observation framework)
- SwiftUI + AppKit + Accessibility APIs (global key capture + text insertion via CGEvent)
- AVFoundation (live audio capture + file decoding)
- Speech framework (Apple ASR backend)
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) (on-device Whisper inference)
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift) (optional LLM formatter)

## Requirements

- macOS 15.0+
- Xcode with Swift Package Manager support
- Microphone permission
- Accessibility permission (required for automatic insertion into other apps)
- Internet connection for first-time model download (~600 MB)
- Apple Silicon recommended

## Getting Started

1. Clone the repository:
```bash
git clone https://github.com/aristocratte/Zphyr.git
cd Zphyr
```

2. Open the project:
```bash
open Zphyr.xcodeproj
```

3. Build and run target `Zphyr` in Xcode (SPM packages resolve automatically).

4. On first launch:
  - complete onboarding/preflight
  - grant microphone permission
  - optionally grant Accessibility
  - install the Whisper model when prompted (~600 MB, one-time)

## Usage

### Live Dictation

1. Place cursor in target app/editor.
2. Hold the trigger key (default: right `Option`).
3. Speak.
4. Release key → Zphyr transcribes, stabilizes, formats, and inserts text.

If Accessibility is not granted, Zphyr falls back to clipboard insertion.

### Audio File Transcription

1. Open the `Audio` section.
2. Import an audio file.
3. Select language.
4. Run local transcription.
5. Copy or export result as `.txt`.

## Project Structure

### App shell
- `Zphyr/ZphyrApp.swift` — app lifecycle, window behavior, menu bar popover
- `Zphyr/ContentView.swift` — top-level routing (Onboarding → Preflight → Main)
- `Zphyr/PreflightView.swift` — setup flow, permissions, model onboarding
- `Zphyr/MainView.swift` — primary shell + feature sections
- `Zphyr/MenuBarPopoverView.swift` — quick-access popover (metrics, model state)

### Dictation pipeline
- `Zphyr/DictationEngine.swift` — session orchestrator (hold → capture → ASR → format → insert)
- `Zphyr/AudioCaptureService.swift` — real-time mic capture, resampling to 16 kHz mono Float32
- `Zphyr/ASROrchestrator.swift` — VAD trim → backend dispatch → timeout/quality gating
- `Zphyr/VoiceActivityDetector.swift` — silence detection and buffer trimming
- `Zphyr/TranscriptStabilizer.swift` — filler removal, tone routing, dictionary substitutions, snippets
- `Zphyr/CommandInterpreter.swift` — spoken meta-command detection (cancel, copy, list, …)
- `Zphyr/InsertionEngine.swift` — CGEvent keystroke injection with clipboard fallback

### Model management
- `Zphyr/ModelManager.swift` — backend selection, download, install, and lifecycle
- `Zphyr/ASRBackend.swift` / `ASRBackendLifecycle.swift` / `ASRBackendFactory.swift` — ASR protocol + factory
- `Zphyr/WhisperKitBackend.swift` — WhisperKit integration (Whisper Large v3 Turbo)
- `Zphyr/AppleSpeechAnalyzerBackend.swift` — Apple Speech framework backend
- `Zphyr/WhisperLanguage.swift` — supported language definitions for Whisper

### Formatting
- `Zphyr/TextFormatter.swift` — formatter protocol and dispatch
- `Zphyr/EcoTextFormatter.swift` — deterministic formatter (always available)
- `Zphyr/ProTextFormatter.swift` — LLM-based formatter (Pro tier)
- `Zphyr/AdvancedLLMFormatter.swift` — low-level MLX LLM runner
- `Zphyr/TextIntegrityVerifier.swift` — output quality guard for LLM formatter
- `Zphyr/SmartTextFormatter.swift` / `CodeFormatter.swift` — specialized formatters

### System & state
- `Zphyr/AppState.swift` — shared observable app state
- `Zphyr/PerformanceRouter.swift` — memory-tier detection and backend routing
- `Zphyr/LocalMetrics.swift` — per-session performance metrics (local only)
- `Zphyr/ShortcutManager.swift` — global keyboard shortcut capture
- `Zphyr/ContextFetcher.swift` — active app context (bundle ID, focused field)
- `Zphyr/L10n.swift` — localization helpers
- `DictionaryView.swift` — custom dictionary UI

## Testing

Targets:

- `ZphyrTests` — unit tests (formatting pipeline, …)
- `ZphyrUITests` — UI automation tests

Run tests from Xcode (`Product > Test`) or CLI:

```bash
xcodebuild test \
  -project Zphyr.xcodeproj \
  -scheme Zphyr \
  -destination 'platform=macOS'
```

## Privacy

- Audio is captured, processed, and transcribed entirely on-device.
- No external LLM or transcription API is called during the dictation pipeline.
- `LocalMetrics` records per-session timings locally and never transmits data.
- Data stays on device except for the one-time model download on first setup.
