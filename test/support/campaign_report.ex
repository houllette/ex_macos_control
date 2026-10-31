defmodule ExMacOSControl.CampaignReport do
  @moduledoc false
  alias ExMacOSControl.{Composition, LiveEvidence}

  def build(root) do
    runs = root |> Path.join("*/manifest.json") |> Path.wildcard() |> Enum.map(&read_run/1)
    runs = Enum.sort_by(runs, &{&1.started_at || "", &1.marker || ""})
    latest = runs |> Map.new(&{{&1.case, &1.macos, &1.apps}, &1}) |> Map.values() |> Enum.sort_by(& &1.case)

    %{
      schema: 1,
      generated_at: DateTime.to_iso8601(DateTime.utc_now()),
      runs: runs,
      totals: Enum.frequencies_by(runs, & &1.status),
      latest_per_configuration: latest,
      latest_totals: Enum.frequencies_by(latest, & &1.status)
    }
  end

  defp read_run(path) do
    manifest = read_manifest(path)
    root = Path.dirname(path)
    evidence = read_evidence(root)
    journals = Path.wildcard(Path.join(root, "execution/*.jsonl")) |> Enum.map(&journal_summary/1)

    %{
      case: manifest["case"] || "unreadable manifest",
      marker: manifest["marker"],
      revision: manifest["revision"],
      source_sha256: manifest["source_sha256"],
      mode: manifest["mode"] || "qualification",
      macos: get_in(manifest, ["host", "macos"]),
      apps:
        Map.new(manifest["apps"] || %{}, fn {id, fields} ->
          {id, Map.take(fields, ["bundle_id", "version", "build", "status"])}
        end),
      status: if(manifest == %{}, do: :unverified, else: compatibility_status(evidence.status)),
      evidence_status: evidence.status,
      unresolved_resources: length(evidence.pending),
      resources: length(evidence.resources),
      iterations_started: Enum.count(evidence.events, &(&1["event"] == "iteration_started")),
      iterations_verified: Enum.count(evidence.events, &(&1["event"] == "iteration_verified")),
      journals: length(journals),
      pending_journal_steps: Enum.sum(Enum.map(journals, & &1.pending)),
      unreadable_journals: Enum.count(journals, & &1.unreadable),
      latency_ms: latency(Enum.flat_map(journals, & &1.durations)),
      observations: observations(evidence.events),
      started_at: evidence.events |> List.first(%{}) |> Map.get("at", manifest_time(path)),
      last_activity: evidence.events |> List.last(%{}) |> Map.get("at")
    }
  end

  defp manifest_time(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime |> DateTime.from_unix!() |> DateTime.to_iso8601()
      _ -> nil
    end
  end

  defp read_manifest(path) do
    with {:ok, text} <- File.read(path),
         {:ok, value} when is_map(value) <- Jason.decode(text),
         do: value,
         else: (_ -> %{})
  end

  defp read_evidence(root) do
    case LiveEvidence.inspect_session(root) do
      {:ok, evidence} -> evidence
      _ -> %{status: :unverified, pending: [], resources: [], events: []}
    end
  end

  defp compatibility_status(:needs_reconciliation), do: :failed
  defp compatibility_status(status), do: status

  defp observations(events) do
    events
    |> Enum.filter(&(&1["event"] == "verified"))
    |> Enum.map(&Map.take(&1, ["repeats", "batch_sizes", "ambiguous_dates", "expected_unknown", "recurring_delete"]))
  end

  defp journal_summary(path) do
    case Composition.Journal.inspect_run(path) do
      {:ok, summary} -> %{pending: length(summary.pending), durations: run_durations(summary.events), unreadable: false}
      {:error, _} -> %{pending: 1, durations: [], unreadable: true}
    end
  end

  defp run_durations(events) do
    for %{"event" => "run_finished", "duration" => duration} <- events,
        is_integer(duration) and duration >= 0,
        do: System.convert_time_unit(duration, :native, :millisecond)
  end

  defp latency([]), do: %{samples: 0}

  defp latency(durations) do
    sorted = Enum.sort(durations)
    count = length(sorted)
    base = %{samples: count, median: Enum.at(sorted, div(count, 2)), maximum: List.last(sorted)}
    if count >= 20, do: Map.put(base, :p95, Enum.at(sorted, ceil(count * 0.95) - 1)), else: base
  end
end
