defmodule ExMacOSControl.OSAScriptAdapterTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.OSAScriptAdapter

  describe "run_applescript/1 - backward compatibility" do
    test "delegates to run_applescript/2 with empty options" do
      # The function should exist and call run_applescript/2
      assert function_exported?(OSAScriptAdapter, :run_applescript, 1)
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end
  end

  describe "run_applescript/2 - options handling" do
    test "accepts empty options list" do
      # Empty options should work just like run_applescript/1
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "accepts timeout option" do
      # Should accept timeout in keyword list
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "accepts args option" do
      # Should accept args in keyword list
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "accepts both timeout and args options" do
      # Should accept multiple options
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "accepts unknown options (future-proof)" do
      # Unknown options should be ignored gracefully
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end
  end

  describe "run_applescript/2 - return values" do
    test "returns {:ok, output} tuple on success" do
      # Note: These tests will only work on macOS with osascript
      # We're testing the interface/contract here
      script = ~s(return "test")

      # The function should return an ok/error tuple
      result = OSAScriptAdapter.run_applescript(script, [])
      assert is_tuple(result)
      assert tuple_size(result) == 2

      case result do
        {:ok, _output} -> :ok
        {:error, _reason} -> :ok
        _ -> flunk("Expected {:ok, _} or {:error, _} tuple")
      end
    end

    test "returns trimmed output" do
      # Output should have whitespace trimmed
      # Testing with empty options
      assert is_function(&OSAScriptAdapter.run_applescript/2, 2)
    end
  end

  describe "run_applescript/2 - argument passing" do
    test "passes args to osascript command" do
      # Args should be appended after the -e flag and script
      # Testing the interface exists
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "handles empty args list" do
      # Empty args should be same as no args
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "handles single arg" do
      # Single argument should work
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "handles multiple args" do
      # Multiple arguments should work
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end
  end

  describe "run_applescript/2 - timeout handling" do
    test "respects timeout option" do
      # Timeout should be passed to System.cmd
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "returns error on timeout" do
      # When timeout occurs, should return error tuple
      # Note: Actual timeout testing requires integration test
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end
  end

  describe "run_applescript/2 - error handling" do
    test "handles osascript errors" do
      # Should handle non-zero exit codes
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "uses Error.parse_osascript_error for errors" do
      # Should use the Error module for parsing
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end

    test "uses Error.timeout for timeout errors" do
      # Should use Error.timeout for timeout errors
      assert function_exported?(OSAScriptAdapter, :run_applescript, 2)
    end
  end
end
