defmodule ExMacOSControl.LiveEvidenceFormatter do
  @moduledoc false
  use GenServer
  alias ExMacOSControl.LiveEvidence

  def register(context, session), do: :persistent_term.put({__MODULE__, context.module, context.test}, session)
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def init(_opts), do: {:ok, nil}

  @impl true
  def handle_cast({:test_finished, test}, state) do
    key = {__MODULE__, test.module, test.name}

    case :persistent_term.get(key, nil) do
      nil ->
        :ok

      session ->
        :persistent_term.erase(key)
        event = if match?({:failed, _}, test.state), do: "case_failed", else: "case_finished"
        LiveEvidence.event(session, event)
        LiveEvidence.finish(session)
    end

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
