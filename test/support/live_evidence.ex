defmodule ExMacOSControl.LiveEvidence do
  @moduledoc false

  def open(root, manifest) do
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    File.write!(Path.join(root, "manifest.json"), Jason.encode!(manifest), [:exclusive, :sync])
    File.chmod!(Path.join(root, "manifest.json"), 0o600)
    %{root: root, marker: manifest.marker}
  end

  def event(session, name, data \\ %{}) do
    record = Map.merge(data, %{event: name, at: DateTime.to_iso8601(DateTime.utc_now()), marker: session.marker})
    path = Path.join(session.root, "events.jsonl")
    File.write!(path, Jason.encode!(record) <> "\n", [:append, :sync])
    File.chmod!(path, 0o600)
    :ok
  end

  def intent(session, kind, identity \\ %{}) do
    id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    event(session, "resource_intent", %{intent_id: id, kind: kind, identity: identity})
    id
  end

  def inspect_session(root) do
    with {:ok, text} <- File.read(Path.join(root, "events.jsonl")),
         {:ok, records} <- decode(text) do
      intents = Enum.filter(records, &(&1["event"] in ["resource_intent", "owned"]))
      resolved = Enum.filter(records, &(&1["event"] in ["cleanup_verified", "resource_not_started"]))
      resolved_ids = MapSet.new(resolved, & &1["intent_id"])

      pending =
        intents
        |> Enum.reject(&MapSet.member?(resolved_ids, &1["intent_id"]))
        |> Enum.reduce(%{}, fn record, acc -> Map.update(acc, record["intent_id"], record, &Map.merge(&1, record)) end)
        |> Map.values()

      {:ok,
       %{
         status: status(records, pending),
         pending: pending,
         events: records,
         resources: Enum.filter(records, &(&1["event"] == "owned"))
       }}
    end
  end

  def finish(session) do
    {:ok, summary} = inspect_session(session.root)
    File.write!(Path.join(session.root, "summary.json"), Jason.encode!(Map.delete(summary, :events)), [:sync])
    File.chmod!(Path.join(session.root, "summary.json"), 0o600)
    summary
  end

  def cleanup(session, intent, cleanup, verify, opts \\ [timeout: 15_000, interval: 100]) do
    event(session, "cleanup_intent", %{intent_id: intent})
    result = attempt_cleanup(cleanup, verify, opts)
    event(session, if(result == :ok, do: "cleanup_verified", else: "cleanup_failed"), %{intent_id: intent})
    result
  end

  defp attempt_cleanup(cleanup, verify, opts) when is_function(verify, 0) do
    with :ok <- cleanup.(), do: ExMacOSControl.Wait.until(verify, opts)
  rescue
    _ -> {:error, :cleanup_raised}
  catch
    _, _ -> {:error, :cleanup_exited}
  end

  defp attempt_cleanup(_cleanup, _verify, _opts), do: {:error, :missing_absence_verifier}

  defp decode(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, records} ->
      case Jason.decode(line) do
        {:ok, record} -> {:cont, {:ok, records ++ [record]}}
        _ -> {:halt, {:error, :invalid_evidence}}
      end
    end)
  end

  defp status(_records, [_ | _]), do: :needs_reconciliation

  defp status(records, []) do
    cond do
      Enum.any?(records, &(&1["event"] in ["effect_failed", "cleanup_failed", "case_failed"])) -> :failed
      Enum.any?(records, &(&1["event"] == "verified")) -> :passed
      Enum.any?(records, &(&1["event"] == "unavailable")) -> :unavailable
      true -> :unverified
    end
  end
end
