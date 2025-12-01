# ExMacOSControl
============

[![hex.pm version](https://img.shields.io/hexpm/v/ex_macos_control.svg)](https://hex.pm/packages/ex_macos_control)
[![hex.pm downloads](https://img.shields.io/hexpm/dt/ex_macos_control.svg)](https://hex.pm/packages/ex_macos_control)
[![hex.pm license](https://img.shields.io/hexpm/l/ex_macos_control.svg)](https://github.com/houllette/ex_macos_control/blob/main/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/houllette/ex_macos_control.svg)](https://github.com/houllette/ex_macos_control/commits/master)

An Elixir library for macOS automation via AppleScript and JavaScript for Automation (JXA).

## Features

- **AppleScript Execution**: Execute AppleScript code with full control
  - Timeout support for long-running scripts
  - Argument passing to scripts
  - Comprehensive error handling with detailed error messages
- **JavaScript for Automation (JXA)**: Execute JavaScript-based automation scripts
  - Full JXA support with timeout and argument passing
  - Access to ObjC bridge for Objective-C integration
- **Script File Execution**: Execute scripts from files with automatic language detection
  - Support for `.applescript`, `.scpt`, `.js`, and `.jxa` file extensions
  - Explicit language override option
  - All standard options (timeout, arguments) supported
- **macOS Shortcuts**: Run Shortcuts on macOS with input parameter support
  - Pass strings, numbers, maps, and lists as input
  - List available shortcuts
- **System Events**: Process management and application control
  - List running processes
  - Launch, activate, and quit applications
  - Check if applications are running
- **Safari Automation**: Control Safari browser programmatically
  - Open URLs in new tabs
  - Get current tab URL
  - Execute JavaScript in tabs
  - List all tab URLs
  - Close tabs by index
- **Mail Automation**: Control Mail.app for email operations
  - Send emails with CC and BCC support
  - Get unread message counts
  - Search mailboxes by subject
- **Messages Automation**: Control Messages.app for iMessage and SMS
  - Send iMessages and SMS programmatically
  - Retrieve recent messages from chats
  - List all active chats with unread counts
  - Get total unread message count
- **Platform Detection**: Automatic macOS platform detection and validation
- **Test-Friendly**: Adapter pattern with Mox support for easy testing

## Quick Start

### AppleScript Execution

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
```

### JavaScript for Automation (JXA)

```elixir
# Basic JXA execution
{:ok, result} = ExMacOSControl.run_javascript("(function() { return 'Hello from JXA!'; })()")
# => {:ok, "Hello from JXA!"}

# Application automation
{:ok, name} = ExMacOSControl.run_javascript("Application('Finder').name()")
# => {:ok, "Finder"}

# With arguments
script = "function run(argv) { return argv[0]; }"
{:ok, result} = ExMacOSControl.run_javascript(script, args: ["test"])
# => {:ok, "test"}
```

### Script File Execution

```elixir
# Execute AppleScript file (auto-detected from .applescript extension)
{:ok, result} = ExMacOSControl.run_script_file("/path/to/script.applescript")

# Execute JavaScript file (auto-detected from .js extension)
{:ok, result} = ExMacOSControl.run_script_file("/path/to/script.js")

# With arguments
{:ok, result} = ExMacOSControl.run_script_file(
  "/path/to/script.applescript",
  args: ["arg1", "arg2"]
)

# With timeout
{:ok, result} = ExMacOSControl.run_script_file(
  "/path/to/script.js",
  timeout: 5000
)

# Override language detection for files with non-standard extensions
{:ok, result} = ExMacOSControl.run_script_file(
  "/path/to/script.txt",
  language: :applescript
)

# All options combined
{:ok, result} = ExMacOSControl.run_script_file(
  "/path/to/script.scpt",
  language: :applescript,
  args: ["test"],
  timeout: 10_000
)
```

### macOS Shortcuts

```elixir
# Run macOS Shortcuts
:ok = ExMacOSControl.run_shortcut("My Shortcut Name")

# Run Shortcut with string input
{:ok, result} = ExMacOSControl.run_shortcut("Process Text", input: "Hello, World!")

# Run Shortcut with map input (serialized as JSON)
{:ok, result} = ExMacOSControl.run_shortcut("Process Data", input: %{
  "name" => "John",
  "age" => 30
})

# Run Shortcut with list input
{:ok, result} = ExMacOSControl.run_shortcut("Process Items", input: ["item1", "item2", "item3"])

# List available shortcuts
{:ok, shortcuts} = ExMacOSControl.list_shortcuts()
# => {:ok, ["Shortcut 1", "Shortcut 2", "My Shortcut"]}

# Check if a shortcut exists before running it
case ExMacOSControl.list_shortcuts() do
  {:ok, shortcuts} ->
    if "My Shortcut" in shortcuts do
      ExMacOSControl.run_shortcut("My Shortcut")
    end
  {:error, reason} ->
    {:error, reason}
end
```

### System Events - Process Management

Control running applications on macOS:

```elixir
# List all running apps
{:ok, processes} = ExMacOSControl.SystemEvents.list_processes()
# => {:ok, ["Safari", "Finder", "Terminal", "Mail", ...]}

# Check if an app is running
{:ok, true} = ExMacOSControl.SystemEvents.process_exists?("Safari")
# => {:ok, true}

{:ok, false} = ExMacOSControl.SystemEvents.process_exists?("NonexistentApp")
# => {:ok, false}

# Launch an app
:ok = ExMacOSControl.SystemEvents.launch_application("Calculator")
# => :ok

# Activate (bring to front) an app - same as launch
:ok = ExMacOSControl.SystemEvents.activate_application("Safari")
# => :ok

# Quit an app gracefully
:ok = ExMacOSControl.SystemEvents.quit_application("Calculator")
# => :ok

# Full workflow example
app_name = "Calculator"

# Check if it's running
case ExMacOSControl.SystemEvents.process_exists?(app_name) do
  {:ok, false} ->
    # Not running, launch it
    ExMacOSControl.SystemEvents.launch_application(app_name)
  {:ok, true} ->
    # Already running, bring to front
    ExMacOSControl.SystemEvents.activate_application(app_name)
end
```

**Note**: This module requires automation permission for System Events. macOS may prompt for permission on first use.

### System Events - UI Automation

Control application UI elements programmatically (requires Accessibility permission):

```elixir
# Click menu items
:ok = ExMacOSControl.SystemEvents.click_menu_item("Safari", "File", "New Tab")
# => :ok

:ok = ExMacOSControl.SystemEvents.click_menu_item("TextEdit", "Format", "Make Plain Text")
# => :ok

# Send keystrokes
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "a")
# => :ok

# Send keystrokes with modifiers
:ok = ExMacOSControl.SystemEvents.press_key("Safari", "t", using: [:command])
# => :ok

# Multiple modifiers (Command+Shift+Q)
:ok = ExMacOSControl.SystemEvents.press_key("Safari", "q", using: [:command, :shift])
# => :ok

# Get window properties
{:ok, props} = ExMacOSControl.SystemEvents.get_window_properties("Safari")
# => {:ok, %{position: [100, 100], size: [800, 600], title: "Google"}}

# Application with no windows returns nil
{:ok, nil} = ExMacOSControl.SystemEvents.get_window_properties("AppWithNoWindows")
# => {:ok, nil}

# Set window bounds
:ok = ExMacOSControl.SystemEvents.set_window_bounds("Calculator",
  position: [100, 100],
  size: [400, 500]
)
# => :ok

# Complete UI automation workflow
# 1. Launch app
:ok = ExMacOSControl.SystemEvents.launch_application("TextEdit")

# 2. Create new document (Command+N)
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "n", using: [:command])

# 3. Type some text
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "H")
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "e")
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "l")
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "l")
:ok = ExMacOSControl.SystemEvents.press_key("TextEdit", "o")

