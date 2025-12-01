# Getting Started with ExMacOSControl

Welcome to ExMacOSControl! This guide will help you get up and running with macOS automation using Elixir.

## What You'll Learn

- Installing and verifying ExMacOSControl
- Understanding AppleScript vs JavaScript for Automation (JXA)
- Setting up required macOS permissions
- Running your first automation
- Common gotchas and troubleshooting
- Next steps for building real automation

## Prerequisites

Before you begin, ensure you have:

- **macOS 10.15 (Catalina) or later**
- **Elixir 1.19 or later** - [Install Elixir](https://elixir-lang.org/install.html)
- **Basic Elixir knowledge** - Familiarity with pattern matching, modules, and functions
- **Terminal access** - You'll be running commands from the terminal

## Installation

### 1. Add Dependency

Add ExMacOSControl to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_macos_control, "~> 0.1.0"}
  ]
end
```

### 2. Fetch Dependencies

```bash
mix deps.get
```

### 3. Verify Installation

Start an IEx session and try a simple command:

```elixir
iex -S mix

iex> ExMacOSControl.run_applescript(~s(return "Hello from macOS!"))
{:ok, "Hello from macOS!"}
```

If you see `{:ok, "Hello from macOS!"}`, congratulations! ExMacOSControl is installed and working.

## Your First Automation

Let's build a simple automation that:
1. Checks if Safari is running
2. Launches it if needed
3. Opens a URL
4. Extracts the page title

### Step 1: Check if Safari is Running

```elixir
alias ExMacOSControl.SystemEvents

{:ok, is_running} = SystemEvents.process_exists?("Safari")

if is_running do
  IO.puts("Safari is already running")
else
  IO.puts("Safari is not running, launching...")
  SystemEvents.launch_application("Safari")
  Process.sleep(1000)  # Wait for Safari to launch
end
```

### Step 2: Open a URL

```elixir
alias ExMacOSControl.Safari

:ok = Safari.open_url("https://example.com")
Process.sleep(2000)  # Wait for page to load
```

### Step 3: Extract Page Title

```elixir
{:ok, title} = Safari.execute_javascript("document.title")
IO.puts("Page title: #{title}")
# => Page title: Example Domain
```

### Complete Script

Here's the complete automation in one script:

```elixir
defmodule MyFirstAutomation do
  alias ExMacOSControl.{SystemEvents, Safari}

  def run do
    # Check if Safari is running
    {:ok, is_running} = SystemEvents.process_exists?("Safari")

    unless is_running do
      IO.puts("Launching Safari...")
      SystemEvents.launch_application("Safari")
      Process.sleep(1000)
    end

    # Open URL
    IO.puts("Opening https://example.com...")
    :ok = Safari.open_url("https://example.com")
    Process.sleep(2000)

    # Get page title
    {:ok, title} = Safari.execute_javascript("document.title")
    IO.puts("Page title: #{title}")

    {:ok, title}
  end
end

# Run it
MyFirstAutomation.run()
```

## Understanding AppleScript vs JXA

ExMacOSControl supports two macOS automation languages:

### AppleScript

**Pros:**
- Native macOS scripting language
- Excellent app support
- Extensive documentation and community resources
- Natural language-like syntax

**Cons:**
- Quirky syntax
- Less familiar to developers coming from other languages

**Example:**

```elixir
script = """
tell application "Finder"
  get name of every file of desktop
end tell
"""

{:ok, files} = ExMacOSControl.run_applescript(script)
```

### JavaScript for Automation (JXA)

**Pros:**
- Uses JavaScript syntax (familiar to web developers)
- Access to Objective-C bridge
- More programmatic feel

**Cons:**
- Less documentation than AppleScript
- Some apps have better AppleScript support
- Slightly less community resources

**Example:**

```elixir
script = """
var finder = Application('Finder')
finder.desktop.files.name()
"""

