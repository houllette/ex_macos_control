defmodule ExMacOSControl.GUITest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.GUI

  setup do
    root = Path.expand("tmp/gui-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "a helper job executes at most once and publishes a complete nonce-bound result", %{root: root} do
    counter = Path.join(root, "counter")
    path = Path.join(root, "request.json")
    result_path = Path.join(root, "result.json")

    request = %{
      directory: root,
      result: result_path,
      token: "token",
      executable: "/bin/sh",
      arguments: ["-c", "printf x >> \"$1\"", "sh", counter],
      timeout: 1000,
      max_output_bytes: 1000
    }

    File.write!(path, Jason.encode!(request))
    assert :ok = GUI.execute(path)
    assert {:error, _} = GUI.execute(path)
    assert File.read!(counter) == "x"

    assert %{"token" => "token", "ok" => true, "output" => %{"exit_status" => 0}} =
             Jason.decode!(File.read!(result_path))
  end

  test "invalid GUI arguments cannot launch a command" do
    assert {:error, _} = GUI.run("echo", [nil])
    assert {:error, _} = GUI.run("echo", ["ok"], keep_window: :invalid)
  end

  if ExMacOSControl.TestHelpers.macos?() do
    setup %{root: root} do
      open = Path.join(root, "open")
      File.cp!("test/support/fixtures/gui_open.py", open)
      File.chmod!(open, 0o700)
      previous = System.get_env("PATH")
      System.put_env("PATH", root <> ":" <> previous)
      on_exit(fn -> System.put_env("PATH", previous) end)
      %{opts: [root: Path.join(root, "jobs with spaces"), timeout: 1000]}
    end

    test "GUI launch passes arguments as data and requires successful cleanup", %{root: root, opts: opts} do
      argument = "quotes ' 雪 `$()`"

      assert {:ok, %{exit_status: 0, window_retained: false, evidence: evidence}} =
               GUI.run("/bin/echo", [argument], opts)

      assert Jason.decode!(File.read!(Path.join(evidence, "request.json")))["arguments"] == [argument]
      refute File.read!(Path.join(evidence, "run.command")) =~ argument
      assert File.read!(Path.join(root, "calls")) == "launch\n"
    end

    test "a failed command and an unacknowledged cleanup remain distinguishable", %{root: root, opts: opts} do
      File.write!(Path.join(root, "mode"), "command_failure")
      assert {:ok, %{exit_status: 7}} = GUI.run("/bin/echo", [], opts)
      File.write!(Path.join(root, "mode"), "cleanup_failure")
      assert {:error, %{details: %{cause: %{cleanup: %{"ok" => false}}}}} = GUI.run("/bin/echo", [], opts)
    end

    test "failed window ownership returns immediately without dispatching or relaunching", %{root: root, opts: opts} do
      File.write!(Path.join(root, "mode"), "startup_failure")
      assert {:error, %{details: %{outcome: :unknown}}} = GUI.run("/bin/echo", [], opts)
      assert File.read!(Path.join(root, "calls")) == "launch\n"
    end

    test "lost or unrelated replies remain unknown and never replay the launch", %{root: root, opts: opts} do
      for mode <- ["lost_reply", "wrong_token"] do
        File.write!(Path.join(root, "mode"), mode)
        assert {:error, %{details: %{outcome: :unknown}}} = GUI.run("/bin/echo", [], opts)
      end

      assert File.read!(Path.join(root, "calls")) == "launch\nlaunch\n"
    end
  end
end
