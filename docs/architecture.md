# Architecture

Three processes, one shared library, one file between them.

```
  Claude Code ──stdin──> StatusLineShim ─────> claude.json ──┐
   (on every render)     (exits immediately)                 │
                                                             ▼
  Codex ──> rollout-*.jsonl ──FSEvents──────────────> AILimits.app
   (on every turn)                                    (collector)
                                                       │      │
                                    snapshot.json <────┘      └───> menu bar
                                    (widget container)
                                          │
                                          ▼
                                  AILimitsWidget.appex
                                     (desktop widget)
```

## Why the widget reads a pushed file

macOS requires app extensions to be sandboxed, so the widget cannot read
`~/.claude` or `~/.codex` itself. The usual answer is an App Group, whose
entitlement needs a Team ID — which means an Apple Developer account, which
means this could not be built from source by anyone who clones it.

Instead the collector, which is not sandboxed, **writes the snapshot into the
widget extension's own container**:

```
~/Library/Containers/com.dimural.AILimits.Widget/Data/
    Library/Application Support/AILimits/snapshot.json
```

The sandbox restricts what the *extension* may reach, not what other processes
may place inside it, and an extension reading a file in its own container needs
no entitlement at all. The push is one-way; nothing is ever read back.

Inside the sandbox the extension's home *is* that container, so
`Paths.snapshotForWidget` and `Paths.widgetContainerSnapshot` resolve to the
same file from their two different vantage points.

The container does not exist until the widget has been added to the desktop
once, so the push fails quietly until then.

## Why it costs nothing when idle

- **No polling of provider files.** FSEvents watches `~/.codex/sessions` and
  our own directory; the collector does no work until something writes.
  `DispatchSource` would not do — Codex writes several levels deep and a
  source on the root directory never sees it.
- **One slow timer.** A 60-second heartbeat, with 30 seconds of tolerance so
  it coalesces with other wake-ups and never wakes a sleeping Mac. It exists
  only so countdowns and staleness stay right while nothing is changing.
- **Bounded reads.** Rollout files reach tens of megabytes; `FileTail` reads
  the last 256 KB, read-only.
- **The menu is built when opened.** Not on every snapshot — nobody is looking
  at it the rest of the time.

## Why widget reloads are rate limited

WidgetKit budgets how often a widget may reload, and a busy Codex session can
write several times a minute. Spending the budget early means the widget stops
updating later, which is worse than updating a little less often. `Collector`
reloads at most once a minute and defers the rest of a burst so the last value
still lands.

Between reloads the display is not frozen: reset countdowns use WidgetKit's
timer text, which ticks every second without a reload, and timelines describe
an hour ahead in five-minute steps so the staleness label stays honest even if
no reload arrives at all.

## Why writes are atomic

The widget may read at any moment the system chooses. Every write goes through
`SnapshotStore.writeAtomically`: a temporary file in the same directory, then a
rename. A reader sees either the old contents or the new ones, never a
half-written file. Files are mode 0600.

## Why there is no Xcode project

A generated `.pbxproj` is unreadable and unmergeable. This project is built for
people who read and write code through an AI agent, and a file no one can read
is a file no one can safely change. SwiftPM compiles the three binaries;
`scripts/build-app.sh` assembles the bundles, which are just directories with a
known shape.

The cost is that AppIntents-based widget configuration is unavailable — it
needs a metadata step only Xcode runs. Hence three static widget kinds rather
than one configurable widget.

## Process boundaries

| | Sandboxed | Runs when | Can read |
|---|---|---|---|
| `StatusLineShim` | no | every Claude Code render | stdin, our own directory |
| `AILimits.app` | no | always (login item) | provider files, our directory |
| `AILimitsWidget.appex` | **yes** | when the system decides | its own container only |

The shim exits immediately after one small write, so the only process that
stays resident is the menu bar app.
