#!/bin/bash
#
# AI Limits makes three promises. This script is how they are kept honest:
# it fails the build when code violates one, so the rules are enforced rather
# than merely documented.
#
#   1. No network access, ever.
#   2. Nothing outside our own directories is written to, except the single
#      documented Claude Code status line edit.
#   3. Nothing is read beyond the specific files we declare.
#
# Run it with `make check`, or on its own.

set -uo pipefail
cd "$(dirname "$0")/.."

failures=0

fail() {
	printf '\033[31mFAIL\033[0m %s\n' "$1"
	shift
	printf '     %s\n' "$@"
	failures=$((failures + 1))
}

pass() {
	printf '\033[32m ok \033[0m %s\n' "$1"
}

# Source files only: tests and docs legitimately mention these names.
sources() {
	find Sources -name '*.swift'
}

# Greps Swift code while ignoring comments, so a doc comment explaining a rule
# does not trip the rule it explains. Output stays as file:line:text.
grep_code() {
	local pattern="$1"
	shift
	local file found=""
	for file in "$@"; do
		local hits
		hits=$(grep -nE "$pattern" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)') || true
		if [ -n "$hits" ]; then
			found="${found}$(echo "$hits" | sed "s|^|$file:|")
"
		fi
	done
	[ -n "$found" ] && printf '%s' "$found"
}

# --- 1. No network -----------------------------------------------------------

network_symbols='URLSession|NSURLConnection|CFStream|Network\.framework|import Network|NWConnection|getaddrinfo|CFSocket'
if matches=$(grep_code "$network_symbols" $(sources)); then
	fail "Networking API found in Sources/" \
		"AI Limits must never make a network request." \
		"$matches"
else
	pass "no networking APIs in Sources/"
fi

# --- 2. Only one writer outside our own directories --------------------------

# Writes are funnelled through SnapshotStore.writeAtomically. Anything else
# reaching for a write API is a new, unreviewed way to touch the disk.
write_apis='\.write\(to:|createFile\(atPath:|removeItem\(at:|moveItem\(at:|copyItem\(at:|replaceItemAt\('
allowed_writers='Sources/LimitKit/SnapshotStore.swift|Sources/LimitKit/ClaudeHookInstaller.swift'
if matches=$(grep_code "$write_apis" $(sources | grep -vE "$allowed_writers")); then
	fail "Filesystem write outside SnapshotStore/ClaudeHookInstaller" \
		"Route writes through SnapshotStore.writeAtomically so they stay atomic and private." \
		"$matches"
else
	pass "writes confined to SnapshotStore and ClaudeHookInstaller"
fi

# Only the installer may write anywhere near Claude Code's own files.
# Paths.swift declares the location; ClaudeHookInstaller is the only user.
if matches=$(grep_code 'claudeSettings' \
	$(sources | grep -vE 'ClaudeHookInstaller\.swift|Paths\.swift')); then
	fail "Claude Code settings referenced outside ClaudeHookInstaller" \
		"$matches"
else
	pass "only ClaudeHookInstaller touches ~/.claude/settings.json"
fi

# --- 3. Provider paths are declared in one place -----------------------------

if matches=$(grep_code '"\.codex|"\.claude|\.codex/|\.claude/' \
	$(sources | grep -v 'Sources/LimitKit/Paths.swift')); then
	fail "Hard-coded provider path outside Paths.swift" \
		"Every path AI Limits touches is declared in Paths.swift so it can be audited in one read." \
		"$matches"
else
	pass "provider paths declared only in Paths.swift"
fi

# --- 4. No stubs left behind -------------------------------------------------

if matches=$(grep_code 'TODO|FIXME|unimplemented' $(sources)); then
	fail "Unfinished work left in Sources/" "$matches"
else
	pass "no TODO/FIXME/unimplemented markers"
fi

echo
if [ "$failures" -gt 0 ]; then
	echo "$failures safety check(s) failed."
	exit 1
fi
echo "All safety checks passed."
