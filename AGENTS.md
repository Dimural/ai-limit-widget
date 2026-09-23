# AI Limits — working notes

A macOS desktop widget and menu bar app that shows how much of your Claude Code
and Codex usage windows you have left, and when they reset.

This file is the entry point. It is written to be enough on its own: read it
and you should be able to make a correct change without reading every file.

## What you may not break

These four rules are why the project is safe to install. Each one is enforced
by `scripts/check-safety.sh`, which `make verify` runs and which fails the
build — they are not style preferences.

1. **No network access, ever.** There is no `URLSession` anywhere, and adding
   one fails the build. Every number comes from a local file.
2. **No credentials are read.** Not the Keychain, not `~/.claude/.credentials`,
   not `~/.codex/auth.json`. If a change needs a token, the change is wrong.
3. **One writer outside our own directories.** `ClaudeHookInstaller` edits
   `~/.claude/settings.json`, backs it up first, and restores it on uninstall.
   Nothing else writes outside `~/Library/Application Support/AILimits`.
4. **Only the declared paths are touched.** Every path lives in `Paths.swift`
   so the whole footprint can be audited in one read.

Two more rules are not mechanically checkable, so they are on you:

- **Never show a number as if it were live when it is not.** Claude Code only
  reports limits while a session is open, so its data goes stale as a matter
  of course; the card says when the reading was taken.
  `Presentation.stalenessThreshold` is the boundary. Say it in words, not by
  fading the card — a dimmed reading looks like a broken one, which is exactly
  the bug that fading caused.
- **A window past its reset time is not a reading.** The allowance has rolled
  over and we have no measurement of the new one, so expired windows are
  dropped rather than quoted. See `LimitWindow.hasReset`.
- **A provider with no data is absent, not zero.** An empty bar reads as
  "plenty left", which is the opposite of the truth. Readers return `nil`.

## Where the numbers come from

Neither provider offers an API we are willing to call, so both are read from
files they already write. The full detail, with real payloads, is in
[`docs/data-sources.md`](docs/data-sources.md) — read it before changing a
reader.

| Provider | Source | Needs install? |
|---|---|---|
| Claude Code | `rate_limits` piped to a status line command, captured by `StatusLineShim` | Yes — one `settings.json` key |
| Codex | `rate_limits` in `~/.codex/sessions/**/rollout-*.jsonl` | No |

## Layout

```
Sources/LimitKit/         Data layer. No AppKit, no WidgetKit, no network.
                          Everything here is unit tested.
Sources/LimitUI/          SwiftUI views shared by the widget and the preview
                          renderer. Kept out of the extension so they can be
                          drawn to an image and looked at.
Sources/StatusLineShim/   Tiny binary Claude Code runs on every render.
                          Logic lives in LimitKit/StatusLineCapture.swift.
Sources/AILimitsApp/      Menu bar app. The collector; the process that stays
                          running; the only non-sandboxed piece.
Sources/AILimitsWidget/   WidgetKit extension. Sandboxed. Reads one file.
Tests/LimitKitTests/      Tests, and fixtures captured from real tools.
scripts/                  Build, install, uninstall, safety checks.
docs/                     Where the numbers come from, and how to add more.
```

Data flows one way:

```
Claude Code ──stdin──> StatusLineShim ──> claude.json ──┐
                                                        ├──> Collector ──> snapshot.json ──> Widget
Codex ──> rollout-*.jsonl ──────────────────────────────┘        │
                                                                 └──> menu bar
```

## Reading order

Changing a **parser**: `docs/data-sources.md`, then `RateLimitParsing.swift`,
then the reader, then its test.

Changing what is **displayed**: `Presentation.swift` holds the rules both UIs
share, so they can never disagree. Then `MenuBarController.swift` or
`WidgetViews.swift`.

Changing **install behaviour**: `ClaudeHookInstaller.swift` and its test. This
file writes to someone else's config; its test file is the specification.

Adding a **provider**: [`docs/adding-a-provider.md`](docs/adding-a-provider.md).

## Conventions

- **Fixtures, not mocks.** Tests read payloads captured from real Claude Code
  and Codex runs, in `Tests/LimitKitTests/Fixtures`. A passing test means the
  parser handles what these tools genuinely emit. When you add a case, add a
  fixture — do not hand-write a shape you have not seen.
- **Parsers return `nil`, they do not throw.** These are third-party formats
  that change without notice. A field we cannot read costs one window; it must
  never crash the collector or break someone's status line.
- **Comments explain why.** What the code does is visible. Why a threshold is
  60 seconds, or why FSEvents instead of `DispatchSource`, is not.
- **One file, one job.** Files stay small enough to hold in context whole.
- **No TODOs.** `check-safety.sh` fails on them. Finish it or leave it out.

## Commands

```
make verify     build + test + safety checks. Run this before you claim done.
make test       tests alone
make check      safety checks alone
make app        assemble AILimits.app
make install    build, install to /Applications, launch
make uninstall  remove the app, its data, and the Claude Code hook
```

`make verify` is the definition of "did I break anything". There is no other.

Useful while working:

```
make app && ./AILimits.app/Contents/MacOS/AILimits --render-preview /tmp/ui.png
./AILimits.app/Contents/MacOS/AILimits --print-snapshot   # what the widget sees
pluginkit -m -p com.apple.widgetkit-extension | grep -i ailimits   # is it registered
echo '<payload>' | ./AILimits.app/Contents/Resources/ai-limits-statusline
```

**Look at the UI before you claim it works.** `--render-preview` draws the
real menu rows to `/tmp/ui.png` and the real widget layouts to
`/tmp/ui.widgets.png`, both light and dark, using sample readings that cover
the states live data rarely shows at the moment you look: exhausted, past the
warning notch, and no longer current. Open the images. Reviewing a visual
change by reading the diff does not work, and this is the whole reason the
SwiftUI views live in `LimitUI` rather than inside the widget extension.

## Requirements

macOS 14 or later and the Xcode command line tools. No Apple Developer
account, no CocoaPods, no Homebrew, no other dependency — `Package.swift` has
none and should keep having none.

**Full Xcode is required to run the tests**, and only for that: XCTest ships
with Xcode, not with the command line tools. `swift build`, `make check` and
`make app` all work without it, and `make test` says so plainly rather than
failing with a wall of "no such module" errors. If you cannot run the tests in
your environment, say so — do not claim the suite passed.
