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

  @type option ::
          {:timeout, pos_integer()}
          | {:args, [String.t()]}
          | {:input, String.t() | number() | map() | list()}

  @type options :: [option()]

  @callback run_applescript(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback run_applescript(String.t(), options()) :: {:ok, String.t()} | {:error, term()}
  @callback run_javascript(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback run_javascript(String.t(), options()) :: {:ok, String.t()} | {:error, term()}
  @callback run_shortcut(String.t()) :: :ok | {:ok, String.t()} | {:error, term()}
  @callback run_shortcut(String.t(), options()) :: :ok | {:ok, String.t()} | {:error, term()}
  @callback list_shortcuts() :: {:ok, [String.t()]} | {:error, term()}
end
