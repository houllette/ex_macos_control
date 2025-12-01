# Creating New App Modules for ExMacOSControl

A comprehensive guide to creating macOS app automation modules.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Step-by-Step Guide](#step-by-step-guide)
5. [Common Patterns](#common-patterns)
6. [Testing Strategies](#testing-strategies)
7. [Best Practices](#best-practices)
8. [Examples](#examples)
9. [Troubleshooting](#troubleshooting)
10. [Contributing](#contributing)

---

## Overview

### What Makes a Good App Module

A good app module should:
- **Solve real use cases**: Focus on common automation tasks
- **Be well-tested**: High unit test coverage plus integration tests
- **Be safe**: Clear warnings for destructive operations
- **Be documented**: Examples, specs, and clear error messages
- **Follow patterns**: Consistent with existing modules

### When to Create a New Module

Create a dedicated module when:
- The app has 3+ commonly used automation operations
- You need type-safe, documented APIs
- You want to abstract away AppleScript complexity
- The app has complex scripting requirements

Use `ExMacOSControl.run_applescript/1` directly for:
- One-off automation tasks
- Simple, app-specific workflows
- Exploratory scripting

### Module Organization

All app modules follow this structure:

```
lib/ex_macos_control/
  app_name.ex              # Main module

test/ex_macos_control/
  app_name_test.exs        # Unit tests

test/integration/
  app_name_integration_test.exs  # Integration tests (often skipped)

README.md                   # Updated with examples
```

---

## Prerequisites

### Required Knowledge

- **Elixir basics**: Functions, pattern matching, error handling
- **AppleScript fundamentals**: tell blocks, properties, commands
- **macOS automation concepts**: Scripting dictionaries, permissions

### Required Tools

- macOS (Ventura or later recommended)
- Elixir 1.14+ and Erlang/OTP 25+
- Script Editor (built into macOS)
- This project cloned and dependencies installed

### Permissions Setup

You'll need to grant automation permissions to your terminal or IDE:
- System Preferences > Privacy & Security > Automation
- Add Terminal or your IDE
- Grant access to the target app

---

## Quick Start

### 1. Explore the App's Scripting Dictionary

Open Script Editor (Applications > Utilities > Script Editor):

```
File > Open Dictionary... > [Select your app]
```

This shows:
- Available commands
- Properties you can access
- Expected data types
- Example usage

### 2. Prototype in Script Editor

Test commands interactively:

```applescript
tell application "Music"
    get name of current track
end tell
```

Click "Run" to see results and identify errors early.

### 3. Identify Key Operations

Based on the dictionary and common use cases, identify 3-5 key operations. Examples:
- Music: play/pause, get current track, set volume
- Calendar: create event, list events, delete event
- Notes: create note, search notes, list notebooks

### 4. Review Existing Modules

Look at similar modules for patterns:
- **Simple data retrieval**: `Finder.get_selection/0`
- **Simple commands**: `SystemEvents.quit_application/1`
- **Complex operations**: `Safari.execute_javascript/1`
- **Sending data**: `Mail.send_email/1`

---

## Step-by-Step Guide

### Step 1: Create the Module Structure

**File**: `lib/ex_macos_control/app_name.ex`

```elixir
defmodule ExMacOSControl.AppName do
  @moduledoc """
  Provides functions for automating the [App Name] application on macOS.

  ## Examples

      # Basic operation
      ExMacOSControl.AppName.some_operation()
      # => {:ok, result}

  ## Permissions

  Requires:
  - Automation permission for Terminal/your app to control [App Name]
  - [Any additional permissions, e.g., Full Disk Access]

  Grant in: System Preferences > Privacy & Security > Automation
  """

  alias ExMacOSControl.Error

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  # Your functions go here
end
```

### Step 2: Implement Functions

Follow this pattern for each function:

```elixir
@doc """
[Clear description of what the function does]

## Parameters

- `param1` - Description
- `param2` - Description (optional)

## Returns

- `{:ok, result}` on success
- `{:error, Error.t()}` on failure

## Examples

    some_function("arg")
    # => {:ok, "result"}

## Errors

- `:not_found` - App or resource not found
- `:execution_error` - AppleScript execution failed
- `:permission_denied` - Permissions required
"""
@spec some_function(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
def some_function(arg) do
  script = """
  tell application "AppName"
    -- Your AppleScript here
  end tell
  """

  case adapter().run_applescript(script) do
    {:ok, result} -> {:ok, parse_result(result)}
    {:error, reason} -> {:error, reason}
  end
end

# Private helper to parse AppleScript output
defp parse_result(output) do
  output |> String.trim()
end
```

**Key principles:**
- Delegate to `adapter().run_applescript/1`
- Never shell out directly
- Parse results into structured Elixir data
- Use private helpers for parsing logic
- Return tagged tuples `{:ok, _}` or `{:error, _}`

### Step 3: Handle Quote Escaping

Always escape quotes in user input:

```elixir
defp escape_quotes(str) do
  String.replace(str, "\"", "\\\"")
end

# Use in scripts:
script = """
tell application "AppName"
  do something with "#{escape_quotes(user_input)}"
end tell
"""
```

### Step 4: Write Unit Tests

**File**: `test/ex_macos_control/app_name_test.exs`

```elixir
defmodule ExMacOSControl.AppNameTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  setup do
    # Stub the adapter for all tests
    stub(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
      {:ok, "default response"}
    end)

    :ok
  end

  describe "some_function/1" do
    test "calls AppleScript with correct script" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ "tell application \"AppName\""
        {:ok, "result"}
      end)

      assert {:ok, "result"} = AppName.some_function("arg")
    end

    test "escapes quotes in arguments" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(\\")
        {:ok, ""}
      end)

      AppName.some_function("text with \"quotes\"")
    end

    test "handles errors from adapter" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:error, %Error{type: :execution_error}}
      end)

      assert {:error, %Error{type: :execution_error}} =
        AppName.some_function("arg")
    end
  end
end
```

**Test each function for:**
- Correct AppleScript generation
- Quote escaping
- Result parsing
- Error handling
- Edge cases (empty results, malformed data)

### Step 5: Write Integration Tests

**File**: `test/integration/app_name_integration_test.exs`

```elixir
defmodule ExMacOSControl.AppNameIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{AppName, SystemEvents, TestHelpers}

  @moduletag :integration

  setup do
    TestHelpers.skip_unless_integration()

    # Use real adapter
    original_adapter = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)

    on_exit(fn ->
      Application.put_env(:ex_macos_control, :adapter, original_adapter)
    end)

    # Launch app if needed
    SystemEvents.launch_application("AppName")
    Process.sleep(1000)

    :ok
  end

  describe "some_function/1" do
    @tag :integration
    test "performs real operation" do
      assert {:ok, result} = AppName.some_function("test")
      assert is_binary(result)
    end
  end
end
```

**Safety considerations:**
- Use `@tag :integration` on all tests
- For destructive operations, use `@tag :skip` by default
- Document what setup is needed (test data, permissions)
- Add cleanup in `on_exit` if needed

### Step 6: Update Documentation

**Add to README.md:**

````markdown
### AppName Automation

```elixir
# Basic operation
ExMacOSControl.AppName.some_operation()
# => {:ok, result}

# With parameters
ExMacOSControl.AppName.other_operation("param")
# => :ok
```

**Required Permissions:**
- Automation permission for Terminal/your app
- [Any additional permissions]
````

---

## Common Patterns

### Pattern 1: Simple Command Execution

**Use case**: Operations that don't return data (quit, play, pause)

**Example from SystemEvents.quit_application/1:**

```elixir
def quit_application(app_name) do
  script = ~s(tell application "#{escape_quotes(app_name)}" to quit)

  case adapter().run_applescript(script) do
    {:ok, _} -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

**Pattern:**
- Build AppleScript string
- Escape user input
- Delegate to adapter
- Return `:ok` or `{:error, _}`

---

### Pattern 2: Data Retrieval and Parsing

**Use case**: Getting information from the app (selection, status, lists)

**Example from Finder.get_selection/0:**

```elixir
def get_selection do
  script = """
  tell application "Finder"
    set selectedItems to selection
    set itemPaths to {}

    repeat with anItem in selectedItems
      set end of itemPaths to POSIX path of (anItem as alias)
    end repeat

    return itemPaths
  end tell
  """

  case adapter().run_applescript(script) do
    {:ok, ""} -> {:ok, []}
    {:ok, result} -> {:ok, parse_paths(result)}
    {:error, reason} -> {:error, reason}
  end
end

defp parse_paths(output) do
  output
  |> String.split(",")
  |> Enum.map(&String.trim/1)
end
```

**Pattern:**
- Request data from app
- Handle empty results
- Parse output into Elixir data structures
- Return `{:ok, data}` or `{:error, _}`

---

### Pattern 3: Complex Operations with Options

**Use case**: Operations with multiple optional parameters

**Example from Mail.send_email/1:**

```elixir
def send_email(opts) do
  with :ok <- validate_required(opts, :to),
       :ok <- validate_required(opts, :subject),
       :ok <- validate_required(opts, :body) do

    cc = Keyword.get(opts, :cc, [])
    bcc = Keyword.get(opts, :bcc, [])

    script = build_send_email_script(opts[:to], opts[:subject], opts[:body], cc, bcc)

    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

defp validate_required(opts, key) do
  case Keyword.get(opts, key) do
    nil -> {:error, Error.execution_error("Missing required field: #{key}")}
    value when value == "" -> {:error, Error.execution_error("Missing required field: #{key}")}
    _value -> :ok
  end
end

defp build_send_email_script(to, subject, body, cc, bcc) do
  # Build complex AppleScript with all parameters
  """
  tell application "Mail"
    -- Complex script here
  end tell
  """
end
```

**Pattern:**
- Validate required parameters with `with`
- Extract optional parameters with defaults
- Build script in separate helper function
- Use `with` for clean error handling

---

### Pattern 4: List Operations with Structured Data

**Use case**: Returning lists of structured data

**Example pattern for Messages.list_chats/0:**

```elixir
def list_chats do
  script = """
  tell application "Messages"
    set chatList to {}
    repeat with c in chats
      try
        set chatInfo to (id of c) & "|" & (name of c) & "|" & (unread count of c)
        copy chatInfo to end of chatList
      end try
    end repeat
    return chatList as text
  end tell
  """

  case adapter().run_applescript(script) do
    {:ok, result} -> {:ok, parse_chats(result)}
    {:error, reason} -> {:error, reason}
  end
end

defp parse_chats(""), do: []

defp parse_chats(output) do
  output
  |> String.split(",", trim: true)
  |> Enum.map(&parse_chat_line/1)
end

defp parse_chat_line(line) do
  [id, name, unread] = String.split(line, "|", parts: 3)

  %{
    id: String.trim(id),
    name: String.trim(name),
    unread: String.trim(unread) |> String.to_integer()
  }
end
```

**Pattern:**
- Use delimiter (e.g., "|") to separate fields
- Use try/catch in AppleScript for robustness
- Parse into maps with clear keys
- Handle empty results gracefully

---

### Pattern 5: Window and UI Automation

**Use case**: Controlling application windows and UI elements

**Example from SystemEvents.set_window_bounds/3:**

```elixir
def set_window_bounds(app_name, position: position, size: size) do
  # Validate parameters
  with :ok <- validate_position(position),
       :ok <- validate_size(size) do
    [x, y] = position
    [width, height] = size

    script = """
    tell application "System Events"
      tell process "#{escape_quotes(app_name)}"
        if (count of windows) > 0 then
          set position of front window to {#{x}, #{y}}
          set size of front window to {#{width}, #{height}}
        else
          error "No windows available"
        end if
      end tell
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  else
    {:error, reason} -> {:error, reason}
  end
end

defp validate_position([_x, _y]), do: :ok
defp validate_position(_) do
  {:error, Error.execution_error("Invalid position format, expected [x, y]")}
end

defp validate_size([_width, _height]), do: :ok
defp validate_size(_) do
  {:error, Error.execution_error("Invalid size format, expected [width, height]")}
end
```

**Pattern:**
- Validate structured parameters
- Check for window existence before acting
- Provide clear error messages for validation failures
- Use System Events for UI manipulation

---

## Testing Strategies

### Unit Testing with Mox

**Goal**: Test all logic without running AppleScript

**Setup:**

```elixir
setup do
  stub(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
    {:ok, ""}
  end)

  :ok
end
```

**What to test:**
- AppleScript generation is correct
- Quote escaping works
- Result parsing produces correct data structures
- Error handling propagates correctly
- Edge cases (empty results, malformed data)

**Example:**

```elixir
test "parses multiple items correctly" do
  expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
    {:ok, "item1, item2, item3"}
  end)

  assert {:ok, ["item1", "item2", "item3"]} = AppName.list_items()
end

test "handles empty results" do
  expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
    {:ok, ""}
  end)

  assert {:ok, []} = AppName.list_items()
end

test "parses structured data correctly" do
  expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
    {:ok, "id1|Name 1|5, id2|Name 2|3"}
  end)

  assert {:ok, [
    %{id: "id1", name: "Name 1", count: 5},
    %{id: "id2", name: "Name 2", count: 3}
  ]} = AppName.list_items()
end
```

### Integration Testing on macOS

**Goal**: Verify real AppleScript execution works

**When to skip tests:**
- Destructive operations (delete, send, modify)
- Operations requiring user interaction
- Operations that cost money or send data externally

**Use `@tag :skip` for safety:**

```elixir
describe "delete_item/1" do
  @tag :skip
  @tag :integration
  test "actually deletes an item" do
    # This test would really delete something, so it's skipped by default
  end
end
```

**Document test requirements:**

```elixir
# IMPORTANT: To run integration tests:
# 1. Ensure AppName is installed
# 2. Grant automation permissions
# 3. [Any additional setup]
# 4. Run: mix test --include integration
```

**Integration test structure:**

```elixir
setup do
  TestHelpers.skip_unless_integration()

  # Save original adapter
  original_adapter = Application.get_env(:ex_macos_control, :adapter)
  Application.put_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)

  on_exit(fn ->
    # Restore adapter
    Application.put_env(:ex_macos_control, :adapter, original_adapter)
  end)

  # Setup test environment
  SystemEvents.launch_application("AppName")
  Process.sleep(1000)

  :ok
end
```

---

## Best Practices

### 1. Keep Functions Focused

**Good**: One function, one operation
```elixir
def get_current_track()
def play()
def pause()
```

**Avoid**: Doing too much in one function
```elixir
def control_playback(action, options \\ []) # Too generic
```

### 2. Delegate to Adapter

**Good**: Use the adapter
```elixir
adapter().run_applescript(script)
```

**Avoid**: Shelling out directly
```elixir
System.cmd("osascript", ["-e", script])  # Don't do this!
```

**Why**: Adapter enables mocking, error handling, and consistent behavior.

### 3. Use Consistent Error Types

Map AppleScript errors to standard types:

```elixir
# From ExMacOSControl.Error
:not_found          # App or resource not found
:execution_error    # General AppleScript error
:permission_denied  # Automation permission needed
:timeout            # Operation timed out
```

### 4. Document Permissions

Always note required permissions in @moduledoc:

```elixir
## Permissions

Requires:
- Automation permission for Terminal/your app to control AppName
- Full Disk Access (for reading app data)

Grant in: System Preferences > Privacy & Security
```

### 5. Add Safety Warnings

For destructive operations, add clear warnings:

```elixir
@doc """
Deletes an item permanently.

**Warning**: This operation cannot be undone.

## Examples
    ...
"""
```

### 6. Handle Edge Cases

Common edge cases:
- Empty results: Return `[]` or `{:ok, []}`, not error
- App not running: Launch it or return clear error
- Malformed data: Parse defensively, return error if invalid
- Unicode/special characters: Escape properly

### 7. Follow Naming Conventions

- Use snake_case for function names
- Prefix boolean functions with `is_` or `has_`
- Use descriptive names: `get_current_folder/0` not `folder/0`
- Keep names consistent with app terminology

### 8. Provide Helpful Examples

Every public function should have:
- At least one basic example
- Example showing error case (if applicable)
- Example with all options (for complex functions)

### 9. Use Specs Consistently

All public functions must have `@spec`:

```elixir
@spec function_name(String.t()) :: {:ok, result_type} | {:error, Error.t()}
@spec function_name(atom(), keyword()) :: :ok | {:error, Error.t()}
```

---

## Examples

### Example 1: Music Module (Simple)

A simple module with basic playback controls:

```elixir
defmodule ExMacOSControl.Music do
  @moduledoc """
  Provides functions for automating the Music application on macOS.

  ## Examples

      # Playback control
      :ok = ExMacOSControl.Music.play()
      :ok = ExMacOSControl.Music.pause()

      # Get track info
      {:ok, track} = ExMacOSControl.Music.get_current_track()
      # => {:ok, %{name: "Song Name", artist: "Artist", album: "Album"}}

  ## Permissions

  Requires:
  - Automation permission for Terminal/your app to control Music

  Grant in: System Preferences > Privacy & Security > Automation
  """

  alias ExMacOSControl.Error

  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Starts playback in Music.

  ## Returns

  - `:ok` - Playback started successfully
  - `{:error, Error.t()}` - If Music is not available

  ## Examples

      Music.play()
      # => :ok
  """
  @spec play() :: :ok | {:error, Error.t()}
  def play do
    script = ~s(tell application "Music" to play)

    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Pauses playback in Music.

  ## Returns

  - `:ok` - Playback paused successfully
  - `{:error, Error.t()}` - If Music is not available

  ## Examples

      Music.pause()
      # => :ok
  """
  @spec pause() :: :ok | {:error, Error.t()}
  def pause do
    script = ~s(tell application "Music" to pause)

    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets information about the current track.

  Returns a map with the track name, artist, and album.

  ## Returns

  - `{:ok, track}` - Map with `:name`, `:artist`, `:album` keys
  - `{:error, Error.t()}` - If no track is playing or Music is not available

  ## Examples

      Music.get_current_track()
      # => {:ok, %{name: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera"}}
  """
  @spec get_current_track() :: {:ok, map()} | {:error, Error.t()}
  def get_current_track do
    script = """
    tell application "Music"
      set trackName to name of current track
      set trackArtist to artist of current track
      set trackAlbum to album of current track
      return trackName & "|" & trackArtist & "|" & trackAlbum
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, result} -> {:ok, parse_track_info(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets the playback volume.

  ## Parameters

  - `volume` - Volume level (0-100)

  ## Returns

  - `:ok` - Volume set successfully
  - `{:error, Error.t()}` - If volume is out of range or Music is not available

  ## Examples

      Music.set_volume(50)
      # => :ok

      Music.set_volume(0)
      # => :ok

      Music.set_volume(150)
      # => {:error, %Error{type: :execution_error, message: "Volume must be 0-100"}}
  """
  @spec set_volume(integer()) :: :ok | {:error, Error.t()}
  def set_volume(volume) when is_integer(volume) and volume >= 0 and volume <= 100 do
    script = """
    tell application "Music"
      set sound volume to #{volume}
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def set_volume(_volume) do
    {:error, Error.execution_error("Volume must be an integer between 0 and 100")}
  end

  ## Private Helpers

  defp parse_track_info(output) do
    case String.split(output, "|", parts: 3) do
      [name, artist, album] ->
        %{
          name: String.trim(name),
          artist: String.trim(artist),
          album: String.trim(album)
        }

      _ ->
        %{name: "", artist: "", album: ""}
    end
  end
end
```

**Tests for Music module:**

```elixir
defmodule ExMacOSControl.MusicTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.Music

  setup :verify_on_exit!

  setup do
    stub(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
      {:ok, ""}
    end)

    :ok
  end

  describe "play/0" do
    test "sends play command" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(tell application "Music" to play)
        {:ok, ""}
      end)

      assert :ok = Music.play()
    end
  end

  describe "pause/0" do
    test "sends pause command" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(tell application "Music" to pause)
        {:ok, ""}
      end)

      assert :ok = Music.pause()
    end
  end

  describe "get_current_track/0" do
    test "parses track info correctly" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, "Song Name|Artist Name|Album Name"}
      end)

      assert {:ok, %{name: "Song Name", artist: "Artist Name", album: "Album Name"}} =
        Music.get_current_track()
    end

    test "handles malformed output" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, "incomplete"}
      end)

      assert {:ok, %{name: "", artist: "", album: ""}} = Music.get_current_track()
    end
  end

  describe "set_volume/1" do
    test "sets volume within valid range" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ "set sound volume to 50"
        {:ok, ""}
      end)

      assert :ok = Music.set_volume(50)
    end

    test "accepts 0 volume" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ "set sound volume to 0"
        {:ok, ""}
      end)

      assert :ok = Music.set_volume(0)
    end

    test "accepts 100 volume" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ "set sound volume to 100"
        {:ok, ""}
      end)

      assert :ok = Music.set_volume(100)
    end

    test "rejects volume above 100" do
      assert {:error, _error} = Music.set_volume(150)
    end

    test "rejects negative volume" do
      assert {:error, _error} = Music.set_volume(-1)
    end
  end
end
```

---

### Example 2: Calendar Module (Complex)

A more complex module with validation and options:

```elixir
defmodule ExMacOSControl.Calendar do
  @moduledoc """
  Provides functions for automating the Calendar application on macOS.

  ## Examples

      # Create an event
      :ok = ExMacOSControl.Calendar.create_event(
        summary: "Team Meeting",
        start_date: ~U[2024-01-15 14:00:00Z],
        end_date: ~U[2024-01-15 15:00:00Z],
        location: "Conference Room A"
      )

      # List today's events
      {:ok, events} = ExMacOSControl.Calendar.list_events_today()

      # Delete an event
      :ok = ExMacOSControl.Calendar.delete_event("Meeting ID")

  ## Permissions

  Requires:
  - Automation permission for Terminal/your app to control Calendar
  - Calendar access permission (macOS may prompt on first use)

  Grant in: System Preferences > Privacy & Security > Automation
  """

  alias ExMacOSControl.Error

  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Creates a new calendar event.

  ## Parameters

  - `opts` - Keyword list with:
    - `:summary` (required) - Event title
    - `:start_date` (required) - Start date/time (DateTime)
    - `:end_date` (required) - End date/time (DateTime)
    - `:calendar` (optional) - Calendar name (default: "Calendar")
    - `:location` (optional) - Event location
    - `:notes` (optional) - Event notes

  ## Returns

  - `:ok` - Event created successfully
  - `{:error, Error.t()}` - If required fields missing or creation fails

  ## Examples

      create_event(
        summary: "Team Meeting",
        start_date: ~U[2024-01-15 14:00:00Z],
        end_date: ~U[2024-01-15 15:00:00Z],
        location: "Conference Room A"
      )
      # => :ok

      create_event(
        summary: "Lunch",
        start_date: ~U[2024-01-15 12:00:00Z],
        end_date: ~U[2024-01-15 13:00:00Z],
        calendar: "Personal",
        notes: "Remember to bring wallet"
      )
      # => :ok
  """
  @spec create_event(keyword()) :: :ok | {:error, Error.t()}
  def create_event(opts) do
    with {:ok, summary} <- validate_required(opts, :summary),
         {:ok, start_date} <- validate_required(opts, :start_date),
         {:ok, end_date} <- validate_required(opts, :end_date),
         :ok <- validate_date_range(start_date, end_date) do

      calendar = Keyword.get(opts, :calendar, "Calendar")
      location = Keyword.get(opts, :location, "")
      notes = Keyword.get(opts, :notes, "")

      script = build_create_event_script(
        summary, start_date, end_date, calendar, location, notes
      )

      case adapter().run_applescript(script) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Lists all events for today.

  Returns a list of events scheduled for the current day.

  ## Returns

  - `{:ok, events}` - List of event maps
  - `{:ok, []}` - If no events today
  - `{:error, Error.t()}` - If Calendar is not available

  Each event is a map with:
  - `:summary` - Event title
  - `:start_date` - Start time as string
  - `:location` - Event location (if any)

  ## Examples

      list_events_today()
      # => {:ok, [
      #      %{summary: "Meeting", start_date: "2024-01-15 14:00:00", location: "Room A"},
      #      %{summary: "Lunch", start_date: "2024-01-15 12:00:00", location: ""}
      #    ]}
  """
  @spec list_events_today() :: {:ok, [map()]} | {:error, Error.t()}
  def list_events_today do
    script = """
    tell application "Calendar"
      set todayStart to current date
      set time of todayStart to 0
      set todayEnd to todayStart + (24 * 60 * 60)

      set eventList to {}
      repeat with cal in calendars
        set calEvents to (events of cal whose start date is greater than or equal to todayStart and start date is less than todayEnd)
        repeat with evt in calEvents
          set evtSummary to summary of evt
          set evtStart to start date of evt as text
          set evtLocation to location of evt
          if evtLocation is missing value then
            set evtLocation to ""
          end if
          set end of eventList to evtSummary & "|" & evtStart & "|" & evtLocation
        end repeat
      end repeat

      return eventList as text
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, ""} -> {:ok, []}
      {:ok, result} -> {:ok, parse_events(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes an event by its summary.

  **Warning**: This operation cannot be undone. The event will be permanently removed.

  ## Parameters

  - `summary` - Title of the event to delete (must match exactly)

  ## Returns

  - `:ok` - Event deleted successfully
  - `{:error, Error.t()}` - If event not found or deletion fails

  ## Examples

      delete_event("Team Meeting")
      # => :ok

      delete_event("Nonexistent Event")
      # => {:error, %Error{type: :not_found, ...}}
  """
  @spec delete_event(String.t()) :: :ok | {:error, Error.t()}
  def delete_event(summary) do
    script = """
    tell application "Calendar"
      set foundEvent to false
      repeat with cal in calendars
        set matchingEvents to (events of cal whose summary is "#{escape_quotes(summary)}")
        if (count of matchingEvents) > 0 then
          delete item 1 of matchingEvents
          set foundEvent to true
          exit repeat
        end if
      end repeat

      if foundEvent is false then
        error "Event not found"
      end if
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private Helpers

  defp validate_required(opts, key) do
    case Keyword.get(opts, key) do
      nil ->
        {:error, Error.execution_error("Missing required field", field: key)}
      value ->
        {:ok, value}
    end
  end

  defp validate_date_range(start_date, end_date) do
    if DateTime.compare(start_date, end_date) == :lt do
      :ok
    else
      {:error, Error.execution_error("Start date must be before end date")}
    end
  end

  defp build_create_event_script(summary, start_date, end_date, calendar, location, notes) do
    # Format dates for AppleScript
    start_str = format_date(start_date)
    end_str = format_date(end_date)

    """
    tell application "Calendar"
      tell calendar "#{escape_quotes(calendar)}"
        set newEvent to make new event with properties {
          summary: "#{escape_quotes(summary)}",
          start date: date "#{start_str}",
          end date: date "#{end_str}",
          location: "#{escape_quotes(location)}",
          description: "#{escape_quotes(notes)}"
        }
      end tell
    end tell
    """
  end

  defp format_date(%DateTime{} = dt) do
    # Convert to local time and format for AppleScript
    # AppleScript date format: "Monday, January 15, 2024 at 2:00:00 PM"
    local_dt = DateTime.shift_zone!(dt, "America/New_York")
    Calendar.strftime(local_dt, "%A, %B %-d, %Y at %-I:%M:%S %p")
  end

  defp parse_events(output) do
    output
    |> String.split(",", trim: true)
    |> Enum.map(&parse_event_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_event_line(line) do
    case String.split(line, "|", parts: 3) do
      [summary, start_date, location] ->
        %{
          summary: String.trim(summary),
          start_date: String.trim(start_date),
          location: String.trim(location)
        }

      _ ->
        nil
    end
  end

  defp escape_quotes(str) when is_binary(str) do
    String.replace(str, "\"", "\\\"")
  end
end
```

**Tests for Calendar module:**

```elixir
defmodule ExMacOSControl.CalendarTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.{Calendar, Error}

  setup :verify_on_exit!

  setup do
    stub(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
      {:ok, ""}
    end)

    :ok
  end

  describe "create_event/1" do
    test "creates event with required fields" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(summary: "Team Meeting")
        assert script =~ "start date:"
        assert script =~ "end date:"
        {:ok, ""}
      end)

      assert :ok = Calendar.create_event(
        summary: "Team Meeting",
        start_date: ~U[2024-01-15 14:00:00Z],
        end_date: ~U[2024-01-15 15:00:00Z]
      )
    end

    test "includes optional location and notes" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(location: "Room A")
        assert script =~ ~s(description: "Important meeting")
        {:ok, ""}
      end)

      assert :ok = Calendar.create_event(
        summary: "Meeting",
        start_date: ~U[2024-01-15 14:00:00Z],
        end_date: ~U[2024-01-15 15:00:00Z],
        location: "Room A",
        notes: "Important meeting"
      )
    end

    test "returns error when summary missing" do
      assert {:error, %Error{type: :execution_error}} = Calendar.create_event(
        start_date: ~U[2024-01-15 14:00:00Z],
        end_date: ~U[2024-01-15 15:00:00Z]
      )
    end

    test "returns error when start_date is after end_date" do
      assert {:error, %Error{type: :execution_error}} = Calendar.create_event(
        summary: "Meeting",
        start_date: ~U[2024-01-15 15:00:00Z],
        end_date: ~U[2024-01-15 14:00:00Z]
      )
    end

    test "escapes quotes in summary" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(\\\")
        {:ok, ""}
      end)

      Calendar.create_event(
        summary: "Meeting \"Important\"",
        start_date: ~U[2024-01-15 14:00:00Z],
        end_date: ~U[2024-01-15 15:00:00Z]
      )
    end
  end

  describe "list_events_today/0" do
    test "parses events correctly" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, "Meeting|Monday, January 15, 2024 at 2:00:00 PM|Room A, Lunch|Monday, January 15, 2024 at 12:00:00 PM|"}
      end)

      assert {:ok, events} = Calendar.list_events_today()
      assert length(events) == 2
      assert [first, second] = events
      assert first.summary == "Meeting"
      assert first.location == "Room A"
      assert second.summary == "Lunch"
      assert second.location == ""
    end

    test "returns empty list when no events" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, []} = Calendar.list_events_today()
    end
  end

  describe "delete_event/1" do
    test "deletes event by summary" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(whose summary is "Team Meeting")
        assert script =~ "delete"
        {:ok, ""}
      end)

      assert :ok = Calendar.delete_event("Team Meeting")
    end

    test "escapes quotes in summary" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        assert script =~ ~s(\\\")
        {:ok, ""}
      end)

      Calendar.delete_event("Meeting \"Important\"")
    end
  end
end
```

---

## Troubleshooting

### Common AppleScript Errors

**Error: "Application isn't running"**
- Solution: Launch the app first using `SystemEvents.launch_application/1`
- Or: Modify script to launch app automatically with `activate` command

**Error: "Can't get [property]"**
- Cause: Property doesn't exist or wrong object type
- Solution: Check scripting dictionary, verify object reference
- Tip: Use `try...end try` blocks for optional properties

**Error: "Not authorized"**
- Cause: Missing automation permission
- Solution: Grant in System Preferences > Privacy & Security > Automation
- Note: May need to restart Terminal/IDE after granting permission

**Error: Timeout**
- Cause: Operation takes too long
- Solution: Increase timeout in adapter call
- Example: `adapter().run_applescript(script, timeout: 10_000)`

**Error: "Syntax error" in AppleScript**
- Cause: Invalid AppleScript syntax
- Solution: Test script in Script Editor first
- Tip: Check for unescaped quotes or special characters

### Permission Issues

**Granting Automation Permissions:**
1. Open System Preferences (or System Settings on newer macOS)
2. Go to Privacy & Security > Automation
3. Find your Terminal or IDE in the list
4. Check the box next to the target app
5. Restart your Terminal/IDE if needed

**Checking Permissions Programmatically:**
- Some apps will show a permission dialog on first use
- Others will silently fail - check Console.app for error messages
- Look for "not authorized" or "permission denied" in errors

**Full Disk Access (for some apps):**
- Required for: Messages (reading history), Mail (reading mailboxes)
- Grant in: System Preferences > Privacy & Security > Full Disk Access
- Add Terminal or your IDE to the list

### Debugging AppleScript

**1. Test in Script Editor first:**
- Prototype your AppleScript in Script Editor
- Fix syntax errors before translating to Elixir
- Use `log` statements for debugging:
  ```applescript
  log "Debug: value is " & someValue
  ```

**2. Print the generated script:**
```elixir
script = build_script(args)
IO.puts("Generated script:\n#{script}")
adapter().run_applescript(script)
```

**3. Check Console.app:**
- Open Console.app
- Filter for "osascript" or your app name
- Look for error messages and permission denials

**4. Use simpler data:**
- Test with simple strings first
- Add complexity (quotes, special chars) incrementally
- Verify escaping is correct at each step

**5. Verify app is scriptable:**
- Not all apps support AppleScript
- Check File > Open Dictionary in Script Editor
- If app doesn't appear, it may not be scriptable

### App-Specific Quirks

**Finder:**
- Requires POSIX paths: Use `POSIX path of (item as alias)`
- Selection can be empty: Always check for empty results
- Some operations require window to be open

**Safari:**
- Requires "Allow JavaScript from Apple Events" setting
- Enable in Safari > Settings > Developer tab
- Tabs are 1-indexed (not 0-indexed)
- JavaScript execution requires page to be loaded

**Mail:**
- Can be slow to send: Add delays or increase timeout
- Email validation is basic - validate addresses yourself
- May show "New Message" window briefly when sending

**Messages:**
- Service type matters (iMessage vs SMS)
- May require Full Disk Access for reading history
- Contact names may not match exactly - use phone numbers

**Calendar:**
- Date formatting is specific to locale
- Calendar names are case-sensitive
- Events need both start and end dates

**Music/TV:**
- Legacy "iTunes" commands may still work
- Track metadata may be missing for some songs
- Requires content to be playing for current track info

### Common Parsing Issues

**Problem: Commas in data break parsing**
- Solution: Use a different delimiter like "|" or use JSON

**Problem: Empty values cause parse errors**
- Solution: Check for empty strings before parsing
- Handle `missing value` in AppleScript with conditionals

**Problem: Unicode characters**
- Solution: AppleScript handles Unicode well, just escape quotes
- Test with non-ASCII characters to verify

**Problem: Numbers returned as strings**
- Solution: Use `String.to_integer/1` with error handling
- Example:
  ```elixir
  case Integer.parse(str) do
    {num, _} -> num
    :error -> 0  # or appropriate default
  end
  ```

---

## Contributing

### Submitting a New Module

1. **Discuss first**: Open an issue to discuss the module before starting work
2. **Follow patterns**: Use existing modules (Finder, Safari, Mail) as examples
3. **Write tests**: Aim for >90% unit test coverage
4. **Document thoroughly**: Every public function needs @doc, @spec, examples
5. **Update README**: Add usage examples to the main README
6. **Create PR**: Include clear description and link to issue

### Code Review Expectations

Your PR will be reviewed for:
- **Correctness**: Does it work? Are edge cases handled?
- **Testing**: High test coverage, both unit and integration tests
- **Documentation**: Clear docs with practical examples
- **Code quality**: Passes Credo, Dialyzer, formatter
- **Consistency**: Follows established patterns from existing modules

### Pull Request Checklist

Before submitting your PR:

- [ ] Module file created in `lib/ex_macos_control/`
- [ ] Unit tests in `test/ex_macos_control/`
- [ ] Integration tests in `test/integration/`
- [ ] All public functions have @doc and @spec
- [ ] All public functions have examples
- [ ] @moduledoc includes permissions info
- [ ] README updated with usage examples
- [ ] All tests pass: `mix test`
- [ ] No Credo issues: `mix credo --strict`
- [ ] No Dialyzer warnings: `mix dialyzer`
- [ ] Code formatted: `mix format`
- [ ] Integration tests tagged appropriately
- [ ] Destructive operations skipped by default

### Module Maintenance

If you contribute a module, you're expected to:
- Respond to issues related to your module
- Keep it updated as the app changes across macOS versions
- Fix bugs promptly
- Consider backward compatibility

### macOS Version Compatibility

When creating modules:
- Test on the latest macOS version
- Note any version-specific features in documentation
- Use fallbacks for features not available on older versions
- Document minimum macOS version if applicable

---

## Additional Resources

### Official Documentation

- [AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/) - Comprehensive AppleScript reference
- [Script Editor Help](https://support.apple.com/guide/script-editor/) - How to use Script Editor
- [macOS Automation](https://developer.apple.com/macos/automation/) - Apple's automation resources

### ExMacOSControl Documentation

- [ExMacOSControl on Hex](https://hexdocs.pm/ex_macos_control) - API documentation
- [GitHub Repository](https://github.com/houllette/ex_macos_control) - Source code and issues
- [Testing Guide](testing.md) - Comprehensive testing documentation

### Community Resources

- [Elixir Forum](https://elixirforum.com/) - Ask questions about Elixir
- [MacScripter](https://macscripter.net/) - AppleScript community forum
- [Stack Overflow](https://stackoverflow.com/questions/tagged/applescript) - AppleScript Q&A

---

## Summary Checklist

When creating a new module, use this checklist:

### Planning Phase
- [ ] Explored app's scripting dictionary
- [ ] Prototyped key operations in Script Editor
- [ ] Identified 3-5 key functions to implement
- [ ] Reviewed similar existing modules
- [ ] Determined required permissions

### Implementation Phase
- [ ] Created module file with @moduledoc
- [ ] Implemented functions with @doc and @spec
- [ ] Added private helper functions for parsing
- [ ] Implemented quote escaping where needed
- [ ] Used adapter pattern (no direct shell calls)

### Testing Phase
- [ ] Wrote 20+ unit tests (>90% coverage)
- [ ] Wrote integration tests with proper tags
- [ ] Used `@tag :skip` for destructive operations
- [ ] Tested edge cases (empty results, malformed data)
- [ ] All tests pass: `mix test`

### Documentation Phase
- [ ] Documented all permissions required
- [ ] Added practical examples to @doc
- [ ] Updated README with usage examples
- [ ] Added safety warnings for destructive operations
- [ ] Documented known limitations or quirks

### Quality Checks
- [ ] Ran Credo: `mix credo --strict` (0 issues)
- [ ] Ran Dialyzer: `mix dialyzer` (0 warnings)
- [ ] Ran formatter: `mix format --check-formatted`
- [ ] Tested on real macOS system
- [ ] Verified all examples work

### Submission
- [ ] Created feature branch
- [ ] Committed all changes with clear messages
- [ ] Created PR with description
- [ ] Linked to related issue
- [ ] Responded to code review feedback

---

## Final Tips

### Start Small
Don't try to implement every feature at once. Start with:
1. One simple function (e.g., get status)
2. One command function (e.g., play/pause)
3. One complex function (e.g., create item)

Then expand based on feedback and usage.

### Iterate Based on Real Use
The best modules evolve from real usage:
- Start with your own use cases
- Get feedback from users
- Add features as they're requested
- Remove features that aren't used

### Prioritize Safety
Always err on the side of caution:
- Skip destructive tests by default
- Add clear warnings in documentation
- Validate user input thoroughly
- Provide undo mechanisms where possible

### Keep It Simple
Prefer:
- Simple functions over complex ones
- Clear names over clever ones
- Explicit behavior over implicit
- Direct implementations over abstractions

### Get Help
If you're stuck:
- Open an issue to discuss
- Ask on the Elixir Forum
- Review existing modules for patterns
- Check the troubleshooting section

---

**Happy automating!**

For questions, issues, or contributions, visit:
[https://github.com/houllette/ex_macos_control](https://github.com/houllette/ex_macos_control)
