defmodule ExMacOSControl do
  @moduledoc """
  Facade for macOS automation: AppleScript, Shortcuts, etc.
  """

  @doc """
  Hello world.

  ## Examples

      iex> ExMacOSControl.run_applescript(~s(return "Hello, World!"))
      {:ok, "Hello, World!"}

  """

  @adapter Application.compile_env(
             :ex_macos_control,
             :adapter,
             ExMacOSControl.OSAScriptAdapter
           )

  def run_applescript(script), do: @adapter.run_applescript(script)
  def run_shortcut(name), do: @adapter.run_shortcut(name)
end
