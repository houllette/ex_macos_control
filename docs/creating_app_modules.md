# Creating app modules

Add an app wrapper when an operation is useful repeatedly and the app exposes a
scripting interface. For a one-off command, a raw script is often sufficient.
For a new combination of existing operations, create an ordinary
[workflow](guides/building_workflows.md) instead.

## Explore the actual app interface

Use Script Editor's **Open Dictionary** command or
`ExMacOSControl.Capabilities.dictionary/2` to inspect the installed app's
terminology. Prototype the operation on a suitable macOS session with explicit
test resources. A declaration establishes syntax, not live permission or account
compatibility. Some apps have no scripting dictionary and require a Shortcut or
Accessibility interaction instead.

Choose a bundle ID where possible. Keep names/indices separate from stable native
IDs and document where identity can become stale. Write down the operation's
input, output, side effects, required permissions, and what success actually
acknowledges before adding the wrapper.

## Use the public facade

An app module can live in your own application's namespace. It does not need to
be added to ExMacOSControl itself. This complete example reads a TextEdit name
through JXA; it may launch TextEdit and needs the applicable Automation access:

```elixir
defmodule MyAutomation.TextEdit do
  @moduledoc "A small TextEdit scripting wrapper."

  @doc "Reads the application name. Accepts the facade's JXA execution options."
  @spec name(ExMacOSControl.Adapter.options()) ::
          {:ok, term()} | {:error, ExMacOSControl.Error.t()}
  def name(opts \\ []) do
    ExMacOSControl.run_javascript("Application('com.apple.TextEdit').name()", opts)
  end
end
```

Call with `timeout: 5_000` or inside `Composition.run/2`. Raw facade calls have no
default deadline. The facade preserves runtime adapter configuration and caps
execution against an enclosing composition; calling an adapter directly bypasses
those guards.

The Automation and Resources modules under ExMacOSControl are internal implementation modules
marked `@moduledoc false`; consumer extensions should use the public facade and
their own validation/decoding instead of depending on those internals.

## Pass data separately from source

Use `args:` and a `run` handler for external values. For structured data, encode a
JSON payload and return JSON text:

```elixir
defmodule MyAutomation.Transform do
  @moduledoc "An example of explicit JSON transport through JXA."

  def uppercase(text, opts \\ []) when is_binary(text) do
    script = """
    function run(argv) {
      var input = JSON.parse(argv[0]);
      return JSON.stringify({text: input.text.toUpperCase()});
    }
    """

    ExMacOSControl.run_javascript(script,
      Keyword.merge(opts, args: [Jason.encode!(%{text: text})], output: :json))
  end
end
```

This example owns its `:args` and `:output` options. Document such reserved
options rather than silently accepting values the wrapper ignores. Validate
application-specific fields before dispatch. Do not interpolate user-controlled
source fragments or use comma/pipe/line splitting as a general serialization
format. `Script.cmd/2` escapes literal string arguments when the small DSL fits.

## Preserve the execution contract

- Return `:ok`, `{:ok, value}`, or `{:error, %ExMacOSControl.Error{}}` consistently.
- State whether a result is an acknowledgement or independently observed state.
- Accept and honor a deadline and output bound through the facade.
- Do not retry sends or writes automatically; a timeout may follow a real change.
- For related mutations, use named composition effects and retain created IDs.
- If you acquire windows, files, or native references, define ownership and cleanup.
- Keep raw source, recipients, and private content out of telemetry by default.

Errors from the facade are already structured. Preserve them rather than
replacing them with a generic atom. Use an `Error` constructor for your own
validation/decoding failures and retain useful context without exposing content.

## Test the boundary

Use `ExMacOSControl.Adapter` with Mox and expect the exact callback arity.
Assert data transport, requested destination, decoding, and the failure path.
An arbitrary string returned by a mock proves no native app compatibility.

Add native compile/execution contracts when they test something mocks cannot,
then opt into live tests separately for actual app state changes. Native reads
may launch apps, so consider desktop effects even when no account data is written.
Keep external communication and personal-account mutation out of default tests.
The [testing guide](testing.md) covers repository tags and consumer mock setup.

## Templates

Repository templates are examples to copy and adapt:

- [App module](templates/app_module_template.ex)
- [Unit test](templates/app_module_test_template.exs)
- [Native integration test](templates/app_module_integration_test_template.exs)

Replace the placeholder namespace/bundle identity, then update docs and tests for
the actual operation. Unit templates use the repository's
`ExMacOSControl.AdapterMock`; consumer projects define their own mock as shown in
the testing guide. Integration templates remain explicitly skipped until adapted.

For a library contribution, place the module in `lib/ex_macos_control/`, unit
tests in `test/ex_macos_control/`, and native tests in `test/integration/`. Add its
module to ExDoc's group in `mix.exs` and update the
[capability reference](capabilities.md) with its limitations. Run formatting,
appropriate tests, strict docs generation, and the repository quality checks.
