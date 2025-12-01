defmodule ExMacOSControl do
  @moduledoc """
  Facade for macOS automation: AppleScript, Shortcuts, etc.
  """

  @adapter Application.compile_env(
             :ex_macos_control,
             :adapter,
             ExMacOSControl.OSAScriptAdapter
           )

  @doc """
  Runs an AppleScript script.

  ## Examples

      iex> ExMacOSControl.run_applescript(~s(return "Hello, World!"))
      {:ok, "Hello, World!"}

  """
  @spec run_applescript(String.t()) :: {:ok, String.t()} | {:error, ExMacOSControl.Error.t()}
  def run_applescript(script), do: @adapter.run_applescript(script)

  @doc """
  Runs an AppleScript script with options.

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

  @spec run_shortcut(String.t()) :: :ok | {:error, term()}
  def run_shortcut(name), do: @adapter.run_shortcut(name)
end
