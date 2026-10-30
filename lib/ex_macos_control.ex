defmodule ExMacOSControl do
  @moduledoc """
  Facade for macOS automation: AppleScript, JavaScript for Automation (JXA), Shortcuts, etc.

  This module provides a high-level interface for automating macOS using:
  - AppleScript - Apple's scripting language for macOS automation
  - JXA (JavaScript for Automation) - JavaScript-based alternative to AppleScript
  - Script Files - Execute AppleScript and JXA files from disk with automatic language detection
  - Shortcuts - Execute and list macOS Shortcuts with input parameter support

  ## Examples

      # Execute AppleScript
      iex> ExMacOSControl.run_applescript(~s(return "Hello, World!"))
      {:ok, "Hello, World!"}

      # Execute AppleScript with arguments
      iex> script = "on run argv\\nreturn item 1 of argv\\nend run"
      iex> ExMacOSControl.run_applescript(script, args: ["test"])
      {:ok, "test"}

      # Execute JXA
      iex> ExMacOSControl.run_javascript("(function() { return 'Hello from JXA!'; })()")
      {:ok, "Hello from JXA!"}

      # Execute JXA with arguments
      iex> ExMacOSControl.run_javascript("function run(argv) { return argv[0]; }", args: ["test"])
      {:ok, "test"}

  ## Script Files

      # Execute script files with automatic language detection
      ExMacOSControl.run_script_file("/path/to/script.applescript")
      # => {:ok, "result"}

      ExMacOSControl.run_script_file("/path/to/script.js", args: ["arg1", "arg2"])
      # => {:ok, "result"}

  ## Shortcuts

      # Run a Shortcut
      ExMacOSControl.run_shortcut("My Shortcut")
      # => :ok

      # Run a Shortcut with input
      ExMacOSControl.run_shortcut("Process Text", input: "Hello, World!")
      # => {:ok, "processed result"}

      # List available Shortcuts
      ExMacOSControl.list_shortcuts()
      # => {:ok, ["Shortcut 1", "Shortcut 2", "My Shortcut"]}

  """

  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Executes AppleScript code.

  ## Parameters

  - `script` - The AppleScript code to execute

  ## Returns

  - `{:ok, output}` - Success with script output
  - `{:error, reason}` - Failure with error reason

  ## Examples

      iex> ExMacOSControl.run_applescript(~s(return "Hello"))
      {:ok, "Hello"}

  """
  @spec run_applescript(String.t()) :: {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  def run_applescript(script) do
    ExMacOSControl.Composition.guard(fn ->
      case execution_options() do
        [] -> adapter().run_applescript(script)
        opts -> adapter().run_applescript(script, opts)
      end
    end)
  end

  @doc """
  Executes AppleScript code with options.

  ## Options

    * `:timeout` - Maximum time in milliseconds to wait for script execution
    * `:args` - List of string arguments to pass to the script
    * `:output` - `:text` (default), `:source` (AppleScript source representation),
      `:json` (decode returned JSON text), or `:execution` (stdout, stderr and status)
    * `:trim` - Preserve text whitespace when false (default true)
    * `:stdin` - Pass source through stdin; automatic for source larger than 64 KiB
    * `:max_output_bytes` - Combined stdout/stderr limit (default 10 MiB)
    * `:telemetry_script` - Include a source preview in telemetry (default false)

  Raw calls have no default deadline. A timeout terminates the owned process group;
  effects already dispatched to an app can have an unknown outcome.

  ## Examples

  With timeout option:

      ExMacOSControl.run_applescript("delay 1", timeout: 5000)
      # => {:ok, ""}

  With arguments option:

      script = \"\"\"
      on run argv
        return item 1 of argv
      end run
      \"\"\"
      ExMacOSControl.run_applescript(script, args: ["hello"])
      # => {:ok, "hello"}

  With both timeout and args:

      ExMacOSControl.run_applescript(script, args: ["test"], timeout: 5000)
      # => {:ok, "test"}

  """
  @spec run_applescript(String.t(), ExMacOSControl.Adapter.options()) ::
          {:ok, term()} | {:error, ExMacOSControl.Error.t()}
  def run_applescript(script, opts),
    do: ExMacOSControl.Composition.guard(fn -> adapter().run_applescript(script, execution_options(opts)) end)

  @doc """
  Executes JavaScript for Automation (JXA) code.

  ## Parameters

  - `script` - The JXA code to execute

  ## Returns

  - `{:ok, output}` - Success with script output
  - `{:error, reason}` - Failure with error reason

  ## Examples

      iex> ExMacOSControl.run_javascript("(function() { return 'test'; })()")
      {:ok, "test"}

      iex> ExMacOSControl.run_javascript("Application('Finder').running()")
      {:ok, "true"}

  """
  @spec run_javascript(String.t()) :: {:ok, String.t()} | {:error, term()}
  def run_javascript(script) do
    ExMacOSControl.Composition.guard(fn ->
      case execution_options() do
        [] -> adapter().run_javascript(script)
        opts -> adapter().run_javascript(script, opts)
      end
    end)
  end

  @doc """
  Executes JavaScript for Automation (JXA) code with options.

  ## Parameters

  - `script` - The JXA code to execute
  - `opts` - Keyword list of options:
    - `:args` - List of string arguments to pass to the script

  ## Returns

  - `{:ok, output}` - Success with script output
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # With arguments
      iex> script = "function run(argv) { return argv[0]; }"
      iex> ExMacOSControl.run_javascript(script, args: ["hello"])
      {:ok, "hello"}

      # With multiple arguments
      iex> script = "function run(argv) { return argv.join(' '); }"
      iex> ExMacOSControl.run_javascript(script, args: ["hello", "world"])
      {:ok, "hello world"}

  """
  @spec run_javascript(String.t(), ExMacOSControl.Adapter.options()) ::
          {:ok, term()} | {:error, term()}
  def run_javascript(script, opts),
    do: ExMacOSControl.Composition.guard(fn -> adapter().run_javascript(script, execution_options(opts)) end)

  @doc """
  Executes a script file from disk with automatic language detection.

  This function executes AppleScript or JavaScript files directly, with automatic
  language detection based on file extension. It supports all the same options as
  `run_applescript/2` and `run_javascript/2`, including timeout and argument passing.

  ## Parameters

  - `file_path` - Absolute or relative path to the script file

  ## Language Detection

  The language is automatically detected from the file extension:

    * `.applescript` → AppleScript
    * `.scpt`, `.scptd` → Native compiled language (including script bundles)
    * `.js`, `.jxa` → JavaScript

  ## Returns

  - `{:ok, output}` - Success with script output
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Execute AppleScript file
      ExMacOSControl.run_script_file("/path/to/script.applescript")
      # => {:ok, "result"}

      # Execute JavaScript file
      ExMacOSControl.run_script_file("/path/to/script.js")
      # => {:ok, "result"}

  """
  @spec run_script_file(String.t()) :: {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  def run_script_file(file_path), do: run_script_file(file_path, [])

  @doc """
  Executes a script file from disk with options.

  This function executes AppleScript or JavaScript files directly, with automatic
  language detection based on file extension. You can override the language detection
  and pass arguments and timeout options.

  ## Parameters

  - `file_path` - Absolute or relative path to the script file
  - `opts` - Keyword list of options:
    - `:language` - Explicit language (`:applescript` or `:javascript`), overrides detection
    - `:timeout` - Maximum time in milliseconds to wait for execution
    - `:args` - List of string arguments to pass to the script

  ## Language Detection

  The language is automatically detected from the file extension:

    * `.applescript` → AppleScript
    * `.scpt`, `.scptd` → Native compiled language (including script bundles)
    * `.js`, `.jxa` → JavaScript

  You can override automatic detection using the `:language` option.

  ## Returns

  - `{:ok, output}` - Success with script output
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Override language detection
      ExMacOSControl.run_script_file("/path/to/script.txt", language: :applescript)
      # => {:ok, "result"}

      # With arguments
      ExMacOSControl.run_script_file(
        "/path/to/script.applescript",
        args: ["arg1", "arg2"]
      )
      # => {:ok, "result"}

      # With timeout
      ExMacOSControl.run_script_file("/path/to/script.js", timeout: 5000)
      # => {:ok, "result"}

      # Combined options
      ExMacOSControl.run_script_file(
        "/path/to/script.scpt",
        language: :applescript,
        args: ["test"],
        timeout: 10_000
      )
      # => {:ok, "result"}

  """
  @spec run_script_file(String.t(), ExMacOSControl.Adapter.options()) ::
          {:ok, term()} | {:error, ExMacOSControl.Error.t()}
  def run_script_file(file_path, opts),
    do: ExMacOSControl.Composition.guard(fn -> adapter().run_script_file(file_path, execution_options(opts)) end)

  @doc """
  Executes a macOS Shortcut by name.

  ## Parameters

  - `name` - The name of the Shortcut to run

  ## Returns

  - `:ok` - Success with no output
  - `{:ok, output}` - Success with output from the shortcut
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Assuming you have a shortcut named "My Shortcut"
      ExMacOSControl.run_shortcut("My Shortcut")
      # => :ok (if shortcut exists and returns no output)
      # => {:ok, "result"} (if shortcut returns output)
      # => {:error, reason} (if not found)

  """
  @spec run_shortcut(String.t()) :: :ok | {:ok, String.t()} | {:error, term()}
  def run_shortcut(name) do
    ExMacOSControl.Composition.guard(fn ->
      case execution_options() do
        [] -> adapter().run_shortcut(name)
        opts -> adapter().run_shortcut(name, opts)
      end
    end)
  end

  @doc """
  Executes a macOS Shortcut by name with input parameters.

  ## Parameters

  - `name` - The name of the Shortcut to run
  - `opts` - Keyword list of options:
    - `:input` - Input data to pass to the shortcut (string, number, map, or list)

  ## Returns

  - `:ok` - Success with no output
  - `{:ok, output}` - Success with output from the shortcut
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # With string input
      ExMacOSControl.run_shortcut("Process Text", input: "Hello, World!")
      # => {:ok, "processed result"}

      # With number input
      ExMacOSControl.run_shortcut("Calculate", input: 42)
      # => {:ok, "84"}

      # With map input (serialized as JSON)
      ExMacOSControl.run_shortcut("Process Data", input: %{"name" => "John", "age" => 30})
      # => {:ok, "result"}

      # With list input (serialized as JSON)
      ExMacOSControl.run_shortcut("Process Items", input: ["item1", "item2", "item3"])
      # => {:ok, "result"}

  """
  @spec run_shortcut(String.t(), ExMacOSControl.Adapter.options()) ::
          :ok | {:ok, String.t()} | {:error, term()}
  def run_shortcut(name, opts),
    do: ExMacOSControl.Composition.guard(fn -> adapter().run_shortcut(name, execution_options(opts)) end)

  @doc """
  Lists all available macOS Shortcuts.

  ## Returns

  - `{:ok, shortcuts}` - Success with list of shortcut names
  - `{:error, reason}` - Failure (e.g., Shortcuts app not available)

  ## Examples

      ExMacOSControl.list_shortcuts()
      # => {:ok, ["Shortcut 1", "Shortcut 2", "My Shortcut"]}

      # Check if a specific shortcut exists
      case ExMacOSControl.list_shortcuts() do
        {:ok, shortcuts} ->
          if "My Shortcut" in shortcuts do
            ExMacOSControl.run_shortcut("My Shortcut")
          end
        {:error, reason} ->
          {:error, reason}
      end

  """
  @spec list_shortcuts() :: {:ok, [String.t()]} | {:error, term()}
  def list_shortcuts, do: adapter().list_shortcuts()

  @doc "Applies execution deadlines and output limits to app calls in the current process. Nested scopes restore prior options."
  def with_options(opts, fun) when is_function(fun, 0) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:timeout, :max_output_bytes]) do
      key = {__MODULE__, :options}
      previous = Process.get(key, [])
      Process.put(key, Keyword.merge(previous, opts))

      try do
        fun.()
      after
        Process.put(key, previous)
      end
    end
  end

  @doc false
  def execution_options(opts \\ []),
    do: Process.get({__MODULE__, :options}, []) |> Keyword.merge(opts) |> ExMacOSControl.Composition.cap_options()
end
