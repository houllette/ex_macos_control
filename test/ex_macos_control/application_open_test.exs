defmodule ExMacOSControl.ApplicationOpenTest do
  use ExUnit.Case, async: false
  import Mox
  alias ExMacOSControl.Applications
  setup :verify_on_exit!

  test "normal UI startup uses explicit LaunchServices arguments and preserves a background request" do
    root = Path.expand("tmp/application-open-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    executable = Path.join(root, "open")
    args_path = Path.join(root, "args")
    File.write!(executable, "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$EXMC_OPEN_ARGS\"\n")
    File.chmod!(executable, 0o700)
    previous = System.get_env("PATH")
    previous_args = System.get_env("EXMC_OPEN_ARGS")
    System.put_env("PATH", root <> ":" <> previous)
    System.put_env("EXMC_OPEN_ARGS", args_path)

    on_exit(fn ->
      System.put_env("PATH", previous)
      if previous_args, do: System.put_env("EXMC_OPEN_ARGS", previous_args), else: System.delete_env("EXMC_OPEN_ARGS")
      File.rm_rf!(root)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, 2, fn _, _ ->
      {:ok,
       Jason.encode!(%{exmc: 1, result: %{bundle_id: "fixture", path: "/fixture app.app", running: true, pid: 42}})}
    end)

    assert {:ok, %{pid: 42}} = Applications.open("fixture", background: true)
    assert File.read!(args_path) == "-g\n-a\n/fixture app.app\n"
    assert {:error, _} = Applications.open("fixture", background: :invalid)
  end
end
