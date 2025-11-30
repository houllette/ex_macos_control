defmodule ExMacOSControl.OSAScriptAdapter do
  @moduledoc """
  Default adapter implementation using the `osascript` command-line tool.

  This module implements the `ExMacOSControl.Adapter` behaviour and provides
  macOS automation functionality by executing AppleScript code and Shortcuts
  via the `osascript` system command.

  ## Implementation Details

  - Uses `System.cmd/2` to execute `osascript` with the provided script
  - Returns `{:ok, output}` on success (exit code 0)
  - Returns `{:error, {:exit_code, code, output}}` on failure
  - Trims whitespace from successful output
  """

  @behaviour ExMacOSControl.Adapter

  @impl true
  def run_applescript(script) do
    {output, exit} = System.cmd("osascript", ["-e", script])

    case exit do
      0 -> {:ok, String.trim(output)}
      _ -> {:error, {:exit_code, exit, output}}
    end
  end

  @impl true
  def run_shortcut(name) do
    script = ~s(tell application "Shortcuts Events" to run shortcut "#{name}")

    case run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
