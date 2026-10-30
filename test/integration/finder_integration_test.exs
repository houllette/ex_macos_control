defmodule ExMacOSControl.FinderIntegrationTest do
  use ExUnit.Case, async: false

  import Mox

  @moduletag :integration
  @moduletag :desktop

  # ExUnit includes override excludes; :integration alone must not enable mutations.
  unless Enum.any?(ExUnit.configuration()[:include], &(&1 in [:desktop, {:desktop, true}])) do
    @moduletag skip: "Requires --include desktop (use an isolated macOS session)"
  end

  alias ExMacOSControl.{DesktopSession, Finder}

  setup :verify_on_exit!

  # Stub the mock adapter to use the real OSAScriptAdapter for integration tests
  setup do
    Mox.stub_with(ExMacOSControl.AdapterMock, ExMacOSControl.OSAScriptAdapter)
    DesktopSession.start(finder: true)
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
    test "opens valid location", %{desktop_directory: directory} do
      assert :ok = Finder.open_location(directory)
      Process.sleep(500)
    end

    test "handles invalid location" do
      result = Finder.open_location("/nonexistent/path/12345/xyz")
      assert match?({:error, _}, result)
    end
  end

  describe "new_window/1" do
    test "creates new window at location", %{desktop_directory: directory} do
      assert :ok = Finder.new_window(directory)
      Process.sleep(500)
    end

    test "handles invalid location" do
      result = Finder.new_window("/nonexistent/path/12345/xyz")
      assert match?({:error, _}, result)
    end
  end

  describe "get_current_folder/0" do
    setup %{desktop_directory: directory} do
      # Open a known location to ensure we have a window
      Finder.open_location(directory)
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
    setup %{desktop_directory: directory} do
      # Ensure we have a Finder window
      Finder.open_location(directory)
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
