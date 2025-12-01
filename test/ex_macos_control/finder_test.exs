defmodule ExMacOSControl.FinderTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  alias ExMacOSControl.Finder

  describe "get_selection/0" do
    test "returns parsed list of selected paths" do
      output = "/Users/me/file1.txt, /Users/me/file2.txt"

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"Finder\""
        assert script =~ "selection"
        {:ok, output}
      end)

      assert {:ok, paths} = Finder.get_selection()
      assert length(paths) == 2
      assert "/Users/me/file1.txt" in paths
      assert "/Users/me/file2.txt" in paths
    end

    test "returns empty list when no selection" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, []} = Finder.get_selection()
    end

    test "handles Finder errors gracefully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, ExMacOSControl.Error.execution_error("Finder error")}
      end)

      assert {:error, error} = Finder.get_selection()
      assert error.type == :execution_error
    end
  end

  describe "open_location/1" do
    test "opens location successfully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"Finder\""
        assert script =~ "activate"
        assert script =~ "open POSIX file \"/Users/me/Documents\""
        {:ok, ""}
      end)

      assert :ok = Finder.open_location("/Users/me/Documents")
    end

    test "handles invalid paths" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, ExMacOSControl.Error.not_found("Path not found", path: "/nonexistent")}
      end)

      assert {:error, error} = Finder.open_location("/nonexistent")
      assert error.type == :not_found
    end
  end

  describe "new_window/1" do
    test "creates new window at path" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"Finder\""
        assert script =~ "activate"
        assert script =~ "make new Finder window to POSIX file \"/Applications\""
        {:ok, ""}
      end)

      assert :ok = Finder.new_window("/Applications")
    end

    test "handles invalid paths" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, ExMacOSControl.Error.not_found("Path not found", path: "/invalid")}
      end)

      assert {:error, error} = Finder.new_window("/invalid")
      assert error.type == :not_found
    end
  end

  describe "get_current_folder/0" do
    test "returns current folder path" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"Finder\""
        assert script =~ "target of front Finder window"
        {:ok, "/Users/me/Documents"}
      end)

      assert {:ok, "/Users/me/Documents"} = Finder.get_current_folder()
    end

    test "returns empty string when no windows" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, ""} = Finder.get_current_folder()
    end

    test "handles Finder errors" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, ExMacOSControl.Error.execution_error("Finder error")}
      end)

      assert {:error, error} = Finder.get_current_folder()
      assert error.type == :execution_error
    end
  end

  describe "set_view/1" do
    test "sets view to icon" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"Finder\""
        assert script =~ "set current view of front Finder window to icon view"
        {:ok, ""}
      end)

      assert :ok = Finder.set_view(:icon)
    end

    test "sets view to list" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "set current view of front Finder window to list view"
        {:ok, ""}
      end)

      assert :ok = Finder.set_view(:list)
    end

    test "sets view to column" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "set current view of front Finder window to column view"
        {:ok, ""}
      end)

      assert :ok = Finder.set_view(:column)
    end

    test "sets view to gallery" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "set current view of front Finder window to flow view"
        {:ok, ""}
      end)

      assert :ok = Finder.set_view(:gallery)
    end

    test "returns error for invalid view mode" do
      assert {:error, error} = Finder.set_view(:invalid)
      assert error.type == :execution_error
      assert error.message =~ "Invalid view mode"
    end

    test "handles Finder errors" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, ExMacOSControl.Error.execution_error("No Finder windows")}
      end)

      assert {:error, error} = Finder.set_view(:icon)
      assert error.type == :execution_error
    end
  end
end
