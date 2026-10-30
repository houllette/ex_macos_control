defmodule ExMacOSControl.CommandTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.{Command, Error}

  test "preserves stdout and stderr independently and passes data without shell interpretation" do
    data = "-e; $(false) `false` space\n雪"
    script = ~S(printf '%s' "$1"; printf 'diagnostic' >&2)

    assert {:ok, %{stdout: ^data, stderr: "diagnostic", exit_status: 0}} =
             Command.run("/bin/sh", ["-c", script, "exmc-test", data])
  end

  test "terminates the owned command group on timeout" do
    path = Path.expand("tmp/timeout-marker-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    script = ~S(/bin/sleep 0.3; printf completed > "$1")

    assert {:error, %Error{type: :timeout, details: %{outcome: :unknown}}} =
             Command.run("/bin/sh", ["-c", script, "exmc-test", path], timeout: 30)

    Process.sleep(400)
    refute File.exists?(path)
  end

  test "bounds combined output, including a stderr-only command" do
    for script <- ["printf 123456789", "printf 123456789 >&2"] do
      assert {:error, %Error{message: "Command output exceeded max_output_bytes"}} =
               Command.run("/bin/sh", ["-c", script], max_output_bytes: 4)
    end
  end

  test "caller cancellation also terminates the owned process group" do
    marker = Path.expand("tmp/cancel-marker-#{System.unique_integer([:positive])}")
    started = marker <> ".started"

    on_exit(fn ->
      File.rm(marker)
      File.rm(started)
    end)

    script = ~S(printf started > "$1"; /bin/sleep 0.4; printf completed > "$2")
    caller = spawn(fn -> Command.run("/bin/sh", ["-c", script, "exmc-test", started, marker]) end)
    assert :ok = ExMacOSControl.Wait.until(fn -> File.exists?(started) end, timeout: 1000, interval: 5)
    Process.exit(caller, :kill)
    Process.sleep(500)
    refute File.exists?(marker)
  end

  test "validates data and timeouts before execution" do
    for opts <- [[timeout: -1], [timeout: false], [max_output_bytes: 0]] do
      assert {:error, %Error{type: :execution_error}} = Command.run("/bin/echo", ["hello"], opts)
    end

    assert {:error, %Error{}} = Command.run("/bin/echo", [<<0>>])
    assert {:error, %Error{}} = Command.run("/bin/echo", [1])
    assert {:error, %Error{details: %{reason: :enoent}}} = Command.run("exmc-nonexistent-command", [])
  end
end
