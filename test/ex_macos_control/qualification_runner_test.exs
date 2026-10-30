defmodule ExMacOSControl.Qualification.RunnerTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Error, Qualification, QualificationFixture}
  alias ExMacOSControl.Qualification.{Host, Journal, Runner, Session}

  setup do
    workspace = Path.expand("tmp/runner-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)
    manifest = QualificationFixture.manifest(workspace)
    QualificationFixture.setup(manifest)
    %{manifest: manifest, workspace: workspace, run_id: String.duplicate("a", 32)}
  end

  test "default readiness check performs no effects and creates no journal", %{manifest: manifest, workspace: workspace} do
    assert {:ok, %{status: :ready}} = Runner.check(manifest, "notes-crud", QualificationFixture)
    refute_received {:effect, _}
    refute File.exists?(Path.join(workspace, "tmp/qualification"))
  end

  test "CRUD verifies and deletes only its returned identity, journaling intent before dispatch", %{
    manifest: manifest,
    run_id: run_id,
    workspace: workspace
  } do
    events = Path.join(workspace, "tmp/qualification/#{run_id}/events.jsonl")

    Process.put({QualificationFixture, :dispatch_hook}, fn operation, _ ->
      last = File.read!(events) |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
      assert last["event"] == "intent"
      assert last["operation"] == Atom.to_string(operation)
    end)

    Process.put({QualificationFixture, :hook}, fn count ->
      if count == 3 do
        entries = File.read!(events) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
        assert Enum.any?(entries, &(&1["event"] == "intent" and &1["operation"] == "notes_create"))
        assert Enum.any?(entries, &(&1["object_id"] == "created-note"))
      end
    end)

    assert {:ok, %{status: "passed", effects: 3, sends: 0}} =
             Runner.run(manifest, "notes-crud", QualificationFixture, run_id)

    assert_received {:effect, :notes_create}
    assert_received {:effect, :notes_update}
    assert_received {:effect, :notes_delete}
    assert Process.get({QualificationFixture, :guards}) == 7
    assert {:error, %Error{}} = Runner.run(manifest, "notes-crud", QualificationFixture, run_id)
    assert File.stat!(events).mode |> Bitwise.band(0o777) == 0o600
  end

  test "identity change between calls prevents the next write and blocks a new run", %{
    manifest: manifest,
    run_id: run_id
  } do
    Process.put({QualificationFixture, :hook}, fn count ->
      if count == 4, do: Process.put({QualificationFixture, :snapshot}, %{})
    end)

    assert {:error, %Error{}} = Runner.run(manifest, "notes-crud", QualificationFixture, run_id)
    assert_received {:effect, :notes_create}
    refute_received {:effect, :notes_update}
    refute_received {:effect, :notes_delete}
    QualificationFixture.setup(manifest)
    assert {:error, %Error{}} = Runner.run(manifest, "notes-crud", QualificationFixture, String.duplicate("b", 32))
    refute_received {:effect, _}
  end

  test "unknown outcomes are never retried or recorded with private backend errors", %{
    manifest: manifest,
    run_id: run_id,
    workspace: workspace
  } do
    Process.put({QualificationFixture, :failure}, :notes_create)
    assert {:error, %Error{}} = Runner.run(manifest, "notes-crud", QualificationFixture, run_id)
    assert_received {:effect, :notes_create}
    refute_received {:effect, _}
    events = File.read!(Path.join(workspace, "tmp/qualification/#{run_id}/events.jsonl"))
    assert events =~ "needs_reconciliation"
    refute events =~ "private synthetic content"
    assert {:error, %Error{}} = Runner.run(manifest, "notes-crud", QualificationFixture, String.duplicate("b", 32))
  end

  test "expired leases and exhausted effects cannot dispatch", %{manifest: manifest, run_id: run_id} do
    {:ok, journal} = Journal.open(manifest["workspace"], run_id)
    on_exit(fn -> Journal.close(journal) end)
    state = Session.new(manifest, "notes-crud", QualificationFixture, journal)
    assert {:error, %Error{}, _} = Session.effect(%{state | effects: 3}, :notes_create)

    assert {:error, %Error{}, _} =
             Session.effect(%{state | deadline: System.monotonic_time(:millisecond) - 1}, :notes_create)

    assert {:error, %Error{}, _} = Session.effect(state, :mail_send)
    refute_received {:effect, _}
  end

  test "a second runner cannot acquire the host-wide mutex" do
    assert {:ok, lock} = Host.lock()

    try do
      assert {:error, _} = Host.lock()
    after
      Host.unlock(lock)
    end
  end

  test "journal write failure prevents dispatch and unknown results halt the session", %{
    manifest: manifest,
    run_id: run_id
  } do
    {:ok, journal} = Journal.open(manifest["workspace"], run_id)
    state = Session.new(manifest, "notes-crud", QualificationFixture, journal)
    Process.put({QualificationFixture, :failure}, :notes_create)
    assert {:error, %Error{}, halted} = Session.effect(state, :notes_create)
    assert_received {:effect, :notes_create}
    assert {:error, %Error{}, _} = Session.effect(halted, :notes_create)
    refute_received {:effect, _}
    Journal.close(journal)
    assert {:error, %Error{}, _} = Session.effect(state, :notes_create)
    refute_received {:effect, _}
  end

  test "execute requires its environment opt-in before reading a manifest" do
    previous = System.get_env("EXMC_LIVE_TESTS")
    System.delete_env("EXMC_LIVE_TESTS")

    on_exit(fn ->
      if previous, do: System.put_env("EXMC_LIVE_TESTS", previous), else: System.delete_env("EXMC_LIVE_TESTS")
    end)

    assert {:error, %Error{message: message}} = Qualification.run("missing", "notes-crud", execute: true)
    assert message =~ "EXMC_LIVE_TESTS"
    refute_received {:effect, _}
  end
end
