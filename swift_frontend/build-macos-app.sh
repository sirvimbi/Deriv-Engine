#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

swift build -c release --product DerivEngine

APP_DIR="$ROOT/.build/DerivEngine.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT/.build/release/DerivEngine" "$APP_DIR/Contents/MacOS/DerivEngine"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing makes the generated bundle launch as a normal macOS app
# during local development without requiring a Developer ID certificate.
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
echo "Launch with: open "$APP_DIR""
