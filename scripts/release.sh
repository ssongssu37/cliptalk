#!/bin/bash
# scripts/release.sh
#
# One-shot release pipeline:
#   1. fetch vendored binaries (yt-dlp, ffmpeg)
#   2. xcodegen + xcodebuild Release archive
#   3. sign embedded binaries + the .app with Developer ID + hardened runtime
#   4. notarize via App Store Connect API key, wait, staple
#   5. wrap in a DMG, sign + notarize + staple the DMG
#
# Usage:
#   ./scripts/release.sh                  # uses VERSION below
#   VERSION=0.1.1 ./scripts/release.sh    # override version
#
# Requires (already set up on this machine):
#   - Developer ID Application cert in Keychain (verified by find-identity)
#   - ASC API key file at ~/private_keys/AuthKey_HCWJYJ5M3J.p8
#   - create-dmg, xcodegen, xcodebuild, codesign, notarytool, stapler

set -euo pipefail

# --- Config -----------------------------------------------------------------
VERSION="${VERSION:-0.1.0}"
APP_NAME="ClipTalk"
SCHEME="ClipTalk"
BUNDLE_ID="com.sunghun.ClipTalk"
TEAM_ID="N999F5MRQC"
SIGN_ID="Developer ID Application: sunghun song (${TEAM_ID})"
ASC_KEY_ID="HCWJYJ5M3J"
ASC_ISSUER="864de59b-dc99-4bf3-b3da-b19273222f0f"
ASC_KEY_PATH="${HOME}/private_keys/AuthKey_${ASC_KEY_ID}.p8"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
RELEASE_DIR="$ROOT/release"
ARCHIVE="$BUILD_DIR/${APP_NAME}.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/${APP_NAME}.app"
DMG_PATH="$RELEASE_DIR/${APP_NAME}.dmg"

mkdir -p "$BUILD_DIR" "$RELEASE_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "=== ClipTalk release ${VERSION} ==="
echo

# --- 1. Fetch vendored binaries ---------------------------------------------
echo "[1/6] Fetching vendored binaries…"
"$ROOT/scripts/fetch-binaries.sh"
echo

# --- 2. Build Release archive -----------------------------------------------
echo "[2/6] Building Release archive…"
xcodegen >/dev/null

# ExportOptions.plist for Developer ID distribution
EXPORT_OPTS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'platform=macOS' \
  archive \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  | xcbeautify 2>/dev/null || \
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'platform=macOS' \
  archive \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS"
echo

# --- 3. Re-sign embedded binaries + app -------------------------------------
# xcodebuild signs the .app outer shell, but it doesn't always sign loose
# executables in Resources/. We sign yt-dlp and ffmpeg explicitly with the
# hardened runtime flag, then re-seal the app.
echo "[3/6] Signing embedded binaries…"

ENTITLEMENTS_HELPER=$(mktemp)
cat > "$ENTITLEMENTS_HELPER" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
  <key>com.apple.security.cs.allow-jit</key><true/>
</dict>
</plist>
EOF

for bin in "$APP_PATH/Contents/Resources/bin/yt-dlp" "$APP_PATH/Contents/Resources/bin/ffmpeg"; do
  if [ -f "$bin" ]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS_HELPER" \
      --sign "$SIGN_ID" "$bin"
  fi
done

# Re-sign the outer .app to seal embedded signature changes
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/ClipTalk/ClipTalk.entitlements" \
  --sign "$SIGN_ID" "$APP_PATH"

# Verify
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|TeamID|Runtime"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo

# --- 4. Notarize the .app ---------------------------------------------------
echo "[4/6] Notarizing app…"
NOTARY_ZIP="$BUILD_DIR/ClipTalk-notary.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER" \
  --wait

xcrun stapler staple "$APP_PATH"
echo

# --- 5. Build DMG -----------------------------------------------------------
echo "[5/6] Building DMG…"
rm -f "$DMG_PATH"

create-dmg \
  --volname "${APP_NAME} ${VERSION}" \
  --window-size 540 360 \
  --icon-size 96 \
  --icon "${APP_NAME}.app" 140 170 \
  --app-drop-link 400 170 \
  --hide-extension "${APP_NAME}.app" \
  "$DMG_PATH" \
  "$EXPORT_DIR" || true

if [ ! -f "$DMG_PATH" ]; then
  echo "create-dmg failed; falling back to hdiutil"
  hdiutil create -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$EXPORT_DIR" -ov -format UDZO "$DMG_PATH"
fi

# --- 6. Sign + notarize + staple the DMG ------------------------------------
echo "[6/6] Signing & notarizing DMG…"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER" \
  --wait

xcrun stapler staple "$DMG_PATH"

# --- Done -------------------------------------------------------------------
echo
echo "=== Done ==="
echo "DMG:  $DMG_PATH"
ls -lh "$DMG_PATH"
echo
echo "Verify Gatekeeper acceptance:"
spctl --assess --type install --verbose "$DMG_PATH" || true
