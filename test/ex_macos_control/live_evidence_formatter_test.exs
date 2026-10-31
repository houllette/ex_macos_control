defmodule ExMacOSControl.LiveEvidenceFormatterTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.{LiveEvidence, LiveEvidenceFormatter}

  test "a test assertion failure after verification cannot become a reported pass" do
    root = Path.expand("tmp/formatter-#{System.unique_integer([:positive])}")
    session = LiveEvidence.open(root, %{marker: "fixture"})
    on_exit(fn -> File.rm_rf!(root) end)
    test_name = :"fixture #{System.unique_integer([:positive])}"
    LiveEvidenceFormatter.register(%{module: __MODULE__, test: test_name}, session)
    LiveEvidence.event(session, "verified")
    assert LiveEvidence.finish(session).status == :passed
    formatter = start_supervised!({LiveEvidenceFormatter, []})
    GenServer.cast(formatter, {:test_finished, %ExUnit.Test{module: __MODULE__, name: test_name, state: {:failed, []}}})
    :sys.get_state(formatter)
    assert {:ok, %{status: :failed}} = LiveEvidence.inspect_session(root)
    assert %{"status" => "failed"} = Jason.decode!(File.read!(Path.join(root, "summary.json")))
    # Repeated formatter delivery cannot append a second completion record.
    GenServer.cast(formatter, {:test_finished, %ExUnit.Test{module: __MODULE__, name: test_name, state: nil}})
    :sys.get_state(formatter)
    assert {:ok, %{events: events}} = LiveEvidence.inspect_session(root)
    assert Enum.count(events, &(&1["event"] == "case_failed")) == 1
    refute Enum.any?(events, &(&1["event"] == "case_finished"))
  end
end
