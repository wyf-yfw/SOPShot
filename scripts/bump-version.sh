#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$PROJECT_DIR/VERSION"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$VERSION_FILE")"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  print -u2 "VERSION 格式应为 major.minor，例如 1.0，当前：$VERSION"
  exit 1
fi

MAJOR="${VERSION%%.*}"
MINOR="${VERSION#*.}"
MINOR=$((MINOR + 1))
NEXT="${MAJOR}.${MINOR}"

print "$NEXT" > "$VERSION_FILE"
"$PROJECT_DIR/scripts/sync-version.sh"

print "版本已从 $VERSION 增加到 $NEXT"
