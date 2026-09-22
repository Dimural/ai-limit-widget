# Adding a provider

A provider is worth adding when it reports **server-side limit windows** to a
local file. If the best you can do is count requests locally and compare them
against a quota you looked up, stop — a confident wrong number is worse than no
number, and that is why Gemini CLI and Qwen Code are not here.

The whole job is five steps and touches four files.

## 1. Find the data, and write down where

Before any code, find where the tool records its own limits and add a section
to [`data-sources.md`](data-sources.md): the file path, a real payload, the
field names, and the gaps. Someone will have to re-derive this otherwise.

Useful places to look, in order:

```bash
# Anything with limit-shaped fields in the tool's own directory
grep -rl 'rate_limit\|used_percent\|resets_at' ~/.toolname --include='*.json*' | head

# Session or rollout logs, newest first
ls -t ~/.toolname/sessions/**/*.jsonl 2>/dev/null | head -1

# A status line, hook, or plugin interface the tool pipes JSON to
toolname --help | grep -iE 'status|hook|usage'
```

**Do not** reach for the Keychain, an auth file, or an HTTP endpoint. That is a
different product, and `make check` will fail the build.

## 2. Capture a fixture

Real payloads, not hand-written ones. Strip anything that identifies you —
conversation text, paths, account ids — and keep the numbers.

```bash
grep -h 'rate_limit' ~/.toolname/sessions/…/session.jsonl | tail -3 \
  > Tests/LimitKitTests/Fixtures/toolname-both-windows.jsonl
```

Capture the awkward cases too, because they are where readers break: a missing
second window, a payload with no limits at all, a truncated final line.

## 3. Write the test first

In `Tests/LimitKitTests/ToolnameReaderTests.swift`. The test states what the
parser must survive, so write the failure cases, not just the happy path:

```swift
func testReadsBothWindows() throws {
    let snapshot = try XCTUnwrap(
        ToolnameReader.parse(lines: Fixture.lines("toolname-both-windows.jsonl"))
    )
    XCTAssertEqual(Set(snapshot.windows.map(\.label)), ["5-hour", "Weekly"])
}

func testReturnsNilRatherThanZeroWhenThereIsNoData() {
    XCTAssertNil(ToolnameReader.parse(lines: []))
}
```

## 4. Write the reader

Add the case to `ProviderID` in `Models.swift`, the path to `Paths.swift`
(nowhere else — `make check` enforces this), and the reader in
`Sources/LimitKit/ToolnameReader.swift`.

Model it on `CodexReader`. Three things matter:

- **Split parsing from file access.** A `static func parse(…)` that takes data
  is testable; one that opens a file is not.
- **Return `nil`, never throw, never zero.** A provider with no data is absent
  from the display. An empty bar reads as "plenty left".
- **Use `RateLimitParsing`.** It already handles Unix seconds, Unix
  milliseconds, ISO-8601, numeric strings, both key spellings, and window
  labels. Do not re-derive any of that.

Then add it to `SnapshotBuilder.build()`. That is the only wiring; both UIs
iterate `snapshot.providers` and pick it up with no further changes.

## 5. If it needs an install step

Most will not. If yours does, it must be reversible, recorded, and backed up —
read `ClaudeHookInstaller.swift` and its test file, which is the specification
for how that is done here, and add the same round-trip tests.

## Before you call it done

```bash
make verify
```

Then check the two things tests cannot: that the reader reports nothing at all
before the tool has ever run, and that its numbers match what the tool's own
usage command says.
