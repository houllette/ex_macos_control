defmodule ExMacOSControl.OSAScriptAdapter do
  @moduledoc """
  Default adapter implementation using the `osascript` command-line tool.

  This module implements the `ExMacOSControl.Adapter` behaviour and provides
  macOS automation functionality by executing AppleScript code, JavaScript for
  Automation (JXA) code, and Shortcuts via the `osascript` system command.

  ## Features

  - Execute AppleScript code with timeout and argument support
  - Execute JXA code with timeout and argument support
  - Comprehensive error handling with `ExMacOSControl.Error`
  - Platform-independent timeout implementation using `Task`
  - Run macOS Shortcuts

  ## Implementation Details

  - Uses `System.cmd/3` to execute `osascript` with the provided script
  - Returns `{:ok, output}` on success (exit code 0)
  - Returns `{:error, error}` on failure with detailed error information
  - Trims whitespace from successful output
  - Supports timeout via `Task.yield/2` and `Task.shutdown/1`
  - Supports both AppleScript (default) and JXA (`-l JavaScript` flag)
  - Arguments are passed directly to osascript (secure, no shell interpretation)

  ## AppleScript Examples

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

  ## Security Considerations

  Arguments are passed directly to `osascript` without shell interpretation,
  making them safe from shell injection attacks. However, the AppleScript/JXA
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

  @doc """
  Executes JavaScript for Automation (JXA) code using osascript.

  This is a convenience wrapper around `run_javascript/2` with no options.

  ## Parameters

  - `script` - The JXA code to execute

  ## Returns

  - `{:ok, output}` - Success with trimmed output
  - `{:error, error}` - Failure with detailed error information

  ## Examples

      iex> run_javascript("(function() { return 'test'; })()")
      {:ok, "test"}

      iex> run_javascript("Application('Finder').name()")
      {:ok, "Finder"}

  """
  @spec run_javascript(String.t()) :: {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
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
  - `{:error, error}` - Failure with detailed error information

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
  @spec run_javascript(String.t(), ExMacOSControl.Adapter.options()) ::
          {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  @impl true
  def run_javascript(script, opts) do
    args = Keyword.get(opts, :args, [])

    # Build the command arguments: -l JavaScript -e script [args...]
    cmd_args = ["-l", "JavaScript", "-e", script] ++ args

    # JXA doesn't currently support timeout in this implementation
    # Could be added later similar to run_applescript/2
    run_without_timeout("osascript", cmd_args)
  end

  # Extracts the script content from osascript arguments
  # Args format: ["-e", script, ...] or ["-l", "JavaScript", "-e", script, ...] or [file_path, ...]
  defp extract_script_from_args(args) do
    case args do
      ["-e", script | _] -> script
      ["-l", "JavaScript", "-e", script | _] -> script
      [file_path | _] when is_binary(file_path) -> Path.basename(file_path)
      _ -> ""
    end
  end

  # Private function to run command with timeout using Task
  defp run_with_timeout(cmd, args, timeout) do
    script = extract_script_from_args(args)

    metadata = %{
      command: cmd,
      script: String.slice(script, 0, 100),
      timeout: timeout
    }

    measurements = %{
      script_length: String.length(script)
    }

    start_time = System.monotonic_time()
    :telemetry.execute([:ex_macos_control, :applescript, :start], measurements, metadata)

    task =
      Task.async(fn ->
        System.cmd(cmd, args, stderr_to_stdout: true)
      end)

    result =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, 0}} ->
          {:ok, String.trim(output)}

        {:ok, {stderr, exit_code}} ->
          {:error, Error.parse_osascript_error(stderr, exit_code)}

        nil ->
          {:error, Error.timeout("Script execution", timeout: timeout)}
      end

    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :microsecond)

    case result do
      {:ok, output} ->
        measurements_with_duration = Map.merge(measurements, %{duration: duration})
        metadata_with_result = Map.merge(metadata, %{result_type: :success, output_length: String.length(output)})
        :telemetry.execute([:ex_macos_control, :applescript, :stop], measurements_with_duration, metadata_with_result)

      {:error, error} ->
        measurements_with_duration = Map.merge(measurements, %{duration: duration})
        metadata_with_error = Map.merge(metadata, %{error: error, result_type: :error})

        :telemetry.execute(
          [:ex_macos_control, :applescript, :exception],
          measurements_with_duration,
          metadata_with_error
        )
    end

    result
  end

  # Private function to run command without timeout
  defp run_without_timeout(cmd, args) do
    script = extract_script_from_args(args)

    metadata = %{
      command: cmd,
      script: String.slice(script, 0, 100),
      timeout: nil
    }

    measurements = %{
      script_length: String.length(script)
    }

    start_time = System.monotonic_time()
    :telemetry.execute([:ex_macos_control, :applescript, :start], measurements, metadata)

    result =
      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, String.trim(output)}

        {stderr, exit_code} ->
          {:error, Error.parse_osascript_error(stderr, exit_code)}
      end

    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :microsecond)

    case result do
      {:ok, output} ->
        measurements_with_duration = Map.merge(measurements, %{duration: duration})
        metadata_with_result = Map.merge(metadata, %{result_type: :success, output_length: String.length(output)})
        :telemetry.execute([:ex_macos_control, :applescript, :stop], measurements_with_duration, metadata_with_result)

      {:error, error} ->
        measurements_with_duration = Map.merge(measurements, %{duration: duration})
        metadata_with_error = Map.merge(metadata, %{error: error, result_type: :error})

        :telemetry.execute(
          [:ex_macos_control, :applescript, :exception],
          measurements_with_duration,
          metadata_with_error
        )
    end

    result
  end

  @doc """
  Executes a script file from disk with automatic language detection.

  This function executes AppleScript or JavaScript files directly using osascript,
  with automatic language detection based on file extension. It supports all the
  same options as `run_applescript/2` and `run_javascript/2`, including timeout
  and argument passing.

  ## Parameters

    * `file_path` - Absolute or relative path to the script file
    * `opts` - Keyword list of options:
      * `:language` - Explicit language (`:applescript` or `:javascript`), overrides detection
      * `:timeout` - Maximum time in milliseconds to wait for execution
      * `:args` - List of string arguments to pass to the script

  ## Language Detection

  The language is automatically detected from the file extension:

    * `.scpt`, `.applescript` → AppleScript
    * `.js`, `.jxa` → JavaScript

  You can override automatic detection using the `:language` option.

  ## File Validation

  The function validates that:
    * The file exists
    * The path points to a regular file (not a directory)

  ## Returns

    * `{:ok, output}` - On successful execution with script output
    * `{:error, error}` - On failure with detailed error information

  ## Examples

      # Execute AppleScript file with auto-detection
      OSAScriptAdapter.run_script_file("/path/to/script.applescript")
      # => {:ok, "result"}

      # Execute JavaScript file with auto-detection
      OSAScriptAdapter.run_script_file("/path/to/script.js")
      # => {:ok, "result"}

      # Override language detection
      OSAScriptAdapter.run_script_file("/path/to/script.txt", language: :applescript)
      # => {:ok, "result"}

      # With arguments
      OSAScriptAdapter.run_script_file(
        "/path/to/script.applescript",
        args: ["arg1", "arg2"]
      )
      # => {:ok, "result"}

      # With timeout
      OSAScriptAdapter.run_script_file("/path/to/script.js", timeout: 5000)
      # => {:ok, "result"}

      # Combined options
      OSAScriptAdapter.run_script_file(
        "/path/to/script.scpt",
        language: :applescript,
        args: ["test"],
        timeout: 10_000
      )
      # => {:ok, "result"}

      # File not found
      OSAScriptAdapter.run_script_file("/nonexistent.scpt")
      # => {:error, %ExMacOSControl.Error{type: :not_found, ...}}

  """
  @spec run_script_file(String.t(), ExMacOSControl.Adapter.options()) ::
          {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  @impl true
  def run_script_file(file_path, opts) when is_list(opts) do
    with :ok <- validate_file_exists(file_path),
         {:ok, language} <- determine_language(file_path, opts) do
      execute_script_file(file_path, language, opts)
    end
  end

  # Validates that the file exists and is a regular file
  defp validate_file_exists(file_path) do
    cond do
      not File.exists?(file_path) ->
        {:error, Error.not_found("Script file not found", file: file_path)}

      not File.regular?(file_path) ->
        {:error, Error.not_found("Path is not a regular file", file: file_path)}

      true ->
        :ok
    end
  end

  # Detects the language from file extension
  defp detect_language(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ext when ext in [".scpt", ".applescript"] -> :applescript
      ext when ext in [".js", ".jxa"] -> :javascript
      _ -> nil
    end
  end

  # Determines the language to use, preferring explicit option over detection
  defp determine_language(file_path, opts) do
    case Keyword.get(opts, :language) do
      nil ->
        case detect_language(file_path) do
          nil ->
            {:error,
             Error.execution_error(
               "Unknown file extension. Use :language option to specify :applescript or :javascript",
               file: file_path
             )}

          lang ->
            {:ok, lang}
        end

      lang when lang in [:applescript, :javascript] ->
        {:ok, lang}

      invalid ->
        {:error,
         Error.execution_error("Invalid language option: #{inspect(invalid)}. Must be :applescript or :javascript")}
    end
  end

  # Executes the script file using osascript
  defp execute_script_file(file_path, language, opts) do
    timeout = Keyword.get(opts, :timeout)
    args = Keyword.get(opts, :args, [])

    # Build command arguments based on language
    cmd_args = build_command_args(language, file_path, args)

    # Execute with or without timeout
    if timeout do
      run_with_timeout("osascript", cmd_args, timeout)
    else
      run_without_timeout("osascript", cmd_args)
    end
  end

  # Builds osascript command arguments for the given language
  defp build_command_args(:applescript, file_path, args) do
    # osascript file_path [args...]
    [file_path | args]
  end

  defp build_command_args(:javascript, file_path, args) do
    # osascript -l JavaScript file_path [args...]
    ["-l", "JavaScript", file_path | args]
  end

  @doc """
  Executes a macOS Shortcut by name without options.

  This is a convenience function that delegates to `run_shortcut/2`
  with an empty options list, maintaining backward compatibility.

  Uses AppleScript to run the shortcut via Shortcuts Events.

  ## Parameters

  - `name` - The name of the Shortcut to run

  ## Returns

  - `:ok` - Success with no output
  - `{:ok, output}` - Success with output from the shortcut
  - `{:error, error}` - Failure with error reason

  ## Examples

      OSAScriptAdapter.run_shortcut("My Shortcut")
      # => :ok (if shortcut exists and returns no output)
      # => {:ok, "result"} (if shortcut returns output)
      # => {:error, error} (if not found or error occurs)

  """
  @spec run_shortcut(String.t()) :: :ok | {:ok, String.t()} | {:error, term()}
  @impl true
  def run_shortcut(name) do
    run_shortcut(name, [])
  end

  @doc """
  Executes a macOS Shortcut by name with input parameters.

  Uses AppleScript to run the shortcut via Shortcuts Events. Supports passing
  input data to the shortcut, which can be a string, number, map, or list.

  ## Parameters

  - `name` - The name of the Shortcut to run
  - `opts` - Keyword list of options:
    - `:input` - Input data to pass to the shortcut (string, number, map, or list)

  ## Returns

  - `:ok` - Success with no output
  - `{:ok, output}` - Success with output from the shortcut
  - `{:error, error}` - Failure with error reason

  ## Input Types

  The `:input` option supports various data types:

  - **String**: Passed directly as text
  - **Number**: Passed as a numeric value
  - **Map**: Serialized to JSON and passed as text
  - **List**: Serialized to JSON and passed as text

  ## Examples

      # Without input
      OSAScriptAdapter.run_shortcut("My Shortcut")
      # => :ok

      # With string input
      OSAScriptAdapter.run_shortcut("Process Text", input: "Hello, World!")
      # => {:ok, "processed result"}

      # With number input
      OSAScriptAdapter.run_shortcut("Calculate", input: 42)
      # => {:ok, "84"}

      # With map input (serialized as JSON)
      OSAScriptAdapter.run_shortcut("Process Data", input: %{"name" => "John", "age" => 30})
      # => {:ok, "result"}

      # With list input (serialized as JSON)
      OSAScriptAdapter.run_shortcut("Process Items", input: ["item1", "item2", "item3"])
      # => {:ok, "result"}

  """
  @spec run_shortcut(String.t(), ExMacOSControl.Adapter.options()) ::
          :ok | {:ok, String.t()} | {:error, term()}
  @impl true
  def run_shortcut(name, opts) when is_list(opts) do
    input = Keyword.get(opts, :input)

    script =
      if input do
        serialized = serialize_shortcut_input(input)
        ~s(tell application "Shortcuts Events" to run shortcut "#{name}" with input #{serialized})
      else
        ~s(tell application "Shortcuts Events" to run shortcut "#{name}")
      end

    case run_applescript(script) do
      {:ok, ""} -> :ok
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all available macOS Shortcuts.

  Uses AppleScript to query the Shortcuts app for all shortcuts.

  ## Returns

  - `{:ok, shortcuts}` - Success with list of shortcut names
  - `{:error, error}` - Failure (e.g., Shortcuts app not available)

  ## Examples

      OSAScriptAdapter.list_shortcuts()
      # => {:ok, ["Shortcut 1", "Shortcut 2", "My Shortcut"]}

      # If Shortcuts app is not available
      # => {:error, error}

  """
  @spec list_shortcuts() :: {:ok, [String.t()]} | {:error, term()}
  @impl true
  def list_shortcuts do
    script = ~s(tell application "Shortcuts Events" to return name of every shortcut)

    case run_applescript(script) do
      {:ok, output} ->
        # Parse comma-separated list from AppleScript
        shortcuts =
          output
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, shortcuts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private function to serialize input for shortcut execution
  defp serialize_shortcut_input(input) when is_binary(input) do
    # Escape double quotes in the string and wrap in quotes
    escaped = String.replace(input, "\"", "\\\"")
    ~s("#{escaped}")
  end

  defp serialize_shortcut_input(input) when is_number(input) do
    # Numbers can be passed directly
    to_string(input)
  end

  defp serialize_shortcut_input(input) when is_map(input) do
    # Convert map to JSON and pass as quoted string
    json = Jason.encode!(input)
    escaped = String.replace(json, "\"", "\\\"")
    ~s("#{escaped}")
  end

  defp serialize_shortcut_input(input) when is_list(input) do
    # Convert list to JSON and pass as quoted string
    json = Jason.encode!(input)
    escaped = String.replace(json, "\"", "\\\"")
    ~s("#{escaped}")
  end
end
