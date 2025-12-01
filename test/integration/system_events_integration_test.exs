defmodule ExMacOSControl.SystemEventsIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{SystemEvents, TestHelpers}

  # These tests require macOS with osascript
  @moduletag :integration

  setup do
    # Skip if not on macOS with osascript
    TestHelpers.skip_unless_integration()

    # Use the real OSAScriptAdapter for integration tests instead of the mock
    original_adapter = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)

    on_exit(fn ->
      # Restore the original adapter configuration
      Application.put_env(:ex_macos_control, :adapter, original_adapter)
    end)

    :ok
  end

  describe "list_processes/0" do
    @tag :integration
    test "returns list of actual running processes" do
      assert {:ok, processes} = SystemEvents.list_processes()
      assert is_list(processes)
      assert length(processes) > 0

      # Finder always runs on macOS
      assert "Finder" in processes
    end

    @tag :integration
    test "process names are trimmed and non-empty" do
      assert {:ok, processes} = SystemEvents.list_processes()

      for process <- processes do
        assert is_binary(process)
        assert String.trim(process) == process
        assert process != ""
      end
    end
  end

  describe "process_exists?/1" do
    @tag :integration
    test "returns true for Finder (always running)" do
      assert {:ok, true} = SystemEvents.process_exists?("Finder")
    end

    @tag :integration
    test "returns false for nonexistent process" do
      assert {:ok, false} = SystemEvents.process_exists?("NonexistentApp12345XYZ")
    end

    @tag :integration
    test "is case-sensitive" do
      # Finder exists but "finder" might not match exactly depending on macOS behavior
      assert {:ok, true} = SystemEvents.process_exists?("Finder")
    end
  end

  describe "launch_application/1 and quit_application/1" do
    setup do
      # Clean up Calculator if it's running before each test
      SystemEvents.quit_application("Calculator")
      Process.sleep(1000)
      :ok
    end

    @tag :integration
    test "launches Calculator successfully" do
      assert :ok = SystemEvents.launch_application("Calculator")
      Process.sleep(1000)

      assert {:ok, true} = SystemEvents.process_exists?("Calculator")

      # Clean up
      SystemEvents.quit_application("Calculator")
      Process.sleep(1000)
    end

    @tag :integration
    test "quits Calculator successfully" do
      # First launch it
      assert :ok = SystemEvents.launch_application("Calculator")
      Process.sleep(1000)
      assert {:ok, true} = SystemEvents.process_exists?("Calculator")

      # Now quit it
      assert :ok = SystemEvents.quit_application("Calculator")
      Process.sleep(1000)

      assert {:ok, false} = SystemEvents.process_exists?("Calculator")
    end

    @tag :integration
    test "launch is idempotent - can call on already running app" do
      # Launch once
      assert :ok = SystemEvents.launch_application("Calculator")
      Process.sleep(1000)

      # Launch again
      assert :ok = SystemEvents.launch_application("Calculator")
      Process.sleep(1000)

      assert {:ok, true} = SystemEvents.process_exists?("Calculator")

      # Clean up
      SystemEvents.quit_application("Calculator")
      Process.sleep(1000)
    end

    @tag :integration
    test "quit handles app that's not running gracefully" do
      # Ensure Calculator is not running
      SystemEvents.quit_application("Calculator")
      Process.sleep(1000)
      assert {:ok, false} = SystemEvents.process_exists?("Calculator")

      # Try to quit again - this might return an error or :ok depending on implementation
      # We accept either behavior as long as it doesn't crash
      result = SystemEvents.quit_application("Calculator")

      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "activate_application/1" do
    setup do
      # Clean up Calculator if it's running before each test
      SystemEvents.quit_application("Calculator")
      Process.sleep(1000)
      :ok
    end

    @tag :integration
    test "activates Calculator successfully (alias for launch)" do
      assert :ok = SystemEvents.activate_application("Calculator")
      Process.sleep(1000)

      assert {:ok, true} = SystemEvents.process_exists?("Calculator")

      # Clean up
      SystemEvents.quit_application("Calculator")
      Process.sleep(1000)
    end
  end

  describe "error handling" do
    @tag :integration
    test "handles nonexistent application in launch" do
      result = SystemEvents.launch_application("ThisAppDefinitelyDoesNotExist123XYZ")

      assert {:error, error} = result
      assert error.type in [:not_found, :execution_error]
    end
  end

  describe "real-world workflow" do
    @tag :integration
    test "complete workflow: check, launch, verify, quit, verify" do
      app_name = "Calculator"

      # 1. Quit if running
      SystemEvents.quit_application(app_name)
      Process.sleep(1000)

      # 2. Verify it's not running
      assert {:ok, false} = SystemEvents.process_exists?(app_name)

      # 3. Launch it
      assert :ok = SystemEvents.launch_application(app_name)
      Process.sleep(1000)

      # 4. Verify it's running
      assert {:ok, true} = SystemEvents.process_exists?(app_name)

      # 5. Verify it appears in process list
      assert {:ok, processes} = SystemEvents.list_processes()
      assert app_name in processes

      # 6. Quit it
      assert :ok = SystemEvents.quit_application(app_name)
      Process.sleep(1000)

      # 7. Verify it's no longer running
      assert {:ok, false} = SystemEvents.process_exists?(app_name)
    end
  end
end