# 4. Get window properties
{:ok, props} = ExMacOSControl.SystemEvents.get_window_properties("TextEdit")

# 5. Resize window
:ok = ExMacOSControl.SystemEvents.set_window_bounds("TextEdit",
  position: [0, 0],
  size: [1000, 800]
)
```

**Important**: UI automation requires Accessibility permission. Enable in:

System Settings → Privacy & Security → Accessibility

(Or System Preferences → Security & Privacy → Privacy → Accessibility on older macOS)

Add Terminal (or your Elixir runtime) to the list of allowed applications.

**Available Modifiers**: `:command`, `:control`, `:option`, `:shift`

### System Events - File Operations

Convenient helpers for file operations using Finder:

```elixir
# Reveal file in Finder (opens window and selects the file)
:ok = ExMacOSControl.SystemEvents.reveal_in_finder("/Users/me/Documents/report.pdf")
# => :ok

# Get currently selected items in Finder
{:ok, selected} = ExMacOSControl.SystemEvents.get_selected_finder_items()
# => {:ok, ["/Users/me/file1.txt", "/Users/me/file2.txt"]}

# Empty selection returns empty list
{:ok, []} = ExMacOSControl.SystemEvents.get_selected_finder_items()
# => {:ok, []}

# Move file to trash
:ok = ExMacOSControl.SystemEvents.trash_file("/Users/me/old_file.txt")
# => :ok

