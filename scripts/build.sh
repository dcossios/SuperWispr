#!/usr/bin/env bash
#
# Build the superWispr macOS app bundle.
#
set -euo pipefail

SUPERWISPR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$SUPERWISPR_DIR/.build"
APP_DIR="$SUPERWISPR_DIR/dist/superWispr.app"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building superWispr"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ── 1. Build with Swift ─────────────────────────────────────────────────────

echo "[1/3] Compiling Swift sources …"
cd "$SUPERWISPR_DIR"
swift build -c release 2>&1 | tail -5

BINARY="$BUILD_DIR/release/SuperWispr"
if [ ! -f "$BINARY" ]; then
    # Try the arm64 path
    BINARY="$BUILD_DIR/arm64-apple-macosx/release/SuperWispr"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Build failed. Binary not found."
    echo "Run 'swift build -c release' manually to see full errors."
    exit 1
fi
echo "     Binary: $BINARY"

# ── 2. Create .app bundle ──────────────────────────────────────────────────

echo "[2/3] Creating app bundle …"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/SuperWispr"
cp "$SUPERWISPR_DIR/SuperWisprApp/Info.plist" "$APP_DIR/Contents/Info.plist"

# Embed the server alongside the app
cp -r "$SUPERWISPR_DIR/server" "$APP_DIR/Contents/Resources/server"

# ── 3. Code sign (ad-hoc) ──────────────────────────────────────────────────

echo "[3/3] Code signing (ad-hoc) …"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Build complete!"
echo ""
echo "  App bundle: $APP_DIR"
echo ""
echo "  To run:"
echo "    open $APP_DIR"
echo ""
echo "  Or copy to /Applications:"
echo "    cp -r $APP_DIR /Applications/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
