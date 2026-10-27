#!/bin/bash
# Builds build/SubWave.app (release, universal for Intel and Apple chip Macs, signed for this Mac).
# Set SIGN_IDENTITY to sign with a certificate, e.g. "Developer ID Application: Name (TEAMID)".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/SubWave.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/SubWave"

[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SubWave"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi

echo "==> Built $APP"
