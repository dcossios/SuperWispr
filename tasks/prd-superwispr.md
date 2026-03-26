# PRD: superWispr

## Introduction

superWispr is a free, fully local, macOS voice-to-text dictation tool that replicates the core experience of [Wispr Flow](https://wisprflow.ai). It runs entirely on-device using [insanely-fast-whisper](https://github.com/Vaibhavs10/insanely-fast-whisper) for transcription, requires no internet connection, and sends zero data to external servers.

The app lives in the macOS menu bar as a native Swift application. A global push-to-talk hotkey lets users dictate into any text field in any application. A local Python backend handles transcription via Whisper models accelerated on Apple Silicon (MPS), then applies a text cleanup pipeline that removes filler words and normalizes punctuation before pasting the result into the active app.

### Problem Statement

Wispr Flow costs $15/month and requires an internet connection. Existing open-source alternatives are either CLI-only, lack system-wide integration, or require manual file-based workflows. There is no polished, free, offline macOS dictation tool that combines fast local Whisper transcription with system-wide push-to-talk input.

---

## Goals

- Provide system-wide voice dictation on macOS via a single hotkey, with text appearing in any active text field
- Run 100% locally with no network dependency and no data leaving the machine
- Achieve transcription latency under 3 seconds for a typical 15-second utterance on Apple Silicon (M1+)
- Automatically clean transcribed text: remove filler words ("uh", "um", "like"), normalize punctuation, and fix capitalization
- Deliver a native macOS menu bar experience that feels lightweight and invisible until needed
- Support multiple Whisper model sizes so users can trade off speed vs. accuracy for their hardware

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Swift Menu Bar App                     │
│                                                         │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐ │
│  │ NSStatus │  │ Global Hotkey│  │  AVAudioRecorder  │ │
│  │   Item   │  │  (CGEvent)   │  │  (WAV capture)    │ │
│  └──────────┘  └──────┬───────┘  └────────┬──────────┘ │
│                       │                    │            │
│              hold ──► │    start/stop ──►  │            │
│              release─►│                    │            │
│                       │                    │            │
│  ┌────────────────────┴────────────────────┴──────────┐ │
│  │              Transcription Controller               │ │
│  │  1. Save temp .wav file                            │ │
│  │  2. POST to local Python server                    │ │
│  │  3. Receive cleaned text                           │ │
│  │  4. Copy to clipboard + simulate Cmd+V             │ │
│  └────────────────────────────────────────────────────┘ │
│                                                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Settings Window (SwiftUI)              │ │
│  │  - Hotkey config       - Model selection           │ │
│  │  - Audio input device  - Language selection         │ │
│  │  - Text cleanup toggle - Launch at login           │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │
                     HTTP (localhost:9876)
                          │
┌─────────────────────────┴───────────────────────────────┐
│               Python Transcription Server               │
│                                                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │  FastAPI  (/transcribe endpoint)                   │ │
│  │  - Receives WAV audio via multipart upload         │ │
│  │  - Runs insanely-fast-whisper pipeline (MPS)       │ │
│  │  - Applies text cleanup (filler removal, punct.)   │ │
│  │  - Returns cleaned text as JSON                    │ │
│  └────────────────────────────────────────────────────┘ │
│                                                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Model Manager                                     │ │
│  │  - Loads/caches Whisper model on startup           │ │
│  │  - Supports hot-swapping models via /config        │ │
│  │  - Keeps pipeline warm in memory                   │ │
│  └────────────────────────────────────────────────────┘ │
│                                                         │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Text Cleanup Pipeline                             │ │
│  │  - Filler word removal (regex-based)               │ │
│  │  - Repeated word/phrase deduplication              │ │
│  │  - Punctuation normalization                       │ │
│  │  - Sentence capitalization                         │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Technology | Responsibility |
|---|---|---|
| Menu Bar App | Swift / SwiftUI / AppKit | UI, global hotkey, audio recording, clipboard paste, settings, lifecycle management of Python server |
| Transcription Server | Python 3.11+, FastAPI, insanely-fast-whisper | Audio-to-text transcription, text cleanup, model management |
| Communication | HTTP over localhost | Swift sends WAV audio, Python returns cleaned text |

### Why This Split?

- **Swift for the app shell**: Native macOS integration (menu bar, global hotkeys, accessibility APIs for paste, AVFoundation for audio) is dramatically simpler and more reliable in Swift than any cross-platform alternative.
- **Python for transcription**: insanely-fast-whisper is a Python library built on HuggingFace Transformers. Keeping it in Python avoids porting complexity and benefits from the PyTorch/MPS ecosystem directly.
- **Local HTTP**: A localhost FastAPI server is the simplest IPC mechanism that allows the Swift app to manage the Python process lifecycle (start on launch, stop on quit) while keeping the two codebases cleanly separated.

---

## User Stories

### US-001: First-Time Setup

**Description:** As a new user, I want to install superWispr and have it guide me through granting the required macOS permissions so that I can start dictating immediately.

**Acceptance Criteria:**
- [ ] App opens a welcome window on first launch explaining what permissions are needed and why
- [ ] App requests Microphone permission via system dialog (triggered by `AVAudioRecorder`)
- [ ] App requests Accessibility permission and deep-links to System Settings > Privacy & Security > Accessibility
- [ ] App detects when permissions are granted and updates the welcome window status indicators
- [ ] App downloads the default Whisper model (`openai/whisper-large-v3-turbo`) on first launch with a progress indicator
- [ ] Python backend server starts automatically and the menu bar icon transitions from "inactive" to "ready"
- [ ] If Python or pip dependencies are missing, app shows clear instructions for installing them

---

### US-002: Push-to-Talk Dictation

**Description:** As a user, I want to hold a hotkey to record my voice and have the transcribed text automatically pasted into whatever text field is active so that I can dictate anywhere on my Mac.

**Acceptance Criteria:**
- [ ] Default hotkey is `Fn` (configurable in settings)
- [ ] Holding the hotkey starts audio recording; menu bar icon changes to a red "recording" state
- [ ] A small floating indicator (similar to Wispr's "Flow Bar") appears near the cursor or center-screen showing recording is active
- [ ] Releasing the hotkey stops recording, sends the audio to the Python server, and shows a "processing" state
- [ ] Transcribed and cleaned text is placed on the clipboard and a `Cmd+V` keystroke is simulated to paste it into the active app
- [ ] The previously clipboard content is saved before paste and restored afterward so the user's clipboard is not clobbered
- [ ] Total latency from key release to text appearing is under 3 seconds for a 15-second utterance on M1+
- [ ] If recording is shorter than 0.5 seconds (accidental tap), no transcription is triggered

---

### US-003: Text Cleanup Pipeline

**Description:** As a user, I want my dictated text to be automatically cleaned up so that it reads naturally without filler words or formatting issues.

**Acceptance Criteria:**
- [ ] Filler words are removed: "uh", "um", "umm", "uh huh", "hmm", "like" (when used as filler), "you know", "I mean", "sort of", "kind of" (when used as filler), "basically", "actually" (when used as filler)
- [ ] Repeated words are deduplicated (e.g., "I I went" becomes "I went")
- [ ] Sentence-initial capitalization is applied
- [ ] Whitespace is normalized (no double spaces, no leading/trailing whitespace)
- [ ] Whisper's native punctuation is preserved and supplemented where missing
- [ ] Cleanup can be toggled off entirely via settings (for verbatim transcription mode)

---

### US-004: Menu Bar Interface

**Description:** As a user, I want a minimal menu bar icon that shows the current state of superWispr and gives me quick access to settings and controls.

**Acceptance Criteria:**
- [ ] Menu bar icon shows distinct states: ready (default), recording (red/pulsing), processing (spinner), error (yellow)
- [ ] Clicking the icon opens a dropdown menu with: current status, last transcription preview (truncated), Settings, Quit
- [ ] The dropdown shows which Whisper model is loaded and its status
- [ ] "Quit" stops the Python backend server before exiting the Swift app
- [ ] Menu bar icon is monochrome and follows macOS design conventions (SF Symbols)

---

### US-005: Settings Window

**Description:** As a user, I want to configure the hotkey, model, language, and behavior of superWispr through a native settings window.

**Acceptance Criteria:**
- [ ] Settings window is a native SwiftUI window opened from the menu bar dropdown
- [ ] Hotkey configuration: record a new global shortcut by pressing keys (using a shortcut recorder view)
- [ ] Model selection dropdown with these options: `openai/whisper-large-v3-turbo` (default, fast), `openai/whisper-large-v3` (accurate), `distil-whisper/distil-large-v3` (fastest)
- [ ] Changing the model triggers the Python server to reload the pipeline (with a loading indicator)
- [ ] Language dropdown: "Auto-detect" (default) plus a list of Whisper-supported languages
- [ ] Audio input device selector (lists available microphones via `AVAudioSession`)
- [ ] Toggle: "Clean up text" (on by default) - enables/disables the filler word removal pipeline
- [ ] Toggle: "Launch at login" - registers/unregisters the app as a login item
- [ ] Toggle: "Sound feedback" - plays a start/stop chime when recording begins/ends

---

### US-006: Python Server Lifecycle Management

**Description:** As a developer, I need the Swift app to manage the Python transcription server as a child process so that the user never has to start or stop it manually.

**Acceptance Criteria:**
- [ ] Swift app starts the Python server (`uvicorn`) as a child process on launch
- [ ] Server binds to `127.0.0.1:9876` (not exposed to network)
- [ ] Swift app performs a health check (`GET /health`) on startup and retries up to 10 times with 1-second intervals
- [ ] If the server crashes, Swift app detects the process exit and restarts it automatically (max 3 retries, then show error)
- [ ] On app quit, Swift app sends `SIGTERM` to the Python process and waits up to 5 seconds before `SIGKILL`
- [ ] Server stdout/stderr is captured and written to `~/Library/Logs/superWispr/server.log` for debugging

---

### US-007: Audio Recording

**Description:** As a developer, I need reliable audio capture in the Swift app that produces files compatible with insanely-fast-whisper.

**Acceptance Criteria:**
- [ ] Audio is recorded using `AVAudioRecorder` with settings: Linear PCM, 16kHz sample rate, 16-bit, mono
- [ ] Recording saves to a temporary `.wav` file in the system temp directory
- [ ] Temporary files are cleaned up after transcription completes (success or failure)
- [ ] If the selected microphone is disconnected during recording, the app gracefully stops and shows an error
- [ ] Recording level (amplitude) is accessible for the visual indicator in the Flow Bar

---

### US-008: Floating Recording Indicator (Flow Bar)

**Description:** As a user, I want a small floating visual indicator during recording so that I know superWispr is listening without looking at the menu bar.

**Acceptance Criteria:**
- [ ] A small, translucent floating panel appears when recording starts
- [ ] Panel shows an animated audio waveform or pulsing dot reflecting microphone input level
- [ ] Panel appears at the top-center of the screen (below the menu bar)
- [ ] Panel disappears when recording stops and transcription begins (replaced briefly by a "processing" indicator)
- [ ] Panel does not steal focus from the active application
- [ ] Panel is implemented as an `NSPanel` with `.nonactivatingPanel` behavior

---

## Functional Requirements

- **FR-01:** The app must run as a macOS menu bar application (no Dock icon) using `LSUIElement = true` in Info.plist.
- **FR-02:** The app must register a global hotkey (default: `Fn`) that works regardless of which application is in the foreground, using `CGEvent` taps with Accessibility permission.
- **FR-03:** Holding the hotkey must start audio recording; releasing it must stop recording. Taps shorter than 0.5 seconds must be ignored.
- **FR-04:** Audio must be recorded as 16kHz, 16-bit, mono WAV via `AVAudioRecorder`.
- **FR-05:** The recorded WAV file must be sent to the local Python server via HTTP POST (multipart/form-data) to `http://127.0.0.1:9876/transcribe`.
- **FR-06:** The Python server must run the `transformers` pipeline with `insanely-fast-whisper`'s approach: `pipeline("automatic-speech-recognition", model=<selected_model>, device="mps", torch_dtype=torch.float16)`.
- **FR-07:** The Python server must apply the text cleanup pipeline to the raw transcription before returning the result.
- **FR-08:** The `/transcribe` endpoint must accept optional query parameters: `language` (ISO code or "auto"), `cleanup` (boolean).
- **FR-09:** The Swift app must save the current clipboard contents, place the transcribed text on the clipboard, simulate `Cmd+V` via `CGEvent`, then restore the original clipboard contents after a short delay (200ms).
- **FR-10:** The Python server must expose `GET /health` returning `{"status": "ok", "model": "<loaded_model_name>"}`.
- **FR-11:** The Python server must expose `POST /config` accepting `{"model": "<model_name>"}` to hot-swap the loaded Whisper model.
- **FR-12:** The Python server must keep the Whisper pipeline loaded in memory between requests to avoid cold-start latency.
- **FR-13:** The app must store user preferences (hotkey, model, language, toggles) in `UserDefaults`.
- **FR-14:** The app must play an optional audio chime (short, subtle) when recording starts and stops, controllable via settings.
- **FR-15:** The app must support macOS 14.0 (Sonoma) and later, on Apple Silicon (M1+). Intel Macs are not a target (MPS is Apple Silicon only).

---

## Non-Goals (Out of Scope)

- **No LLM-powered reformatting.** Text cleanup is rule-based only. There is no local LLM (e.g., Ollama) integration for rewriting or style adaptation in this version.
- **No hands-free / continuous listening mode.** Only push-to-talk (hold-to-record) is supported.
- **No custom dictionary or learned corrections.** The app does not learn user-specific vocabulary or corrections.
- **No writing styles or per-app tone adaptation.** All transcriptions use the same cleanup rules.
- **No multi-language within a single utterance.** Language is either auto-detected or explicitly set per-session, not per-sentence.
- **No speaker diarization.** The app transcribes a single speaker.
- **No iOS, Windows, or Linux support.** macOS only.
- **No App Store distribution.** The app is distributed as a direct `.app` download or built from source. This avoids sandboxing constraints that would block accessibility and global hotkey features.
- **No cloud/API fallback.** If local transcription fails, there is no fallback to a cloud Whisper API.
- **No voice commands.** Users cannot say "comma" or "new line" to insert punctuation. Whisper handles punctuation natively.

---

## Design Considerations

### Visual Design

- **Menu bar icon:** SF Symbol `waveform` (ready), `waveform.circle.fill` (recording), `arrow.trianglehead.2.clockwise` (processing). Monochrome, adapts to light/dark mode automatically.
- **Flow Bar:** A 200x40pt translucent `NSPanel` with rounded corners, vibrancy material (`.hudWindow`), positioned at top-center of the main screen. Contains a simple animated waveform visualization driven by `AVAudioRecorder.averagePower(forChannel:)`.
- **Settings window:** Standard macOS settings layout using SwiftUI `Form` with `Section` groupings. Approximately 400x500pt. Uses `@AppStorage` for bindings to `UserDefaults`.
- **Welcome/onboarding window:** Single-page checklist showing permission statuses (green checkmark / red X) and a "Download Model" button with a progress bar.

### Audio UX

- Start chime: short, soft rising tone (~100ms)
- Stop chime: short, soft falling tone (~100ms)
- Error: macOS system alert sound (`NSSound.beep()`)

---

## Technical Considerations

### Python Server

- **Framework:** FastAPI with `uvicorn` as the ASGI server.
- **Transcription pipeline:** Uses `transformers.pipeline("automatic-speech-recognition")` directly (the same approach as insanely-fast-whisper) rather than shelling out to the `insanely-fast-whisper` CLI. This avoids process startup overhead on every request and keeps the model warm in memory.
- **Default model:** `openai/whisper-large-v3-turbo` — benchmarked at ~0.74s per 30s of audio on M2, ~2.1 GB RAM.
- **Batch size:** `4` for MPS (higher values cause OOM on most Macs).
- **Model cache:** Models are downloaded to `~/.cache/huggingface/hub/` (HuggingFace default). The Swift app should check this directory to determine if the model is already downloaded.
- **Text cleanup implementation:**
  ```python
  import re

  FILLER_PATTERNS = [
      r'\b(uh|um|umm|uhh|hmm|hm)\b',
      r'\b(you know|I mean|sort of|kind of|basically|actually)\b',
      # contextual fillers only removed at sentence boundaries or between commas
  ]

  def cleanup(text: str) -> str:
      # 1. Remove filler words
      for pattern in FILLER_PATTERNS:
          text = re.sub(pattern, '', text, flags=re.IGNORECASE)
      # 2. Deduplicate repeated words
      text = re.sub(r'\b(\w+)\s+\1\b', r'\1', text)
      # 3. Normalize whitespace
      text = re.sub(r'\s+', ' ', text).strip()
      # 4. Fix capitalization after periods
      text = re.sub(r'(?<=\.\s)([a-z])', lambda m: m.group(1).upper(), text)
      # 5. Capitalize first character
      if text:
          text = text[0].upper() + text[1:]
      return text
  ```
- **Dependencies** (`requirements.txt`):
  ```
  fastapi>=0.110.0
  uvicorn>=0.29.0
  transformers>=4.40.0
  torch>=2.2.0
  accelerate>=0.28.0
  optimum>=1.18.0
  python-multipart>=0.0.9
  ```

### Swift App

- **Minimum deployment target:** macOS 14.0 (Sonoma)
- **Architecture:** `arm64` only (Apple Silicon)
- **Key frameworks:** AppKit (NSStatusItem, NSPanel), SwiftUI (Settings), AVFoundation (audio recording), Carbon/CoreGraphics (CGEvent for hotkeys and paste simulation)
- **Hotkey implementation:** `CGEvent.tapCreate()` with `CGEventMask` filtering for key down/up events. The `Fn` key is key code `63`. The tap requires Accessibility permission.
- **Paste implementation:**
  1. Save current `NSPasteboard.general` contents
  2. Set transcribed text on `NSPasteboard.general`
  3. Create and post `CGEvent` for `Cmd+V` (key code `9`, flag `.maskCommand`)
  4. After 200ms delay, restore original clipboard contents
- **Process management:** Use `Process` (Foundation) to launch `uvicorn` with the Python server module. Capture stdout/stderr via `Pipe`. Monitor `terminationHandler` for crash detection.
- **Bundling Python:** The app does NOT bundle a Python runtime. It expects Python 3.11+ to be installed on the system (via Homebrew, pyenv, or system Python). The app stores the path to the Python executable in settings and validates it on launch.

### Directory Structure

```
superWispr/
├── SuperWisprApp/                    # Swift/Xcode project
│   ├── SuperWisprApp.swift           # App entry point, lifecycle
│   ├── MenuBarController.swift       # NSStatusItem management
│   ├── HotkeyManager.swift          # Global hotkey via CGEvent
│   ├── AudioRecorder.swift           # AVAudioRecorder wrapper
│   ├── TranscriptionClient.swift     # HTTP client for Python server
│   ├── ClipboardManager.swift        # Clipboard save/restore/paste
│   ├── FlowBarPanel.swift            # Floating recording indicator
│   ├── SettingsView.swift            # SwiftUI settings window
│   ├── OnboardingView.swift          # First-launch permission setup
│   ├── ServerManager.swift           # Python process lifecycle
│   ├── Assets.xcassets/              # App icon, chime sounds
│   └── Info.plist
├── server/                           # Python transcription server
│   ├── main.py                       # FastAPI app, /transcribe endpoint
│   ├── transcriber.py                # Whisper pipeline wrapper
│   ├── cleanup.py                    # Text cleanup pipeline
│   ├── config.py                     # Server configuration
│   └── requirements.txt
├── scripts/
│   ├── install.sh                    # One-line installer (brew, pip, model download)
│   └── build.sh                      # Build .app bundle from Xcode project
├── README.md
└── LICENSE
```

### Performance Budget

| Metric | Target | Notes |
|---|---|---|
| Recording start latency | < 100ms | Time from hotkey press to audio capture beginning |
| Transcription (15s audio) | < 2.5s | Using whisper-large-v3-turbo on M1+ with MPS |
| Text cleanup | < 50ms | Regex-based, negligible |
| Paste latency | < 200ms | Clipboard + CGEvent simulation |
| **Total end-to-end** | **< 3s** | From releasing the hotkey to text appearing in the active app |
| Memory (idle) | < 300 MB | Python server with model loaded, Swift app idle |
| Memory (recording) | < 500 MB | During active transcription |

### macOS Permissions Required

| Permission | Why | How |
|---|---|---|
| Microphone | Audio recording | `NSMicrophoneUsageDescription` in Info.plist triggers system dialog |
| Accessibility | Global hotkey monitoring + simulating Cmd+V paste | Must be manually enabled in System Settings > Privacy & Security > Accessibility |
| (no network) | Localhost HTTP only | No network entitlement needed; `127.0.0.1` works without it |

---

## Success Metrics

- Users can dictate and have text appear in any macOS app within 3 seconds of releasing the hotkey
- Text output has zero filler words when cleanup is enabled
- The app uses zero network bandwidth (verified: no outbound connections beyond `127.0.0.1`)
- Memory usage stays under 500 MB during active use on a base M1 (8 GB RAM)
- The app survives 100 consecutive dictation cycles without crashing or leaking memory
- First-time setup (install + model download + permissions) completes in under 10 minutes on a broadband connection

---

## Open Questions

1. **Fn key capture:** The `Fn` key (key code 63) behaves differently across keyboard types and macOS versions. Should we default to a safer combo like `Ctrl+Option` and let users remap to `Fn` if they want? -> Yes
2. **Model download UX:** HuggingFace model downloads can be 3+ GB. Should we show download progress in the Swift app by polling the `~/.cache/huggingface/` directory, or run a separate download script? -> Show progress
3. **Python discovery:** The app needs to find a valid Python 3.11+ installation. Should we bundle a minimal Python via `conda` / `pyenv`, or require the user to have Python pre-installed and let them point to it? -> bundle a minimal python
4. **Clipboard restoration race condition:** The 200ms delay before restoring the original clipboard may be too short for slow apps (e.g., Electron apps). Should we monitor the paste event completion via Accessibility APIs instead of a fixed delay? -> Yes
5. **Multiple monitor support:** Should the Flow Bar appear on the screen with the active text field, or always on the primary display? -> Yes
6. **Audio format:** Should we support sending raw PCM bytes over HTTP instead of writing a WAV file to disk, to shave off disk I/O latency? -> Yes
