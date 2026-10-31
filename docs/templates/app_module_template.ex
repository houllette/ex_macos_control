defmodule ExMacOSControl.AppName do
  @moduledoc """
  Example scripting wrapper. Replace the bundle ID and operation before use.

  Native reads can launch the app and require Automation permission. Raw facade
  calls have no default deadline; pass timeout or use an enclosing composition.
  """

  @doc "Reads the app name through JXA. Accepts facade JXA execution options."
  @spec name(ExMacOSControl.Adapter.options()) ::
          {:ok, term()} | {:error, ExMacOSControl.Error.t()}
  def name(opts \\ []) do
    ExMacOSControl.run_javascript("Application('com.example.AppName').name()", opts)
  end
end
