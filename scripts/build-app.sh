#!/bin/bash
#
# Assembles AILimits.app from the binaries SwiftPM produces.
#
# There is no .xcodeproj in this repo on purpose: generated project files are
# unreadable and unmergeable, which makes them hostile to humans and AI agents
# alike. A .app is just a directory with a known shape, so we build it here
# where every step is visible.
#
#   AILimits.app/Contents/
#     Info.plist
#     MacOS/AILimits                        menu bar app + collector
#     Resources/ai-limits-statusline        Claude Code status line shim
#     PlugIns/AILimitsWidget.appex/         the desktop widget
#
# Signing is ad-hoc (`-`), which is all macOS needs to run a locally built app
# and load its widget. No Apple Developer account is required.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
BUILD_DIR=".build/${CONFIGURATION}"
APP="AILimits.app"
APPEX="${APP}/Contents/PlugIns/AILimitsWidget.appex"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" "${APPEX}/Contents/MacOS"

cp Resources/AILimits-Info.plist "${APP}/Contents/Info.plist"
cp Resources/AILimitsWidget-Info.plist "${APPEX}/Contents/Info.plist"

cp "${BUILD_DIR}/AILimits" "${APP}/Contents/MacOS/AILimits"
cp "${BUILD_DIR}/ai-limits-statusline" "${APP}/Contents/Resources/ai-limits-statusline"
cp "${BUILD_DIR}/AILimitsWidget" "${APPEX}/Contents/MacOS/AILimitsWidget"

# The widget extension must be sandboxed; macOS will not load it otherwise.
# The shim and the app are not, because they read files the sandbox forbids.
echo "==> Signing"
codesign --force --sign - \
	--entitlements Resources/AILimitsWidget.entitlements \
	"$APPEX" >/dev/null

codesign --force --sign - "${APP}/Contents/Resources/ai-limits-statusline" >/dev/null
codesign --force --sign - "$APP" >/dev/null

echo "==> Verifying"
codesign --verify --verbose=1 "$APP"

echo
echo "Built $APP"