# Complete workflow example
# 1. Create a test file
File.write!("/tmp/test.txt", "test content")

# 2. Reveal it in Finder
:ok = ExMacOSControl.SystemEvents.reveal_in_finder("/tmp/test.txt")

# 3. Get selected items (the file we just revealed should be selected)
{:ok, selected} = ExMacOSControl.SystemEvents.get_selected_finder_items()
# => {:ok, ["/tmp/test.txt"]}

# 4. Move to trash when done
:ok = ExMacOSControl.SystemEvents.trash_file("/tmp/test.txt")

# Error handling
{:error, error} = ExMacOSControl.SystemEvents.reveal_in_finder("/nonexistent/file")
# => {:error, %ExMacOSControl.Error{type: :not_found, ...}}

{:error, error} = ExMacOSControl.SystemEvents.trash_file("relative/path")
# => {:error, %ExMacOSControl.Error{type: :execution_error, message: "Path must be absolute", ...}}
```

**Important Notes**:
- File operation paths must be absolute (start with `/`)
- `reveal_in_finder/1` will open a Finder window and bring Finder to the front
- `trash_file/1` moves items to Trash (not permanent deletion), but should still be used with caution
- File operations require Finder access (usually granted automatically)

### Finder Automation

Control the macOS Finder application:

```elixir
# Get selected files in Finder
{:ok, files} = ExMacOSControl.Finder.get_selection()
# => {:ok, ["/Users/me/file.txt", "/Users/me/file2.txt"]}

# Empty selection returns empty list
{:ok, []} = ExMacOSControl.Finder.get_selection()
# => {:ok, []}

# Open Finder at a location
:ok = ExMacOSControl.Finder.open_location("/Users/me/Documents")
# => :ok

# Create new Finder window
:ok = ExMacOSControl.Finder.new_window("/Applications")
# => :ok

# Get current folder path
{:ok, path} = ExMacOSControl.Finder.get_current_folder()
# => {:ok, "/Users/me/Documents"}

# Returns empty string if no Finder windows open
{:ok, ""} = ExMacOSControl.Finder.get_current_folder()
# => {:ok, ""}

# Set view mode
:ok = ExMacOSControl.Finder.set_view(:icon)    # Icon view
:ok = ExMacOSControl.Finder.set_view(:list)    # List view
:ok = ExMacOSControl.Finder.set_view(:column)  # Column view
:ok = ExMacOSControl.Finder.set_view(:gallery) # Gallery view

# Error handling
{:error, error} = ExMacOSControl.Finder.open_location("/nonexistent/path")
# => {:error, %ExMacOSControl.Error{...}}

{:error, error} = ExMacOSControl.Finder.set_view(:invalid)
# => {:error, %ExMacOSControl.Error{type: :execution_error, message: "Invalid view mode", ...}}
```

**Note**: This module requires automation permission for Finder. macOS may prompt for permission on first use.

### Safari Automation

Control Safari browser programmatically:

```elixir
# Open URL in new tab
:ok = ExMacOSControl.Safari.open_url("https://example.com")
# => :ok

# Get current tab URL
{:ok, url} = ExMacOSControl.Safari.get_current_url()
# => {:ok, "https://example.com"}

# Execute JavaScript in current tab
{:ok, title} = ExMacOSControl.Safari.execute_javascript("document.title")
# => {:ok, "Example Domain"}

{:ok, result} = ExMacOSControl.Safari.execute_javascript("2 + 2")
# => {:ok, "4"}

# List all tab URLs across all windows
{:ok, urls} = ExMacOSControl.Safari.list_tabs()
# => {:ok, ["https://example.com", "https://google.com", "https://github.com"]}

# Close a tab by index (1-based)
:ok = ExMacOSControl.Safari.close_tab(2)
# => :ok

# Complete workflow example
# Open a new tab
:ok = ExMacOSControl.Safari.open_url("https://example.com")

# Wait for page to load, then execute JavaScript
Process.sleep(2000)
{:ok, title} = ExMacOSControl.Safari.execute_javascript("document.title")

# List all tabs
{:ok, tabs} = ExMacOSControl.Safari.list_tabs()
IO.inspect(tabs, label: "Open tabs")

# Close the first tab
:ok = ExMacOSControl.Safari.close_tab(1)
```

**Note**: This module requires automation permission for Safari. Tab indices are 1-based (1 is the first tab).

### Mail Automation

Control Mail.app programmatically:

```elixir
# Send an email
:ok = ExMacOSControl.Mail.send_email(
  to: "recipient@example.com",
  subject: "Automated Report",
  body: "Here is your daily report."
)