{:ok, files} = ExMacOSControl.run_javascript(script)
```

### Which Should You Use?

- **Use AppleScript when:**
  - Working with apps that have excellent AppleScript dictionaries
  - Following existing tutorials/documentation
  - You find natural language syntax easier

- **Use JXA when:**
  - You're more comfortable with JavaScript
  - You need ObjC bridge features
  - You want more programmatic control

**Good news:** You can mix both! Use whatever works best for each task.

## macOS Permissions

macOS requires explicit permissions for automation. ExMacOSControl makes it easy to check and request permissions.

### Understanding Permission Types

1. **Accessibility Permission**
   - Required for: UI automation (menu clicks, keystrokes)
   - Granted in: System Settings → Privacy & Security → Accessibility

2. **Automation Permission**
   - Required for: Controlling specific apps (Safari, Finder, Mail, etc.)
   - Granted per-app when first accessed (macOS will prompt)

3. **Full Disk Access** (rarely needed)
   - Required for: Reading Messages database
   - Granted in: System Settings → Privacy & Security → Full Disk Access

### Checking Permissions

```elixir
alias ExMacOSControl.Permissions

# Check accessibility permission
case Permissions.check_accessibility() do
  {:ok, :granted} ->
    IO.puts("✅ Accessibility permission granted")
  {:ok, :not_granted} ->
    IO.puts("❌ Accessibility permission not granted")
    Permissions.show_accessibility_help()
end

# Check automation permission for Safari
case Permissions.check_automation("Safari") do
  {:ok, :granted} ->
    IO.puts("✅ Safari automation granted")
  {:ok, :not_granted} ->
    IO.puts("❌ Safari automation not granted")
    Permissions.show_automation_help("Safari")
end

# Get overview of all permissions
statuses = Permissions.check_all()
IO.inspect(statuses)
```

### Pre-flight Check Pattern

It's good practice to check permissions before running automation:

```elixir
defmodule SafeAutomation do
  alias ExMacOSControl.{Permissions, Safari}

  def run do
    # Pre-flight check
    with {:ok, :granted} <- Permissions.check_automation("Safari") do
      # Run automation
      Safari.open_url("https://example.com")
    else
      {:ok, :not_granted} ->
        Permissions.show_automation_help("Safari")
        {:error, :permission_denied}

      error ->
        error
    end
  end
end
```

### Granting Permissions

ExMacOSControl can open System Settings to the right location:

```elixir
# Open accessibility preferences
Permissions.open_accessibility_preferences()

# Open automation preferences
Permissions.open_automation_preferences()
```

macOS 13+ will open System Settings directly to the Privacy & Security pane.

## Common Gotchas

### 1. Scripts Need Time to Complete

macOS automation isn't instant. Always account for timing:

```elixir
# ❌ BAD: No time for page to load
Safari.open_url("https://example.com")
Safari.execute_javascript("document.title")  # Might get previous page!

# ✅ GOOD: Wait for page load
Safari.open_url("https://example.com")
Process.sleep(2000)
{:ok, title} = Safari.execute_javascript("document.title")
```

### 2. Timeout Errors

If scripts take too long, they'll timeout. Adjust the timeout:

```elixir
# Default timeout is usually 30 seconds
{:ok, result} = ExMacOSControl.run_applescript(script)

# Custom timeout (60 seconds)
{:ok, result} = ExMacOSControl.run_applescript(script, timeout: 60_000)
```

### 3. App Names Are Case-Sensitive

```elixir
SystemEvents.process_exists?("safari")   # ❌ Won't work
SystemEvents.process_exists?("Safari")   # ✅ Correct
```

### 4. Quote Escaping in AppleScript

AppleScript strings need proper quote escaping:

```elixir
# ❌ BAD: Breaks AppleScript syntax
script = ~s(display dialog "Hello "World"")

# ✅ GOOD: Escape quotes
script = ~s(display dialog "Hello \\"World\\"")

# ✅ BETTER: Use triple-quoted string
script = """
display dialog "Hello \\"World\\""
"""
```

### 5. Permission Prompts Block Execution

When macOS prompts for permission, your script will pause:

```elixir
# First time running - macOS shows permission dialog
# Script waits for user response
Safari.open_url("https://example.com")
```

**Solution:** Check permissions first or inform users to expect prompts.

### 6. Apps Must Be Installed

Trying to control non-existent apps will fail:

```elixir
# If Safari isn't installed
{:error, %{type: :not_found}} = Safari.open_url("https://example.com")
```

**Solution:** Check if processes exist before controlling them.

## Error Handling

ExMacOSControl uses structured errors. Always handle them:

```elixir
case ExMacOSControl.run_applescript(script) do
  {:ok, result} ->
    # Success
    process_result(result)

  {:error, %{type: :timeout}} ->
    # Script took too long
    Logger.warn("Script timed out")
    {:error, :timeout}

  {:error, %{type: :permission_denied}} ->
    # Permission issue
    Permissions.show_accessibility_help()
    {:error, :needs_permission}

  {:error, %{type: :syntax_error, message: msg}} ->
    # AppleScript syntax error
    Logger.error("Syntax error: #{msg}")
    {:error, :syntax}

  {:error, error} ->
    # Other error
    Logger.error("Automation failed: #{inspect(error)}")
    {:error, :unknown}
