defmodule ExMacOSControl.OSAScriptAdapter do
  @moduledoc """
  Default adapter implementation using the `osascript` command-line tool.

  This module implements the `ExMacOSControl.Adapter` behaviour and provides
  macOS automation functionality by executing AppleScript code, JavaScript for
  Automation (JXA) code, and Shortcuts via the `osascript` system command.

  ## Implementation Details

  - Uses `System.cmd/2` to execute `osascript` with the provided script
  - Returns `{:ok, output}` on success (exit code 0)
  - Returns `{:error, {:exit_code, code, output}}` on failure
  - Trims whitespace from successful output
  - Supports both AppleScript (default language) and JXA (`-l JavaScript` flag)

  ## JXA Support

  JavaScript for Automation (JXA) is Apple's JavaScript-based alternative to AppleScript.
  It provides the same automation capabilities but uses JavaScript syntax and semantics.

  ### When to use JXA vs AppleScript

  **Use JXA when:**
  - You're more comfortable with JavaScript than AppleScript
  - You need to leverage JavaScript's functional programming features
  - You want to use the ObjC bridge for direct Objective-C interaction
  - You're building complex data transformations

  **Use AppleScript when:**
  - You're working with legacy scripts or examples
  - You need maximum compatibility (AppleScript is more widely documented)
  - The automation task is simple and straightforward

  ### JXA Examples

      # Basic JXA
      {:ok, result} = run_javascript("(function() { return 'test'; })()")

      # Application automation
      {:ok, name} = run_javascript("Application('Finder').name()")

      # With arguments
      script = "function run(argv) { return argv[0]; }"
      {:ok, result} = run_javascript(script, args: ["hello"])

      # ObjC bridge
      script = \"\"\"
      ObjC.import('Foundation');
      var str = $.NSString.alloc.initWithUTF8String('test');
      str.js;
      \"\"\"
      {:ok, result} = run_javascript(script)

  """

  @behaviour ExMacOSControl.Adapter

  @doc """
  Executes AppleScript code using osascript.

  ## Parameters

  - `script` - The AppleScript code to execute

  ## Returns

  - `{:ok, output}` - Success with trimmed output
  - `{:error, {:exit_code, code, output}}` - Failure with exit code and error output

  ## Examples

      iex> run_applescript(~s(return "Hello"))
      {:ok, "Hello"}

      iex> run_applescript("invalid syntax")
      {:error, {:exit_code, 1, _output}}

  """
  @spec run_applescript(String.t()) :: {:ok, String.t()} | {:error, {:exit_code, integer(), String.t()}}
  @impl true
  def run_applescript(script) do
    {output, exit} = System.cmd("osascript", ["-e", script])

    case exit do
      0 -> {:ok, String.trim(output)}
      _ -> {:error, {:exit_code, exit, output}}
    end
  end

  @doc """
  Executes JavaScript for Automation (JXA) code using osascript.

  This is a convenience wrapper around `run_javascript/2` with no options.

  ## Parameters

  - `script` - The JXA code to execute

  ## Returns

  - `{:ok, output}` - Success with trimmed output
  - `{:error, {:exit_code, code, output}}` - Failure with exit code and error output

  ## Examples

      iex> run_javascript("(function() { return 'test'; })()")
      {:ok, "test"}

      iex> run_javascript("Application('Finder').name()")
      {:ok, "Finder"}

  """
  @spec run_javascript(String.t()) :: {:ok, String.t()} | {:error, {:exit_code, integer(), String.t()}}
  @impl true
  def run_javascript(script) do
    run_javascript(script, [])
  end

  @doc """
  Executes JavaScript for Automation (JXA) code with options.

  Uses `osascript -l JavaScript` to execute JXA code. Supports passing arguments
  to the script using the `args` option.

  ## Parameters

  - `script` - The JXA code to execute
  - `opts` - Keyword list of options:
    - `:args` - List of string arguments to pass to the script (default: `[]`)

  ## Returns

  - `{:ok, output}` - Success with trimmed output
  - `{:error, {:exit_code, code, output}}` - Failure with exit code and error output

  ## Options

  ### Arguments (`:args`)

  Arguments are passed to the JXA script and available via the `run(argv)` function:

      # JXA script receives arguments
      function run(argv) {
        return argv[0];  // Returns first argument
      }

  ## Examples

      # Basic execution
      iex> run_javascript("(function() { return 'test'; })()", [])
      {:ok, "test"}

      # With arguments
      iex> script = "function run(argv) { return argv[0]; }"
      iex> run_javascript(script, args: ["hello"])
      {:ok, "hello"}

      # With multiple arguments
      iex> script = "function run(argv) { return argv.join(' '); }"
      iex> run_javascript(script, args: ["hello", "world"])
      {:ok, "hello world"}

      # System Events automation
      iex> script = \"\"\"
      ...> var app = Application('System Events');
      ...> var processes = app.processes.whose({ name: 'Finder' });
      ...> processes.length.toString();
      ...> \"\"\"
      iex> run_javascript(script, [])
      {:ok, "1"}

  """
  @spec run_javascript(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, {:exit_code, integer(), String.t()}}
  @impl true
  def run_javascript(script, opts) do
    args = Keyword.get(opts, :args, [])

    # Build the command arguments: -l JavaScript -e script [args...]
    cmd_args = ["-l", "JavaScript", "-e", script] ++ args

    {output, exit} = System.cmd("osascript", cmd_args, stderr_to_stdout: true)

    case exit do
      0 -> {:ok, String.trim(output)}
      _ -> {:error, {:exit_code, exit, output}}
    end
  end

  @doc """
  Executes a macOS Shortcut by name.

  Uses AppleScript to run the shortcut via Shortcuts Events.

  ## Parameters

  - `name` - The name of the Shortcut to run

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Failure

  ## Examples

      iex> run_shortcut("My Shortcut")
      :ok

  """
  @spec run_shortcut(String.t()) :: :ok | {:error, term()}
  @impl true
  def run_shortcut(name) do
    script = ~s(tell application "Shortcuts Events" to run shortcut "#{name}")

    case run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
