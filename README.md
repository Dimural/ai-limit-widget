# AI Limits

A macOS desktop widget that shows how much of your Claude Code and Codex usage
you have left, and when it resets.

No more stopping to run `/usage`, and no more finding out you hit a limit by
being refused mid-task.

```
┌─────────────────────────┐   ┌───────────────────────────────────────┐
│ Claude Code             │   │ Claude Code  max    Codex  plus       │
│                         │   │ 5-hour  ███████░░░  5-hour  ███░░░░░░ │
│      68%                │   │            68%                 33%    │
│ 5-hour                  │   │ 2:03:41                    1:09:12    │
│ ███████░░░              │   │ Weekly  ██░░░░░░░░  Weekly  █░░░░░░░░ │
│ 2:03:41                 │   │            24%                  7%    │
└─────────────────────────┘   └───────────────────────────────────────┘
        Small                              Medium
```

The reset countdown ticks live. The percentages update as you work.

---

## What it reads, and what it does not

AI Limits is built to be safe to leave running on a machine you do real work
on. It:

- **Makes no network requests at all.** Not one. There is no HTTP client in the
  codebase, and the build fails if someone adds one.
- **Reads no credentials.** Not your Keychain, not `auth.json`, nothing.
- **Reads no conversation content.** It takes percentages and reset times from
  files your CLIs already write, and nothing else from them.
- **Changes exactly one thing on your Mac** — one key in
  `~/.claude/settings.json` — and only if you ask it to. It is backed up first
  and restored on uninstall.
- **Costs nothing when idle.** No polling; it sleeps until a CLI writes
  something.

These are enforced by `scripts/check-safety.sh`, which the build runs. They are
checks, not promises.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode command line tools — `xcode-select --install`

No Apple Developer account. No Homebrew. No other dependencies.

Full Xcode is needed only to run the test suite, because XCTest ships with
Xcode rather than with the command line tools. Building, installing and
running AI Limits do not need it.

## Install

```bash
git clone https://github.com/dimural/ai-limit-widget.git
cd ai-limit-widget
./install.sh
```

Then:

1. Click the menu bar item → **Connect Claude Code**. Codex needs no setup.
2. Turn on **Open at Login** so it comes back after a restart.
3. Right-click your desktop → **Edit Widgets** → search **AI Limits**.

Three widgets are offered: everything at once, Claude Code alone, and Codex
alone. Small shows whichever window is closest to running out.

## How it gets the numbers

| | How | Needs setup |
|---|---|---|
| **Codex** | Reads the rate limits Codex already writes to its session files after every turn | No |
| **Claude Code** | Claude Code passes its real usage windows to a status line command; AI Limits wraps yours and reads them | Yes, one setting |

### The Claude Code setting, in full

Claude Code keeps no live usage figures on disk. The only way to get real ones
without reading your credentials or calling the network is the status line,
which Claude Code pipes usage data to on every render.

So **Connect Claude Code** changes this one key in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "/Applications/AILimits.app/Contents/Resources/ai-limits-statusline",
  "refreshInterval": 10
}
```

Before doing it, your file is copied to `settings.json.ailimits-backup`, and
your previous status line command is recorded. **Your status line keeps working
exactly as before** — the shim runs your command with the same input and passes
its output straight through. If you had no status line, you get a compact usage
summary instead of a blank one.

Disconnecting, or `./scripts/uninstall.sh`, puts the original value back and
leaves every other setting alone.

### One honest limitation

Claude Code only reports its usage while a session is open. With no session
running, nothing updates those numbers — so AI Limits **dims the card and
labels it "as of 9:42 PM"** rather than showing an old figure as if it were
current. Codex has no such gap; its data is on disk whether it is running or
not.

## Uninstall

```bash
./scripts/uninstall.sh
```

Restores your status line, removes the app, and deletes its data. Your settings
backup is left behind for you to delete once you are happy.

## Not supported

**Gemini CLI** and **Qwen Code** report no server-side usage windows. The only
number available would be a local request count measured against a quota we
guessed at, and a confident wrong number is worse than none. If they gain real
windows, [`docs/adding-a-provider.md`](docs/adding-a-provider.md) is the recipe.

## Contributing

This repo is built to be worked on through an AI agent.
**[`AGENTS.md`](AGENTS.md)** is the entry point — it is written to be enough
context on its own to make a correct change.

```bash
make verify     # build, test, and check the safety invariants
```

- [`docs/data-sources.md`](docs/data-sources.md) — where every number comes
  from, with real payloads
- [`docs/architecture.md`](docs/architecture.md) — why the widget reads a
  pushed file, and why it costs nothing when idle
- [`docs/adding-a-provider.md`](docs/adding-a-provider.md) — adding another CLI

## Licence

MIT. See [LICENSE](LICENSE).
