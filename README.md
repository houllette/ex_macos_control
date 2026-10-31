# ExMacOSControl

[![hex.pm version](https://img.shields.io/hexpm/v/ex_macos_control.svg)](https://hex.pm/packages/ex_macos_control)
[![hex.pm license](https://img.shields.io/hexpm/l/ex_macos_control.svg)](LICENSE)

Control macOS applications from Elixir through AppleScript, JavaScript for
Automation (JXA), native command-line tools, and an optional EventKit helper.

Use app modules for individual operations, ready-made workflows for common
handoffs, or ordinary Elixir functions to compose your own automation. The library
provides shared deadlines, structured errors, scoped resources, and optional
execution journals. It runs on your Mac and uses the applications and accounts
available to the process running Elixir.

## Install

Add the dependency to your project's `mix.exs`, then run `mix deps.get`:

```elixir
defp deps do
  [{:ex_macos_control, "~> 0.3.0"}]
end
```

Start `iex -S mix` and verify script execution:

```elixir
{:ok, "Hello from macOS"} =
  ExMacOSControl.run_applescript(~s(return "Hello from macOS"), timeout: 5_000)
```

The project requires Elixir `~> 1.19`. Real automation requires macOS and the
native tool for the operation (`osascript`, `shortcuts`, etc.). CI checks native
contracts on macOS 26; that is the tested host, not a promise that every API works
on all macOS releases. Shortcuts needs macOS 12 or later. The optional EventKit
helper targets macOS 14 or later and requires Apple's Swift toolchain to build.
App versions, account configuration, and macOS permissions also affect availability.

## Try a workflow

Select a page in Safari, then save it to Notes:

```elixir
alias ExMacOSControl.Workflows

{:ok, note_id} = Workflows.current_page_to_note(timeout: 15_000)
```

This captures the page once, then creates a note containing its URL and selected
text, falling back to visible page text when nothing is selected. Without
`folder_id:`, Notes uses its default account and folder. For an explicit
destination, discover folders with `ExMacOSControl.Notes.list_folders/1` and pass
the chosen ID. Safari captures require **Allow JavaScript from Apple Events** in
Safari's developer settings, as well as Automation permission.

Other built-in handoffs include clipboard → Notes/Reminders/Shortcuts, selected
Finder files → a Mail draft/Photos/Image Events/Shortcuts, and Mail messages or
Calendar events → Notes/Reminders. Messages workflows perform real sends to an
explicit chat ID. Mail workflows create drafts. See the
[workflow guide](docs/guides/workflows.md) for destinations, return values, and
examples.

## Build your own

Compose reads and writes with `with`, and give the whole operation one deadline:

```elixir
alias ExMacOSControl.{Capture, Composition, Notes}

Composition.run(fn ->
  with {:ok, text} <- Composition.step(:capture_clipboard, &Capture.clipboard/0),
       {:ok, id} <- Composition.effect(:create_note, fn ->
         Notes.create_from(text, title: "Clipboard capture")
       end, resource: :note) do
    {:ok, id}
  end
end, timeout: 10_000)
```

Steps return `:ok`, `{:ok, value}`, or `{:error, %ExMacOSControl.Error{}}`.
Effects are attempted once. On failure, completed results remain available in
the error details; previous changes are not rolled back. Follow
[building workflows](docs/guides/building_workflows.md) to add verification,
batch operations, tracing, and tests.

## Capabilities

| Area | What you can do |
| --- | --- |
| Execution | Run AppleScript/JXA source or files, including compiled scripts and bundles; compile, validate, and decompile scripts. |
| Safari | Address windows/tabs, capture pages, wait for selectors, extract fields, fill forms, and click elements; use owned windows with cleanup and optional document guards. |
| Finder | Read/set selections, inspect windows and metadata, copy/move/rename files, create folders, and process a captured selection. |
| Mail and Messages | Discover accounts and chats, read/search Mail, manage attachments and flags, create saved/verified drafts, and explicitly send mail or Messages text/files. |
| Productivity | Read and write Notes, Reminders, Calendar, and Contacts resources using native IDs; compose batches and related operations. |
| Media | Manage Photos imports/albums/exports; control Music/TV; work with QuickTime documents; transform images through Image Events; read Final Cut Pro library/project metadata. |
| Desktop | Manage application lifecycle/focus; inspect accessibility trees and actions; operate menus, keys, and windows; run commands in an owned Terminal window in the logged-in GUI session. |
| Native utilities | Clipboard, dialogs, notifications, speech, volume, property lists, Terminal scripts, existing Automator workflows, and System Settings pane navigation. |
| Shortcuts | Discover names/IDs/folders, run text/JSON/file input, handle typed output, chain installed shortcuts, and use a versioned workflow protocol. |
| Discovery and diagnostics | Inspect installed apps, OSA languages, scripting dictionaries, permission states, and fixed live qualification profiles. |
| Optional EventKit | Build/install a native helper for verified Calendar event operations and Reminder batches using separate EventKit references. |

The [capability reference](docs/capabilities.md) covers module boundaries and
limitations. In particular, Messages history needs a user-configured Shortcut,
Messages unread counts are unavailable, System Settings has no universal toggle
API, and Final Cut Pro support does not include general timeline editing.
Scripting dictionary declarations are unverified until exercised on the target
host. Mock tests and native source contracts do not establish live account or UI
compatibility.

## Execution and permissions

New typed app helpers and compositions generally use a 30-second deadline. Raw
script execution and legacy wrappers have no default deadline; pass `timeout:`
explicitly or use `ExMacOSControl.with_options/2`. The default combined stdout
and stderr limit is 10 MiB. A composition shares one budget across its operations;
a `with_options/2` scope applies options to individual calls in the current process.

Timeout stops the owned command process group, but an app may already have acted.
An unknown outcome needs observation before another write. The library does not
automatically retry sends or mutations. See
[captures and recovery](docs/guides/captures_and_recovery.md).

macOS may require Automation access to each target app, Accessibility access for
UI work, and separate EventKit access for the optional helper. The library can
inspect permission states and open settings; the user grants access. Follow
[getting started](docs/guides/getting_started.md) for setup and troubleshooting.

## Documentation

Guides are readable here on GitHub and are included alongside the
[HexDocs API reference](https://hexdocs.pm/ex_macos_control):

- [Documentation index](docs/index.md) — choose a guide by task.
- [Getting started](docs/guides/getting_started.md) — install, permissions, first automation.
- [Using built-in workflows](docs/guides/workflows.md) — practical recipes and their effects.
- [Building your own workflows](docs/guides/building_workflows.md) — compositions, verification, batches, testing.
- [Common patterns](docs/guides/common_patterns.md) — browser extraction, app focus, file batches, drafts.
- [Integrating Shortcuts](docs/guides/shortcuts.md) — create a companion Shortcut and exchange data.
- [Captures and recovery](docs/guides/captures_and_recovery.md) — snapshots, staged files, journals, partial failures.
- [Optional EventKit](docs/guides/eventkit.md) — install the helper and use native references.
- [Advanced usage](docs/guides/advanced_usage.md) — execution options, telemetry, adapters, tasks.
- [Script DSL and raw scripts](docs/guides/dsl_vs_raw.md) — extend beyond the app wrappers.

Build the documentation locally with `mix docs --warnings-as-errors --output
tmp/docs`. Start at `tmp/docs/index.html`.

## Development

```sh
mix deps.get
mix test --warnings-as-errors
mix quality
mix docs --warnings-as-errors --output tmp/docs
```

`mix test` excludes integration, desktop, Shortcut, and personal-account tests by
default. Live tests require an appropriate macOS session and explicit opt-ins.
See [testing](docs/testing.md), [contributing](CONTRIBUTING.md), and
[creating app modules](docs/creating_app_modules.md). Optional local hooks are
installed with `./scripts/install-hooks.sh`; their behavior is documented in
[Git hooks](docs/git_hooks.md).

## License

[MIT](LICENSE).
