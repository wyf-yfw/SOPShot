#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${SOPSHOT_APP_PATH:-$PROJECT_DIR/SOPShot.app}"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
DMG_PATH="${SOPSHOT_DMG_PATH:-$PROJECT_DIR/SOPShot-${VERSION}.dmg}"
STAGE="$PROJECT_DIR/.dmg-stage"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "找不到应用：$APP_PATH（请先运行 scripts/build-app.sh）"
  exit 1
fi

/bin/rm -rf "$STAGE"
/bin/mkdir -p "$STAGE"
/bin/cp -R "$APP_PATH" "$STAGE/SOPShot.app"
/bin/ln -s /Applications "$STAGE/Applications"

/bin/rm -f "$DMG_PATH"
/usr/bin/hdiutil create \
  -volname "SOPShot $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

/bin/rm -rf "$STAGE"
print "DMG 已生成：$DMG_PATH"
