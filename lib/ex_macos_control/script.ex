defmodule ExMacOSControl.Script do
  @moduledoc """
  Simple DSL for building AppleScript programmatically.

  This module provides a minimal, pragmatic DSL for constructing common
  AppleScript patterns using Elixir syntax. It's designed for simple use cases
  like tell blocks and basic commands.

  **Note:** This is an optional helper. For complex scripts, use raw AppleScript
  strings with `ExMacOSControl.run_applescript/1`.

  ## Examples

      alias ExMacOSControl.Script

      # Basic tell block
      script = Script.tell("Finder", [
        "activate"
      ])

      # Generates:
      # tell application "Finder"
      #   activate
      # end tell

      ExMacOSControl.run_applescript(script)

      # Tell block with commands and arguments
      script = Script.tell("Finder", [
        "activate",
        Script.cmd("open", "Macintosh HD")
      ])

      # Generates:
      # tell application "Finder"
      #   activate
      #   open "Macintosh HD"
      # end tell

      # Nested tell blocks
      script = Script.tell("System Events", [
        Script.tell_obj("process", "Safari", [
          "set frontmost to true"
        ])
      ])

      # Generates:
      # tell application "System Events"
      #   tell process "Safari"
      #     set frontmost to true
      #   end tell
      # end tell

  ## Limitations

  This DSL is intentionally minimal and does NOT support:
  - Complex control flow (if/while/repeat)
  - Variable assignments
  - Handlers/subroutines
  - Full AppleScript language coverage

  For these cases, use raw AppleScript strings instead.
  """

  @doc """
  Creates a tell block for an application.

  Generates an AppleScript `tell application` block with the given application
  name and commands.

  ## Parameters

  - `app_name` - The name of the application (e.g., "Finder", "Safari")
  - `commands` - A list of command strings to execute within the tell block

  ## Returns

  A string containing the formatted AppleScript code.

  ## Examples

      alias ExMacOSControl.Script

      # Simple tell block
      Script.tell("Finder", ["activate"])
      # => "tell application \\"Finder\\"\\n  activate\\nend tell"

      # Multiple commands
      Script.tell("Finder", [
        "activate",
        Script.cmd("open", "Macintosh HD")
      ])
      # => "tell application \\"Finder\\"\\n  activate\\n  open \\"Macintosh HD\\"\\nend tell"

  """
  @spec tell(String.t(), [String.t()]) :: String.t()
  def tell(app_name, commands) when is_binary(app_name) and is_list(commands) do
    formatted_commands = Enum.map_join(commands, "\n", &indent(&1, 2))

    """
    tell application #{quote_string(app_name)}
    #{formatted_commands}
    end tell\
    """
  end

  @doc """
  Creates a tell block for a specific object.

  Generates an AppleScript `tell` block targeting a specific object (like a
  process, window, or document) with the given commands.

  ## Parameters

  - `object_type` - The type of object (e.g., "process", "window", "document")
  - `object_name` - The name of the object
  - `commands` - A list of command strings to execute within the tell block

  ## Returns

  A string containing the formatted AppleScript code.

  ## Examples

      alias ExMacOSControl.Script

      # Tell a specific process
      Script.tell_obj("process", "Safari", ["set frontmost to true"])
      # => "tell process \\"Safari\\"\\n  set frontmost to true\\nend tell"

  """
  @spec tell_obj(String.t(), String.t(), [String.t()]) :: String.t()
  def tell_obj(object_type, object_name, commands)
      when is_binary(object_type) and is_binary(object_name) and is_list(commands) do
    formatted_commands = Enum.map_join(commands, "\n", &indent(&1, 2))

    """
    tell #{object_type} #{quote_string(object_name)}
    #{formatted_commands}
    end tell\
    """
  end

  @doc """
  Generates a command with arguments.

  The argument will be automatically quoted if it's a string. For lists,
  all-numeric lists are formatted as AppleScript lists (e.g., {0, 0, 800, 600}),
  while other lists are formatted as space-separated quoted values.

  ## Parameters

  - `command` - The command string
  - `arg` - The argument (string, number, boolean, or list)

  ## Returns

  A string containing the command with its argument.

  ## Examples

      alias ExMacOSControl.Script

      # Single string argument
      Script.cmd("open", "Macintosh HD")
      # => "open \\"Macintosh HD\\""

      # Single numeric argument
      Script.cmd("set volume", 50)
      # => "set volume 50"

      # Single boolean argument
      Script.cmd("set muted", true)
      # => "set muted true"

      # List of strings
      Script.cmd("make", ["new", "window"])
      # => "make \\"new\\" \\"window\\""

      # List of numbers (formatted as AppleScript list)
      Script.cmd("set bounds of window 1 to", [0, 0, 800, 600])
      # => "set bounds of window 1 to {0, 0, 800, 600}"

  """
  @spec cmd(String.t(), String.t() | number() | boolean() | [String.t() | number() | boolean()]) ::
          String.t()
  def cmd(command, arg) when is_binary(command) and is_list(arg) do
    # Check if all args are numbers (bounds/coordinates)
    all_numbers? = Enum.all?(arg, &is_number/1)

    formatted_args =
      if all_numbers? do
        # Format as AppleScript list for coordinates
        "{#{Enum.join(arg, ", ")}}"
      else
        # Format as space-separated values with quoting
        Enum.map_join(arg, " ", &format_argument/1)
      end

    "#{command} #{formatted_args}"
  end

  def cmd(command, arg) when is_binary(command) do
    formatted_arg = format_argument(arg)
    "#{command} #{formatted_arg}"
  end

  ## Private Helpers

  defp format_argument(arg) when is_binary(arg) do
    quote_string(arg)
  end

  defp format_argument(arg) when is_number(arg) do
    to_string(arg)
  end

  defp format_argument(true), do: "true"
  defp format_argument(false), do: "false"

  defp quote_string(str) when is_binary(str) do
    # Escape any existing quotes and wrap in quotes
    escaped = String.replace(str, "\"", "\\\"")
    "\"#{escaped}\""
  end

  defp indent(text, spaces) do
    padding = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.trim(line) == "" do
        line
      else
        padding <> line
      end
    end)
  end
end
