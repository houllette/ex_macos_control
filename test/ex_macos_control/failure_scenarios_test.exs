defmodule ExMacOSControl.FailureScenariosTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.{Composition, Error}
  alias ExMacOSControl.Composition.Journal

  setup do
    root = Path.expand("tmp/failure-scenarios-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, journal: Path.join(root, "journal")}
  end

  for mode <- [:execution_error, :timeout, :malformed, :raise] do
    test "a persisted #{mode} remains observable and is never replayed", %{journal: journal} do
      {:ok, store} = Agent.start_link(fn -> [] end)

      operation = fn ->
        Agent.update(store, &["native-id" | &1])

        case unquote(mode) do
          :execution_error -> {:error, Error.execution_error("failed after commit")}
          :timeout -> {:error, Error.timeout("lost reply", outcome: :unknown)}
          :malformed -> :invalid_acknowledgement
          :raise -> raise "callback raised after persistence"
        end
      end

      run = fn ->
        Composition.run(fn -> Composition.effect(:create, operation, resource: :fixture) end, journal: journal)
      end

      if unquote(mode) == :raise do
        assert_raise RuntimeError, run
      else
        assert {:error, %{details: %{outcome: :unknown}}} = run.()
      end

      assert Agent.get(store, & &1) == ["native-id"]
      [path] = Path.wildcard(Path.join(journal, "*.jsonl"))
      assert {:ok, %{status: :needs_reconciliation, pending: [_]}} = Journal.inspect_run(path)
      assert Agent.get(store, & &1) == ["native-id"]
    end
  end

  test "a lost result-sync retains the acknowledged ID and root correlation", %{journal: journal} do
    assert {:error, error} =
             Composition.run(
               fn ->
                 Composition.effect(
                   :create,
                   fn ->
                     File.close(Composition.capture_context().journal.io)
                     {:ok, "created-id"}
                   end,
                   resource: :fixture
                 )
               end,
               journal: journal
             )

    assert error.details.acknowledged_result == {:ok, "created-id"}
    assert error.details.recovery_status == :needs_reconciliation
    assert {:ok, %{status: :needs_reconciliation}} = Journal.inspect_run(error.details.journal_path)
  end

  test "long valid journals remain inspectable with an explicit memory bound", %{root: root} do
    path = Path.join(root, "long.jsonl")

    events =
      for index <- 1..13_000 do
        Jason.encode!(%{
          event: "observation",
          run_id: "fixture",
          index: index,
          duration: 1000,
          parent_step_id: String.duplicate("a", 32),
          step_id: String.duplicate("b", 32)
        }) <> "\n"
      end

    File.write!(path, [
      events,
      Jason.encode!(%{event: "run_finished", outcome: "acknowledged", run_id: "fixture"}) <> "\n"
    ])

    File.chmod!(path, 0o600)
    assert File.stat!(path).size > 2_097_152
    assert {:ok, %{status: :complete}} = Journal.inspect_run(path)
    assert {:error, _} = Journal.inspect_run(path, max_bytes: 2_097_152)
  end

  test "batch identities remain durable and resource results grow linearly", %{journal: journal} do
    ids = Enum.map(1..1000, &"id-#{&1}")

    assert {:ok, ^ids} =
             Composition.run(
               fn ->
                 Composition.effect(:bulk, fn -> {:ok, ids} end,
                   resource: :reminder,
                   identity: %{list_id: "list", ids: ids}
                 )
               end,
               journal: journal
             )

    [path] = Path.wildcard(Path.join(journal, "*.jsonl"))
    assert {:ok, %{resources: resources, events: events}} = Journal.inspect_run(path)
    assert length(resources) == 1000
    refute Enum.any?(resources, &Map.has_key?(&1, "ids"))
    assert Enum.find(events, &(&1["event"] == "step_started"))["resource"]["identity"]["ids"] == ids
    assert File.stat!(path).size < 300_000
  end
end
