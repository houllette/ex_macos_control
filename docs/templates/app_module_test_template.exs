defmodule ExMacOSControl.AppNameTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExMacOSControl.{AppName, Error}

  # This ensures all expectations are verified after each test
  setup :verify_on_exit!

  setup do
    # Stub the adapter for all tests with a default response
    # This prevents tests from failing if we don't set expectations
    stub(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
      {:ok, ""}
    end)

    :ok
  end

  # TODO: Create a describe block for each public function
  describe "some_function/1" do
    test "generates correct AppleScript" do
      # TODO: Set expectation for the adapter
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        # TODO: Verify the script contains expected AppleScript commands
        assert script =~ ~s(tell application "AppName")
        assert script =~ ~s(return "result")
        {:ok, "result"}
      end)

      # TODO: Call your function and verify the result
      assert {:ok, "result"} = AppName.some_function("value")
    end

    test "escapes quotes in parameters" do
      # TODO: Verify that quotes in user input are properly escaped
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        # The escaped quote should appear as \" in the AppleScript
        assert script =~ ~s(\\")
        {:ok, ""}
      end)

      # Call with input containing quotes
      AppName.some_function(~s(value with "quotes"))
    end

    test "handles adapter errors" do
      # TODO: Test error handling
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:error, %Error{type: :execution_error, message: "error"}}
      end)

      # Verify the error is propagated correctly
      assert {:error, %Error{type: :execution_error}} =
        AppName.some_function("value")
    end

    test "parses results correctly" do
      # TODO: Test result parsing
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        # Return a result that needs parsing (e.g., with whitespace)
        {:ok, "  result  "}
      end)

      # Verify the result is parsed (trimmed in this case)
      assert {:ok, "result"} = AppName.some_function("value")
    end

    # TODO: Add more test cases:
    # - Test with empty results
    # - Test with malformed data
    # - Test with edge case inputs
    # - Test validation logic
  end

  # TODO: Add describe blocks for other functions
  # Example:
  # describe "another_function/2" do
  #   test "..." do
  #     ...
  #   end
  # end

  # TODO: For functions that return lists
  describe "list_items/0" do
    test "parses multiple items correctly" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, "item1, item2, item3"}
      end)

      assert {:ok, ["item1", "item2", "item3"]} = AppName.list_items()
    end

    test "handles empty results" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, []} = AppName.list_items()
    end

    test "handles single item" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, "item1"}
      end)

      assert {:ok, ["item1"]} = AppName.list_items()
    end
  end

  # TODO: For functions with structured data
  describe "get_structured_data/0" do
    test "parses structured data correctly" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        # Using pipe delimiter for structured data
        {:ok, "field1|field2|field3"}
      end)

      assert {:ok, %{field1: "field1", field2: "field2", field3: "field3"}} =
        AppName.get_structured_data()
    end

    test "handles malformed data gracefully" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, "incomplete"}
      end)

      # Verify graceful handling (return error or default values)
      assert {:error, _} = AppName.get_structured_data()
    end
  end

  # TODO: For functions with validation
  describe "create_item/1" do
    test "validates required fields" do
      # Test with missing required field
      assert {:error, %Error{type: :execution_error}} =
        AppName.create_item(field2: "value")
    end

    test "accepts valid input" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert :ok = AppName.create_item(field1: "value1", field2: "value2")
    end

    test "uses default values for optional fields" do
      expect(ExMacOSControl.MockAdapter, :run_applescript, fn script ->
        # Verify default value is used
        assert script =~ ~s(default_value)
        {:ok, ""}
      end)

      AppName.create_item(field1: "value1")
    end
  end
end
