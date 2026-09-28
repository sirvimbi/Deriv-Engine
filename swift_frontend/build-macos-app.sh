#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="Deriv Engine.app"
BUNDLE_ID="com.sirvimbi.derivengine"
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

SWIFT_SOURCES=()
while IFS= read -r -d '' SOURCE; do
    SWIFT_SOURCES+=( "$SOURCE" )
done < <(find "$ROOT" -type f -name '*.swift' \
    ! -name 'Package.swift' \
    ! -path "$ROOT/.build/*" \
    ! -path "$ROOT/Tests/*" \
    ! -path "$ROOT/test/*" -print0)

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
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable DerivEngine" "$CONTENTS/Info.plist"

# Sign with the same explicit bundle identifier that LaunchServices sees in Info.plist.
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null

# Fail the build instead of producing an app that LaunchServices cannot index.
ACTUAL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$CONTENTS/Info.plist")
if [[ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "error: bundle identifier mismatch: $ACTUAL_BUNDLE_ID" >&2
    exit 1
fi

echo
echo "Built: $APP_DIR"
echo "Bundle identifier: $BUNDLE_ID"
echo
echo "Launch with:"
echo "  open \"$APP_DIR\""
