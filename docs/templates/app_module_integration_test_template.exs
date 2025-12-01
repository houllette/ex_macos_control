defmodule ExMacOSControl.AppNameIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{AppName, SystemEvents, TestHelpers}

  # Tag all tests in this module as integration tests
  # They will only run when: mix test --include integration
  @moduletag :integration

  # TODO: If ALL tests in this module are destructive/risky, add:
  # @moduletag :skip
  # This will skip all tests by default for safety

  setup do
    # Skip unless integration tests are explicitly requested
    TestHelpers.skip_unless_integration()

    # Save the original adapter configuration
    original_adapter = Application.get_env(:ex_macos_control, :adapter)

    # Set to use the real OSAScriptAdapter for integration tests
    Application.put_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)

    # Restore the original adapter after the test
    on_exit(fn ->
      Application.put_env(:ex_macos_control, :adapter, original_adapter)
    end)

    # TODO: Launch the application if needed
    # Some apps need to be running before automation works
    SystemEvents.launch_application("AppName")

    # TODO: Wait for app to be ready
    # Adjust sleep time as needed for your app
    Process.sleep(1000)

    # TODO: Add any additional setup
    # - Create test data
    # - Configure app settings
    # - Clear previous state

    :ok
  end

  # TODO: Create describe blocks for each function you want to integration test
  describe "some_function/1" do
    @tag :integration
    test "performs real operation" do
      # TODO: Call the function with real data
      assert {:ok, result} = AppName.some_function("test value")

      # TODO: Verify the result
      assert is_binary(result)
      # Add more specific assertions based on expected behavior
    end

    # TODO: Add more integration tests for different scenarios
    @tag :integration
    test "handles edge case in real environment" do
      # Test edge cases that are hard to mock
      assert {:ok, _result} = AppName.some_function("")
    end
  end

  # TODO: For READ-ONLY operations, safe to run by default
  describe "get_status/0" do
    @tag :integration
    test "retrieves current status from app" do
      assert {:ok, status} = AppName.get_status()
      assert is_map(status)
      # Verify expected fields exist
      assert Map.has_key?(status, :field1)
    end
  end

  # TODO: For DESTRUCTIVE operations, use @tag :skip
  # These tests document the functionality but don't run automatically
  describe "delete_item/1" do
    @tag :skip
    @tag :integration
    test "actually deletes an item" do
      # This test would really delete something, so it's skipped by default
      # To run: Remove @tag :skip and run manually with caution

      # TODO: Setup - create test item first
      # {:ok, item_id} = AppName.create_test_item()

      # TODO: Perform deletion
      # assert :ok = AppName.delete_item(item_id)

      # TODO: Verify deletion
      # assert {:error, %Error{type: :not_found}} = AppName.get_item(item_id)

      # TODO: Cleanup if needed
    end
  end

  # TODO: For operations that SEND data externally (email, messages, etc.)
  describe "send_message/2" do
    @tag :skip
    @tag :integration
    test "sends a real message" do
      # IMPORTANT: This test sends real messages!
      # Only run manually with safe test recipients

      # TODO: Use a safe test recipient
      # test_recipient = "your-test-number@example.com"
      # assert :ok = AppName.send_message(test_recipient, "Test message")

      # TODO: Verify message was sent (if possible)
      # May require checking app UI or logs
    end
  end

  # TODO: For operations requiring user interaction
  describe "operation_with_ui_confirmation/1" do
    @tag :skip
    @tag :integration
    test "handles confirmation dialog" do
      # This test requires user to click a dialog
      # Document what the user should do

      # TODO: Explain in test output what user should do
      # IO.puts("Please click 'OK' when the dialog appears...")

      # TODO: Call the function
      # assert :ok = AppName.operation_with_ui_confirmation("test")
    end
  end

  # TODO: Add cleanup if needed
  # Use on_exit in setup or specific tests to clean up
  # Example:
  # on_exit(fn ->
  #   AppName.delete_test_data()
  # end)
end

# IMPORTANT: Integration Test Guidelines
#
# 1. READ-ONLY tests: Safe to run, tag with @integration only
#    - Getting status, listing items, reading data
#
# 2. DESTRUCTIVE tests: Skip by default, tag with @skip and @integration
#    - Deleting items, modifying data, changing settings
#
# 3. EXTERNAL COMMUNICATION: Always skip, tag with @skip and @integration
#    - Sending emails, messages, making purchases
#
# 4. USER INTERACTION: Skip by default, document steps
#    - Operations requiring user to click dialogs
#
# 5. Setup Requirements:
#    - Document what needs to be configured before tests run
#    - Include app settings, test accounts, permissions
#
# 6. Test Data:
#    - Create test data in setup when possible
#    - Clean up test data in on_exit
#    - Use unique identifiers to avoid conflicts
#
# To run integration tests:
#   mix test --include integration
#
# To run specific skipped test:
#   1. Remove @tag :skip from the test
#   2. Run: mix test path/to/test.exs:line_number --include integration
#   3. Re-add @tag :skip after manual testing
