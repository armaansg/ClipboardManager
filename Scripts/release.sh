#!/bin/zsh
# Builds a distributable ClipboardManager release: .app → .zip + .dmg (+ Sparkle appcast).
#
# Unsigned (no Apple Developer account): just run it. Output is ad-hoc signed; users must approve the
# app once in System Settings → Privacy & Security.
#
# Signed + notarized: set
#   SIGNING_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   and either NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`>
#   or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (app-specific password)
# Optional:
#   VERSION            marketing version to stamp (default: value in the project, 1.0)
#   BUILD_NUMBER       CFBundleVersion (default: 1)
#   SPARKLE_PRIVATE_KEY_FILE   EdDSA private key exported by Sparkle's generate_keys, for appcast signing
#   APPCAST_DOWNLOAD_PREFIX    URL prefix where the zip will be hosted (appcast enclosure URLs)
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APP_NAME="ClipboardManager"
BUILD_DIR="$PWD/build"
DIST_DIR="$PWD/dist"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

extra_settings=()
[[ -n "${VERSION:-}" ]] && extra_settings+=("MARKETING_VERSION=$VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && extra_settings+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "▸ Building Release, signed as: $SIGNING_IDENTITY (hardened runtime)"
  extra_settings+=("CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" "CODE_SIGN_STYLE=Manual"
                   "ENABLE_HARDENED_RUNTIME=YES" "OTHER_CODE_SIGN_FLAGS=--timestamp --options runtime")
else
  echo "▸ Building Release, ad-hoc signed (set SIGNING_IDENTITY for a Developer ID build)"
  extra_settings+=("CODE_SIGN_IDENTITY=-")
fi

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" build -quiet "${extra_settings[@]}"

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
VERSION_STAMPED=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$DIST_DIR/$APP_NAME-$VERSION_STAMPED.zip"
DMG="$DIST_DIR/$APP_NAME-$VERSION_STAMPED.dmg"

echo "▸ Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() {
  local artifact="$1"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$artifact" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  else
    echo "  (no notarization credentials; skipping notarization of $(basename "$artifact"))"
    return 1
  fi
}

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "▸ Notarizing the app"
  ditto -c -k --keepParent "$APP" "$ZIP"
  if notarize "$ZIP"; then
    xcrun stapler staple "$APP"
  fi
fi

echo "▸ Zipping"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Building DMG"
STAGING="$DIST_DIR/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Clipboard Manager" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
  if notarize "$DMG"; then
    xcrun stapler staple "$DMG"
  fi
fi

echo "▸ Checksums"
(cd "$DIST_DIR" && shasum -a 256 *.zip *.dmg > SHA256SUMS)

GENERATE_APPCAST="$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" && -x "$GENERATE_APPCAST" ]]; then
  echo "▸ Generating Sparkle appcast"
  args=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
  [[ -n "${APPCAST_DOWNLOAD_PREFIX:-}" ]] && args+=(--download-url-prefix "$APPCAST_DOWNLOAD_PREFIX")
  mkdir -p "$DIST_DIR/appcast"; cp "$ZIP" "$DIST_DIR/appcast/"
  "$GENERATE_APPCAST" "${args[@]}" "$DIST_DIR/appcast"
  mv "$DIST_DIR/appcast/appcast.xml" "$DIST_DIR/appcast.xml"; rm -rf "$DIST_DIR/appcast"
fi

echo
echo "Done. Artifacts in $DIST_DIR:"
ls -la "$DIST_DIR"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo
  echo "NOTE: unsigned build. Downloaders must approve it once: open it, dismiss the warning, then"
  echo "System Settings → Privacy & Security → Open Anyway."
fi
