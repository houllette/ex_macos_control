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
end
