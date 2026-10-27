#!/bin/bash
# Installs build/SubWave.app into /Applications (quits a running copy first).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$ROOT/build/SubWave.app" ] || { echo "error: run scripts/build.sh first" >&2; exit 1; }

osascript -e 'tell application id "com.subwave.app" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/SubWave.app
cp -R "$ROOT/build/SubWave.app" /Applications/
echo "==> Installed /Applications/SubWave.app"
