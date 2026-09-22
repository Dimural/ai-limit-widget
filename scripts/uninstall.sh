#!/bin/bash
#
# Removes AI Limits and puts everything it touched back the way it was.
#
# Anything installed should be removable in one command, and the user should be
# able to read that command before running it. This is that command.

set -uo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/AILimits.app"
DATA="$HOME/Library/Application Support/AILimits"
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$HOME/.claude/settings.json.ailimits-backup"

echo "==> Restoring Claude Code's status line"
# The app restores the exact previous value; it knows what was there before.
if [ -d "$APP" ]; then
	"$APP/Contents/MacOS/AILimits" --uninstall-hook 2>/dev/null || true
fi

# Belt and braces: if the app could not run, undo the edit directly.
if [ -f "$SETTINGS" ] && grep -q 'ai-limits-statusline' "$SETTINGS" 2>/dev/null; then
	if [ -f "$BACKUP" ]; then
		echo "    app could not run; restoring from backup"
		cp "$BACKUP" "$SETTINGS"
	else
		echo "    WARNING: $SETTINGS still references AI Limits and no backup exists."
		echo "    Remove the \"statusLine\" entry by hand."
	fi
fi

echo "==> Quitting and removing the app"
osascript -e 'tell application "AILimits" to quit' 2>/dev/null || true
pkill -x AILimits 2>/dev/null || true
rm -rf "$APP"

echo "==> Removing stored data"
rm -rf "$DATA"

echo
echo "Done. Your settings backup is kept at:"
echo "  $BACKUP"
echo "Delete it once you are satisfied nothing was lost."
