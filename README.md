# Zphyr

Zphyr is a macOS voice dictation app focused on developer workflows.
It records audio locally, transcribes with WhisperKit, post-processes the text, and injects it back into the active app.

The project is SwiftUI-first and currently built as a native macOS app (`.xcodeproj`).

## Highlights

- 100% local transcription pipeline (no external LLM calls in the dictation flow)
- Whisper model download + loading flow with onboarding/preflight UI
- Hold-to-dictate global shortcut (customizable key)
- Context-aware post-processing:
- Writing tone per app context (personal/work/email/other)
- Optional formal punctuation + paragraph formatting
- Filler-word cleanup by language
- Contextual link snippets (LinkedIn, social, contact email)
- Custom dictionary with spoken aliases to improve recognition
- Dictionary-learning suggestions after manual corrections
- Multi-language UI and dictation language support

## Tech Stack

- Swift 5
- SwiftUI + Observation
- AppKit/Accessibility APIs for global keyboard events and text insertion
- AVFoundation for audio capture
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) for on-device transcription

## Requirements

- macOS (project currently set to deployment target `26.2` in Xcode build settings)
- Xcode with Swift Package Manager support
- Microphone permission
- Accessibility permission (required for auto-insert into other apps)

## Getting Started

1. Clone this repository:
```bash
git clone https://github.com/aristocratte/Zphyr.git
cd Zphyr
```

2. Open the project:
```bash
open Zphyr.xcodeproj
```

3. Build and run the `Zphyr` target in Xcode.

4. On first launch:
- Complete onboarding
- Grant microphone permission
- Optionally grant Accessibility (needed for automatic text injection)
- Let the app download/load the Whisper model

## How To Use

1. Keep your cursor in any target app or editor.
2. Hold the configured trigger key (default: right `Option` key).
3. Speak.
4. Release the key to transcribe.
5. Zphyr injects the processed text into the previously focused app (or falls back to clipboard-based insertion when relevant settings/permissions apply).

## Main Project Structure

- `Zphyr/ZphyrApp.swift`: app entry point, menu bar item, window lifecycle
- `Zphyr/ContentView.swift`: top-level flow routing (Onboarding → Preflight → Main)
- `Zphyr/PreflightView.swift`: immersive setup slides + model readiness
- `Zphyr/MainView.swift`: app shell + sidebar + settings overlay
- `Zphyr/DictationEngine.swift`: core pipeline (audio → Whisper → post-process → insert)
- `Zphyr/AppState.swift`: shared observable state + permissions/model/dictation status
- `Zphyr/ShortcutManager.swift`: global/local hold-to-dictate shortcut listener
- `Zphyr/ContextFetcher.swift`: extracts focused-app tokens for prompt context
- `DictionaryView.swift`: custom dictionary storage and management UI

## Testing

Basic test targets are present:

- `ZphyrTests`
- `ZphyrUITests`

Run from Xcode (`Product > Test`) or from command line:

```bash
xcodebuild test \
  -project Zphyr.xcodeproj \
  -scheme Zphyr \
  -destination 'platform=macOS'
```

## Notes

- The app is currently optimized for a developer-centric dictation workflow on macOS.
- Advanced formatting/snippet behavior is language-dependent in parts of the pipeline.
