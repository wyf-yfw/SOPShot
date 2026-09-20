#!/bin/zsh

# CI / release build: produce SOPShot.app without the local development certificate.
# Uses ad-hoc signing so the binary is runnable; Gatekeeper may still warn on download.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${SOPSHOT_APP_PATH:-$PROJECT_DIR/SOPShot.app}"
BUILD_CONFIGURATION="${SOPSHOT_BUILD_CONFIGURATION:-release}"
SIGNING_IDENTITY="${SOPSHOT_SIGN_IDENTITY:--}"

"$PROJECT_DIR/scripts/sync-version.sh"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"

print "构建 SOPShot $VERSION（$BUILD_CONFIGURATION）..."
(cd "$PROJECT_DIR" && /usr/bin/swift build -c "$BUILD_CONFIGURATION")
BIN_DIR="$(cd "$PROJECT_DIR" && /usr/bin/swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"

/bin/rm -rf "$APP_PATH"
/bin/mkdir -p "$APP_PATH/Contents/MacOS"
/bin/mkdir -p "$APP_PATH/Contents/Resources"
/bin/cp -f "$BIN_DIR/SOPShot" "$APP_PATH/Contents/MacOS/SOPShot"
/bin/cp -f "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
/bin/cp -f "$PROJECT_DIR/Resources/SOPShot.icns" "$APP_PATH/Contents/Resources/SOPShot.icns"
/bin/cp -f "$PROJECT_DIR/Sources/SOPShot/Resources/AppIcon.png" "$APP_PATH/Contents/Resources/AppIcon.png"

print "签名（identity: $SIGNING_IDENTITY）..."
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
/usr/bin/codesign --verify --deep --verbose=2 "$APP_PATH" || true

print "应用已生成：$APP_PATH"
print "VERSION=$VERSION"
