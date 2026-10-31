# Captures and recovery

Capture a source once when several destinations must see the same data. Retain
created IDs and execution evidence when a workflow can fail after making a change.
Neither captures nor journals turn app automation into a transaction.

## Capture once, render locally

```elixir
alias ExMacOSControl.Capture

{:ok, page} = Capture.current_page(timeout: 10_000)
plain = Capture.render(page, :plain)
html = Capture.render(page, :html)
reference = Capture.render(page, :reference)
```

Captures retain a `source` map with native identity and a `captured_at` timestamp.
Rendering, `Capture.title/1`, `Capture.files/1`, and `Capture.source/1` do not query
apps. They do not prove that a source still exists.

| Source API | Capture | Contents |
| --- | --- | --- |
| `Capture.current_page/1` or `Capture.page/2` | `Capture.Page` | URL, title, visible page text, selected text |
| `Capture.clipboard/1` | `Capture.Text` | Current text clipboard |
| `Capture.note/2` | `Capture.Text` | Note title and plain text |
| `Capture.selection/1` | `Capture.Files` | A non-empty Finder selection as paths |
| `Capture.message/4` | `Capture.Message` | Mail subject, sender, and content |
| `Capture.event/3` | `Capture.Event` | Calendar title, times, location, description, URL, and recurrence metadata |

Page `:plain` includes the URL and selection, falling back to visible text.
Page `:reference` includes only the URL and selection. `:html` escapes plain
content and wraps it in a paragraph; it does not preserve a source page's HTML.
Notes uses escaped HTML, while Mail and Reminders handoffs use plain/reference
text. File renders list paths; they do not embed file contents.

## Freeze file bytes when needed

A file capture records paths. It does not copy bytes, and another process can
change those paths before a destination reads them. For stable copies:

```elixir
alias ExMacOSControl.Capture

File.mkdir_p!("tmp/staged-captures")
destination = Path.expand("tmp/staged-captures/" <> Integer.to_string(System.unique_integer([:positive])))

{:ok, selected} = Capture.selection(timeout: 5_000)
{:ok, staged} = Capture.stage_files(selected, destination,
  max_bytes: 100_000_000, timeout: 15_000
)
:ok = Capture.verify_files(staged)
paths = Capture.files(staged)
```

The destination must be a new directory with an existing parent. Staging accepts
regular files, rejects final symlinks and colliding basenames, copies to a private
directory, and records checksums and file identities. `max_bytes` bounds the
total source bytes and defaults to 1 GiB.

Staging detects observed source changes; it is not an atomic filesystem
snapshot. Copies preserve file bytes, not extended attributes or resource forks.
Verify again immediately before handing staged paths to a destination.

Pass `paths` to a destination, then call `Capture.cleanup_files(staged)` only
when that destination no longer needs them. Verification checks owned copies;
cleanup refuses changed or foreign entries rather than deleting them. Cleanup
is explicit. A failed staging operation may leave a partial private directory;
inspect `:staging_root` and the cause in its error details.

`Capture.verify_files/2` is a no-op for an ordinary paths-only capture. It does
not retrospectively verify source content.

## Understand a failure

Inspect `error.details` on a `%ExMacOSControl.Error{}` returned by a composition:

| Detail | Meaning |
| --- | --- |
| `:outcome` | `:not_started` when that operation was refused before dispatch; `:unknown` when it may have acted. |
| `:composition` | Failed step and acknowledged completed step results; nested failures may include `:cause`. |
| `:run_completed` | Top-level run's completed results. |
| `:recovery_status` | `:no_effects`, `:partial`, or `:needs_reconciliation`, based on effects recorded by the composition. |
| `:run_id`, `:journal_path` | Correlation information, when available. |
| `:cleanup_error`, `:resource` | A scoped resource could not be cleaned up. |

The status reflects effects declared through composition helpers, not arbitrary
external code in your callback. A verification timeout can be `:not_started` for
the observation while an earlier create has already succeeded. Always consider
the whole run, including completed results.

Completed results can contain captured private app data. Avoid logging them
indiscriminately. No automatic rollback, deduplication, or exactly-once external
delivery is promised.

## Keep a durable journal

Enable journaling on an outer composition, so recipes inside it inherit the same
run and deadline:

```elixir
alias ExMacOSControl.{Composition, Workflows}

Composition.run(fn ->
  Workflows.clipboard_to_note("Captured text")
end, timeout: 10_000, journal: Path.expand("tmp/workflow-journals"), trace_to: self())
```

The journal directory is created privately, or must already be private. Its path
and ancestor directories must not be symlinks. Each run writes a new JSONL file;
run IDs cannot be reused. A supplied `run_id:` must be 32 lowercase hexadecimal
characters. Nested runs inherit the run ID and journal and cannot set their own.

An intent is synced before a step callback. Events retain timing, outcome, and
declared resource IDs; they omit arbitrary results, app bodies, and arguments.
Step names and explicitly supplied identities must still avoid sensitive content.
If a journal cannot be written before a step, the step is not dispatched. A
journal failure after acknowledgement can leave an acknowledged result in the
error details.

After the owning run has stopped, inspect its exact file path:

```elixir
defmodule InspectWorkflow do
  alias ExMacOSControl.Composition.Journal

  def run(journal_path) do
    with {:ok, summary} <- Journal.inspect_run(journal_path) do
      {:ok, Map.take(summary, [:run_id, :status, :pending, :resources])}
    end
  end
end
```

The summary status is `:complete`, `:failed`, or `:needs_reconciliation`.
Unfinished intents, unknown effects, or a truncated final record require
reconciliation. Inspection defaults to a 64 MiB file limit; `max_bytes:` may
lower it. An active run can legitimately have pending intents, so wait for its
owner to stop before interpreting those as an interruption.

Inspection never replays work. Observe recorded resources through the appropriate
app API, decide whether the intended state exists, and perform any corrective
action explicitly. Creating a fresh run ID does not make an uncertain write safe
to repeat. Unlike the separate live qualification harness, ordinary composition
journals do not automatically block new runs after an incomplete prior run.

## Retry only operations you can repeat

`Retry.with_retry/2` retries timeout errors only. Unknown-outcome and composition
timeouts require `idempotent: true` to opt into retry; that flag is your claim
that repetition is safe, not a deduplication mechanism. Do not wrap a send/create
workflow in a blanket retry.

Prefer `Wait.until/2` or `Composition.verify/3` when the issue is waiting for
observable state. For scoped Safari windows and app focus, use
[common patterns](common_patterns.md) so cleanup is tied to the acquired resource.
