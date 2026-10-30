defmodule ExMacOSControl.CompositionTraceTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.{Composition, Error}
  alias ExMacOSControl.Composition.Journal

  setup do
    root = Path.expand("tmp/trace-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{directory: Path.join(root, "private")}
  end

  test "nested steps have one run ID, parent spans and explicit acknowledgement/confirmation" do
    assert {:ok, "private body"} =
             Composition.run(
               fn ->
                 Composition.step(:outer, fn ->
                   Composition.run(fn ->
                     with :ok <- Composition.verify(:visible, fn -> true end) do
                       Composition.effect(:create_note, fn -> {:ok, "private body"} end)
                     end
                   end)
                 end)
               end,
               trace_to: self()
             )

    events = events()
    assert length(Enum.uniq(Enum.map(events, & &1.run_id))) == 1
    outer = Enum.find(events, &(&1.event == :step_started and &1.step == "outer"))
    inner = Enum.find(events, &(&1.event == :step_started and &1.step == "create_note"))
    assert inner.parent_step_id == outer.step_id
    assert Enum.any?(events, &(&1.event == :step_finished and &1.step == "visible" and &1.outcome == :confirmed))
    assert Enum.any?(events, &(&1.event == :step_finished and &1.step == "create_note" and &1.outcome == :acknowledged))
  end

  test "trace metadata excludes callback content, arguments and dynamic names" do
    secret = "sensitive@example.invalid"

    assert {:ok, ^secret} =
             Composition.run(
               fn ->
                 Composition.step({:shortcut, secret}, fn -> {:ok, secret} end)
               end,
               trace_to: self()
             )

    refute Jason.encode!(events()) =~ secret
  end

  test "durable journals preserve declared IDs without persisting arbitrary results", %{directory: directory} do
    id = String.duplicate("a", 32)

    assert {:ok, "private content"} =
             Composition.run(
               fn ->
                 Composition.effect(:created, fn -> {:ok, "native-id"} end, resource: :note)
                 Composition.step(:read, fn -> {:ok, "private content"} end)
               end,
               journal: directory,
               run_id: id
             )

    path = Path.join(directory, id <> ".jsonl")

    assert {:ok, %{status: :complete, resources: [%{"type" => "note", "id" => "native-id"}]}} =
             Journal.inspect_run(path)

    refute File.read!(path) =~ "private content"

    assert {:error, %Error{}} =
             Composition.run(fn -> flunk("run ID must not be reused") end, journal: directory, run_id: id)
  end

  test "journal failure refuses effects before callback dispatch", %{directory: directory} do
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o755)
    assert {:error, %Error{}} = Composition.run(fn -> flunk("unsafe existing directory") end, journal: directory)
    assert {:ok, %{mode: mode}} = File.stat(directory)
    assert Bitwise.band(mode, 0o777) == 0o755
  end

  test "journal loss during a run prevents subsequent effects", %{directory: directory} do
    assert {:error, %Error{}} =
             Composition.run(
               fn ->
                 context = Composition.capture_context()
                 File.close(context.journal.io)
                 Composition.effect(:write, fn -> flunk("lost intent persistence must stop dispatch") end)
               end,
               journal: directory
             )
  end

  test "a truncated final record remains reconcilable", %{directory: directory} do
    id = String.duplicate("d", 32)
    assert :ok = Composition.run(fn -> :ok end, journal: directory, run_id: id)
    path = Path.join(directory, id <> ".jsonl")
    File.write!(path, "{partial", [:append])
    assert {:ok, %{status: :needs_reconciliation}} = Journal.inspect_run(path)
  end

  test "unknown outcomes remain reconcilable and are never marked complete", %{directory: directory} do
    id = String.duplicate("b", 32)

    assert {:error, _} =
             Composition.run(
               fn ->
                 Composition.effect(:send, fn -> {:error, Error.timeout("send", outcome: :unknown)} end)
               end,
               journal: directory,
               run_id: id
             )

    assert {:ok, %{status: :needs_reconciliation, pending: [_]}} =
             Journal.inspect_run(Path.join(directory, id <> ".jsonl"))
  end

  test "execution errors after dispatch do not imply that an effect was rolled back", %{directory: directory} do
    id = String.duplicate("e", 32)

    assert {:error, _} =
             Composition.run(
               fn ->
                 Composition.effect(:partial_write, fn ->
                   {:error, Error.execution_error("app failed after changing state")}
                 end)
               end,
               journal: directory,
               run_id: id
             )

    assert {:ok, %{status: :needs_reconciliation, pending: [_]}} =
             Journal.inspect_run(Path.join(directory, id <> ".jsonl"))
  end

  test "a killed caller leaves a durable intent rather than an invented successful result", %{directory: directory} do
    parent = self()
    id = String.duplicate("c", 32)

    {pid, monitor} =
      spawn_monitor(fn ->
        Composition.run(
          fn ->
            Composition.effect(:write, fn ->
              send(parent, :dispatched)

              receive do
                :never -> :ok
              end
            end)
          end,
          journal: directory,
          run_id: id
        )
      end)

    assert_receive :dispatched
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}

    assert {:ok, %{status: :needs_reconciliation, pending: [_]}} =
             Journal.inspect_run(Path.join(directory, id <> ".jsonl"))
  end

  test "joined Tasks can explicitly inherit deadlines, limits and tracing" do
    parent = self()

    assert :ok =
             Composition.run(
               fn ->
                 context = Composition.capture_context()

                 task =
                   Task.async(fn ->
                     Composition.with_context(context, fn ->
                       assert Composition.remaining() <= 500
                       assert ExMacOSControl.execution_options()[:max_output_bytes] == 200

                       Composition.step(:child, fn ->
                         send(parent, :child)
                         :ok
                       end)
                     end)
                   end)

                 Task.await(task)
               end,
               timeout: 500,
               max_output_bytes: 200,
               trace_to: self()
             )

    assert_received :child
    assert Enum.any?(events(), &(&1.event == :step_finished and &1.step == "child"))
  end

  test "cleanup failures remain visible when a callback raises" do
    assert_raise RuntimeError, "private exception", fn ->
      Composition.run(
        fn ->
          Composition.resource(:resource, fn _ -> raise "private exception" end, fn _ ->
            {:error, Error.execution_error("private cleanup detail")}
          end)
        end,
        trace_to: self()
      )
    end

    events = events()
    assert Enum.any?(events, &(&1.event == :step_finished and &1.step == "cleanup" and &1.outcome == :failed))
    refute Jason.encode!(events) =~ "private exception"
    refute Jason.encode!(events) =~ "private cleanup detail"
  end

  defp events(acc \\ []) do
    receive do
      {:ex_macos_control, event} -> events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
