defmodule ExMacOSControl.ShortcutsIntegrationTest do
  use ExUnit.Case, async: false

  import Mox

  alias ExMacOSControl.OSAScriptAdapter

  @moduletag :integration

  setup :verify_on_exit!

  setup do
    Mox.stub_with(ExMacOSControl.AdapterMock, OSAScriptAdapter)
    :ok
  end

  test "lists shortcut names without executing them" do
    assert {:ok, shortcuts} = OSAScriptAdapter.list_shortcuts()
    assert Enum.all?(shortcuts, &is_binary/1)
  end

  describe "explicitly opted-in echo fixture" do
    @describetag :shortcut

    # A generic --include integration overrides exclusions, so guard explicitly too.
    unless Enum.any?(ExUnit.configuration()[:include], &(&1 in [:shortcut, {:shortcut, true}])) do
      @describetag skip: "Requires --include shortcut and TEST_SHORTCUT_NAME pointing at a harmless echo fixture"
    end

    # Create a harmless Shortcut that returns its input, then run:
    # TEST_SHORTCUT_NAME=Echo mix test --include integration --include shortcut \
    #   test/integration/shortcuts_integration_test.exs
    # Never select an arbitrary Shortcut from the user's library.
    setup do
      name = System.get_env("TEST_SHORTCUT_NAME")

      unless is_binary(name) and name != "" do
        flunk("Set TEST_SHORTCUT_NAME to a dedicated, harmless echo Shortcut before enabling :shortcut tests")
      end

      %{shortcut: name}
    end

    test "returns string input", %{shortcut: name} do
      assert {:ok, "test input"} = OSAScriptAdapter.run_shortcut(name, input: "test input", timeout: 5000)
    end

    test "returns numeric input", %{shortcut: name} do
      assert {:ok, "42"} = OSAScriptAdapter.run_shortcut(name, input: 42, timeout: 5000)
    end

    test "returns JSON input", %{shortcut: name} do
      input = %{"key" => "value"}
      assert {:ok, output} = OSAScriptAdapter.run_shortcut(name, input: input, timeout: 5000)
      assert Jason.decode!(output) == input
    end

    test "facade returns input", %{shortcut: name} do
      assert {:ok, "test"} = ExMacOSControl.run_shortcut(name, input: "test", timeout: 5000)
    end
  end
end
