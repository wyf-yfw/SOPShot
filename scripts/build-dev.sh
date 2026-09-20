#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/SOPShot.app"
BUILD_CONFIGURATION="${SOPSHOT_BUILD_CONFIGURATION:-release}"

# This is the SHA-1 fingerprint of the local SOPShot Development certificate.
# Keep this fixed: falling back to `-` would create a new ad-hoc identity and
# macOS would treat the rebuilt app as a different privacy-permission client.
SIGNING_IDENTITY="${SOPSHOT_SIGN_IDENTITY:-BE59DB14A96DC94A42BA34638392CCFED4FB39DB}"

if ! /usr/bin/security find-certificate -Z "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
  | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
  print -u2 "找不到 SOPShot 的本地开发签名证书：$SIGNING_IDENTITY"
  print -u2 "请确认登录钥匙串仍然包含 SOPShot Development 证书和私钥。"
  exit 1
fi

GIT_BRANCH="$(cd "$PROJECT_DIR" && /usr/bin/git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
SWIFT_BUILD_FLAGS=()
if [[ "${SOPSHOT_DEBUG_ASSISTANT:-}" == "1" || "$GIT_BRANCH" == "release" || "$GIT_BRANCH" == release/* ]]; then
  SWIFT_BUILD_FLAGS+=(-Xswiftc -DSOPSHOT_DEBUG_ASSISTANT)
  print "调试助手：开启（分支 $GIT_BRANCH）"
else
  print "调试助手：关闭（分支 ${GIT_BRANCH:-unknown}）"
fi

print "构建 SOPShot（$BUILD_CONFIGURATION）..."
"$PROJECT_DIR/scripts/sync-version.sh"
(cd "$PROJECT_DIR" && /usr/bin/swift build -c "$BUILD_CONFIGURATION" "${SWIFT_BUILD_FLAGS[@]}")
BIN_DIR="$(cd "$PROJECT_DIR" && /usr/bin/swift build -c "$BUILD_CONFIGURATION" "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"

/bin/mkdir -p "$APP_PATH/Contents/MacOS"
/bin/mkdir -p "$APP_PATH/Contents/Resources"
/bin/cp -f "$BIN_DIR/SOPShot" "$APP_PATH/Contents/MacOS/SOPShot"
/bin/cp -f "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
/bin/cp -f "$PROJECT_DIR/Resources/SOPShot.icns" "$APP_PATH/Contents/Resources/SOPShot.icns"
/bin/cp -f "$PROJECT_DIR/Sources/SOPShot/Resources/AppIcon.png" "$APP_PATH/Contents/Resources/AppIcon.png"

print "使用固定开发身份签名..."
/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"

SIGNATURE="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if print -r -- "$SIGNATURE" | /usr/bin/grep -Fq "Signature=adhoc"; then
  print -u2 "签名仍然是临时签名，已中止。"
  exit 1
fi
if ! print -r -- "$SIGNATURE" | /usr/bin/grep -Fq "Authority=SOPShot Development"; then
  print -u2 "签名主体不是 SOPShot Development，已中止。"
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
print "开发版已生成：$APP_PATH"
print "固定签名：SOPShot Development ($SIGNING_IDENTITY)"
