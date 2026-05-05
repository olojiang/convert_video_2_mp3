#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ConvertVideo2MP3"
DISPLAY_NAME="Video2Mp3 纪"
APP_BUNDLE="${DISPLAY_NAME}.app"
LEGACY_APP_BUNDLE="${APP_NAME}.app"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_BUNDLE}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"
ICNS_PATH="${RESOURCES_DIR}/AppIcon.icns"
ZIP_PATH="${DIST_DIR}/${DISPLAY_NAME}.zip"

cd "${ROOT_DIR}"

swift test
swift build -c release

rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

swift scripts/generate_icon.swift "${ICONSET_DIR}"
iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>local.convert-video-2-mp3</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.6.0</string>
  <key>CFBundleVersion</key>
  <string>160</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "${APP_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"

rm -rf "/Applications/${APP_BUNDLE}" "/Applications/${LEGACY_APP_BUNDLE}"
cp -R "${APP_DIR}" "/Applications/${APP_BUNDLE}"

echo "Built: ${APP_DIR}"
echo "Package: ${ZIP_PATH}"
echo "Installed: /Applications/${APP_BUNDLE}"
