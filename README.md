# ExMacosControl

An Elixir library for macOS automation via AppleScript and JavaScript for Automation (JXA).

ExMacosControl provides a simple, idiomatic Elixir interface for automating macOS using both AppleScript and JXA, with comprehensive error handling, platform detection, and robust testing infrastructure.

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

## Features

- **AppleScript Execution** - Run AppleScript code directly from Elixir
- **JavaScript for Automation (JXA)** - Execute JXA scripts with full support for:
  - Application automation
  - ObjC bridge
  - Arguments passing
  - System Events integration
- **Shortcuts Integration** - Execute macOS Shortcuts programmatically
- **Comprehensive Error Handling** - Structured error types with helpful remediation steps
- **Platform Detection** - Automatic macOS version and osascript availability checking
- **Robust Testing** - 100% test coverage with unit and integration tests
- **Type Safety** - Full Dialyzer type checking with zero warnings

## Quick Start

### AppleScript

```elixir
# Simple AppleScript execution
{:ok, result} = ExMacOSControl.run_applescript(~s(return "Hello, World!"))
# => {:ok, "Hello, World!"}

# Get application information
{:ok, name} = ExMacOSControl.run_applescript(~s(tell application "Finder" to return name))
# => {:ok, "Finder"}
```

### JavaScript for Automation (JXA)

```elixir
# Basic JXA
{:ok, result} = ExMacOSControl.run_javascript("(function() { return 'Hello from JXA!'; })()")
# => {:ok, "Hello from JXA!"}

# Application automation
{:ok, name} = ExMacOSControl.run_javascript("Application('Finder').name()")
# => {:ok, "Finder"}

# With arguments
script = "function run(argv) { return argv[0]; }"
{:ok, result} = ExMacOSControl.run_javascript(script, args: ["hello"])
# => {:ok, "hello"}

# System Events
script = """
var app = Application('System Events');
var processes = app.processes.whose({ name: 'Finder' });
processes.length.toString();
"""
{:ok, count} = ExMacOSControl.run_javascript(script)
# => {:ok, "1"}

# ObjC Bridge
script = """
ObjC.import('Foundation');
var str = $.NSString.alloc.initWithUTF8String('test');
str.js;
"""
{:ok, result} = ExMacOSControl.run_javascript(script)
# => {:ok, "test"}
```

### Shortcuts

```elixir
# Execute a Shortcut by name
ExMacOSControl.run_shortcut("My Shortcut")
# => :ok
```

## JXA vs AppleScript

### When to use JXA

**Use JXA when:**
- You're more comfortable with JavaScript than AppleScript
- You need to leverage JavaScript's functional programming features
- You want to use the ObjC bridge for direct Objective-C interaction
- You're building complex data transformations
- You prefer JavaScript's syntax and semantics

**Use AppleScript when:**
- You're working with legacy scripts or examples
- You need maximum compatibility (AppleScript is more widely documented)
- The automation task is simple and straightforward
- You're following existing AppleScript documentation

### Comparison Examples

**Getting application name:**

```elixir
# AppleScript
ExMacOSControl.run_applescript(~s(tell application "Finder" to return name))

# JXA
ExMacOSControl.run_javascript("Application('Finder').name()")
```

**Counting windows:**

```elixir
# AppleScript
ExMacOSControl.run_applescript(~s(tell application "Finder" to return count of windows))

# JXA
ExMacOSControl.run_javascript("Application('Finder').windows().length")
```

**With arguments:**

```elixir
# AppleScript
script = """
on run argv
  return item 1 of argv
end run
"""
ExMacOSControl.run_applescript(script)  # Note: AppleScript args not yet supported

# JXA
script = "function run(argv) { return argv[0]; }"
ExMacOSControl.run_javascript(script, args: ["hello"])
# => {:ok, "hello"}
```

## Error Handling

ExMacOSControl provides structured error handling with helpful remediation steps:

```elixir
case ExMacOSControl.run_javascript("invalid syntax {") do
  {:ok, result} ->
    IO.puts("Success: #{result}")

  {:error, {:exit_code, code, output}} ->
    IO.puts("Error (code #{code}): #{output}")
    # You can also use ExMacOSControl.Error.parse_osascript_error/2
    # for structured error information with remediation steps
end
```

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/ex_macos_control) or can be generated locally with [ExDoc](https://github.com/elixir-lang/ex_doc):

```bash
mix docs
```

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

