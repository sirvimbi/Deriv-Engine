#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="Deriv Engine.app"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build-macos}"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$MACOS/DerivEngine"
PLIST="$ROOT/Info.plist"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "error: swiftc was not found. Install Xcode Command Line Tools or Xcode." >&2
    exit 1
fi

if [[ ! -f "$PLIST" ]]; then
    echo "error: Info.plist is missing." >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

mapfile -t SWIFT_SOURCES < <(find "$ROOT" -type f -name '*.swift' \
    ! -path "$ROOT/.build/*" \
    ! -path "$ROOT/Tests/*" \
    ! -path "$ROOT/test/*" | sort)

if [[ "${#SWIFT_SOURCES[@]}" -eq 0 ]]; then
    echo "error: no Swift source files found under $ROOT." >&2
    exit 1
fi

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "error: unsupported ARCH=$ARCH (use arm64 or x86_64)." >&2; exit 1 ;;
esac

MACOS_VERSION="${MACOS_VERSION:-26.0}"

echo "Building Deriv Engine for $ARCH (macOS $MACOS_VERSION)..."
swiftc \
    -parse-as-library \
    -target "$ARCH-apple-macos$MACOS_VERSION" \
    -framework SwiftUI \
    -framework AppKit \
    -o "$EXECUTABLE" \
    "${SWIFT_SOURCES[@]}"

cp "$PLIST" "$CONTENTS/Info.plist"
chmod 755 "$EXECUTABLE"

# Ad-hoc signing gives LaunchServices a valid application bundle while keeping
# this developer build independent of an Apple Developer certificate.
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo
echo "Built: $APP_DIR"
echo "Bundle identifier: com.sirvimbi.derivengine"
echo
echo "Launch with:"
echo "  open \"$APP_DIR\""
