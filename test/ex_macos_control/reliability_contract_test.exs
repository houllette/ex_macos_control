defmodule ExMacOSControl.ReliabilityContractTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Composition, Error, ImageEvents, Reminders, Workflows}
  alias ExMacOSControl.Composition.Journal
  setup :verify_on_exit!

  setup do
    root = Path.expand("tmp/reliability-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, journal: Path.join(root, "journal")}
  end

  test "persisted batch effects remain reconcilable after a non-timeout failure", %{root: root, journal: journal} do
    evidence = Path.join(root, "persisted")
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("first-id") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      File.write!(evidence, "second item persisted")
      {:error, Error.execution_error("failure after persistence")}
    end)

    assert {:error, error} =
             Composition.run(
               fn ->
                 Reminders.create_many("list", [[title: "first"], [title: "second"], [title: "must not run"]])
               end,
               journal: journal
             )

    assert File.exists?(evidence)
    assert error.details.outcome == :unknown
    assert error.details.recovery_status == :needs_reconciliation
    assert {:ok, summary} = Journal.inspect_run(error.details.journal_path)
    assert summary.run_id == error.details.run_id
    assert summary.status == :needs_reconciliation
    assert [pending] = summary.pending
    assert pending["resource"]["identity"] == %{"list_id" => "list"}
    assert summary.resources == [%{"type" => "reminder", "id" => "first-id", "list_id" => "list"}]
  end

  test "image failure retains the intended path even when the save response was lost", %{root: root, journal: journal} do
    source = Path.join(root, "source.png")
    output = Path.join(root, "out")
    File.mkdir!(output)
    File.write!(source, "fixture")

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      File.write!(input(opts)["destination"], "saved")
      {:error, Error.execution_error("close failed")}
    end)

    assert {:error, error} = Composition.run(fn -> ImageEvents.process_many([source], output, []) end, journal: journal)
    assert {:ok, %{status: :needs_reconciliation, pending: [pending]}} = Journal.inspect_run(error.details.journal_path)
    assert pending["resource"]["identity"]["path"] == Path.join(output, "source.png")
    assert File.exists?(pending["resource"]["identity"]["path"])
  end

  test "a later undispatched step does not erase earlier acknowledged effects" do
    assert {:error, error} =
             Composition.run(fn ->
               Composition.effect(:write, fn -> {:ok, "id"} end)
               Composition.step(:later, fn -> {:error, Error.timeout("not dispatched", outcome: :not_started)} end)
             end)

    assert error.details.outcome == :not_started
    assert error.details.recovery_status == :partial
  end

  test "verification cannot dispatch another predicate after the parent expires" do
    key = make_ref()

    assert {:error, %Error{type: :timeout}} =
             Composition.run(
               fn ->
                 Composition.verify(
                   :state,
                   fn ->
                     assert Composition.remaining() > 0
                     Process.put(key, Process.get(key, 0) + 1)
                     Process.sleep(30)
                     false
                   end,
                   timeout: 1000,
                   interval: 1
                 )
               end,
               timeout: 20
             )

    assert Process.get(key) == 1
  end

  test "invalid identity metadata rejects the entire batch before mutation" do
    assert {:error, _} =
             Composition.map_effects([:first, :last], :write, fn _ -> flunk("must not run") end,
               identity: fn
                 :first -> %{id: "valid"}
                 :last -> %{body: "private"}
               end
             )
  end

  test "blank page title uses the same conversion fallback as a captured page" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{window_id: 42, tab_index: 1, url: "file:///fixture.html"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{title: "", url: "file:///fixture.html", text: "body", selection: ""})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["name"] == "file:///fixture.html"
      response("reminder")
    end)

    assert {:ok, "reminder"} = Workflows.current_page_to_reminder("list")
  end

  test "verified event handoff observes all requested fields before completing a reminder" do
    attrs = [start_at: "2026-11-01T12:00:00Z", end_at: "2026-11-01T13:00:00Z"]
    expected = %{title: "task", description: "body", start_at: attrs[:start_at], end_at: attrs[:end_at]}
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{title: "task", body: "body"}) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("event") end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{expected | title: "not yet"}) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{expected | start_at: "2026-11-01T12:00:00.000Z", end_at: "2026-11-01T13:00:00.000Z"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["completed"] == true
      response(true)
    end)

    assert {:ok, %{event_id: "event"}} =
             Workflows.reminder_to_event("reminder", "calendar", attrs, verify_event: true, complete_reminder: true)
  end

  test "failed event readback leaves the source reminder incomplete" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{title: "task", body: "body"}) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("event") end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> {:error, Error.permission_denied("readback")} end)

    assert {:error, error} =
             Workflows.reminder_to_event(
               "reminder",
               "calendar",
               [start_at: "2026-11-01T12:00:00Z", end_at: "2026-11-01T13:00:00Z"],
               verify_event: true,
               complete_reminder: true
             )

    assert error.details.recovery_status == :partial
    assert Enum.any?(error.details.run_completed, &(&1.result == "event"))
  end

  test "Calendar null optional fields verify equivalently to requested empty strings" do
    attrs = [start_at: "2026-11-02T12:00:00Z", end_at: "2026-11-02T13:00:00Z"]
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{title: "task", body: nil}) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("event") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{
        title: "task",
        description: nil,
        start_at: "2026-11-02T12:00:00.000Z",
        end_at: "2026-11-02T13:00:00.000Z"
      })
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)

    assert {:ok, _} =
             Workflows.reminder_to_event("reminder", "calendar", attrs, verify_event: true, complete_reminder: true)
  end

  test "explicit reminder lists scope reads and completion without scanning other accounts" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "byId(app.lists,input.list_id).reminders"
      assert input(opts)["list_id"] == "owned-list"
      response(%{id: "reminder", title: "Task"})
    end)

    assert {:ok, %{id: "reminder"}} = Reminders.get_reminder("reminder", list_id: "owned-list")

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "byId(app.lists,input.list_id).reminders"
      assert input(opts)["list_id"] == "owned-list"
      response(true)
    end)

    assert :ok = Reminders.delete_reminder("reminder", list_id: "owned-list")

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, opts ->
      assert source =~ "set completed of reminder id (wantedID as text) of targetList to true"
      assert opts[:args] == ["owned-list", "reminder"]
      {:ok, "1"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)

    assert {:ok, ["reminder"]} = Reminders.complete_many(["reminder"], list_id: "owned-list")
    assert {:error, _} = Reminders.complete_many(["reminder"], list_id: "")
    assert {:error, _} = Reminders.complete_many(["reminder", "reminder"], list_id: "owned-list")
  end

  test "missing scoped reminders prevent mutation and do not trigger verification" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, "EXMC_MISSING"} end)
    assert {:error, %{details: %{outcome: :not_started}}} = Reminders.complete_many(["missing"], list_id: "list")
  end

  test "native preflight timeouts remain distinct from missing IDs" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, "EXMC_PREFLIGHT:-1712"} end)

    assert {:error, %{type: :timeout, details: %{outcome: :not_started}}} =
             Reminders.complete_many(["id"], list_id: "list")
  end

  test "large scoped completion retains confirmed chunks and stops after an uncertain chunk", %{journal: journal} do
    ids = Enum.map(1..25, &"reminder-#{&1}")

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, opts ->
      assert opts[:args] == ["list" | Enum.take(ids, 10)]
      {:ok, "10"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, opts ->
      assert opts[:args] == ["list" | Enum.slice(ids, 10, 10)]
      {:error, Error.timeout("reply lost after completion", outcome: :unknown)}
    end)

    assert {:error, error} = Composition.run(fn -> Reminders.complete_many(ids, list_id: "list") end, journal: journal)
    assert error.details.recovery_status == :needs_reconciliation
    assert {:ok, summary} = Journal.inspect_run(error.details.journal_path)
    assert Enum.map(summary.resources, & &1["id"]) == Enum.take(ids, 10)
    assert Enum.any?(summary.pending, &(get_in(&1, ["resource", "identity", "ids"]) == Enum.slice(ids, 10, 10)))
    refute Jason.encode!(summary.events) =~ "reminder-25"
  end

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
