# Testing

The repository separates mocked behavior, native execution/source contracts,
desktop mutation, and live account evidence. Passing one category does not prove
the others. Consumer projects can mock the scripting adapter without installing
macOS apps on their test host.

## Run repository checks

From the repository root:

```sh
mix test --warnings-as-errors
mix quality
mix docs --warnings-as-errors --output tmp/docs
```

`mix quality` runs formatting, strict Credo, and Dialyzer; it does not run tests
or build docs. Generated docs, logs, and other working files belong under `tmp/`.
To direct native temporary files there too, set `TMPDIR` to the absolute `tmp`
path before running checks.

Default ExUnit exclusions in `test/test_helper.exs` are `:integration`,
`:desktop`, `:shortcut`, and `:personal`. Some communication tests also have an
explicit `:skip` tag. Unit command tests use fake executables, and the test
environment supplies a headless desktop backend.

| Category | What it establishes | How to opt in |
| --- | --- | --- |
| Unit/mocked | Validation, generated arguments/source, parsing, errors, partial results, timeout/cleanup contracts | Default `mix test` |
| Native integration | Real tools, source compilation, execution and native API contracts | `--include integration` on macOS |
| Desktop integration | UI/app changes such as tabs, windows, app lifecycle, clipboard | Also `--include desktop`; use an isolated desktop session |
| Shortcut execution | A dedicated harmless installed Shortcut | Also `--include shortcut` and the fixture name |
| Personal/live | Real app/account operations with evidence and cleanup | `--include personal`, environment opt-ins, and per-suite prerequisites |

Some integration modules include desktop-tagged cases. Native CI deliberately
selects contract files in `.github/workflows/ci.yml`; it is not a blanket live
compatibility test for every wrapper. Inspect a suite's tags and setup before
running it on your everyday desktop.

For a dedicated Shortcut that simply returns its input:

```sh
TEST_SHORTCUT_NAME=Echo mix test --include integration --include shortcut test/integration/shortcuts_integration_test.exs
```

Do not substitute an arbitrary existing Shortcut: it may have effects.

## Mock a consumer workflow

In your own project, add `{:mox, "~> 1.2", only: :test}`. In
`test/test_helper.exs`, define and configure a mock once:

```elixir
ExUnit.start()
Mox.defmock(MyAutomation.AdapterMock, for: ExMacOSControl.Adapter)
Application.put_env(:ex_macos_control, :adapter, MyAutomation.AdapterMock)
```

The adapter is resolved at runtime. Avoid changing this application-wide setting
inside individual async tests. Mox expectations remain process-owned.

Example consumer workflow:

```elixir
defmodule MyAutomation.ClipToNote do
  alias ExMacOSControl.{Capture, Composition, Notes}

  def run do
    Composition.run(fn ->
      with {:ok, capture} <- Composition.step(:clipboard, &Capture.clipboard/0) do
        Composition.effect(:create_note, fn -> Notes.create_from(capture) end,
          resource: :note)
      end
    end, timeout: 10_000)
  end
end
```

Test its scripting boundary with versioned JXA responses:

```elixir
defmodule MyAutomation.ClipToNoteTest do
  use ExUnit.Case, async: true
  import Mox
  alias MyAutomation.AdapterMock
  setup :verify_on_exit!

  test "captures once and creates one note" do
    expect(AdapterMock, :run_javascript, fn script, opts ->
      assert script =~ "theClipboard"
      assert opts[:timeout] in 1..10_000
      {:ok, Jason.encode!(%{exmc: 1, result: "Captured text"})}
    end)

    expect(AdapterMock, :run_javascript, fn script, _opts ->
      assert script =~ "app.Note"
      {:ok, Jason.encode!(%{exmc: 1, result: "note-id"})}
    end)

    assert {:ok, "note-id"} = MyAutomation.ClipToNote.run()
  end
end
```

The ordered, single-use expectations also catch accidental rereads or duplicate
mutations. Add a failure case for each consequential stage and assert that later
writes are not dispatched. For a partial failure, assert that previously created
IDs remain in the error's completed results.

Typed app calls generate JXA and usually reach `run_javascript/2`. Many legacy
wrappers use `run_applescript/1` until options or a composition deadline cause
them to call `/2`. Mock the callback arity your code actually uses.

Repository modules such as `ExMacOSControl.AdapterFactory`, `TestHelpers`, and
`HeadlessDesktop` live in `test/support`. They are not runtime dependencies
available to consumers of the Hex package.

## Know what the adapter does not intercept

The adapter controls facade-backed AppleScript/JXA/script-file/Shortcut calls.
Direct `Command` operations, richer `Shortcuts` CLI calls, EventKit, GUI, and
filesystem staging can bypass it. A mocked adapter alone does not disable those
effects. Keep business logic separately testable, use explicit fake executables
for command contracts, and opt into real native execution separately.

When a test spawns a process, arrange Mox ownership with explicit allowances or
caller tracking. Composition context propagation and Mox permissions solve
different problems. See [advanced usage](guides/advanced_usage.md).

## Run live evidence suites deliberately

`test/live/` contains suites that create real resources, read them back, and
attempt cleanup. The common opt-ins are `EXMC_LIVE_TESTS=1`,
`EXMC_PERSONAL_TESTS=1`, and `--include personal`. Suites check for the logged-in
Aqua session and require relevant app/account permissions. EventKit suites also
require `EXMC_EVENTKIT_HELPER`; campaign suites may require `EXMC_TEST_EMAIL`.
Read the selected file before enabling it.

For example, after preparing the session, this selects the Safari guard suite:

```sh
EXMC_LIVE_TESTS=1 EXMC_PERSONAL_TESTS=1 mix test --include personal test/live/safari_guard_live_test.exs
```

From a non-GUI launching context, the repository's
`mix ex_macos_control.live -- <mix test arguments>` runner opens an owned Terminal
window in Aqua. It does not supply consent, accounts, or opt-in variables.
`--keep-window` before the separator retains the runner window. Evidence stays
under `tmp/`, including GUI evidence and composition qualification/campaign data.
Inspect evidence and cleanup outcomes rather than treating an exit code alone as
proof that every resource was removed.

## Disposable-session qualification

`mix ex_macos_control.qualify --host-info` reports host provisioning identity
without launching or querying target apps. The qualification harness supports
only `notes-crud` and `mail-capture`, using a private, expiring version 1 manifest
with exact host/user/app/fixture identities and finite limits.

Use `mix help ex_macos_control.qualify` for manifest-check/execute syntax.
Effects require both `--execute` and `EXMC_LIVE_TESTS=1`. Mail capture requires a
local-only test account/server and `.invalid` addresses; external delivery and
recording are disabled. Incomplete journals block new qualification effects until
independently reconciled. This is separate from ordinary composition journals,
which provide evidence without automatically blocking later runs.

The harness never provisions accounts or grants permissions. Its manifest checks
and native source contracts are not substitutes for live UI/account evidence.
