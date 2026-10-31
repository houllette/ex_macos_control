# Using built-in workflows

`ExMacOSControl.Workflows` connects native app operations into common handoffs.
Each recipe captures its source once and shares a total deadline, normally
30 seconds. Writes are attempted once; earlier changes remain if a later step
fails. Use an explicit `timeout:` to set the total budget.

Set up [permissions](getting_started.md#prepare-permissions) first. Recipes may
start destination apps and temporarily establish their UI readiness. Their
desktop scopes restore focus and clean up acquired support windows; they do not
quit apps or undo created notes, reminders, drafts, or imports.

## Choose destinations

Discover resource IDs in your own session:

```elixir
alias ExMacOSControl.{Calendar, Mail, Messages, Notes, Reminders, Shortcuts}

{:ok, folders} = Notes.list_folders(limit: 100)
{:ok, lists} = Reminders.list_lists(limit: 100)
{:ok, calendars} = Calendar.list_calendars()
{:ok, accounts} = Mail.list_accounts()
{:ok, chats} = Messages.list_chats()
{:ok, shortcuts} = Shortcuts.list(limit: 100)
```

Inspect those results and choose IDs intentionally. IDs are opaque, scoped to the
app/backend, and may stop resolving after a resource is moved or deleted. The
examples below accept those IDs as arguments instead of choosing the first
available account or chat. Many list APIs are paged; inspect subsequent pages
when the desired resource is absent.

## Save the current Safari page

Bring the desired Safari tab to the front and optionally select text. Then:

```elixir
defmodule ReadingInbox do
  alias ExMacOSControl.Workflows

  def save(folder_id, list_id) do
    # Each call is a separate workflow and captures the current page again.
    with {:ok, note_id} <- Workflows.current_page_to_note(
           folder_id: folder_id, timeout: 15_000
         ),
         {:ok, reminder_id} <- Workflows.current_page_to_reminder(
           list_id, priority: 5, timeout: 15_000
         ) do
      {:ok, %{note_id: note_id, reminder_id: reminder_id}}
    end
  end
end
```

Notes includes the URL and selected text, falling back to page text. The Reminder
includes the URL and selection, without the full-page fallback. Safari captures
require **Allow JavaScript from Apple Events**. To guarantee two destinations use
the same page content and one deadline, capture once in a
[custom workflow](building_workflows.md).

`current_page_to_draft/2` accepts Mail options as its first argument:

```elixir
ExMacOSControl.Workflows.current_page_to_draft(
  [to: "reader@example.com", subject: "For review"],
  timeout: 15_000
)
```

This creates a draft with the URL and selection; it does not send. The returned
ID addresses Mail's outgoing compose object. Use the verified-draft helper when
you need a saved Drafts-mailbox reference.

## Attach selected files to a verified Mail draft

Select regular files in Finder. The selection must be non-empty; file bytes
remain at their original paths unless you explicitly stage them.

```elixir
alias ExMacOSControl.{Mail, Workflows}

{:ok, draft} = Workflows.selection_to_verified_draft(
  [to: "reviewer@example.com", subject: "Files for review", body: "Please review."],
  timeout: 20_000
)

{:ok, saved} = Mail.get_draft(draft)
IO.inspect(saved.id, label: "Saved draft")
```

Verification waits for a newly saved draft matching normalized body and
recipients, subject, optional sender, and attachment names/sizes. It returns
`%ExMacOSControl.Mail.Draft{}`. It does not checksum Mail's stored attachment
bytes or establish delivery. A verification failure can leave an outgoing or
saved draft; inspect the error before creating another.

For the simpler compose ID, use `selection_to_draft/2`. Both selection-to-draft
recipes accept `:to`, `:subject`, `:body`, `:cc`, `:bcc`, `:sender`, and `:from`
in the Mail options list; selected paths supply attachments. General workflow
options go in the second list.

## Turn a reminder into a scheduled event

The Apple-event Calendar workflow needs explicit start and end timestamps with
timezones. It defaults the title and description from the source reminder.

```elixir
defmodule ScheduleReminder do
  alias ExMacOSControl.Workflows

  def run(reminder_id, list_id, calendar_id, start_at, end_at) do
    Workflows.reminder_to_event(
      reminder_id,
      calendar_id,
      [start_at: start_at, end_at: end_at],
      list_id: list_id,
      verify_event: true,
      complete_reminder: true,
      timeout: 20_000
    )
  end
end
```

Pass `DateTime` values or ISO 8601 strings including an offset. This returns
`{:ok, %{event_id: event_id, reminder_id: reminder_id}}`. The reminder is completed
only after creation succeeds and, with `verify_event: true`, all requested event
fields are observed. Without that option, completion follows acknowledgement.
If completion fails, the created event remains. Neither write is retried.

This recipe uses `ExMacOSControl.Calendar` and `ExMacOSControl.Reminders`; it
does not switch to the optional EventKit backend.

## Use the clipboard or Shortcuts

```elixir
alias ExMacOSControl.Workflows

# Creates a note in the default Notes folder.
Workflows.clipboard_to_note("Scratchpad", timeout: 10_000)

# Requires a user-installed Shortcut that accepts text.
Workflows.clipboard_to_shortcut("Normalize Text", timeout: 10_000)

# Runs the Shortcut, then replaces the clipboard with its text output.
Workflows.shortcut_to_clipboard("Normalize Text", "some text", timeout: 10_000)
```

`clipboard_to_shortcut/2` leaves the clipboard unchanged.
`shortcut_to_clipboard/3` returns `{:ok, text}` and writes an empty string for
empty output. A Shortcut may itself have effects. Read the
[Shortcuts guide](shortcuts.md) to create a companion Shortcut and define its
input/output contract.

## Open a persistent workspace

```elixir
ExMacOSControl.Workflows.open_workspace(File.cwd!(),
  applications: ["com.apple.Terminal"],
  urls: ["https://example.com"],
  timeout: 15_000
)
```

The folder must exist. This opens a Finder window, ensures the requested apps are
running, and opens dedicated Safari pages. It returns
`{:ok, %{folder: path, applications: apps, pages: pages}}`. Those windows stay open.
The page references are owned and can be passed to `Safari.close_page/2` when
you intentionally want to close them. Opening a page does not wait for it to load.

## Recipe reference

All functions below belong to `ExMacOSControl.Workflows`. Optional `opts` include
`:timeout` and `:max_output_bytes`. Recipe-specific options are listed separately;
unknown options are rejected.

| Recipe | Success value / effect | Additional options |
| --- | --- | --- |
| `current_page_to_note(opts)` | `{:ok, note_id}`; URL + selection or page text | `:title`, `:folder_id` |
| `current_page_to_reminder(list_id, opts)` | `{:ok, reminder_id}`; URL + selection | Reminder options below |
| `current_page_to_draft(mail_options, opts)` | `{:ok, outgoing_id}`; creates a draft | Separate Mail options |
| `current_page_to_chat(chat_id, opts)` | `:ok`; sends URL + selection | None |
| `clipboard_to_note(title, opts)` | `{:ok, note_id}` | `:folder_id` |
| `clipboard_to_reminder(list_id, title, opts)` | `{:ok, reminder_id}` | Reminder options |
| `clipboard_to_chat(chat_id, opts)` | `:ok`; sends clipboard text | None |
| `clipboard_to_shortcut(identifier, opts)` | Shortcut result | Shortcut options below |
| `shortcut_to_clipboard(identifier, input, opts)` | `{:ok, text}`; replaces clipboard | `:trim` |
| `selection_to_shortcut(identifier, opts)` | Shortcut result; native file input | Shortcut options |
| `selection_to_draft(mail_options, opts)` | `{:ok, outgoing_id}` | Separate Mail options |
| `selection_to_verified_draft(mail_options, opts)` | `{:ok, %Mail.Draft{}}` | Separate Mail options |
| `selection_to_chat(chat_id, opts)` | `{:ok, [:ok, ...]}`; sends each file | None |
| `selection_to_album(name, opts)` | `{:ok, %{album_id: id, media_ids: ids}}`; imports files | `:folder_id`, `:skip_duplicates` |
| `selection_to_images(destination, steps, opts)` | `{:ok, output_paths}`; writes transformed copies | `:format` |
| `message_to_note(account_id, mailbox, message_id, opts)` | `{:ok, note_id}`; sender, subject, content | `:title`, `:folder_id` |
| `message_to_reminder(account_id, mailbox, message_id, list_id, opts)` | `{:ok, reminder_id}` | Reminder options |
| `event_to_note(calendar_id, event_id, opts)` | `{:ok, note_id}`; event details | `:title`, `:folder_id` |
| `event_to_reminder(calendar_id, event_id, list_id, opts)` | `{:ok, reminder_id}`; due date defaults to event start | Reminder options |
| `note_to_reminder(note_id, list_id, opts)` | `{:ok, reminder_id}`; title + plain text | Reminder options |
| `reminder_to_event(reminder_id, calendar_id, attributes, opts)` | `{:ok, %{event_id: id, reminder_id: id}}` | `:list_id`, `:complete_reminder`, `:verify_event` |
| `open_workspace(directory, opts)` | `{:ok, %{folder: path, applications: apps, pages: pages}}` | `:applications`, `:urls` |

Reminder options are `:title`, `:due_at`, `:reminder_at`, `:priority`, and
`:flagged`. Priority accepts integers `0..9`; common values are `0` (none),
`1` (high), `5` (medium), and `9` (low).
Shortcut options are `:output`, `:trim`, `:output_path`, and `:output_type`.
The page-to-Reminder title option overrides its title; clipboard-to-Reminder
uses its positional title. Other Reminder recipes allow a title override.

Messages recipes send real text/files to an existing chat and never infer a
recipient. A successful send acknowledges the app command, not recipient receipt.

For `selection_to_images/3`, the destination directory must exist and every output
path must be new. Steps use the Image Events form, for example
`[scale: 1200, rotate: 90]`, with `format: "JPEG"` when desired.

Read [captures and recovery](captures_and_recovery.md) before rerunning a failed
recipe. For a recipe with extra behavior or a different destination, continue to
[building your own workflows](building_workflows.md).
