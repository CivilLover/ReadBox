#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

RAW_VERSION="${VERSION:-0.1.0}"
APP_VERSION="${RAW_VERSION#v}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
UNIVERSAL="${UNIVERSAL:-0}"

SWIFT_BUILD_ARGS=(-c release)
if [ "${DISABLE_SANDBOX:-0}" = "1" ]; then
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/readbox-clang-cache}"
  SWIFT_BUILD_ARGS+=(--disable-sandbox -Xswiftc -module-cache-path -Xswiftc "${SWIFT_MODULE_CACHE_PATH:-/tmp/readbox-swift-cache}")
fi
if [ "$UNIVERSAL" = "1" ]; then
  echo "==> Building ReadBox v${APP_VERSION} (release, universal arm64 + x86_64)..."
  SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
else
  echo "==> Building ReadBox v${APP_VERSION} (release)..."
fi

swift build "${SWIFT_BUILD_ARGS[@]}"

BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT_DIR/build/ReadBox.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/ReadBox" "$MACOS_DIR/ReadBox"
chmod +x "$MACOS_DIR/ReadBox"

# Stamp current macOS SDK version into LC_BUILD_VERSION so macOS 26+ enables true native Liquid Glass window chrome, traffic lights & controls!
SDK_VER="$(xcrun --show-sdk-version 2>/dev/null || echo 26.0)"
if command -v vtool >/dev/null 2>&1; then
  vtool -set-build-version macos 14.0 "$SDK_VER" -replace -output "$MACOS_DIR/ReadBox" "$MACOS_DIR/ReadBox"
  echo "==> Stamped Mach-O SDK version: macOS $SDK_VER (native Liquid Glass enabled)"
fi

# Copy AppIcon.icns into Contents/Resources
if [ -f "$ROOT_DIR/Assets/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Copy SwiftPM resource bundle into Contents/Resources so Bundle.module & codesign work cleanly
if [ -d "$BIN_DIR/ReadBox_ReadBox.bundle" ]; then
  cp -R "$BIN_DIR/ReadBox_ReadBox.bundle" "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>ReadBox</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.readbox.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ReadBox</string>
    <key>CFBundleDisplayName</key>
    <string>ReadBox</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.readbox.macos.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>readbox</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Sign the bundle (uses SIGN_IDENTITY if provided, otherwise ad-hoc sign for Apple Silicon / Keychain compatibility)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Packaged successfully: $APP_DIR"
if command -v lipo >/dev/null 2>&1; then
  lipo -info "$MACOS_DIR/ReadBox" || true
fi

# Install into /Applications by default (set NO_INSTALL=1 to skip)
if [ "${NO_INSTALL:-0}" != "1" ] && [ -w "/Applications" ]; then
  echo "==> Installing to /Applications/ReadBox.app..."
  pkill -x ReadBox >/dev/null 2>&1 || true
  sleep 0.5
  rm -rf "/Applications/ReadBox.app"
  cp -R "$APP_DIR" "/Applications/ReadBox.app"
  codesign --force --deep --sign "$SIGN_IDENTITY" "/Applications/ReadBox.app" >/dev/null 2>&1 || true
  touch "/Applications/ReadBox.app"
  echo "==> Installed successfully: /Applications/ReadBox.app"
fi
