#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$PROJECT_DIR/VERSION"
PLIST="$PROJECT_DIR/Resources/Info.plist"

if [[ ! -f "$VERSION_FILE" ]]; then
  print -u2 "缺少 VERSION 文件"
  exit 1
fi

VERSION="$(/usr/bin/tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  print -u2 "VERSION 格式应为 major.minor，例如 1.0，当前：$VERSION"
  exit 1
fi

MAJOR="${VERSION%%.*}"
MINOR="${VERSION#*.}"
BUILD=$((MAJOR * 100 + MINOR))

/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD" "$PLIST"

print "已同步版本：$VERSION（build $BUILD）→ Resources/Info.plist"
