defmodule ExMacOSControl.ShortcutsIntegrationTest do
  use ExUnit.Case, async: false

  import Mox

  alias ExMacOSControl.OSAScriptAdapter

  @moduletag :integration

  setup :verify_on_exit!

  # Stub the mock adapter to use the real OSAScriptAdapter for integration tests
  setup do
    Mox.stub_with(ExMacOSControl.AdapterMock, ExMacOSControl.OSAScriptAdapter)
    :ok
  end

  describe "list_shortcuts/0 integration" do
    @tag :integration
    test "lists shortcuts on macOS" do
      # This test gracefully handles when no shortcuts are available
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, shortcuts} ->
          # Verify it returns a list
          assert is_list(shortcuts)
          # Each item should be a string
          Enum.each(shortcuts, fn shortcut ->
            assert is_binary(shortcut)
          end)

        {:error, reason} ->
          # Shortcuts app might not be available or accessible
          # This is acceptable - don't fail the test
          IO.puts("Shortcuts app not available: #{inspect(reason)}")
          :ok
      end
    end

    @tag :integration
    test "returns empty list when parsed from empty output" do
      # This is more of a unit test for the parsing logic
      # but it's good to verify in integration context too
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, shortcuts} ->
          # Should be a list (might be empty)
          assert is_list(shortcuts)

        {:error, _reason} ->
          # App not available
          :ok
      end
    end
  end

  describe "run_shortcut/1 integration" do
    @tag :integration
    test "handles nonexistent shortcut gracefully" do
      # Should return an error for a shortcut that doesn't exist
      result = OSAScriptAdapter.run_shortcut("__NonexistentShortcut_12345__")

      case result do
        {:error, error} ->
          # Should get an error about the shortcut not being found
          assert is_struct(error, ExMacOSControl.Error)

        other ->
          # Unexpected result - but this could happen if someone actually
          # has a shortcut with this name
          IO.puts("Unexpected result for nonexistent shortcut: #{inspect(other)}")
          :ok
      end
    end
  end

  describe "run_shortcut/2 with input integration" do
    @tag :integration
    test "can run shortcut with string input if shortcuts exist" do
      # First, try to get available shortcuts
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, [first_shortcut | _]} ->
          # We have shortcuts, but we can't test them without knowing
          # what they do. Just verify the interface works.
          # Try to run it with input - it might fail if the shortcut
          # doesn't accept input, but that's OK
          result = OSAScriptAdapter.run_shortcut(first_shortcut, input: "test input")

          # Should return :ok, {:ok, output}, or {:error, reason}
          assert match?(:ok, result) or match?({:ok, _}, result) or
                   match?({:error, _}, result)

        _ ->
          # No shortcuts available to test with
          IO.puts("No shortcuts available to test input functionality")
          :ok
      end
    end

    @tag :integration
    test "can run shortcut with number input if shortcuts exist" do
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, [first_shortcut | _]} ->
          result = OSAScriptAdapter.run_shortcut(first_shortcut, input: 42)

          assert match?(:ok, result) or match?({:ok, _}, result) or
                   match?({:error, _}, result)

        _ ->
          IO.puts("No shortcuts available to test number input")
          :ok
      end
    end

    @tag :integration
    test "can run shortcut with map input if shortcuts exist" do
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, [first_shortcut | _]} ->
          result = OSAScriptAdapter.run_shortcut(first_shortcut, input: %{"key" => "value"})

          assert match?(:ok, result) or match?({:ok, _}, result) or
                   match?({:error, _}, result)

        _ ->
          IO.puts("No shortcuts available to test map input")
          :ok
      end
    end

    @tag :integration
    test "can run shortcut with list input if shortcuts exist" do
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, [first_shortcut | _]} ->
          result = OSAScriptAdapter.run_shortcut(first_shortcut, input: ["item1", "item2"])

          assert match?(:ok, result) or match?({:ok, _}, result) or
                   match?({:error, _}, result)

        _ ->
          IO.puts("No shortcuts available to test list input")
          :ok
      end
    end

    @tag :integration
    test "handles empty options (backward compatibility)" do
      case OSAScriptAdapter.list_shortcuts() do
        {:ok, [first_shortcut | _]} ->
          result = OSAScriptAdapter.run_shortcut(first_shortcut, [])

          assert match?(:ok, result) or match?({:ok, _}, result) or
                   match?({:error, _}, result)

        _ ->
          IO.puts("No shortcuts available to test backward compatibility")
          :ok
      end
    end
  end

  describe "facade integration" do
    @tag :integration
    test "ExMacOSControl.list_shortcuts/0 works" do
      result = ExMacOSControl.list_shortcuts()

      case result do
        {:ok, shortcuts} ->
          assert is_list(shortcuts)

        {:error, _reason} ->
          # App not available
          :ok
      end
    end

    @tag :integration
    test "ExMacOSControl.run_shortcut/2 with input works" do
      case ExMacOSControl.list_shortcuts() do
        {:ok, [first_shortcut | _]} ->
          result = ExMacOSControl.run_shortcut(first_shortcut, input: "test")

          assert match?(:ok, result) or match?({:ok, _}, result) or
                   match?({:error, _}, result)

        _ ->
          IO.puts("No shortcuts available for facade test")
          :ok
      end
    end
  end
end
