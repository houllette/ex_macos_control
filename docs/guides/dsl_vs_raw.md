# Script DSL and raw scripts

Start with an app module or [workflow recipe](workflows.md) when it covers your
operation. For an app command outside those APIs, use a raw script or the small
`ExMacOSControl.Script` string-building DSL.

The DSL builds AppleScript source. It does not execute it, validate an app's
dictionary, or provide type safety for native operations.

## Build a simple tell block

```elixir
alias ExMacOSControl.Script

script = Script.tell("Finder", ["activate"])
ExMacOSControl.run_applescript(script, timeout: 5_000)
```

The public builders are `tell/2`, `tell_obj/3`, and `cmd/2`. There is no `cmd/3`
or DSL builder for control flow, variables, or handlers. Commands inside a tell
block are strings, so raw AppleScript logic can still appear inside one.

```elixir
Script.tell("System Events", [
  Script.tell_obj("process", "Finder", [
    Script.cmd("set position of window 1 to", [100, 100])
  ])
])
```

`cmd/2` quotes string arguments and escapes backslashes and double quotes.
Numeric lists become AppleScript lists such as `{100, 100}`. Other lists become
space-separated arguments, not a general AppleScript list literal. The command
text and `tell_obj/3` object type are trusted source; they are not escaped input.

## Pass data as arguments

For values supplied at runtime, use an argument handler instead of interpolating
unescaped values into source:

```elixir
script = """
on run argv
  return "Hello, " & item 1 of argv
end run
"""

ExMacOSControl.run_applescript(script, args: ["A name with \"quotes\""], timeout: 5_000)
```

JXA uses the same transport:

```elixir
script = """
function run(argv) {
  var input = JSON.parse(argv[0]);
  return JSON.stringify({title: input.title, length: input.title.length});
}
"""

ExMacOSControl.run_javascript(script,
  args: [Jason.encode!(%{title: "A title"})], output: :json, timeout: 5_000
)
```

Raw results are text unless another output mode is requested. Splitting a native
list on commas or lines can corrupt values containing those characters. For
structured output, explicitly return JSON and decode it.

## Use raw control flow

```elixir
script = """
tell application "Finder"
  set fileCount to count of files of desktop
  if fileCount > 10 then
    return "More than ten desktop files"
  else
    return "Ten or fewer desktop files"
  end if
end tell
"""

ExMacOSControl.run_applescript(script, timeout: 5_000)
```

Raw scripts are also appropriate for existing working AppleScript, app-specific
handlers, or JXA's Objective-C bridge. The library does not make every native API
available or compatible just because a script can refer to it.

## Execute and validate files

```elixir
ExMacOSControl.run_script_file("tmp/example.applescript", args: ["input"], timeout: 5_000)
ExMacOSControl.run_script_file("tmp/example.jxa", timeout: 5_000)
ExMacOSControl.run_script_file("tmp/example.scpt", timeout: 5_000)
```

`.applescript` selects AppleScript; `.js`/`.jxa` selects JavaScript.
Compiled `.scpt` files and `.scptd` bundles retain their native language.
Use `language:` for a nonstandard extension or an explicit language selection.
These examples require files you have created; the library does not ship them.

```elixir
alias ExMacOSControl.Script

:ok = Script.validate(~s(return "valid"), timeout: 5_000)
:ok = Script.compile(~s(return "compiled"), "tmp/new-script.scpt", timeout: 5_000)
{:ok, source} = Script.decompile("tmp/new-script.scpt", timeout: 5_000)
```

Compilation requires a new destination and uses `osacompile`. Validation compiles
to an owned temporary file and removes it; it does not execute the script or
prove that the target app supports the command at runtime. Decompilation uses
`osadecompile`. Treat source and compiled scripts as trusted code.

## Extend a wrapper

Use Script Editor's dictionary browser or `ExMacOSControl.Capabilities` to inspect
an app's declared terminology. A dictionary declaration is not a live
qualification result. Once an operation is useful repeatedly, wrap it in a small
module that preserves options and tagged errors; see
[creating app modules](../creating_app_modules.md).
