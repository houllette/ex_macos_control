defmodule ExMacOSControl.FinderIntegrationTest do
  use ExUnit.Case, async: false

  import Mox

  @moduletag :integration

  alias ExMacOSControl.Finder

  setup :verify_on_exit!

  # Stub the mock adapter to use the real OSAScriptAdapter for integration tests
  setup do
    Mox.stub_with(ExMacOSControl.AdapterMock, ExMacOSControl.OSAScriptAdapter)
    :ok
  end

  describe "get_selection/0" do
    test "returns list or empty list" do
      assert {:ok, selection} = Finder.get_selection()
      assert is_list(selection)

      # All paths should be strings starting with /
      Enum.each(selection, fn path ->
        assert is_binary(path)
        assert String.starts_with?(path, "/")
      end)
    end
  end

  describe "open_location/1" do
    test "opens valid location" do
      assert :ok = Finder.open_location("/Users")
      Process.sleep(500)
    end

    test "handles invalid location" do
      result = Finder.open_location("/nonexistent/path/12345/xyz")
      assert match?({:error, _}, result)
    end
  end

  describe "new_window/1" do
    test "creates new window at location" do
      assert :ok = Finder.new_window("/Applications")
      Process.sleep(500)
    end

    test "handles invalid location" do
      result = Finder.new_window("/nonexistent/path/12345/xyz")
      assert match?({:error, _}, result)
    end
  end

  describe "get_current_folder/0" do
    setup do
      # Open a known location to ensure we have a window
      Finder.open_location("/Users")
      Process.sleep(500)
      :ok
    end

    test "returns current folder path" do
      assert {:ok, path} = Finder.get_current_folder()
      assert is_binary(path)

      # Should be a valid POSIX path or empty string
      if path != "" do
        assert String.starts_with?(path, "/")
      end
    end
  end

  describe "set_view/1" do
    setup do
      # Ensure we have a Finder window
      Finder.open_location("/Applications")
      Process.sleep(500)
      :ok
    end

    test "sets view to icon" do
      assert :ok = Finder.set_view(:icon)
      Process.sleep(200)
    end

    test "sets view to list" do
      assert :ok = Finder.set_view(:list)
      Process.sleep(200)
    end

    test "sets view to column" do
      assert :ok = Finder.set_view(:column)
      Process.sleep(200)
    end

    test "sets view to gallery" do
      assert :ok = Finder.set_view(:gallery)
      Process.sleep(200)
    end

    test "returns error for invalid view" do
      assert {:error, error} = Finder.set_view(:invalid)
      assert error.type == :execution_error
      assert error.message =~ "Invalid view mode"
    end
  end
end
