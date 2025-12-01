defmodule ExMacOSControl.OSAScriptAdapter do
  @moduledoc """
  Default adapter implementation using the `osascript` command-line tool.

  This module implements the `ExMacOSControl.Adapter` behaviour and provides
  macOS automation functionality by executing AppleScript code and Shortcuts
  via the `osascript` system command.

  ## Features

  - Execute AppleScript code with timeout support
  - Pass arguments to AppleScript scripts
  - Comprehensive error handling with `ExMacOSControl.Error`
  - Platform-independent timeout implementation using `Task`

  ## Implementation Details

  - Uses `System.cmd/3` to execute `osascript` with the provided script
  - Returns `{:ok, output}` on success (exit code 0)
  - Returns `{:error, error}` on failure with detailed error information
  - Trims whitespace from successful output
  - Supports timeout via `Task.yield/2` and `Task.shutdown/1`
  - Arguments are passed directly to osascript (osascript -e "script" arg1 arg2...)

  ## Examples

      # Basic execution
      {:ok, result} = OSAScriptAdapter.run_applescript(~s(return "Hello"))
      # => {:ok, "Hello"}

      # With timeout
      {:ok, result} = OSAScriptAdapter.run_applescript("delay 1", timeout: 5000)
      # => {:ok, ""}

      # With arguments
      script = \"\"\"
      on run argv
        return item 1 of argv
      end run
      \"\"\"
      {:ok, result} = OSAScriptAdapter.run_applescript(script, args: ["test"])
      # => {:ok, "test"}

      # With both timeout and arguments
      {:ok, result} = OSAScriptAdapter.run_applescript(script, timeout: 5000, args: ["test"])
      # => {:ok, "test"}

  ## Security Considerations

  Arguments are passed directly to `osascript` without shell interpretation,
  making them safe from shell injection attacks. However, the AppleScript
  code itself should be from trusted sources as it executes with full
  system access.
  """

  @behaviour ExMacOSControl.Adapter

  alias ExMacOSControl.Error

  @doc """
  Executes an AppleScript script without options.

  This is a convenience function that delegates to `run_applescript/2`
  with an empty options list, maintaining backward compatibility.

  ## Parameters

    * `script` - The AppleScript code to execute

  ## Returns

    * `{:ok, output}` - On successful execution with script output
    * `{:error, error}` - On failure with detailed error information

  ## Examples

      iex> OSAScriptAdapter.run_applescript(~s(return "Hello, World!"))
      {:ok, "Hello, World!"}

      iex> OSAScriptAdapter.run_applescript("invalid script")
      {:error, %ExMacOSControl.Error{type: :syntax_error, ...}}

  """
  @spec run_applescript(String.t()) :: {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  @impl true
  def run_applescript(script) do
    run_applescript(script, [])
  end

  @doc """
  Executes an AppleScript script with options.

  ## Parameters

    * `script` - The AppleScript code to execute
    * `opts` - Keyword list of options:
      * `:timeout` - Maximum time in milliseconds to wait for execution
      * `:args` - List of string arguments to pass to the script

  ## Returns

    * `{:ok, output}` - On successful execution with script output
    * `{:error, error}` - On failure with detailed error information

  ## Timeout Behavior

  When a timeout is specified, the script execution is monitored via a `Task`.
  If the script doesn't complete within the timeout period, it is terminated
  and a timeout error is returned.

  ## Argument Passing

  Arguments are passed to the AppleScript via the `argv` mechanism. Your
  AppleScript must use the `on run argv` handler to receive arguments.

  ## Examples

      # With timeout
      script = "delay 2\\nreturn \\"done\\""
      OSAScriptAdapter.run_applescript(script, timeout: 5000)
      # => {:ok, "done"}

      # With arguments
      script = \"\"\"
      on run argv
        return (item 1 of argv) & " " & (item 2 of argv)
      end run
      \"\"\"
      OSAScriptAdapter.run_applescript(script, args: ["Hello", "World"])
      # => {:ok, "Hello World"}

      # Timeout exceeded
      script = "delay 10"
      OSAScriptAdapter.run_applescript(script, timeout: 100)
      # => {:error, %ExMacOSControl.Error{type: :timeout, ...}}

      # Multiple options
      OSAScriptAdapter.run_applescript(script, timeout: 5000, args: ["test"])
      # => {:ok, "test"}

  """
  @spec run_applescript(String.t(), ExMacOSControl.Adapter.options()) ::
          {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  @impl true
  def run_applescript(script, opts) when is_list(opts) do
    # Extract options
    timeout = Keyword.get(opts, :timeout)
    args = Keyword.get(opts, :args, [])

    # Build command arguments: ["-e", script] ++ args
    cmd_args = ["-e", script] ++ args

    # Execute with or without timeout
    if timeout do
      run_with_timeout("osascript", cmd_args, timeout)
    else
      run_without_timeout("osascript", cmd_args)
    end
  end

  # Private function to run command with timeout using Task
  defp run_with_timeout(cmd, args, timeout) do
    task =
      Task.async(fn ->
        System.cmd(cmd, args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        {:ok, String.trim(output)}

      {:ok, {stderr, exit_code}} ->
        {:error, Error.parse_osascript_error(stderr, exit_code)}

      nil ->
        {:error, Error.timeout("AppleScript execution", timeout: timeout)}
    end
  end

  # Private function to run command without timeout
  defp run_without_timeout(cmd, args) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {stderr, exit_code} ->
        {:error, Error.parse_osascript_error(stderr, exit_code)}
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
