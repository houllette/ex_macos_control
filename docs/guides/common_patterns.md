# Common automation patterns

These patterns use native resource identities, observable waits, and tagged
results. Set up [permissions](getting_started.md#prepare-permissions) first.
For ready-made cross-app handoffs, start with [built-in workflows](workflows.md).

## Open, wait, and extract in Safari

```elixir
defmodule BrowserSummary do
  alias ExMacOSControl.Safari

  def fetch(url) do
    Safari.with_page(url, [timeout: 15_000], fn page ->
      with :ok <- Safari.wait_for_selector(page, "h1"),
           {:ok, pinned} <- Safari.pin_document(page) do
        Safari.extract(pinned, %{"heading" => "h1", "description" => "p"})
      end
    end)
  end
end
```

The callback receives an owned page in a dedicated window. `with_page/3` waits
for readiness before the callback, then closes the owned window after a tagged
result or exception. `wait_for_selector/3` handles late-rendered content without
guessing a sleep duration. These DOM helpers require Safari's JavaScript from
Apple Events setting.

`Safari.extract/3` returns a map with string keys. A missing selector is an error;
the selector's first match supplies the extracted text. `text/3`, `attribute/4`,
and mutation helpers require an unambiguous match. Use selectors specific enough
for the operation.

`pin_document/2` binds subsequent operations to the current URL and document
token. Navigation and even a same-URL reload invalidate that handle. Use
`Safari.navigate_page/3` for deliberate navigation and retain the newly pinned
handle it returns. `navigate_and_wait/3` returns `:ok` but does not refresh a
previous pinned handle.

For a known URL and one selector, `Safari.extract_text/3` provides the whole
open/wait/read/cleanup sequence.

## Fill a form on a site you control

This example expects your page to contain the named elements and to display
`.submission-confirmation` after submission:

```elixir
defmodule SubmitFeedback do
  alias ExMacOSControl.Safari

  def run(url, name, message) do
    Safari.with_page(url, [timeout: 20_000], fn page ->
      with :ok <- Safari.wait_for_selector(page, "form"),
           {:ok, pinned} <- Safari.pin_document(page),
           {:ok, _} <- Safari.fill_fields(pinned, [
             {"input[name=name]", name},
             {"textarea[name=message]", message}
           ]) do
        Safari.click_and_wait(page, "button[type=submit]", ".submission-confirmation")
      end
    end)
  end
end
```

Fill helpers wait for editable elements, use the value setter, emit input/change
events, and verify the value. Click is dispatched once. This example deliberately
uses the unpinned page for the submission and following wait because submission
may replace the document. A selector appearing after a click establishes only
that observation; choose a stronger check when you need proof of saved server
state. A submission timeout must not trigger a blind second click.

Safari references contain a window ID and 1-based tab index, with a process
identity on acquired references. Safari has no stable tab IDs. Reordering or
closing tabs can stale a reference. Owned windows with additional tabs are
rejected, including during cleanup, and remain available for recovery.

## Manage an app's lifecycle and focus

```elixir
alias ExMacOSControl.{Applications, SystemEvents}

{:ok, app} = Applications.ensure_running("com.apple.TextEdit", timeout: 5_000)
IO.inspect(app.pid)

Applications.with_frontmost("com.apple.TextEdit", fn _app ->
  SystemEvents.press_key("TextEdit", "n", using: [:command])
end, timeout: 5_000)
```

`ensure_running/2` returns the running identity/PID and does not activate an
already-running app. It establishes process readiness, not document readiness.
`Applications.open/2` opens or reopens normal UI; `background: true` preserves
foreground ownership. This is useful for Calendar/Reminders, which can terminate
after a launch-only start without windows.

`with_frontmost/3` verifies foreground ownership and restores previous focus
when possible. Its desktop lock coordinates participating library callers across
BEAM instances. A person or another application can still change focus.
Accessibility permission is required for UI work.

`Applications.quit_if_running/2` waits for exit and returns `:ok` if already
stopped. Unsaved-document dialogs may cause a timeout. `restart/2` deliberately
quits and relaunches; do not use it as a generic recovery step for an app holding
someone's unsaved work.

## Process files from a fixed selection

```elixir
defmodule CopySelection do
  alias ExMacOSControl.{Finder, Composition}

  def run(destination) do
    Finder.with_selection(fn paths ->
      Composition.step(:copy_files, fn -> Finder.copy_files(paths, destination) end)
    end, timeout: 20_000)
  end
end
```

The destination directory must exist. Batch helpers check output collisions
before dispatch and return output paths in order. On a later failure, earlier
copies remain and their paths are retained in error details. Selection captures
store paths, not file bytes; use [staging](captures_and_recovery.md#freeze-file-bytes-when-needed)
when source contents must stay stable.

Image Events can apply several transformations in one open/save operation:

```elixir
ExMacOSControl.ImageEvents.process(
  Path.expand("tmp/source.png"),
  Path.expand("tmp/preview.jpg"),
  [scale: 1200, rotate: 90],
  format: "JPEG", timeout: 10_000
)
```

The input must exist, the output must be new, and its parent directory must
exist. Formats are strings: `"PNG"` (default), `"JPEG"`, `"TIFF"`, `"BMP"`, or
`"PSD"`. `process_many/4` validates the whole batch and output-name collisions.

## Prepare a Mail draft and keep its identity

```elixir
alias ExMacOSControl.Mail

{:ok, draft} = Mail.create_verified_draft(
  to: "reviewer@example.com",
  subject: "Review request",
  body: "Please review the attached material.",
  attachments: [Path.expand("tmp/report.pdf")],
  timeout: 20_000
)

{:ok, saved} = Mail.get_draft(draft)
IO.inspect(saved.subject)
```

The attachment must be an existing regular file. A verified draft is observed
in Drafts with matching content/recipients and attachment names/sizes. Keep the
returned `%Mail.Draft{}` for `Mail.get_draft/2` and deliberate
`Mail.delete_draft/2` cleanup. Verification can fail after a draft was created.

`Mail.create_draft/1` returns the outgoing compose ID without this saved-state
verification. `Mail.send_email/1` performs an actual send; successful execution
does not prove delivery and an uncertain send should not be retried automatically.

## Run a command in the logged-in GUI session

```elixir
ExMacOSControl.GUI.run("/usr/bin/osascript", ["-e", "return 42"],
  root: Path.expand("tmp/gui-runs"), timeout: 10_000
)
```

This opens one owned Terminal window in the logged-in Aqua session and returns
stdout, stderr, exit status, and evidence paths. It closes the window by default,
including after a command failure. `keep_window: true` retains it for inspection.
The evidence directory remains for review. A nonzero command exit is reported in
the result; inspect `exit_status`.

The runner requires macOS, a logged-in desktop session, the Elixir CLI, and the
necessary permissions. Ownership checks include the Terminal process, window,
TTY, token, and tab count. Changed or busy windows remain open with a cleanup
error. `GUI.run/3` never reuses an existing Terminal tab or replays an uncertain
launch. Prefer `ExMacOSControl.Command.run/3` when a GUI session is unnecessary.
