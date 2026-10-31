defmodule ExMacOSControl.Composition.Context do
  @moduledoc """
  An explicitly transferable execution context. Tasks must be joined inside the
  originating run when sharing its journal. Deadlines remain absolute; desktop
  locks and completed-result lists are never transferred.
  """
  @enforce_keys [:deadline, :run_id]
  defstruct [:deadline, :run_id, :trace_to, :journal, :span_id, :progress, completed: [], execution: []]
  @key {ExMacOSControl.Composition, :context}
  def current, do: Process.get(@key)

  def in_span(id, fun) do
    previous = current()
    Process.put(@key, %{previous | span_id: id})

    try do
      fun.()
    after
      context = current()
      Process.put(@key, %{context | span_id: previous.span_id})
    end
  end
end
