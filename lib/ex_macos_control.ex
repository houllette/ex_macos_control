defmodule ExMacOSControl do
  @moduledoc """
  Facade for macOS automation: AppleScript, JavaScript for Automation (JXA), Shortcuts, etc.

  This module provides a high-level interface for automating macOS using:
  - AppleScript - Apple's scripting language for macOS automation
  - JXA (JavaScript for Automation) - JavaScript-based alternative to AppleScript
  - Shortcuts - Execute macOS Shortcuts

  ## Examples

      # Execute AppleScript
      iex> ExMacOSControl.run_applescript(~s(return "Hello, World!"))
      {:ok, "Hello, World!"}

      # Execute JXA
      iex> ExMacOSControl.run_javascript("(function() { return 'Hello from JXA!'; })()")
      {:ok, "Hello from JXA!"}

      # Execute JXA with arguments
      iex> ExMacOSControl.run_javascript("function run(argv) { return argv[0]; }", args: ["test"])
      {:ok, "test"}

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
  @spec run_applescript(String.t()) :: {:ok, String.t()} | {:error, term()}
  def run_applescript(script), do: @adapter.run_applescript(script)

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
  @spec run_javascript(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run_javascript(script, opts), do: @adapter.run_javascript(script, opts)

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
