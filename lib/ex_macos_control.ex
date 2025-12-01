defmodule ExMacOSControl do
  @moduledoc """
  Facade for macOS automation: AppleScript, JavaScript for Automation (JXA), Shortcuts, etc.

  This module provides a high-level interface for automating macOS using:
  - AppleScript - Apple's scripting language for macOS automation
  - JXA (JavaScript for Automation) - JavaScript-based alternative to AppleScript
  - Script Files - Execute AppleScript and JXA files from disk with automatic language detection
  - Shortcuts - Execute macOS Shortcuts

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

      # Execute script files with automatic language detection
      # ExMacOSControl.run_script_file("/path/to/script.applescript")
      # => {:ok, "result"}

      # ExMacOSControl.run_script_file("/path/to/script.js", args: ["arg1", "arg2"])
      # => {:ok, "result"}

  """

  @adapter Application.compile_env(
             :ex_macos_control,
             :adapter,
             ExMacOSControl.OSAScriptAdapter
           )

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
  def run_applescript(script), do: @adapter.run_applescript(script)

  @doc """
  Executes AppleScript code with options.

  ## Options

    * `:timeout` - Maximum time in milliseconds to wait for script execution
    * `:args` - List of string arguments to pass to the script

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
          {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  def run_applescript(script, opts), do: @adapter.run_applescript(script, opts)

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
  def run_javascript(script), do: @adapter.run_javascript(script)

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
          {:ok, String.t()} | {:error, term()}
  def run_javascript(script, opts), do: @adapter.run_javascript(script, opts)

  @doc """
  Executes a script file from disk with automatic language detection.

  This function executes AppleScript or JavaScript files directly, with automatic
  language detection based on file extension. It supports all the same options as
  `run_applescript/2` and `run_javascript/2`, including timeout and argument passing.

  ## Parameters

  - `file_path` - Absolute or relative path to the script file

  ## Language Detection

  The language is automatically detected from the file extension:

    * `.scpt`, `.applescript` → AppleScript
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
  def run_script_file(file_path), do: @adapter.run_script_file(file_path, [])

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

    * `.scpt`, `.applescript` → AppleScript
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
          {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  def run_script_file(file_path, opts), do: @adapter.run_script_file(file_path, opts)

  @doc """
  Executes a macOS Shortcut by name.

  ## Parameters

  - `name` - The name of the Shortcut to run

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Assuming you have a shortcut named "My Shortcut"
      ExMacOSControl.run_shortcut("My Shortcut")
      # => :ok (if shortcut exists) or {:error, reason} (if not found)

  """
  @spec run_shortcut(String.t()) :: :ok | {:error, term()}
  def run_shortcut(name), do: @adapter.run_shortcut(name)
end
