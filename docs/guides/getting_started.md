# Getting started

This guide takes you from installation to a page extraction and a cross-app
workflow. Run examples from an Elixir project on your Mac.

## Requirements

- Elixir `~> 1.19` and an Erlang/OTP release compatible with it. CI exercises
  Elixir 1.19/OTP 28 and Elixir 1.20/OTP 29.
- macOS for real automation. CI's native contract checks run on macOS 26;
  availability on other releases depends on the native APIs and app versions used.
- A logged-in desktop session for app/UI automation. SSH or a background service
  does not necessarily have the same GUI or permission context as Terminal.
- The target apps, accounts, and permissions required for the operation.

Shortcuts requires macOS 12 or later. The optional EventKit helper targets macOS
14 or later and needs Apple's Swift compiler for installation. Ordinary
AppleScript/JXA calls do not build or install that helper.

## Install and verify

Add to your project's dependency list in `mix.exs`:

```elixir
{:ex_macos_control, "~> 0.3.0"}
```

Fetch dependencies and start IEx:

```sh
mix deps.get
iex -S mix
```

Verify the execution layer without controlling another app:

```elixir
{:ok, "Hello from macOS"} =
  ExMacOSControl.run_applescript(~s(return "Hello from macOS"), timeout: 5_000)

{:ok, "Hello from JXA"} =
  ExMacOSControl.run_javascript("'Hello from JXA'", timeout: 5_000)
```

Raw results are text by default, even when the script returns a number or a list.
For structured results, return JSON and use `output: :json`:

```elixir
{:ok, %{"count" => 3}} =
  ExMacOSControl.run_javascript("JSON.stringify({count: 3})",
    output: :json,
    timeout: 5_000
  )
```

## Prepare permissions

Automation permission is per target application. Accessibility permission is
needed for UI actions such as menus and keystrokes. Grant permissions to the host
macOS identifies in its prompt or settings; this may be Terminal, your IDE, or a
packaged application. Switching how you launch Elixir can change that identity.

```elixir
alias ExMacOSControl.{Applications, Permissions}

Permissions.check_accessibility()
Permissions.open_accessibility_preferences()
Permissions.open_automation_preferences()
```

The settings helpers open the appropriate pane; they do not grant access.
For a deliberate consent flow, start the target and check its state:

```elixir
{:ok, _app} = Applications.ensure_running("com.apple.Safari", timeout: 5_000)

case Permissions.preflight_automation("com.apple.Safari") do
  {:ok, :granted} -> :ok
  {:ok, :requires_consent} -> Permissions.request_automation("com.apple.Safari")
  {:ok, state} -> {:permission_state, state}
  {:error, error} -> {:error, error}
end
```

Preflight does not request consent or launch the target. States are `:granted`,
`:denied`, `:requires_consent`, `:not_running`, `:unavailable`, and `:unknown`.
`request_automation/2` explicitly allows a consent prompt. A granted wildcard
preflight does not prove every app command is supported.

The older `Permissions.check_automation/1` performs a real `get name` Apple event
and returns `:granted` or `:not_granted`; it can launch the app or prompt. Do not
use it as a passive permission inventory.

Safari DOM helpers also require **Allow JavaScript from Apple Events** in
Safari's developer settings. Permission to automate Safari alone is insufficient.
The EventKit helper has its own Calendar/Reminders consent, described in the
[EventKit guide](eventkit.md). Full Disk Access is not a general prerequisite:
this library does not read the Messages database directly.

## Extract a page

Prefer an owned page and an observable wait over a fixed sleep:

```elixir
alias ExMacOSControl.Safari

{:ok, heading} = Safari.extract_text("https://example.com", "h1", timeout: 15_000)
IO.puts(heading)
```

This opens a dedicated Safari window, waits for the page and selector, extracts
the text, and closes the window it owns. It may launch Safari. Existing tabs are
not used for this operation. If someone adds a tab to the owned window, cleanup
refuses to close it and returns an error with resource details.

For more work in one page scope:

```elixir
Safari.with_page("https://example.com", [timeout: 15_000], fn page ->
  with :ok <- Safari.wait_for_selector(page, "h1") do
    Safari.extract(page, %{"heading" => "h1", "paragraph" => "p"})
  end
end)
```

See [common patterns](common_patterns.md) for targeting, navigation, forms, and
document guards.

## Run a cross-app workflow

Copy some text to the clipboard, then create a note:

```elixir
alias ExMacOSControl.Workflows

{:ok, note_id} = Workflows.clipboard_to_note("Captured text", timeout: 10_000)
```

This writes to the default Notes folder. To choose a destination, discover it
first with `ExMacOSControl.Notes.list_folders/1`, inspect the IDs, and pass
`folder_id: chosen_id`. The library does not create account containers implicitly.

The [workflow guide](workflows.md) describes other handoffs and whether they
create resources, send data, or leave windows open.

## Handle failures and deadlines

```elixir
case ExMacOSControl.run_applescript("return 42", timeout: 5_000) do
  {:ok, value} -> IO.puts(value)
  {:error, %ExMacOSControl.Error{} = error} ->
    IO.inspect({error.type, error.message}, label: "Automation failed")
end
```

Raw script calls and legacy wrappers have no default timeout. New typed helpers
and compositions generally default to 30 seconds; a composition uses that as a
total budget. Pass an explicit deadline when the operation matters to a caller.

After a timeout, the target app may already have changed. Check
`error.details[:outcome]`, completed steps, and observable app state before
another write. A timeout is not evidence that a send or creation did nothing.
Read [captures and recovery](captures_and_recovery.md) before adding retries.

## Troubleshoot

| Symptom | Next check |
| --- | --- |
| Executable/platform error | Verify macOS with `ExMacOSControl.Platform.validate_macos/0`; check which native tool the operation needs. |
| Permission denied | Confirm the launching host's Automation/Accessibility settings; explicitly request consent where appropriate. |
| Safari JavaScript error | Enable JavaScript from Apple Events, verify the selector, and wait for the expected page state. |
| App is running but data is unavailable | Running-process readiness does not guarantee that accounts, documents, or network content have loaded. |
| Missing window/tab | Discover a fresh target; tab indices can become stale after reordering, closure, or app restart. |
| Workflow timed out after creating something | Inspect completed results and the app before repeating the workflow. |

Continue with [built-in workflows](workflows.md),
[building your own workflows](building_workflows.md), or the
[capability reference](../capabilities.md).
