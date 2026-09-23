# Where the numbers come from

This is the knowledge that took the longest to find and would be the easiest
to lose. Read it before changing a reader.

Neither Claude Code nor Codex offers a usage API we are willing to call — the
ones that exist need an OAuth token from the Keychain and a network request,
and AI Limits does neither. Both providers are instead read from files they
already write for their own purposes.

---

## Claude Code

**Live figures exist nowhere on disk.** `~/.claude/stats-cache.json` holds
lifetime token totals, not windows. Session transcripts record limit *rejections*
after the fact, but never current utilisation. `claude` has no `usage`
subcommand.

The one place Claude Code hands out its real, server-side windows without
credentials or network access is the **status line**. It runs the configured
command on every render and pipes it a JSON document containing `rate_limits`.
`refreshInterval` makes it re-run on a timer while a session is idle.

That is why AI Limits installs a status line wrapper. It is the entire reason
that install step exists.

### The payload

Claude Code pipes a document shaped like this. Only `rate_limits` is ever
extracted:

```json
{
  "session_id": "…",
  "transcript_path": "…",
  "cwd": "…",
  "model": { "id": "claude-opus-5", "display_name": "Opus" },
  "rate_limits": {
    "five_hour": { "used_percentage": 29, "resets_at": 1790137800 },
    "seven_day": { "used_percentage": 5,  "resets_at": 1790618400 }
  }
}
```

The `rate_limits` object above is a real capture, kept verbatim in
`Tests/LimitKitTests/Fixtures/claude-capture-two-windows.json`. `resets_at`
arrives as Unix seconds; the parser also accepts ISO-8601, which costs nothing
and covers a format change we would not control.

**Window keys are discovered, not hard-coded.** Claude Code adds and removes
windows as plans change — model-specific weekly limits come and go, and a
`spend_limit` window exists for gateway deployments. `ClaudeReader` treats any
value carrying a percentage as a window and humanises unfamiliar keys, so a
new one shows up with a readable label instead of vanishing.

`resets_at` is accepted as ISO-8601 or as a Unix timestamp, because it is not
worth being wrong about.

### Known gaps

- **No session open means no updates.** Nothing writes these figures when
  Claude Code is not running, so the data goes stale by design. The UI dims and
  dates it rather than presenting it as current.
- **Some deployments have no limits at all.** API key, Bedrock, Vertex and
  Foundry sessions carry no `rate_limits`. Nothing is written and the provider
  reads as not connected, which is correct.
- **No plan label.** Unlike Codex, the payload carries no subscription tier,
  so the Claude card shows no plan badge.
- **Other window kinds are unconfirmed.** The two above were captured live.
  A `rate_limits.spend_limit` field exists for gateway deployments with spend
  limits, and model-specific weekly windows come and go with the plan; neither
  has been seen here. That is why window keys are discovered rather than
  listed, and why the parser accepts both snake_case and camelCase. If you
  capture one, add the payload to `Tests/LimitKitTests/Fixtures` and assert
  against it.

---

## Codex

Codex needs no install step. It writes server-reported limits to disk on every
turn, and has done so across every version checked.

**Location:** `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`

Codex also keeps an index of these files in `~/.codex/state_5.sqlite`
(`threads.rollout_path`). **We deliberately do not open it.** Reading a live
SQLite database in WAL mode risks contending with Codex's own locks, and
walking the dated directories newest-first is both cheaper and safer.

### The event

One `token_count` event per turn, carrying the numbers verbatim from the
server:

```json
{"timestamp":"2026-08-05T04:19:41.777Z","type":"event_msg","payload":{
  "type":"token_count",
  "info":{"total_token_usage":{…},"model_context_window":258400},
  "rate_limits":{
    "limit_id":"codex",
    "primary":{"used_percent":33.0,"window_minutes":300,"resets_at":1781855290},
    "secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1782421690},
    "plan_type":"plus",
    "rate_limit_reached_type":null}}}
```

- `window_minutes` names the window: 300 is the 5-hour, 10080 the weekly.
  Labels are derived from it, so a new window length still displays.
- `secondary` is often `null` — some plans report only a weekly window. A null
  window must not become a phantom 0% bar.
- `resets_at` is Unix seconds.

### How it is read

Rollout files reach tens of megabytes and are full of conversation content.
`FileTail` reads the last 256 KB read-only; `CodexReader` scans backwards for
the newest line that actually carries limits and takes only the numbers.
Nothing else in the file is parsed, retained, or logged.

A session's final events often carry no limits, which is why the scan looks for
the newest *usable* reading rather than the newest event.

---

## Providers not supported

**Gemini CLI** and **Qwen Code** report no server-side limit windows at all.
Any figure would be a local request count measured against a quota we guessed,
and a confident wrong number is worse than no number. If either gains a
server-reported window, `docs/adding-a-provider.md` is the recipe.
