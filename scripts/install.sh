#!/usr/bin/env bash
#
# superWispr installer — sets up a Python venv, installs dependencies,
# and pre-downloads the default Whisper model.
#
set -euo pipefail

SUPERWISPR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$HOME/.superwispr/venv"
MODEL="openai/whisper-large-v3-turbo"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  superWispr Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ── 1. Check Python ─────────────────────────────────────────────────────────

PYTHON=""
for candidate in python3.12 python3.11 python3; do
    if command -v "$candidate" &>/dev/null; then
        ver=$("$candidate" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [ "$major" -ge 3 ] && [ "$minor" -ge 11 ]; then
            PYTHON="$(command -v "$candidate")"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo "ERROR: Python 3.11+ is required but not found."
    echo ""
    echo "Install it with:"
    echo "  brew install python@3.12"
    echo ""
    exit 1
fi
echo "[1/4] Python found: $PYTHON ($("$PYTHON" --version))"

# ── 2. Create venv ──────────────────────────────────────────────────────────

if [ ! -d "$VENV_DIR" ]; then
    echo "[2/4] Creating virtual environment at $VENV_DIR …"
    "$PYTHON" -m venv "$VENV_DIR"
else
    echo "[2/4] Virtual environment already exists at $VENV_DIR"
fi

PIP="$VENV_DIR/bin/pip"
PYTHON_VENV="$VENV_DIR/bin/python3"

# ── 3. Install dependencies ────────────────────────────────────────────────

echo "[3/4] Installing Python dependencies …"
"$PIP" install --upgrade pip -q
"$PIP" install -r "$SUPERWISPR_DIR/server/requirements.txt" -q

echo "     Dependencies installed."

# ── 4. Download model ───────────────────────────────────────────────────────

echo "[4/4] Pre-downloading Whisper model: $MODEL"
echo "     (This may take a few minutes on first run — the model is ~3 GB)"
"$PYTHON_VENV" -c "
from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor
print('  Downloading processor …')
AutoProcessor.from_pretrained('$MODEL')
print('  Downloading model …')
AutoModelForSpeechSeq2Seq.from_pretrained('$MODEL')
print('  Done!')
"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Installation complete!"
echo ""
echo "  Python venv: $VENV_DIR"
echo "  Model cached in: ~/.cache/huggingface/hub/"
echo ""
echo "  Next steps:"
echo "    1. Build the app:  ./scripts/build.sh"
echo "    2. Or run the server directly:"
echo "       $PYTHON_VENV -m uvicorn server.main:app \\"
echo "         --host 127.0.0.1 --port 9876"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