# Send with CC and BCC
:ok = ExMacOSControl.Mail.send_email(
  to: "team@example.com",
  subject: "Team Update",
  body: "Weekly status update.",
  cc: ["manager@example.com"],
  bcc: ["archive@example.com"]
)

# Get unread count (inbox)
{:ok, count} = ExMacOSControl.Mail.get_unread_count()
# => {:ok, 42}

# Get unread count (specific mailbox)
{:ok, count} = ExMacOSControl.Mail.get_unread_count("Work")
# => {:ok, 5}

# Search mailbox
{:ok, messages} = ExMacOSControl.Mail.search_mailbox("INBOX", "invoice")
# => {:ok, [%{subject: "Invoice #123", from: "billing@example.com", date: "2025-01-15"}, ...]}

# Complete workflow example
# Check unread count
{:ok, unread} = ExMacOSControl.Mail.get_unread_count()
IO.puts("You have #{unread} unread messages")

# Search for important messages
{:ok, messages} = ExMacOSControl.Mail.search_mailbox("INBOX", "urgent")

# Process search results
Enum.each(messages, fn msg ->
  IO.puts("From: #{msg.from}")
  IO.puts("Subject: #{msg.subject}")
  IO.puts("Date: #{msg.date}")
  IO.puts("---")
end)

# Send notification email if urgent messages found
if length(messages) > 0 do
  :ok = ExMacOSControl.Mail.send_email(
    to: "admin@example.com",
    subject: "Urgent Messages Alert",
    body: "Found #{length(messages)} urgent messages requiring attention."
  )
end
```

**Important Safety Notes**:
- Mail automation requires Mail.app to be configured with an email account
- `send_email/1` sends emails immediately - there is no undo
- Use with caution in production environments
- Consider adding confirmation prompts before sending emails
- Test with safe recipient addresses first

### Messages Automation

⚠️  **Safety Warning:** Message sending functions will send real messages!

Control the Messages app programmatically:

```elixir
# Send a message (iMessage or SMS)
:ok = ExMacOSControl.Messages.send_message("+1234567890", "Hello!")

# Send to a contact name
:ok = ExMacOSControl.Messages.send_message("John Doe", "Meeting at 3pm?")

# Force SMS (not iMessage)
:ok = ExMacOSControl.Messages.send_message(
  "+1234567890",
  "Hello!",
  service: :sms
)

# Force iMessage
:ok = ExMacOSControl.Messages.send_message(
  "john@icloud.com",
  "Hello!",
  service: :imessage
)

# Get recent messages from a chat
{:ok, messages} = ExMacOSControl.Messages.get_recent_messages("+1234567890")
# => {:ok, [
#   %{from: "+1234567890", text: "Hello!", timestamp: "Monday, January 15, 2024 at 2:30:00 PM"},
#   %{from: "+1234567890", text: "How are you?", timestamp: "Monday, January 15, 2024 at 2:31:00 PM"}
# ]}

# List all chats
{:ok, chats} = ExMacOSControl.Messages.list_chats()
# => {:ok, [
#   %{id: "iMessage;+E:+1234567890", name: "+1234567890", unread: 2},
#   %{id: "iMessage;-;+E:john@icloud.com", name: "John Doe", unread: 0}
# ]}

# Get total unread count
{:ok, count} = ExMacOSControl.Messages.get_unread_count()
# => {:ok, 5}

# Complete workflow example
# Check for unread messages
{:ok, unread} = ExMacOSControl.Messages.get_unread_count()

if unread > 0 do
  # List all chats to see who has unread messages
  {:ok, chats} = ExMacOSControl.Messages.list_chats()

  # Find chats with unread messages
  unread_chats = Enum.filter(chats, fn chat -> chat.unread > 0 end)

  # Get recent messages from the first unread chat
  if length(unread_chats) > 0 do
    first_chat = hd(unread_chats)
    {:ok, messages} = ExMacOSControl.Messages.get_recent_messages(first_chat.name)

    # Process the messages
    Enum.each(messages, fn msg ->
      IO.puts("From: #{msg.from}")
      IO.puts("Text: #{msg.text}")
      IO.puts("Time: #{msg.timestamp}")
      IO.puts("---")
    end)
  end
end
```

**Required Permissions:**
- Automation permission for Terminal/your app to control Messages
- Full Disk Access (for reading message history)

**Important Safety Notes**:
- `send_message/2` and `send_message/3` send real messages immediately - there is no undo
- Messages are sent via iMessage by default, falling back to SMS if iMessage is not available
- Use the `:service` option to force SMS or iMessage
- Be extremely careful when using in automated scripts
- Consider adding confirmation prompts before sending messages
- Test with your own phone number first

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