end
```

## Best Practices

### 1. Use Aliases for Readability

```elixir
# Instead of repeating ExMacOSControl everywhere
alias ExMacOSControl, as: Mac
alias ExMacOSControl.{Safari, Finder, Mail}

Mac.run_applescript(script)
Safari.open_url(url)
```

### 2. Create Helper Modules

Wrap common patterns in functions:

```elixir
defmodule BrowserHelper do
  alias ExMacOSControl.Safari

  def navigate_and_extract(url, selector) do
    with :ok <- Safari.open_url(url),
         :ok <- Process.sleep(2000),
         {:ok, content} <- Safari.execute_javascript("""
           document.querySelector('#{selector}').textContent
         """) do
      {:ok, String.trim(content)}
    end
  end
end
```

### 3. Use Retry for Reliability

```elixir
alias ExMacOSControl.Retry

# Automatically retry on timeout
{:ok, result} = Retry.with_retry(fn ->
  Safari.execute_javascript("document.title")
end, max_attempts: 3)
```

### 4. Log Important Operations

```elixir
require Logger

def automate do
  Logger.info("Starting automation...")

  case run_automation() do
    {:ok, result} ->
      Logger.info("Automation succeeded: #{result}")
      {:ok, result}

    {:error, error} ->
      Logger.error("Automation failed: #{inspect(error)}")
      {:error, error}
  end
end
```

## Troubleshooting

### "Operation not permitted" Error

**Cause:** Missing permissions

**Solution:** Check and grant required permissions:

```elixir
Permissions.check_all()
Permissions.open_accessibility_preferences()
```

### "Application isn't running" Error

**Cause:** App isn't launched

**Solution:** Launch app first:

```elixir
SystemEvents.launch_application("Safari")
Process.sleep(1000)
```

### Timeout Errors

**Cause:** Script takes longer than timeout allows

**Solution:** Increase timeout:

```elixir
ExMacOSControl.run_applescript(script, timeout: 60_000)  # 60 seconds
```

### "Can't get window 1" Error

**Cause:** App has no windows open

**Solution:** Check window existence first:

```elixir
{:ok, window_props} = SystemEvents.get_window_properties("Safari")

if is_nil(window_props) do
  # No windows, handle accordingly
  Safari.open_url("https://example.com")  # Opens new window
end
```

## Next Steps

Now that you're comfortable with the basics, explore:

1. **[Common Patterns](common_patterns.html)** - Real-world automation workflows
2. **[DSL vs Raw AppleScript](dsl_vs_raw.html)** - When to use the Script DSL
3. **[Performance Guide](../performance.html)** - Optimizing your automation
4. **[Advanced Usage](advanced_usage.html)** - Telemetry, custom adapters, and more

## Quick Reference

### Most Common Functions

```elixir
# AppleScript
ExMacOSControl.run_applescript(script, timeout: 30_000)

# Process Management
SystemEvents.process_exists?("Safari")
SystemEvents.launch_application("Safari")
SystemEvents.quit_application("Safari")

# Safari
Safari.open_url("https://example.com")
Safari.get_current_url()
Safari.execute_javascript("document.title")

# Finder
Finder.get_selection()
Finder.open_location("/path/to/folder")

# Mail
Mail.send_email(to: "user@example.com", subject: "Test", body: "Hello")
Mail.get_unread_count()

# Permissions
Permissions.check_automation("Safari")
Permissions.show_accessibility_help()
```

## Getting Help

- **Documentation**: [https://hexdocs.pm/ex_macos_control](https://hexdocs.pm/ex_macos_control)
- **GitHub Issues**: [Report bugs or request features](https://github.com/houllette/ex_macos_control/issues)
- **GitHub Discussions**: [Ask questions](https://github.com/houllette/ex_macos_control/discussions)

Happy automating! 🚀
