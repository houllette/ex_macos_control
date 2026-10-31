defmodule ExMacOSControl.DesktopTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Desktop, Error}

  test "lock is reentrant and released after an exception" do
    assert_raise RuntimeError, "inside", fn ->
      Desktop.with_lock(fn -> Desktop.with_lock(fn -> raise "inside" end) end)
    end

    assert {:ok, :again} = Desktop.with_lock(fn -> {:ok, :again} end)
  end

  test "competing processes cannot interleave foreground work" do
    owner = self()

    task =
      Task.async(fn ->
        Desktop.with_lock(fn ->
          send(owner, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    on_exit(fn -> if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill) end)
    assert_receive :locked
    assert {:error, %Error{type: :timeout}} = Desktop.with_lock(fn -> flunk("must not acquire") end, timeout: 20)
    send(task.pid, :release)
    assert Task.await(task) == :ok
    assert :ok = Desktop.with_lock(fn -> :ok end)
  end

  test "a killed owner releases its host lock without running callback cleanup" do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Desktop.with_lock(fn ->
          send(parent, :owned)

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive :owned
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert :ok = Desktop.with_lock(fn -> :ok end, timeout: 1000)
  end

  test "another BEAM instance participates in the same host lock" do
    root = Path.expand("tmp/desktop-beam-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    ready = Path.join(root, "ready")
    release = Path.join(root, "release")

    code = """
    Application.ensure_all_started(:ex_macos_control)
    :ok = ExMacOSControl.Desktop.with_lock(fn ->
      File.write!(#{inspect(ready)}, "owned")
      ExMacOSControl.Wait.until(fn -> File.exists?(#{inspect(release)}) end, timeout: 8000)
    end, timeout: 9000)
    """

    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))
    args = Enum.flat_map(paths, &["-pa", &1]) ++ ["-e", code]
    child = Task.async(fn -> ExMacOSControl.Command.run("elixir", args, timeout: 10_000) end)

    try do
      assert :ok = ExMacOSControl.Wait.until(fn -> File.exists?(ready) end, timeout: 5000, interval: 10)

      assert {:error, %Error{details: %{outcome: :not_started}}} =
               Desktop.with_lock(fn -> flunk("another BEAM owns the lock") end, timeout: 20)
    after
      File.write!(release, "release")
    end

    assert {:ok, %{exit_status: 0}} = Task.await(child, 10_000)
    assert :ok = Desktop.with_lock(fn -> :ok end)
  end
end
