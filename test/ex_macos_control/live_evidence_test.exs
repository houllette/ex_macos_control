defmodule ExMacOSControl.LiveEvidenceTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.LiveEvidence, as: Evidence

  setup do
    root = Path.expand("tmp/evidence-#{System.unique_integer([:positive])}")
    session = Evidence.open(root, %{marker: "fixture", case: "owned resources"})
    on_exit(fn -> File.rm_rf!(root) end)
    %{session: session}
  end

  test "lost creation responses retain a locator even after the creator dies", %{session: session} do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        intent = Evidence.intent(session, :note, %{parent_id: "folder"})
        send(parent, {:intent, intent})

        receive do
          :never -> :ok
        end
      end)

    assert_receive {:intent, intent}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert {:ok, %{status: :needs_reconciliation, pending: [pending]}} = Evidence.inspect_session(session.root)
    assert pending["intent_id"] == intent
    assert pending["identity"] == %{"parent_id" => "folder"}
  end

  test "cleanup acknowledgement alone does not prove absence", %{session: session} do
    intent = Evidence.intent(session, :note)
    Evidence.event(session, "owned", %{intent_id: intent, id: "note"})
    Evidence.event(session, "cleanup_intent", %{intent_id: intent})
    Evidence.event(session, "verified")
    assert Evidence.finish(session).status == :needs_reconciliation
    Evidence.event(session, "cleanup_verified", %{intent_id: intent})
    assert Evidence.finish(session).status == :passed
  end

  test "cleanup failure and the original failure both survive", %{session: session} do
    intent = Evidence.intent(session, :note)
    Evidence.event(session, "effect_failed", %{run_id: "run"})
    Evidence.event(session, "cleanup_failed", %{intent_id: intent})
    assert {:ok, %{status: :needs_reconciliation, events: events}} = Evidence.inspect_session(session.root)
    assert Enum.any?(events, &(&1["event"] == "effect_failed"))
    assert Enum.any?(events, &(&1["event"] == "cleanup_failed"))
  end

  test "unavailable prerequisites remain distinct from a pass", %{session: session} do
    Evidence.event(session, "unavailable", %{reason: :missing_fixture})
    assert Evidence.finish(session).status == :unavailable
    assert_raise File.Error, fn -> Evidence.open(session.root, %{marker: "fixture"}) end
  end

  test "a raised cleanup is recorded and does not masquerade as verified absence", %{session: session} do
    intent = Evidence.intent(session, :note)
    assert {:error, :cleanup_raised} = Evidence.cleanup(session, intent, fn -> raise "private body" end, fn -> true end)
    assert {:ok, %{status: :needs_reconciliation, events: events}} = Evidence.inspect_session(session.root)
    assert Enum.any?(events, &(&1["event"] == "cleanup_failed"))
    refute Jason.encode!(events) =~ "private body"
  end
end
