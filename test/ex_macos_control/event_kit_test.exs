defmodule ExMacOSControl.EventKitTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.Composition.Journal
  alias ExMacOSControl.EventKit
  alias ExMacOSControl.EventKit.{Reference, Reminders}

  setup do
    root = Path.expand("tmp/eventkit-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    helper = Path.join(root, "helper")
    File.cp!("test/support/fixtures/eventkit_helper.py", helper)
    File.chmod!(helper, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      opts: [helper: helper, journal: Path.join(root, "journal")],
      list: %Reference{kind: :reminder_list, id: "list"}
    }
  end

  test "status is explicit and correlation rejects an unrelated response", %{root: root, opts: opts} do
    assert {:ok, %{"event" => "not_determined"}} = EventKit.status(opts)
    File.write!(Path.join(root, "mode"), "wrong_request")
    assert {:error, %{details: %{outcome: :unknown}}} = EventKit.status(opts)
    assert {:error, %{details: %{outcome: :not_started}}} = EventKit.status(helper: Path.join(root, "missing"))
  end

  test "all deterministic items and mixed backend references reject before dispatch", %{
    root: root,
    opts: opts,
    list: list
  } do
    assert {:error, _} = Reminders.create_many(list, [[title: "valid"], [title: "invalid", priority: 10]], opts)
    assert {:error, _} = Reminders.complete_many(["x-apple-reminder://native"], opts)
    assert {:error, _} = Reminders.create_many("list", [[title: "wrong namespace"]], opts)
    refute File.exists?(Path.join(root, "state.json"))
  end

  test "batches retain durable identities and independently read completion", %{root: root, opts: opts, list: list} do
    assert {:ok, items} =
             Reminders.create_many(list, Enum.map(1..12, &[title: "item #{&1}"]), Keyword.put(opts, :batch_size, 5))

    assert length(items) == 12
    assert {:ok, complete} = Reminders.complete_many(Enum.map(items, & &1.ref), opts)
    assert Enum.all?(complete, & &1.completed)
    assert Jason.decode!(File.read!(Path.join(root, "state.json")))["mutations"] == 4

    resources =
      Path.wildcard(Path.join(root, "journal/*.jsonl"))
      |> Enum.flat_map(fn path ->
        {:ok, r} = Journal.inspect_run(path)
        r.resources
      end)

    assert Enum.all?(Enum.map(items, & &1.id), fn id -> Enum.any?(resources, &(&1["id"] == id)) end)
  end

  test "persistence then malformed acknowledgement stays unknown and never replays", %{
    root: root,
    opts: opts,
    list: list
  } do
    File.write!(Path.join(root, "mode"), "lost_reply")

    assert {:error, error} =
             Reminders.create_many(list, [[title: "persisted"], [title: "later"]], Keyword.put(opts, :batch_size, 1))

    assert error.details.recovery_status == :needs_reconciliation
    state = Jason.decode!(File.read!(Path.join(root, "state.json")))
    assert state["mutations"] == 1 and map_size(state["items"]) == 1
    assert {:ok, summary} = Journal.inspect_run(error.details.journal_path)
    assert Enum.any?(summary.pending, &(get_in(&1, ["resource", "identity", "calendar_id"]) == "list"))
  end

  test "wrong completion identities remain uncertain inside the mutation span", %{root: root, opts: opts, list: list} do
    assert {:ok, [item]} = Reminders.create_many(list, [[title: "one"]], opts)
    File.write!(Path.join(root, "mode"), "wrong_identity")
    assert {:error, error} = Reminders.complete_many([item.ref], opts)
    assert error.details.recovery_status == :needs_reconciliation
    assert {:ok, %{pending: [_ | _]}} = Journal.inspect_run(error.details.journal_path)
  end

  test "malformed post-write resources never report not started" do
    assert {:error, %{details: %{outcome: :unknown}}} = EventKit.record(%{"ref" => %{}})

    assert {:error, %{details: %{outcome: :unknown}}} =
             EventKit.record(%{
               "ref" => %{"backend" => "eventkit", "kind" => "reminder", "id" => "id", "calendar_id" => "list"}
             })

    assert {:error, _} = Reference.validate(%Reference{kind: :event, id: "id"}, :reminder)
  end
end
