# Performance and execution budgets

App startup, permissions, document loading, and Apple-event round trips usually
matter more than building a script string. Measure the operation on its actual
host and accounts before choosing a deadline.

## Distinguish a call timeout from a workflow budget

| API | Default |
| --- | --- |
| Raw AppleScript/JXA/script files and legacy wrappers | No deadline |
| New typed app helpers | Generally 30 seconds per operation |
| `Composition.run/2` and built-in workflows | 30 seconds total |
| `Wait.until/2` outside a scope | 5 seconds, polling every 50 ms |
| `GUI.run/3` | 5 minutes |
| `EventKit.install/2` | 2 minutes |

`ExMacOSControl.with_options/2` applies per-call limits in the current process.
Use `Composition.run/2` when all steps must share one finite budget. Nested runs
cannot extend the parent deadline. Callbacks are cooperative; arbitrary Elixir
code is not forcibly cancelled. Resource cleanup may use up to five additional
seconds after work ends.

The command runner bounds combined stdout/stderr to 10 MiB by default. Raise or
lower `max_output_bytes:` when appropriate. That limit does not constrain files
an external app writes or every intermediate allocation in native scripts.

## Poll the state you need

Use `Safari.wait_for_selector/3`, `Accessibility.wait_for/3`,
`Wait.until/2`, or `Composition.verify/3` instead of fixed sleeps.
Pass the predicate's remaining budget to app queries. Predicates may return
`true`/`false` or tagged booleans; errors stop polling immediately.

App process readiness does not imply a loaded account or document. A page's
`document.readyState` does not prove that asynchronous data has arrived. Choose
a selector or readback that establishes the next operation's actual prerequisite.

## Reduce repeated work

- Capture once when several steps use the same page, message, clipboard, or selection.
- Prefer batch helpers that validate inputs before the first write.
- Use Image Events `process/4` for several transforms in one image open/save.
- Return structured JSON from a native script when many properties can be fetched together.
- Use list pagination deliberately rather than repeatedly reading the first page.

Paged results are not stable database snapshots; app changes between pages can
shift contents. Larger batches also make partial failure and unknown outcomes
more consequential. Keep a recoverable resource identity for every write.

## Coordinate desktop work

Parallel reads can help when they address independent resources and do not
compete for app state. Focus-dependent UI work needs serialization.
`Desktop.with_lock/2` coordinates participating callers on the host, including
other BEAM instances. Waiting for the lock consumes the workflow budget. The
lock cannot prevent a person or unrelated app from changing focus.

Task context is explicit; see [advanced usage](guides/advanced_usage.md).
Do not hold a foreground lock while awaiting a child task that needs the same
lock. A generic task pool or rate-limiting GenServer does not automatically
preserve composition deadlines or desktop ownership.

## Measure

```elixir
{microseconds, result} = :timer.tc(fn ->
  ExMacOSControl.Finder.list_windows(timeout: 5_000)
end)
IO.inspect(microseconds / 1_000, label: "Elapsed milliseconds")
```

The OSAScript adapter's telemetry `duration` is in microseconds. Composition
event durations are native monotonic units. The
[telemetry guide](guides/advanced_usage.md#observe-execution-telemetry) describes
event names and conversion; do not mix those units.

## Do not use retries to hide uncertain writes

`Retry.with_retry/2` retries timeout errors, with exponential backoff starting at
200 ms or constant one-second linear backoff. It refuses unknown-outcome and
composition timeouts unless you explicitly declare `idempotent: true`.
That option does not deduplicate effects. Permission errors and syntax errors
are not retried. When state is still loading, polling a read is often a better
fit than rerunning an entire workflow.

For timeout after a mutation, inspect completed steps, journal evidence, and the
app state before another attempt. See
[captures and recovery](guides/captures_and_recovery.md).
