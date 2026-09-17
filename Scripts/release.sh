#!/bin/zsh
# Produces a signed, notarized, stapled release zip plus a Sparkle appcast.
#
# Required environment:
#   SIGNING_IDENTITY   "Developer ID Application: Your Name (TEAMID)"   (security find-identity -v -p codesigning)
#   NOTARY_PROFILE     keychain profile created with: xcrun notarytool store-credentials <name>
# Optional:
#   SPARKLE_PRIVATE_KEY_FILE  path to the EdDSA private key exported by Sparkle's generate_keys (-x)
#   APPCAST_DOWNLOAD_PREFIX   base URL where the zip will be hosted, e.g. https://github.com/you/ClipboardManager/releases/download/v1.0/
#
# One-time Sparkle setup (keys live in your login keychain):
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
#   → paste the printed public key into Supporting/Info.plist as SUPublicEDKey
#   → set SUFeedURL in Supporting/Info.plist to where appcast.xml will be hosted
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"

APP_NAME="ClipboardManager"
BUILD_DIR="$PWD/build"
DIST_DIR="$PWD/dist"
mkdir -p "$DIST_DIR"

echo "▸ Building Release with hardened runtime, signed as: $SIGNING_IDENTITY"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" build -quiet \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

echo "▸ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Zipping and submitting for notarization"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling ticket and re-zipping"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP" || true

GENERATE_APPCAST="$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ -x "$GENERATE_APPCAST" ]]; then
  echo "▸ Generating Sparkle appcast in $DIST_DIR"
  args=()
  [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] && args+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
  [[ -n "${APPCAST_DOWNLOAD_PREFIX:-}" ]] && args+=(--download-url-prefix "$APPCAST_DOWNLOAD_PREFIX")
  "$GENERATE_APPCAST" "${args[@]}" "$DIST_DIR"
else
  echo "▸ Sparkle's generate_appcast not found (build once so SPM downloads it); skipping appcast"
fi

echo "Done: $ZIP"
echo "Upload the zip and dist/appcast.xml to the locations referenced by SUFeedURL / APPCAST_DOWNLOAD_PREFIX."
