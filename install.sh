#!/bin/bash
#
# Builds AI Limits from source and installs it.
#
# Requires the Xcode command line tools and macOS 14 or later. No Apple
# Developer account, no package manager, no other dependencies.

set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swift >/dev/null 2>&1; then
	echo "Swift toolchain not found. Install the Xcode command line tools:"
	echo "  xcode-select --install"
	exit 1
fi

echo "==> Checking the safety invariants"
./scripts/check-safety.sh

echo
echo "==> Running tests"
swift test

echo
./scripts/build-app.sh

echo "==> Installing to /Applications"
rm -rf /Applications/AILimits.app
cp -R AILimits.app /Applications/AILimits.app
open /Applications/AILimits.app

cat <<'MSG'

AI Limits is running in your menu bar.

Next:
  1. Click the menu bar item and choose "Connect Claude Code" to start
     reading Claude Code's usage windows. Codex needs no setup.
  2. Turn on "Open at Login" so it comes back after a restart.
  3. Right-click your desktop, choose Edit Widgets, and search "AI Limits".

To remove everything, including the Claude Code change:
  ./scripts/uninstall.sh
MSG
