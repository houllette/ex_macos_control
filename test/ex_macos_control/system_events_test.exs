defmodule ExMacOSControl.SystemEventsTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.Error
  alias ExMacOSControl.SystemEvents

  setup :verify_on_exit!

  describe "list_processes/0" do
    test "returns parsed list of processes" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ "name of every application process"
        {:ok, "Safari, Finder, Terminal"}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == ["Safari", "Finder", "Terminal"]
    end

    test "trims whitespace from process names" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, " Safari , Finder ,  Terminal  "}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == ["Safari", "Finder", "Terminal"]
    end

    test "handles empty process list" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == []
    end

    test "handles single process" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "Finder"}
      end)

      assert {:ok, processes} = SystemEvents.list_processes()
      assert processes == ["Finder"]
    end

    test "returns error when System Events unavailable" do
      error = Error.execution_error("System Events not available")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.list_processes()
    end
  end

  describe "process_exists?/1" do
    test "returns true when process exists" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(exists process "Safari")
        {:ok, "true"}
      end)

      assert {:ok, true} = SystemEvents.process_exists?("Safari")
    end

    test "returns false when process doesn't exist" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(exists process "NonexistentApp")
        {:ok, "false"}
      end)

      assert {:ok, false} = SystemEvents.process_exists?("NonexistentApp")
    end

    test "handles execution errors" do
      error = Error.execution_error("System Events error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.process_exists?("Safari")
    end

    test "handles mixed case boolean values" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "True"}
      end)

      assert {:ok, true} = SystemEvents.process_exists?("Safari")
    end
  end

  describe "quit_application/1" do
    test "returns :ok on successful quit" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(application "Calculator")
        assert script =~ "quit"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.quit_application("Calculator")
    end

    test "returns error when application not found" do
      error = Error.not_found("Application not found", app: "NonexistentApp")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.quit_application("NonexistentApp")
    end

    test "handles permission errors" do
      error = Error.permission_denied("Automation permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.quit_application("Safari")
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to quit application")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.quit_application("Safari")
    end
  end

  describe "launch_application/1" do
    test "returns :ok on successful launch" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(application "Calculator")
        assert script =~ "activate"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.launch_application("Calculator")
    end

    test "returns error when application not found" do
      error = Error.not_found("Application not found", app: "NonexistentApp")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.launch_application("NonexistentApp")
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to launch application")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.launch_application("Calculator")
    end
  end

  describe "activate_application/1" do
    test "delegates to launch_application/1" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(application "Calculator")
        assert script =~ "activate"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.activate_application("Calculator")
    end

    test "returns error when application not found" do
      error = Error.not_found("Application not found", app: "NonexistentApp")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.activate_application("NonexistentApp")
    end
  end

  describe "click_menu_item/3" do
    test "clicks menu item successfully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(process "Safari")
        assert script =~ ~s(menu item "New Tab")
        assert script =~ ~s(menu "File")
        assert script =~ "menu bar 1"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.click_menu_item("Safari", "File", "New Tab")
    end

    test "handles application not running" do
      error = Error.not_found("Process not found", app: "Safari")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.click_menu_item("Safari", "File", "New Tab")
    end

    test "handles menu not found" do
      error = Error.not_found("Menu not found", menu: "Nonexistent")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.click_menu_item("Safari", "Nonexistent", "New Tab")
    end

    test "handles menu item not found" do
      error = Error.not_found("Menu item not found", item: "Nonexistent")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.click_menu_item("Safari", "File", "Nonexistent")
    end

    test "handles permission errors" do
      error = Error.permission_denied("Accessibility permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.click_menu_item("Safari", "File", "New Tab")
    end

    test "escapes special characters in names" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(process "App\\"Name")
        assert script =~ ~s(menu "Menu\\"Name")
        assert script =~ ~s(menu item "Item\\"Name")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.click_menu_item("App\"Name", "Menu\"Name", "Item\"Name")
    end
  end

  describe "press_key/2" do
    test "presses simple key" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(process "Safari")
        assert script =~ ~s(keystroke "t")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.press_key("Safari", "t")
    end

    test "handles app not running" do
      error = Error.not_found("Process not found", app: "Safari")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.press_key("Safari", "t")
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to send keystroke")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.press_key("Safari", "t")
    end

    test "escapes special characters in app name" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(process "App\\"Name")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.press_key("App\"Name", "t")
    end
  end

  describe "press_key/3" do
    test "presses key with single modifier" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(process "Safari")
        assert script =~ ~s(keystroke "t")
        assert script =~ "using {command down}"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.press_key("Safari", "t", using: [:command])
    end

    test "presses key with multiple modifiers" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(keystroke "q")
        assert script =~ "command down"
        assert script =~ "shift down"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.press_key("Safari", "q", using: [:command, :shift])
    end

    test "validates modifier keys" do
      valid_modifiers = [:command, :control, :option, :shift]

      for modifier <- valid_modifiers do
        expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
          {:ok, ""}
        end)

        assert :ok = SystemEvents.press_key("Safari", "t", using: [modifier])
      end
    end

    test "returns error for invalid modifiers" do
      assert {:error, error} = SystemEvents.press_key("Safari", "t", using: [:invalid])
      assert error.type == :execution_error
      assert error.message =~ "Invalid modifier"
    end

    test "handles multiple invalid modifiers" do
      assert {:error, error} = SystemEvents.press_key("Safari", "t", using: [:invalid, :bad])
      assert error.type == :execution_error
    end

    test "handles permission errors" do
      error = Error.permission_denied("Accessibility permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.press_key("Safari", "t", using: [:command])
    end
  end

  describe "get_window_properties/1" do
    test "returns window properties" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(process "Safari")
        assert script =~ "front window"
        {:ok, "100, 200, 800, 600, Google"}
      end)

      assert {:ok, props} = SystemEvents.get_window_properties("Safari")
      assert props == %{position: [100, 200], size: [800, 600], title: "Google"}
    end

    test "returns nil when no windows" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "count of windows"
        {:ok, ""}
      end)

      assert {:ok, nil} = SystemEvents.get_window_properties("Safari")
    end

    test "parses position and size correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "0, 0, 1920, 1080, My Window"}
      end)

      assert {:ok, props} = SystemEvents.get_window_properties("App")
      assert props.position == [0, 0]
      assert props.size == [1920, 1080]
      assert props.title == "My Window"
    end

    test "handles app not running" do
      error = Error.not_found("Process not found", app: "Safari")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.get_window_properties("Safari")
    end

    test "handles permission errors" do
      error = Error.permission_denied("Accessibility permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.get_window_properties("Safari")
    end
  end

  describe "set_window_bounds/3" do
    test "sets window position and size" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ ~s(process "Calculator")
        assert script =~ "position of front window to {100, 100}"
        assert script =~ "size of front window to {400, 500}"
        {:ok, ""}
      end)

      assert :ok =
               SystemEvents.set_window_bounds("Calculator", position: [100, 100], size: [400, 500])
    end

    test "handles no windows" do
      error = Error.execution_error("No windows available", app: "Calculator")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} =
               SystemEvents.set_window_bounds("Calculator", position: [100, 100], size: [400, 500])
    end

    test "handles app not running" do
      error = Error.not_found("Process not found", app: "Safari")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} =
               SystemEvents.set_window_bounds("Safari", position: [100, 100], size: [400, 500])
    end

    test "validates bounds parameters" do
      assert {:error, error} = SystemEvents.set_window_bounds("App", position: [100], size: [400, 500])
      assert error.type == :execution_error
      assert error.message =~ "Invalid position"
    end

    test "validates size parameters" do
      assert {:error, error} = SystemEvents.set_window_bounds("App", position: [100, 100], size: [400])
      assert error.type == :execution_error
      assert error.message =~ "Invalid size"
    end

    test "handles permission errors" do
      error = Error.permission_denied("Accessibility permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} =
               SystemEvents.set_window_bounds("Safari", position: [100, 100], size: [400, 500])
    end
  end

  describe "reveal_in_finder/1" do
    test "reveals file in Finder successfully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(tell application "Finder")
        assert script =~ ~s(POSIX file "/Users/test/file.txt")
        assert script =~ "reveal"
        assert script =~ "activate"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.reveal_in_finder("/Users/test/file.txt")
    end

    test "reveals folder in Finder successfully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(POSIX file "/Users/test/folder")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.reveal_in_finder("/Users/test/folder")
    end

    test "handles nonexistent path" do
      error = Error.not_found("File not found", path: "/nonexistent/path")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.reveal_in_finder("/nonexistent/path")
    end

    test "validates absolute path" do
      assert {:error, error} = SystemEvents.reveal_in_finder("relative/path")
      assert error.type == :execution_error
      assert error.message =~ "Path must be absolute"
    end

    test "handles Finder errors" do
      error = Error.execution_error("Finder error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.reveal_in_finder("/Users/test/file.txt")
    end

    test "escapes special characters in path" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(POSIX file "/Users/test/file\\"name.txt")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.reveal_in_finder("/Users/test/file\"name.txt")
    end
  end

  describe "get_selected_finder_items/0" do
    test "returns list of selected items" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(tell application "Finder")
        assert script =~ "selection"
        assert script =~ "POSIX path"
        {:ok, "/Users/test/file1.txt, /Users/test/file2.txt"}
      end)

      assert {:ok, items} = SystemEvents.get_selected_finder_items()
      assert items == ["/Users/test/file1.txt", "/Users/test/file2.txt"]
    end

    test "returns empty list when nothing selected" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, []} = SystemEvents.get_selected_finder_items()
    end

    test "handles Finder not running" do
      error = Error.execution_error("Finder is not running")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.get_selected_finder_items()
    end

    test "parses multiple paths correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "/Users/test/a.txt, /Users/test/b.txt, /Users/test/c.txt"}
      end)

      assert {:ok, items} = SystemEvents.get_selected_finder_items()
      assert length(items) == 3
      assert "/Users/test/a.txt" in items
      assert "/Users/test/b.txt" in items
      assert "/Users/test/c.txt" in items
    end

    test "handles single selected item" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "/Users/test/single.txt"}
      end)

      assert {:ok, items} = SystemEvents.get_selected_finder_items()
      assert items == ["/Users/test/single.txt"]
    end

    test "trims whitespace from paths" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, " /Users/test/file1.txt , /Users/test/file2.txt "}
      end)

      assert {:ok, items} = SystemEvents.get_selected_finder_items()
      assert items == ["/Users/test/file1.txt", "/Users/test/file2.txt"]
    end
  end

  describe "trash_file/1" do
    test "moves file to trash successfully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(tell application "Finder")
        assert script =~ ~s(POSIX file "/Users/test/file.txt")
        assert script =~ "move"
        assert script =~ "to trash"
        {:ok, ""}
      end)

      assert :ok = SystemEvents.trash_file("/Users/test/file.txt")
    end

    test "moves folder to trash successfully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(POSIX file "/Users/test/folder")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.trash_file("/Users/test/folder")
    end

    test "handles nonexistent file" do
      error = Error.not_found("File not found", path: "/nonexistent/file")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.trash_file("/nonexistent/file")
    end

    test "validates absolute path" do
      assert {:error, error} = SystemEvents.trash_file("relative/path")
      assert error.type == :execution_error
      assert error.message =~ "Path must be absolute"
    end

    test "handles permission errors" do
      error = Error.permission_denied("Cannot move file to trash", path: "/protected/file")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = SystemEvents.trash_file("/protected/file")
    end

    test "escapes special characters in path" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(POSIX file "/Users/test/file\\"name.txt")
        {:ok, ""}
      end)

      assert :ok = SystemEvents.trash_file("/Users/test/file\"name.txt")
    end
  end
end
