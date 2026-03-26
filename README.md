# superWispr

Free, local, offline voice-to-text dictation for macOS. A [Wispr Flow](https://wisprflow.ai) alternative that runs entirely on your machine using [Whisper](https://github.com/openai/whisper) via [insanely-fast-whisper](https://github.com/Vaibhavs10/insanely-fast-whisper).

Hold **⌃⌥** (Control + Option) anywhere on your Mac. Speak. Release. Text appears.

## How It Works

```
Hold ⌃⌥ → Record audio → Release → Whisper transcribes → Text pastes into active app
```

- **Native Swift menu bar app** handles hotkeys, audio capture, and paste
- **Local Python server** (FastAPI) runs Whisper on Apple Silicon via MPS
- **Zero network traffic** — everything stays on your machine
- **Text cleanup** — removes filler words ("uh", "um"), fixes capitalization

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (M1, M2, M3, M4)
- Python 3.11+
- ~3 GB disk space for the Whisper model

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/your-username/superWispr.git
cd superWispr

# 2. Install Python dependencies and download the Whisper model
./scripts/install.sh

# 3. Build the macOS app
./scripts/build.sh

# 4. Launch
open dist/superWispr.app
```

On first launch, superWispr will ask for:
- **Microphone access** — to record your voice
- **Accessibility access** — for the global hotkey and auto-paste

## Usage

| Action | How |
|---|---|
| **Dictate** | Hold **⌃⌥** (Control + Option), speak, release |
| **Menu** | Click the waveform icon in the menu bar |
| **Settings** | Menu bar → Settings (or **⌘,**) |
| **Quit** | Menu bar → Quit (or **⌘Q**) |

Recordings shorter than 0.5 seconds are ignored (prevents accidental triggers).

## Settings

| Setting | Default | Description |
|---|---|---|
| Model | `whisper-large-v3-turbo` | Fastest. Also available: `large-v3` (accurate), `distil-large-v3` (fastest) |
| Language | Auto-detect | Or pick from 20+ languages |
| Text cleanup | On | Removes fillers, fixes capitalization |
| Sound feedback | On | Chime on record start/stop |
| Launch at login | Off | Start superWispr on boot |

## Architecture

```
superWispr/
├── SuperWisprApp/           # Swift macOS menu bar app
│   ├── SuperWisprApp.swift  # Entry point
│   ├── MenuBarController    # NSStatusItem + orchestration
│   ├── HotkeyManager        # Global ⌃⌥ capture via CGEvent
│   ├── AudioRecorder        # 16kHz mono WAV via AVFoundation
│   ├── TranscriptionClient  # HTTP client → Python server
│   ├── ClipboardManager     # Save/paste/restore clipboard
│   ├── FlowBarPanel         # Floating recording indicator
│   ├── SettingsView         # SwiftUI preferences
│   └── ServerManager        # Python process lifecycle
├── server/                  # Python transcription server
│   ├── main.py              # FastAPI endpoints
│   ├── transcriber.py       # Whisper pipeline (MPS)
│   ├── cleanup.py           # Filler word removal
│   └── requirements.txt
├── scripts/
│   ├── install.sh           # One-line setup
│   └── build.sh             # Build .app bundle
└── Package.swift            # Swift package manifest
```

The Swift app launches the Python server as a child process on startup and kills it on quit. Communication is over `http://127.0.0.1:9876`.

## Server API

The Python server exposes three endpoints:

```
GET  /health      → {"status": "ok", "model": "openai/whisper-large-v3-turbo"}
POST /transcribe  → multipart WAV upload → {"text": "...", "raw": "..."}
POST /config      → {"model": "openai/whisper-large-v3"} → hot-swap model
```

You can run the server standalone for testing:

```bash
~/.superwispr/venv/bin/python -m uvicorn server.main:app --host 127.0.0.1 --port 9876
```

## Performance

Benchmarked on Apple Silicon with `whisper-large-v3-turbo`:

| Metric | Target |
|---|---|
| Transcription (15s audio) | < 2.5s |
| End-to-end (release key → text appears) | < 3s |
| Memory (idle, model loaded) | ~300 MB |
| Memory (during transcription) | ~500 MB |

## Troubleshooting

**"Server failed to start"**
- Check Python is installed: `python3 --version` (needs 3.11+)
- Check the venv exists: `ls ~/.superwispr/venv/bin/python3`
- Re-run `./scripts/install.sh`
- Check server logs: `cat ~/Library/Logs/superWispr/server.log`

**Hotkey not working**
- Grant Accessibility permission: System Settings → Privacy & Security → Accessibility → enable superWispr
- Restart the app after granting

**Slow transcription**
- Ensure MPS is being used (check server log for `device=mps`)
- Try `distil-whisper/distil-large-v3` for faster (slightly less accurate) transcription
- Close other GPU-heavy apps

**MPS errors on macOS**
- Update to the latest macOS version
- If you hit `NotImplementedError` with sparse tensors, the server falls back to CPU automatically

## License

MIT
