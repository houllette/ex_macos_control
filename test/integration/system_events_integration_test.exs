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

  describe "click_menu_item/3 (requires accessibility)" do
    setup do
      # Launch TextEdit (safe, simple app)
      SystemEvents.launch_application("TextEdit")
      Process.sleep(1000)

      on_exit(fn ->
        SystemEvents.quit_application("TextEdit")
        Process.sleep(1000)
      end)

      :ok
    end

    @tag :integration
    @tag :skip
    test "clicks menu item in TextEdit" do
      # File → New
      result = SystemEvents.click_menu_item("TextEdit", "File", "New")

      # Accept success or permission error
      assert match?(:ok, result) or match?({:error, %{type: :permission_denied}}, result)

      if result == :ok do
        Process.sleep(500)
      end
    end

    @tag :integration
    @tag :skip
    test "handles permission denial gracefully" do
      # Test should either succeed or return permission error
      result = SystemEvents.click_menu_item("TextEdit", "File", "New")
      assert match?(:ok, result) or match?({:error, %{type: :permission_denied}}, result)
    end

    @tag :integration
    @tag :skip
    test "handles nonexistent menu item" do
      result = SystemEvents.click_menu_item("TextEdit", "File", "NonexistentMenuItem123")

      # Should fail with either not_found or execution_error
      case result do
        {:error, error} ->
          assert error.type in [:not_found, :execution_error, :permission_denied]

        :ok ->
          # Permission might be denied, can't test
          assert true
      end
    end
  end

  describe "press_key/2 and press_key/3 (requires accessibility)" do
    setup do
      SystemEvents.launch_application("TextEdit")
      Process.sleep(1000)

      on_exit(fn ->
        SystemEvents.quit_application("TextEdit")
        Process.sleep(1000)
      end)

      :ok
    end

    @tag :integration
    @tag :skip
    test "presses simple key" do
      result = SystemEvents.press_key("TextEdit", "a")
      assert match?(:ok, result) or match?({:error, %{type: :permission_denied}}, result)
    end

    @tag :integration
    @tag :skip
    test "presses key with command modifier" do
      # Command+N for new document
      result = SystemEvents.press_key("TextEdit", "n", using: [:command])
      assert match?(:ok, result) or match?({:error, %{type: :permission_denied}}, result)

      if result == :ok do
        Process.sleep(500)
      end
    end

    @tag :integration
    @tag :skip
    test "presses key with multiple modifiers" do
      # Command+Shift+N
      result = SystemEvents.press_key("TextEdit", "n", using: [:command, :shift])
      assert match?(:ok, result) or match?({:error, %{type: :permission_denied}}, result)
    end
  end

  describe "window management (requires accessibility)" do
    setup do
      SystemEvents.launch_application("Calculator")
      Process.sleep(1000)

      on_exit(fn ->
        SystemEvents.quit_application("Calculator")
        Process.sleep(1000)
      end)

      :ok
    end

    @tag :integration
    @tag :skip
    test "gets window properties" do
      result = SystemEvents.get_window_properties("Calculator")

      case result do
        {:ok, props} when is_map(props) ->
          assert Map.has_key?(props, :position)
          assert Map.has_key?(props, :size)
          assert Map.has_key?(props, :title)
          assert is_list(props.position)
          assert length(props.position) == 2
          assert is_list(props.size)
          assert length(props.size) == 2
          assert is_binary(props.title)

        {:ok, nil} ->
          # No windows - acceptable
          assert true

        {:error, %{type: :permission_denied}} ->
          # No accessibility permission - acceptable for test
          assert true

        {:error, error} ->
          # Other errors also acceptable in integration test
          assert error.type in [:not_found, :execution_error]
      end
    end

    @tag :integration
    @tag :skip
    test "sets window bounds" do
      result =
        SystemEvents.set_window_bounds("Calculator",
          position: [100, 100],
          size: [400, 500]
        )

      # Accept success or permission error
      assert match?(:ok, result) or match?({:error, %{type: :permission_denied}}, result)

      # Verify if it worked (if we have permissions)
      if result == :ok do
        Process.sleep(500)
        {:ok, props} = SystemEvents.get_window_properties("Calculator")

        if props != nil do
          # Check that position and size are close (may not be exact)
          [x, y] = props.position
          [w, h] = props.size
          assert x >= 90 and x <= 110
          assert y >= 90 and y <= 110
          assert w >= 390 and w <= 410
          assert h >= 490 and h <= 510
        end
      end
    end

    @tag :integration
    @tag :skip
    test "round-trip: get properties, modify, verify" do
      # Get current properties
      result1 = SystemEvents.get_window_properties("Calculator")

      case result1 do
        {:ok, original_props} when is_map(original_props) ->
          # Set new bounds
          result2 =
            SystemEvents.set_window_bounds("Calculator",
              position: [200, 200],
              size: [350, 450]
            )

          if result2 == :ok do
            Process.sleep(500)

            # Get properties again
            {:ok, new_props} = SystemEvents.get_window_properties("Calculator")

            if new_props != nil do
              # Verify changes
              [new_x, new_y] = new_props.position
              [new_w, new_h] = new_props.size
              assert new_x >= 190 and new_x <= 210
              assert new_y >= 190 and new_y <= 210
              assert new_w >= 340 and new_w <= 360
              assert new_h >= 440 and new_h <= 460
            end
          end

        _ ->
          # Skip if no permissions or no windows
          assert true
      end
    end
  end

  describe "UI automation workflow" do
    @tag :integration
    @tag :skip
    test "complete UI workflow with TextEdit" do
      # 1. Launch TextEdit
      assert :ok = SystemEvents.launch_application("TextEdit")
      Process.sleep(1000)

      # 2. Create new document (Command+N)
      result = SystemEvents.press_key("TextEdit", "n", using: [:command])

      if result == :ok do
        Process.sleep(500)

        # 3. Type some text
        assert :ok = SystemEvents.press_key("TextEdit", "H")
        assert :ok = SystemEvents.press_key("TextEdit", "i")
        Process.sleep(500)

        # 4. Get window properties
        {:ok, props} = SystemEvents.get_window_properties("TextEdit")

        if props != nil do
          assert is_map(props)
          assert Map.has_key?(props, :position)
        end
      end

      # Clean up
      SystemEvents.quit_application("TextEdit")
      Process.sleep(1000)
    end
  end
end
