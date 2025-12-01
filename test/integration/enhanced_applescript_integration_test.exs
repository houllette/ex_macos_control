defmodule ExMacOSControl.EnhancedAppleScriptIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{OSAScriptAdapter, TestHelpers}

  # These tests require macOS with osascript
  @moduletag :integration

  setup do
    # Skip if not on macOS with osascript
    TestHelpers.skip_unless_integration()
    :ok
  end

  # Helper to call the real adapter directly, bypassing the facade's mock configuration
  defp run_applescript(script, opts \\ []) do
    OSAScriptAdapter.run_applescript(script, opts)
  end

  describe "run_applescript/2 with timeout option" do
    @tag :integration
    test "executes script within timeout successfully" do
      # Script that completes quickly should succeed
      script = "delay 0.1\nreturn \"success\""

      {:ok, result} = run_applescript(script, timeout: 5000)
      assert TestHelpers.normalize_output(result) == "success"
    end

    @tag :integration
    test "times out when script exceeds timeout" do
      # Script that takes too long should timeout
      script = "delay 5\nreturn \"should not see this\""

      result = run_applescript(script, timeout: 100)

      assert {:error, error} = result
      assert error.type == :timeout
      assert error.details.timeout == 100
    end

    @tag :integration
    test "works with no timeout option (backward compatibility)" do
      script = ~s(return "Hello, World!")

      {:ok, result} = run_applescript(script)
      assert TestHelpers.normalize_output(result) == "Hello, World!"
    end
  end

  describe "run_applescript/2 with args option" do
    @tag :integration
    test "passes single argument to script" do
      script_content = TestHelpers.read_fixture!("applescript/with_arguments.applescript")

      {:ok, result} = run_applescript(script_content, args: ["test_arg"])
      assert TestHelpers.normalize_output(result) == "test_arg"
    end

    @tag :integration
    test "passes multiple arguments to script" do
      script = """
      on run argv
        set result to ""
        repeat with arg in argv
          set result to result & arg
        end repeat
        return result
      end run
      """

      {:ok, result} = run_applescript(script, args: ["Hello", "World"])
      assert TestHelpers.normalize_output(result) == "HelloWorld"
    end

    @tag :integration
    test "handles arguments with spaces" do
      script_content = TestHelpers.read_fixture!("applescript/with_arguments.applescript")

      {:ok, result} = run_applescript(script_content, args: ["Hello World"])
      assert TestHelpers.normalize_output(result) == "Hello World"
    end

    @tag :integration
    test "handles arguments with special characters" do
      script_content = TestHelpers.read_fixture!("applescript/with_arguments.applescript")

      {:ok, result} = run_applescript(script_content, args: ["test@#$%"])
      assert TestHelpers.normalize_output(result) == "test@#$%"
    end

    @tag :integration
    test "handles empty args list" do
      script_content = TestHelpers.read_fixture!("applescript/with_arguments.applescript")

      {:ok, result} = run_applescript(script_content, args: [])
      assert TestHelpers.normalize_output(result) == "No arguments provided"
    end

    @tag :integration
    test "handles numbers as string arguments" do
      script = """
      on run argv
        if (count of argv) > 0 then
          return (item 1 of argv as integer) * 2
        end if
      end run
      """

      {:ok, result} = run_applescript(script, args: ["42"])
      assert TestHelpers.normalize_output(result) == "84"
    end
  end

  describe "run_applescript/2 with combined options" do
    @tag :integration
    test "uses both timeout and args options together" do
      script_content = TestHelpers.read_fixture!("applescript/with_arguments.applescript")

      {:ok, result} =
        run_applescript(script_content, timeout: 5000, args: ["combined"])

      assert TestHelpers.normalize_output(result) == "combined"
    end

    @tag :integration
    test "timeout works correctly with args" do
      # Script that uses arguments and should timeout
      script = """
      on run argv
        if (count of argv) > 0 then
          delay (item 1 of argv as integer)
        end if
        return "completed"
      end run
      """

      result = run_applescript(script, timeout: 100, args: ["5"])

      assert {:error, error} = result
      assert error.type == :timeout
    end
  end

  describe "run_applescript/2 error handling with options" do
    @tag :integration
    test "returns syntax errors even with options" do
      script = "this is not valid applescript"

      result = run_applescript(script, timeout: 5000)

      assert {:error, error} = result
      assert error.type in [:syntax_error, :execution_error]
    end

    @tag :integration
    test "handles script errors with args" do
      script = """
      on run argv
        error "Intentional error"
      end run
      """

      result = run_applescript(script, args: ["test"])

      assert {:error, error} = result
      assert error.type == :execution_error
    end
  end

  describe "run_applescript/2 real-world scenarios" do
    @tag :integration
    test "calculates sum with arguments" do
      script = """
      on run argv
        set num1 to item 1 of argv as integer
        set num2 to item 2 of argv as integer
        return num1 + num2
      end run
      """

      {:ok, result} = run_applescript(script, args: ["10", "20"])
      assert TestHelpers.normalize_output(result) == "30"
    end

    @tag :integration
    test "concatenates strings with arguments" do
      script = """
      on run argv
        set firstName to item 1 of argv
        set lastName to item 2 of argv
        return firstName & " " & lastName
      end run
      """

      {:ok, result} = run_applescript(script, args: ["John", "Doe"])
      assert TestHelpers.normalize_output(result) == "John Doe"
    end

    @tag :integration
    test "processes list of items with args" do
      script = """
      on run argv
        set resultList to {}
        repeat with arg in argv
          set end of resultList to (arg as text) & "!"
        end repeat
        return resultList as text
      end run
      """

      {:ok, result} = run_applescript(script, args: ["apple", "banana", "cherry"])
      # AppleScript will join with some delimiter, just check it contains our items
      assert result =~ "apple!"
      assert result =~ "banana!"
      assert result =~ "cherry!"
    end
  end
end
