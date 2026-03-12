#!/bin/bash
set -euo pipefail

# ClaudeMeter DMG Builder
# Usage: ./scripts/create-dmg.sh [version]

VERSION="${1:-1.0.0}"
APP_NAME="ClaudeMeter"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

echo "==> Building ${APP_NAME} v${VERSION}..."

xcodebuild -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  clean build \
  -quiet

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Build failed - ${APP_PATH} not found"
  exit 1
fi

echo "==> Build successful"

rm -f "${PROJECT_DIR}/${DMG_NAME}"

echo "==> Creating DMG..."

dmgbuild \
  -s "${SCRIPT_DIR}/dmg-settings.py" \
  -D APP_PATH="$APP_PATH" \
  "$APP_NAME" \
  "${PROJECT_DIR}/${DMG_NAME}"

echo ""
echo "==> Done: ${DMG_NAME} ($(du -h "${PROJECT_DIR}/${DMG_NAME}" | cut -f1))"
echo ""
echo "GitHub release:"
echo "  git tag v${VERSION} && git push origin v${VERSION}"
echo "  gh release create v${VERSION} ${DMG_NAME} --title \"${APP_NAME} v${VERSION}\" --generate-notes"
