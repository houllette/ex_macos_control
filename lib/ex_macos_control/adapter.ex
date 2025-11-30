defmodule ExMacOSControl.Adapter do
  @callback run_applescript(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback run_shortcut(String.t()) :: :ok | {:error, term()}
end
