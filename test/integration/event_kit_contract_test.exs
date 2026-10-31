defmodule ExMacOSControl.EventKitContractTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Command, EventKit}
  @moduletag :integration
  unless ExMacOSControl.TestHelpers.macos?(), do: @moduletag(skip: "Requires the macOS SDK")
  @moduletag timeout: 120_000

  test "optional helper installs into a new bundle and runs its bounded protocol without requesting data access" do
    root = Path.expand("tmp/eventkit-native-#{System.unique_integer([:positive])}")
    path = Path.join(root, "Helper with spaces.app")
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, ^path} = EventKit.install(path)
    assert {:ok, states} = EventKit.status(helper: path)
    assert Map.keys(states) |> Enum.sort() == ["event", "reminder"]

    assert Enum.all?(
             Map.values(states),
             &(&1 in ["not_determined", "denied", "restricted", "full_access", "write_only", "unknown"])
           )

    # Existing installations must not be overwritten by a rebuild.
    binary = Path.join(path, "Contents/MacOS/EventKitBridge")
    bytes = File.read!(binary)
    assert {:error, %{details: %{outcome: :not_started}}} = EventKit.install(path)
    assert File.read!(binary) == bytes
    assert {:ok, %{stdout: response}} = Command.run(binary, [], input: ~s({"version":99}), timeout: 5000)
    assert %{"ok" => false, "error" => %{"outcome" => "not_started"}} = Jason.decode!(response)
  end
end
