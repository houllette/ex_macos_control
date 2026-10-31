# Building your own workflows

A workflow is an Elixir function. Use app modules for operations, `with` for
control flow, and `ExMacOSControl.Composition` for a shared deadline and progress
evidence. No separate DSL, registration, or workflow server is required.

## Capture once, then write

This example saves the same Safari content to a chosen Notes folder and Reminders
list. It returns both created IDs, and retains the note ID if reminder creation
fails.

```elixir
defmodule MyAutomation.ReadingTask do
  alias ExMacOSControl.{Capture, Composition, Notes, Reminders}

  def run(folder_id, list_id, opts \\ []) do
    Composition.run(fn ->
      with {:ok, page} <- Composition.step(:capture_page, &Capture.current_page/0),
           {:ok, note_id} <- Composition.effect(:save_note, fn ->
             Notes.create_from(page, folder_id: folder_id)
           end, resource: :note),
           {:ok, reminder_id} <- Composition.effect(:save_reminder, fn ->
             Reminders.create_from(list_id, page)
           end, resource: :reminder, identity: %{list_id: list_id}) do
        {:ok, %{note_id: note_id, reminder_id: reminder_id}}
      end
    end, opts)
  end
end
```

Call it with IDs selected from `Notes.list_folders/1` and
`Reminders.list_lists/1`, for example `ReadingTask.run(folder_id, list_id,
timeout: 15_000)`. `Capture.current_page/1` freezes the URL, title, visible text,
selection, source identity, and capture timestamp. Rendering that capture later
does not reread Safari.

App callbacks can launch apps. If this workflow should also acquire and clean up
destination support windows, wrap the call in
`ExMacOSControl.Desktop.Session.with_apps/3` with the bundle IDs
`["com.apple.Notes", "com.apple.reminders"]`. The scope cleans up owned support
windows and restores focus, while leaving created account resources in place.

## Name reads, effects, and verification

| Function | Use it for | Behavior |
| --- | --- | --- |
| `Composition.step/2` | Reading or computing one named result | Executes once and records successful results in memory. |
| `Composition.effect/3` | A mutation or externally visible operation | Records an effect intent, executes once, and marks dispatched failures uncertain unless explicitly `:not_started`. |
| `Composition.verify/3` | Observing the expected state | Polls a boolean predicate; records `:confirmed` after success. |
| `Composition.map/3` | Sequential named operations | Stops at the first error and retains completed items. |
| `Composition.map_effects/4` | Sequential mutations | Validates declared identities before starting; records each effect separately. |

Every step callback must return `:ok`, `{:ok, value}`, or `{:error, reason}`.
Non-library reasons are wrapped in `ExMacOSControl.Error`. A `Composition.run/2`
callback should return the same tagged forms. Use atom step names, or tuples of
atoms/indices, so trace labels are meaningful. Arbitrary string labels are redacted.

Resource metadata makes journal entries useful for reconciliation. Pass an atom
such as `resource: :note` and native identity fields such as
`identity: %{list_id: list_id}`. A returned scalar ID can be recorded as the
created resource ID. Keep content, credentials, and recipients out of identities.

## Verify what the next step depends on

Acknowledgement means the command returned successfully. If later work depends
on saved state, read it back:

```elixir
defmodule MyAutomation.VerifiedNote do
  alias ExMacOSControl.{Composition, Notes}

  def create(folder_id, title, text) do
    Composition.run(fn ->
      with {:ok, id} <- Composition.effect(:create_note, fn ->
             Notes.create_text_note(title, text, folder_id: folder_id)
           end, resource: :note),
           :ok <- Composition.verify(:note_title, fn remaining ->
             case Notes.get_note(id, timeout: remaining) do
               {:ok, note} -> note.title == title
               {:error, _} = error -> error
             end
           end, interval: 100) do
        {:ok, id}
      end
    end, timeout: 15_000)
  end
end
```

This verifies only the title. Choose predicates that establish the property your
next operation needs. Predicates return a boolean or `{:ok, boolean}`; an error
stops the wait immediately. They should observe state, not perform writes.
Existing helpers such as `Mail.create_verified_draft/1` and EventKit operations
already provide more specific verification.

## Share a deadline

`Composition.run/2` defaults to a finite 30-second total budget. Nested runs use
the earlier deadline and cannot extend the parent. Calls through the facade and
typed app helpers cap their timeouts to the remaining budget. If the budget is
already exhausted, a subsequent guarded call is refused before dispatch.

Callbacks run in the caller process. Arbitrary Elixir computation, sleeps, and
third-party I/O are cooperative; they are not forcibly interrupted. Give your own
I/O a timeout based on `Composition.remaining/0`. `ExMacOSControl.with_options/2`
sets options for individual calls and does not replace a total composition budget.

Scoped resources may need up to five additional seconds for cleanup after work
times out. Exceptions and throws are re-raised after cleanup.

## Process a batch

Use a domain helper when one exists: `Finder.copy_files/3`,
`Reminders.create_many/3`, `Contacts.create_with_details/3`,
`Photos.import_into_new_album/3`, or `ImageEvents.process_many/4`. These helpers
validate inputs relevant to their operation and retain partial results.

For custom mutations:

```elixir
defmodule MyAutomation.CompleteTasks do
  alias ExMacOSControl.{Composition, Reminders}

  def run(ids, list_id) do
    Composition.run(fn ->
      Composition.map_effects(ids, :complete_reminder, fn id ->
        Reminders.complete_reminder(id, list_id: list_id)
      end, resource: :reminder, identity: fn id -> %{id: id, list_id: list_id} end)
    end, timeout: 15_000)
  end
end
```

The result is `{:ok, results}` in input order. Work stops at the first error.
This is not a transaction; completed items stay changed. Validate all your
business inputs before the first write when partial creation would be undesirable.

## Make failures inspectable

```elixir
defmodule MyAutomation.ReportFailure do
  alias ExMacOSControl.Error

  def describe({:error, %Error{} = error}) do
    details = error.details || %{}
    %{
      type: error.type,
      message: error.message,
      failed_step: get_in(details, [:composition, :step]),
      completed: get_in(details, [:composition, :completed]),
      recovery: details[:recovery_status],
      run_id: details[:run_id],
      journal_path: details[:journal_path]
    }
  end
end
```

Nested failures can have an inner `:cause`, and top-level run errors also expose
`:run_completed`. Inspect the full structure as needed, but avoid logging private
captured content. No write is automatically replayed or rolled back. Read
[captures and recovery](captures_and_recovery.md) for journals and unknown outcomes.

## Test without controlling apps

Configure a Mox adapter in your consumer project's test environment, then expect
the calls your workflow actually uses. Typed app APIs generate JXA and call the
adapter's `run_javascript/2`; many legacy helpers use `run_applescript/1` unless
execution options add the second argument. `Composition` propagates a timeout,
so composition calls normally reach the two-argument callback.

Assert the returned IDs, destination arguments, and the behavior after a partial
failure. Use expectations to prove a mutation is dispatched once. The
[testing guide](../testing.md) includes working consumer setup; the repository's
test helpers are not part of the published runtime API.

When a workflow must run later or repeatedly, schedule your Elixir function with
your application's job/scheduling system. This library provides neither a
scheduler nor automatic persistence/replay of workflows.
