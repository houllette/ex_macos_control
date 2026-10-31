# Advanced usage

For workflow structure, start with [building workflows](building_workflows.md).
This guide covers execution options, observability, adapters, and process context.

## Raw execution options

```elixir
ExMacOSControl.run_javascript("function run(argv) { return JSON.stringify(argv); }",
  args: ["one", "two"], output: :json,
  timeout: 5_000, max_output_bytes: 1_000_000
)
# => {:ok, ["one", "two"]}
```

| Option | Meaning |
| --- | --- |
| `:args` | String arguments passed to the script's `run` handler. |
| `:timeout` | Milliseconds; raw execution defaults to no deadline (`nil`/`:infinity`). |
| `:max_output_bytes` | Combined stdout/stderr bound; default 10 MiB. |
| `:output` | `:text`, `:source`, `:json`, or `:execution`. |
| `:trim` | Trim text output by default; `false` preserves whitespace. |
| `:stdin` | Pass source through stdin; automatic for source larger than 64 KiB. |
| `:telemetry_script` | Include the first 100 source characters in telemetry; default `false`. |

`:json` requires returned JSON text and decodes it. `:source` requests OSA source
representation; it is not JSON serialization. `:execution` returns the execution
map on success. A failed raw script still returns `{:error, %Error{}}`.

For `run_script_file/2`, `.applescript` is AppleScript, `.js`/`.jxa` is JavaScript,
and `.scpt`/`.scptd` uses its native compiled language. `language:` can select
`:applescript` or `:javascript` explicitly. Execution and compilation run trusted
code; these options do not sandbox scripts.

## Apply options to legacy app calls

```elixir
ExMacOSControl.with_options([timeout: 5_000, max_output_bytes: 1_000_000], fn ->
  ExMacOSControl.Safari.list_tabs()
end)
```

This scope affects facade-backed calls in the current process. Nested scopes
restore the prior values; explicit call options override scoped values, subject
to any enclosing composition deadline. It sets a per-call timeout, not a total
deadline for the callback. Use `Composition.run/2` for a total budget.

New typed helpers generally set a 30-second default; legacy wrappers and raw calls
retain an unlimited default. Some native utilities have their own defaults:
`Wait.until/2` defaults to 5 seconds outside a scope, `GUI.run/3` to 5 minutes,
and EventKit installation to 2 minutes. Check the operation rather than assuming
one timeout applies everywhere.

## Observe execution telemetry

The OSAScript adapter emits these events under a shared `:applescript` prefix for
AppleScript, JXA, script-file execution, and facade Shortcut runs:

| Event | Measurements / metadata |
| --- | --- |
| `[:ex_macos_control, :applescript, :start]` | `script_length`; `command`, `source_id`, `timeout` |
| `[:ex_macos_control, :applescript, :stop]` | Adds `duration` in microseconds; `result_type`, `output_length` |
| `[:ex_macos_control, :applescript, :exception]` | Adds `duration` in microseconds; redacted error type |

`source_id` is a SHA-256 hash of source, not the source itself. Script preview is
opt-in and may disclose data embedded in the source. Direct native helpers such
as `Shortcuts.run/2` use `Command` and do not emit adapter events just because
they run a command.

```elixir
defmodule MyAutomation.Telemetry do
  require Logger

  def attach do
    :telemetry.attach("automation-duration",
      [:ex_macos_control, :applescript, :stop], &__MODULE__.handle/4, nil)
  end

  def handle(_event, measurements, metadata, _config) do
    Logger.info("Automation completed",
      duration_ms: measurements.duration / 1_000,
      source_id: metadata.source_id
    )
  end
end
```

Attach once during application startup and detach with `:telemetry.detach/1`
when the handler is no longer needed. Keep handlers fast; they run synchronously.

Retry events use `[:ex_macos_control, :retry, event]`, where `event` is `:start`,
`:attempt`, `:sleep`, `:stop`, or `:error`. Attempt metadata includes `attempt`,
`max_attempts`, and `backoff`. Sleep measurements include `sleep_time` in
milliseconds. Error metadata contains the error type, not arbitrary error details.
Linear backoff is a constant 1 second; exponential backoff starts at 200 ms and
doubles. Retry has no independent total deadline.

## Observe composition events

Composition telemetry uses `[:ex_macos_control, :composition, event]` for
`:run_started`, `:step_started`, `:step_finished`, and `:run_finished`. Its event
metadata includes the run ID, step IDs, declared resources, and outcomes.
Durations here are in native monotonic time units; convert with
`System.convert_time_unit(duration, :native, :millisecond)`. Do not apply the
adapter's microsecond conversion to composition durations.

`trace_to: pid` additionally sends `{:ex_macos_control, event_map}` messages.
These omit arbitrary results. Use a receiver process that drains messages during
long runs rather than leaving them in a caller's mailbox. Optional durable
journaling is covered in [captures and recovery](captures_and_recovery.md).

## Propagate context to a joined task

Process-local options and composition context do not automatically cross tasks:

```elixir
alias ExMacOSControl.{Composition, Finder}

Composition.run(fn ->
  context = Composition.capture_context()
  task = Task.async(fn ->
    Composition.with_context(context, fn ->
      Composition.step(:finder_windows, &Finder.list_windows/0)
    end)
  end)
  Task.await(task, 6_000)
end, timeout: 5_000)
```

Join children before the originating run returns, especially when sharing its
journal. Captured context does not transfer a foreground lock, extend the
deadline, or merge a child's completed-step list into the parent's list. The
shared run/journal correlates their events. Mox ownership is separate: use Mox
allowances or caller tracking when a test spawns processes.

Avoid parallel focus-sensitive operations. A parent holding the desktop lock
must not wait for a child that needs that same lock.

## Implement a custom adapter

The `ExMacOSControl.Adapter` behavior defines eight required callbacks:
`run_applescript/1,2`, `run_javascript/1,2`, `run_script_file/2`,
`run_shortcut/1,2`, and `list_shortcuts/0`. The facade resolves the configured
adapter at call time.

```elixir
defmodule MyAutomation.Adapter do
  @behaviour ExMacOSControl.Adapter
  alias ExMacOSControl.OSAScriptAdapter, as: Native

  defdelegate run_applescript(script), to: Native
  defdelegate run_applescript(script, opts), to: Native
  defdelegate run_javascript(script), to: Native
  defdelegate run_javascript(script, opts), to: Native
  defdelegate run_script_file(path, opts), to: Native
  defdelegate run_shortcut(name), to: Native
  defdelegate run_shortcut(name, opts), to: Native
  defdelegate list_shortcuts(), to: Native
end
```

Configure `config :ex_macos_control, :adapter, MyAutomation.Adapter` in your app.
Preserve deadlines, output limits, error types, and the possibility of `:ok` for
empty Shortcut output. Do not add retries around every adapter operation.

The adapter is a scripting boundary, not a universal transport hook. Direct
`Command`, richer Shortcuts CLI operations, GUI, EventKit, and filesystem staging
can bypass it. Repository tests for those paths use fake executables or dedicated
backends; simply replacing the adapter does not suppress every possible effect.
See [testing](../testing.md) for consumer setup.
