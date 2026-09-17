#!/bin/zsh
# Builds a Release copy and installs it to /Applications.
# Launch at Login must be enabled from the /Applications copy (SMAppService registers the running bundle).
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="$PWD/build"
APP_NAME="ClipboardManager"
BUNDLE_ID="dev.armaan.ClipboardManager"
DEST="/Applications/$APP_NAME.app"

echo "Building Release…"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" build -quiet

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Build product not found at $APP" >&2; exit 1; }

echo "Stopping running instance (if any)…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "Installing to $DEST…"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "Launching…"
open "$DEST"
echo "Done. Enable Launch at Login from the menu bar icon (right-click)."
