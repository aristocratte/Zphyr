# Zphyr

Zphyr is a macOS voice dictation app built for developer workflows.
It captures audio locally, runs on-device ASR, post-processes the transcript, and inserts the final text into the active app.

The app is SwiftUI-first and shipped as a native macOS project (`.xcodeproj`).

## Highlights

- Local-first voice pipeline (no cloud transcription in the dictation flow)
- Pluggable ASR backend architecture (`Apple Speech Analyzer`, `Qwen3-ASR (MLX)`)
- Hardware-aware routing with performance tiers (`Eco`, `Balanced`, `Pro`)
- Hold-to-dictate global shortcut (default: right `Option`)
- Real-time dictation and offline audio file transcription
- Context-aware post-processing:
  - deterministic formatter for explicit code triggers
  - optional advanced local formatter (Qwen3-1.7B) with integrity fallback
  - filler-word cleanup, TODO extraction, spoken-list formatting
  - contextual snippets (LinkedIn, social, contact email)
- Custom dictionary + learning suggestions from user corrections
- Menu bar popover with model disk usage, RAM/CPU telemetry, and quick actions
- Multi-language UI and dictation language support

## ASR Backends

- `Apple Speech Analyzer`
  - local runtime backend
  - no model download required
  - used as fallback when needed
- `Qwen3-ASR (MLX 8-bit)`
  - model: `aufklarer/Qwen3-ASR-1.7B-MLX-8bit` (~2.46 GB)
  - install/load/pause/resume/cancel flows handled in-app
  - runs fully on device after installation
- `WhisperKit`
  - currently a stub backend in this build (not integrated yet)

## Performance Tiers

Zphyr auto-detects machine profile from physical memory:

- `Eco` (`<= 8 GB`)
  - forces lightweight path (Apple backend + deterministic formatting)
- `Balanced` (`8-15 GB`)
  - local ASR backend is configurable
- `Pro` (`>= 16 GB`)
  - unlocks advanced local formatting mode

## Tech Stack

- Swift 5
- SwiftUI + Observation
- AppKit + Accessibility APIs (global key capture + text insertion)
- AVFoundation (live audio + file decoding)
- Speech framework (Apple ASR backend)
- [MLX Swift](https://github.com/ml-explore/mlx-swift) + `mlx-swift-lm` + `swift-transformers` (on-device Qwen inference)

## Requirements

- macOS deployment target: `15.0` (as set in Xcode project)
- Xcode with Swift Package Manager support
- Microphone permission
- Accessibility permission (required for automatic insertion into other apps)
- Internet connection for first-time model download(s)
- Apple Silicon recommended for MLX-based local models

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

3. Build and run target `Zphyr` in Xcode.

4. On first launch:
  - complete onboarding/preflight
  - grant microphone permission
  - optionally grant Accessibility
  - install/load local models as prompted

## Usage

### Live Dictation

1. Place cursor in target app/editor.
2. Hold the trigger key.
3. Speak.
4. Release key to transcribe and insert text.

If auto-insert is unavailable, Zphyr falls back to clipboard insertion.

### Audio File Transcription

1. Open the `Audio` section.
2. Import an audio file.
3. Select language.
4. Run local transcription.
5. Copy or export result as `.txt`.

## Project Structure

- `Zphyr/ZphyrApp.swift`: app lifecycle, window behavior, menu bar popover
- `Zphyr/ContentView.swift`: top-level routing (Onboarding -> Preflight -> Main)
- `Zphyr/PreflightView.swift`: setup flow, permissions, model onboarding
- `Zphyr/MainView.swift`: primary shell + feature sections (Home, Dictionary, Audio, Snippets, Style)
- `Zphyr/DictationEngine.swift`: core pipeline (capture -> backend ASR -> formatting -> insertion)
- `Zphyr/ASRBackend*.swift`: ASR abstraction, lifecycle, backend factory
- `Zphyr/AppleSpeechAnalyzerBackend.swift`: Apple ASR implementation
- `Zphyr/QwenMLXBackend.swift`: Qwen3-ASR backend implementation
- `Zphyr/PerformanceRouter.swift`: memory-tier routing logic
- `Zphyr/TextFormatter.swift`, `EcoTextFormatter.swift`, `ProTextFormatter.swift`: formatting strategy layer
- `Zphyr/TextIntegrityVerifier.swift`: guards advanced formatter output
- `DictionaryView.swift`: custom dictionary UI

## Testing

Targets:

- `ZphyrTests`
- `ZphyrUITests`

Run tests from Xcode (`Product > Test`) or CLI:

```bash
xcodebuild test \
  -project Zphyr.xcodeproj \
  -scheme Zphyr \
  -destination 'platform=macOS'
```

## Privacy

- Audio processing and transcription are local.
- No external LLM API is called during the dictation pipeline.
- Data stays on device except explicit model downloads.
