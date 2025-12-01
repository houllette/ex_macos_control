defmodule ExMacosControlTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExMacOSControl.AdapterFactory

  setup :verify_on_exit!

  # Set up a stub for doctests that might run
  setup do
    # Allow doctests to call the adapter without explicit expectations
    Mox.stub_with(ExMacOSControl.AdapterMock, ExMacOSControl.OSAScriptAdapter)
    :ok
  end

  doctest ExMacOSControl

  describe "facade functions" do
    test "exposes run_shortcut/1 and run_applescript/1" do
      assert function_exported?(ExMacOSControl, :run_shortcut, 1)
      assert function_exported?(ExMacOSControl, :run_applescript, 1)
    end

    test "exposes run_applescript/2 with options" do
      assert function_exported?(ExMacOSControl, :run_applescript, 2)
    end
  end

  describe "run_applescript/1 - facade delegation" do
    test "delegates to adapter run_applescript/1" do
      AdapterFactory.mock_applescript_success("test result")

      result = ExMacOSControl.run_applescript("test script")
      assert result == {:ok, "test result"}
    end

    test "returns errors from adapter" do
      AdapterFactory.mock_applescript_error(:syntax_error)

      result = ExMacOSControl.run_applescript("invalid script")
      assert result == {:error, :syntax_error}
    end
  end

  describe "run_applescript/2 - with options" do
    test "delegates to adapter run_applescript/2" do
      # Need to mock run_applescript/2 on the adapter
      ExMacOSControl.AdapterMock
      |> expect(:run_applescript, fn script, opts ->
        assert script == "test script"
        assert opts == [timeout: 5000]
        {:ok, "result"}
      end)

      result = ExMacOSControl.run_applescript("test script", timeout: 5000)
      assert result == {:ok, "result"}
    end

    test "passes args option to adapter" do
      ExMacOSControl.AdapterMock
      |> expect(:run_applescript, fn script, opts ->
        assert script == "test script"
        assert Keyword.get(opts, :args) == ["arg1", "arg2"]
        {:ok, "result"}
      end)

      result = ExMacOSControl.run_applescript("test script", args: ["arg1", "arg2"])
      assert result == {:ok, "result"}
    end

    test "passes multiple options to adapter" do
      ExMacOSControl.AdapterMock
      |> expect(:run_applescript, fn script, opts ->
        assert script == "test script"
        assert Keyword.get(opts, :timeout) == 5000
        assert Keyword.get(opts, :args) == ["arg1"]
        {:ok, "result"}
      end)

      result = ExMacOSControl.run_applescript("test script", timeout: 5000, args: ["arg1"])
      assert result == {:ok, "result"}
    end

    test "returns timeout errors from adapter" do
      timeout_error = ExMacOSControl.Error.timeout("test", timeout: 1000)

      ExMacOSControl.AdapterMock
      |> expect(:run_applescript, fn _script, _opts ->
        {:error, timeout_error}
      end)

      result = ExMacOSControl.run_applescript("delay 10", timeout: 1000)
      assert {:error, ^timeout_error} = result
    end
  end

  test "exposes run_javascript/1 and run_javascript/2" do
    assert function_exported?(ExMacOSControl, :run_javascript, 1)
    assert function_exported?(ExMacOSControl, :run_javascript, 2)
  end

  describe "run_shortcut/2 - with input" do
    test "delegates to adapter run_shortcut/2 with input" do
      ExMacOSControl.AdapterMock
      |> expect(:run_shortcut, fn name, opts ->
        assert name == "Test Shortcut"
        assert Keyword.get(opts, :input) == "Hello, World!"
        {:ok, "result"}
      end)

      result = ExMacOSControl.run_shortcut("Test Shortcut", input: "Hello, World!")
      assert result == {:ok, "result"}
    end

    test "delegates to adapter run_shortcut/2 with number input" do
      ExMacOSControl.AdapterMock
      |> expect(:run_shortcut, fn name, opts ->
        assert name == "Test Shortcut"
        assert Keyword.get(opts, :input) == 42
        :ok
      end)

      result = ExMacOSControl.run_shortcut("Test Shortcut", input: 42)
      assert result == :ok
    end

    test "delegates to adapter run_shortcut/2 with map input" do
      input_map = %{"key" => "value"}

      ExMacOSControl.AdapterMock
      |> expect(:run_shortcut, fn name, opts ->
        assert name == "Test Shortcut"
        assert Keyword.get(opts, :input) == input_map
        {:ok, "result"}
      end)

      result = ExMacOSControl.run_shortcut("Test Shortcut", input: input_map)
      assert result == {:ok, "result"}
    end

    test "delegates to adapter run_shortcut/2 with list input" do
      input_list = ["item1", "item2"]

      ExMacOSControl.AdapterMock
      |> expect(:run_shortcut, fn name, opts ->
        assert name == "Test Shortcut"
        assert Keyword.get(opts, :input) == input_list
        {:ok, "result"}
      end)

      result = ExMacOSControl.run_shortcut("Test Shortcut", input: input_list)
      assert result == {:ok, "result"}
    end

    test "returns errors from adapter" do
      error = ExMacOSControl.Error.execution_error("Shortcut not found")

      ExMacOSControl.AdapterMock
      |> expect(:run_shortcut, fn _name, _opts ->
        {:error, error}
      end)

      result = ExMacOSControl.run_shortcut("Nonexistent", input: "test")
      assert {:error, ^error} = result
    end
  end

  describe "list_shortcuts/0" do
    test "exposes list_shortcuts/0" do
      assert function_exported?(ExMacOSControl, :list_shortcuts, 0)
    end

    test "delegates to adapter list_shortcuts/0" do
      shortcuts = ["Shortcut 1", "Shortcut 2", "My Shortcut"]

      ExMacOSControl.AdapterMock
      |> expect(:list_shortcuts, fn ->
        {:ok, shortcuts}
      end)

      result = ExMacOSControl.list_shortcuts()
      assert result == {:ok, shortcuts}
    end

    test "returns empty list when no shortcuts exist" do
      ExMacOSControl.AdapterMock
      |> expect(:list_shortcuts, fn ->
        {:ok, []}
      end)

      result = ExMacOSControl.list_shortcuts()
      assert result == {:ok, []}
    end

    test "returns errors from adapter" do
      error = ExMacOSControl.Error.not_found("Shortcuts Events")

      ExMacOSControl.AdapterMock
      |> expect(:list_shortcuts, fn ->
        {:error, error}
      end)

      result = ExMacOSControl.list_shortcuts()
      assert {:error, ^error} = result
    end
  end
end
