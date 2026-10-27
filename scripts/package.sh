#!/bin/bash
# Zips build/SubWave.app into build/SubWave-<version>.zip for a GitHub release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/SubWave.app"
[ -d "$APP" ] || { echo "error: run scripts/build.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$ROOT/build/SubWave-$VERSION.zip"

rm -f "$ZIP"
# ditto keeps the app's signature and metadata intact
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "==> Packaged $ZIP"
