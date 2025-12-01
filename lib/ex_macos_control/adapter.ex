defmodule ExMacOSControl.Adapter do
  @moduledoc """
  Behaviour defining the adapter interface for macOS automation.

  This behaviour defines the callbacks that must be implemented by adapter modules
  to provide macOS automation functionality. Adapters are responsible for executing
  AppleScript code, JavaScript for Automation (JXA) code, and running Shortcuts on macOS.

  The default implementation is `ExMacOSControl.OSAScriptAdapter`, which uses the
  `osascript` command-line tool. Alternative implementations can be provided for
  testing or to support different execution strategies.
  """

  @callback run_applescript(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback run_javascript(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback run_javascript(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback run_shortcut(String.t()) :: :ok | {:error, term()}
end
