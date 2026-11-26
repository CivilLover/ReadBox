#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RAW_VERSION="${VERSION:-0.1.0}"
APP_VERSION="${RAW_VERSION#v}"
APP_DIR="${APP_DIR:-$ROOT_DIR/build/ReadBox.app}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"

if [ ! -d "$APP_DIR" ]; then
  echo "==> $APP_DIR not found, building ReadBox.app first..."
  NO_INSTALL=1 VERSION="$APP_VERSION" "$ROOT_DIR/scripts/build-app.sh"
fi

if [ -z "${ARCH_LABEL:-}" ]; then
  if command -v lipo >/dev/null 2>&1; then
    ARCHS_INFO="$(lipo -archs "$APP_DIR/Contents/MacOS/ReadBox" 2>/dev/null || uname -m)"
    if [[ "$ARCHS_INFO" == *"arm64"* && "$ARCHS_INFO" == *"x86_64"* ]]; then
      ARCH_LABEL="universal"
    else
      ARCH_LABEL="$(echo "$ARCHS_INFO" | tr ' ' '-')"
    fi
  else
    ARCH_LABEL="$(uname -m)"
  fi
fi

mkdir -p "$OUT_DIR"
DMG_NAME="ReadBox-v${APP_VERSION}-macOS-${ARCH_LABEL}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
SHA_PATH="${DMG_PATH}.sha256"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/readbox-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> Staging DMG contents..."
cp -R "$APP_DIR" "$STAGING_DIR/ReadBox.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH" "$SHA_PATH"

echo "==> Creating compressed DMG: $DMG_PATH"
hdiutil create \
  -volname "ReadBox ${APP_VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

(
  cd "$OUT_DIR"
  shasum -a 256 "$DMG_NAME" > "$(basename "$SHA_PATH")"
)

echo "==> DMG ready: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"
echo "==> SHA256:    $(cat "$SHA_PATH")"
