#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ConvertVideo2MP3"
DISPLAY_NAME="Video2Mp3 纪"
APP_BUNDLE="${DISPLAY_NAME}.app"
LEGACY_APP_BUNDLE="${APP_NAME}.app"
DIST_APP="${ROOT_DIR}/dist/${APP_BUNDLE}"
INSTALL_APP="/Applications/${APP_BUNDLE}"
LEGACY_INSTALL_APP="/Applications/${LEGACY_APP_BUNDLE}"

cd "${ROOT_DIR}"

INSTALL_APP=0 "${ROOT_DIR}/scripts/build_release.sh"

osascript -e "tell application \"${DISPLAY_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
pkill -x "${DISPLAY_NAME}" >/dev/null 2>&1 || true
sleep 1

rm -rf "${INSTALL_APP}" "${LEGACY_INSTALL_APP}"
cp -R "${DIST_APP}" "${INSTALL_APP}"

open "${INSTALL_APP}"

echo "Updated and launched: ${INSTALL_APP}"
