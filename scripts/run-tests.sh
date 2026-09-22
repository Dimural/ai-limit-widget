#!/bin/bash
#
# Runs the test suite, and explains itself when it cannot.
#
# XCTest ships inside Xcode, not with the command line tools. AI Limits builds
# and runs perfectly well with the tools alone, so a missing or unusable Xcode
# should produce one clear sentence rather than a wall of "no such module"
# errors.

set -uo pipefail
cd "$(dirname "$0")/.."

explain() {
	echo "Cannot run tests: $1"
	echo
	echo "This does not affect using AI Limits. 'swift build', 'make check' and"
	echo "'make app' all work without Xcode — only the test suite needs it."
	echo
	echo "$2"
	exit 1
}

if ! developer_dir=$(xcode-select -p 2>/dev/null); then
	explain "no developer directory is selected." \
		"Run:  sudo xcode-select -s /Applications/Xcode.app"
fi

# An unaccepted Xcode licence makes every Xcode-provided tool refuse to run,
# while still exiting 0 — so the message has to be read, not the status.
# Captured to a variable rather than piped: `grep -q` closes the pipe on its
# first match, and under `pipefail` that SIGPIPE becomes the pipeline's exit
# status, so the test would silently never fire.
xcrun_message=$(xcrun --find swift 2>&1)
if [[ "$xcrun_message" == *license* ]]; then
	explain "Xcode's licence has not been accepted." \
		"Run:  sudo xcodebuild -license accept"
fi

if [ ! -d "$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" ]; then
	explain "XCTest was not found (the command line tools do not include it)." \
		"Install Xcode from the App Store, then run:
  sudo xcode-select -s /Applications/Xcode.app
  sudo xcodebuild -license accept"
fi

exec swift test "$@"
