defmodule ExMacOSControl.CampaignReportTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.{CampaignReport, LiveEvidence}

  setup do
    root = Path.expand("tmp/report-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "history retains failures while compatibility uses the latest version-specific result", %{root: root} do
    first = session(root, "first", "26.0")
    LiveEvidence.event(first, "effect_failed")
    second = session(root, "second", "26.0")
    LiveEvidence.event(second, "verified", %{repeats: 10})
    other = session(root, "third", "25.0")
    LiveEvidence.event(other, "unavailable")
    # Later reconciliation must not make an old failed qualification look newest.
    LiveEvidence.event(first, "cleanup_verified", %{intent_id: "old"})
    report = CampaignReport.build(root)
    assert length(report.runs) == 3
    assert report.totals == %{failed: 1, passed: 1, unavailable: 1}
    assert report.latest_totals == %{passed: 1, unavailable: 1}
  end

  test "support reports omit bodies, recipient addresses, paths, resource IDs and raw errors", %{root: root} do
    live = session(root, "privacy", "26.0")
    intent = LiveEvidence.intent(live, :note, %{path: "/private/source"})

    LiveEvidence.event(live, "owned", %{
      intent_id: intent,
      id: "secret-native-id",
      body: "private-body",
      to: "private@example.invalid"
    })

    LiveEvidence.event(live, "case_failed", %{message: "private-error"})
    LiveEvidence.event(live, "verified", %{recurring_delete: :uncertain_remaining, body: "private-body"})
    report = CampaignReport.build(root)
    assert [%{status: :failed, unresolved_resources: 1}] = report.runs
    assert [%{observations: [%{"recurring_delete" => "uncertain_remaining"}]}] = report.runs
    encoded = Jason.encode!(report)

    for secret <- [
          "/private/source",
          "secret-native-id",
          "private-body",
          "private@example.invalid",
          "private-error",
          "private-app-path"
        ],
        do: refute(encoded =~ secret)
  end

  test "interrupted and malformed evidence remains unverified", %{root: root} do
    session(root, "never-started", "26.0")
    live = session(root, "truncated", "26.0")
    File.write!(Path.join(live.root, "events.jsonl"), "{truncated")
    report = CampaignReport.build(root)
    assert report.totals == %{unverified: 2}
    assert Enum.all?(report.runs, &(&1.latency_ms == %{samples: 0}))
  end

  defp session(root, marker, macos) do
    LiveEvidence.open(Path.join(root, marker), %{
      marker: marker,
      case: "fixture case",
      revision: "fixture",
      mode: "warm",
      host: %{macos: macos},
      apps: %{
        "com.apple.Notes" => %{bundle_id: "com.apple.Notes", version: "4.0", build: "1", path: "private-app-path"}
      }
    })
  end
end
