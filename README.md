# ExMacosControl

An Elixir library for macOS automation via AppleScript and JavaScript for Automation (JXA).

## Features

- **AppleScript Execution**: Execute AppleScript code with full control
  - Timeout support for long-running scripts
  - Argument passing to scripts
  - Comprehensive error handling with detailed error messages
- **macOS Shortcuts**: Run Shortcuts on macOS
- **Platform Detection**: Automatic macOS platform detection and validation
- **Test-Friendly**: Adapter pattern with Mox support for easy testing

## Quick Start

```elixir
# Basic AppleScript execution
{:ok, result} = ExMacOSControl.run_applescript(~s(return "Hello, World!"))
# => {:ok, "Hello, World!"}

# With timeout (5 seconds)
{:ok, result} = ExMacOSControl.run_applescript("delay 2\nreturn \"done\"", timeout: 5000)
# => {:ok, "done"}

# With arguments
script = """
on run argv
  set name to item 1 of argv
  return "Hello, " & name
end run
"""
{:ok, result} = ExMacOSControl.run_applescript(script, args: ["World"])
# => {:ok, "Hello, World"}

# Combined options
{:ok, result} = ExMacOSControl.run_applescript(script, timeout: 5000, args: ["Elixir"])
# => {:ok, "Hello, Elixir"}

# Run macOS Shortcuts
:ok = ExMacOSControl.run_shortcut("My Shortcut Name")
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_macos_control` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_macos_control, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ex_macos_control>.

## Development

### Setup

```bash
# Install dependencies
mix deps.get

# Run tests
mix test
```

### Code Quality

This project uses strict code quality standards. All contributions must pass the following checks:

#### Run All Quality Checks

```bash
# Run all quality checks (format, credo, dialyzer)
mix quality
```

#### Individual Checks

```bash
# Format code
mix format

# Check code formatting
mix format.check

# Run Credo static analysis (strict mode)
mix credo --strict

# Run Dialyzer type checking
mix dialyzer

# Run tests
mix test
```

### Quality Standards

- **Formatting**: All code must be formatted with `mix format` (120 character line length)
- **Credo**: All code must pass strict Credo checks with zero warnings
- **Dialyzer**: All code must pass Dialyzer type checking with zero warnings
- **Tests**: Aim for 100% test coverage on new code (minimum 90%)
- **Documentation**: All public functions must have `@doc`, `@spec`, and `@moduledoc`

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed development guidelines and standards.

