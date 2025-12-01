defmodule ExMacOSControl.SafariIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{Safari, SystemEvents, TestHelpers}

  # These tests require macOS with osascript and Safari
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

    # Launch Safari if not running
    SystemEvents.launch_application("Safari")
    Process.sleep(1000)

    :ok
  end

  describe "open_url/1" do
    @tag :integration
    test "opens URL in new tab" do
      assert :ok = Safari.open_url("https://example.com")
      Process.sleep(1500)

      # Verify URL was opened
      assert {:ok, url} = Safari.get_current_url()
      assert String.contains?(url, "example.com")
    end

    @tag :integration
    test "opens multiple URLs in separate tabs" do
      assert :ok = Safari.open_url("https://example.com")
      Process.sleep(500)
      assert :ok = Safari.open_url("https://www.iana.org")
      Process.sleep(500)

      assert {:ok, urls} = Safari.list_tabs()
      assert length(urls) >= 2
    end
  end

  describe "get_current_url/0" do
    setup do
      Safari.open_url("https://example.com")
      Process.sleep(1500)
      :ok
    end

    @tag :integration
    test "returns current tab URL" do
      assert {:ok, url} = Safari.get_current_url()
      assert is_binary(url)
      assert String.starts_with?(url, "http")
    end

    @tag :integration
    test "returns actual example.com URL" do
      assert {:ok, url} = Safari.get_current_url()
      assert String.contains?(url, "example.com")
    end
  end

  describe "execute_javascript/1" do
    setup do
      Safari.open_url("https://example.com")
      Process.sleep(2000)
      :ok
    end

    @tag :integration
    test "executes simple arithmetic JavaScript" do
      assert {:ok, result} = Safari.execute_javascript("2 + 2")
      assert result == "4"
    end

    @tag :integration
    test "gets document title" do
      assert {:ok, title} = Safari.execute_javascript("document.title")
      assert is_binary(title)
      assert String.length(title) > 0
    end

    @tag :integration
    test "executes JavaScript that returns a string" do
      assert {:ok, result} = Safari.execute_javascript("'hello world'")
      assert result == "hello world"
    end

    @tag :integration
    test "gets window location" do
      assert {:ok, location} = Safari.execute_javascript("window.location.href")
      assert is_binary(location)
      assert String.starts_with?(location, "http")
    end
  end

  describe "list_tabs/0" do
    setup do
      # Open a few tabs for testing
      Safari.open_url("https://example.com")
      Process.sleep(500)
      :ok
    end

    @tag :integration
    test "returns list of tab URLs" do
      assert {:ok, urls} = Safari.list_tabs()
      assert is_list(urls)
      assert length(urls) > 0
    end

    @tag :integration
    test "all URLs are valid strings" do
      assert {:ok, urls} = Safari.list_tabs()

      for url <- urls do
        assert is_binary(url)
        assert String.length(url) > 0
      end
    end

    @tag :integration
    test "includes opened example.com URL" do
      assert {:ok, urls} = Safari.list_tabs()
      assert Enum.any?(urls, fn url -> String.contains?(url, "example.com") end)
    end
  end

  describe "close_tab/1" do
    setup do
      # Open multiple tabs for testing
      Safari.open_url("https://example.com")
      Process.sleep(500)
      Safari.open_url("https://www.iana.org")
      Process.sleep(500)
      :ok
    end

    @tag :integration
    test "closes tab at index 1" do
      {:ok, tabs_before} = Safari.list_tabs()
      initial_count = length(tabs_before)

      assert :ok = Safari.close_tab(1)
      Process.sleep(500)

      {:ok, tabs_after} = Safari.list_tabs()
      assert length(tabs_after) == initial_count - 1
    end

    @tag :integration
    test "closes current tab" do
      # Get initial state
      {:ok, _initial_url} = Safari.get_current_url()
      {:ok, tabs_before} = Safari.list_tabs()
      initial_count = length(tabs_before)

      # Close the current (first) tab
      assert :ok = Safari.close_tab(1)
      Process.sleep(500)

      # Verify tab count decreased
      {:ok, tabs_after} = Safari.list_tabs()
      assert length(tabs_after) == initial_count - 1

      # Verify current URL changed (different tab is now current)
      {:ok, new_url} = Safari.get_current_url()
      # URLs might be the same if we had duplicate tabs, so we just verify we got a URL
      assert is_binary(new_url)
    end
  end

  describe "real-world workflow" do
    @tag :integration
    test "complete Safari automation workflow" do
      # 1. Open a URL
      assert :ok = Safari.open_url("https://example.com")
      Process.sleep(1500)

      # 2. Verify it's the current tab
      assert {:ok, url} = Safari.get_current_url()
      assert String.contains?(url, "example.com")

      # 3. Execute JavaScript to get page info
      assert {:ok, title} = Safari.execute_javascript("document.title")
      assert is_binary(title)

      # 4. Open another URL in a new tab
      assert :ok = Safari.open_url("https://www.iana.org")
      Process.sleep(1500)

      # 5. List all tabs
      assert {:ok, urls} = Safari.list_tabs()
      assert length(urls) >= 2

      # 6. Close a tab
      assert :ok = Safari.close_tab(1)
      Process.sleep(500)

      # 7. Verify tab was closed
      assert {:ok, urls_after} = Safari.list_tabs()
      assert length(urls_after) == length(urls) - 1
    end
  end

  describe "edge cases" do
    @tag :integration
    test "handles rapid tab operations" do
      # Open several tabs quickly
      assert :ok = Safari.open_url("https://example.com")
      Process.sleep(300)
      assert :ok = Safari.open_url("https://www.iana.org")
      Process.sleep(300)
      assert :ok = Safari.open_url("https://example.org")
      Process.sleep(500)

      # List tabs should still work
      assert {:ok, urls} = Safari.list_tabs()
      assert length(urls) >= 3
    end

    @tag :integration
    test "get_current_url works immediately after opening" do
      assert :ok = Safari.open_url("https://example.com")
      # Minimal wait
      Process.sleep(500)

      # Should still get a URL (even if page hasn't fully loaded)
      assert {:ok, url} = Safari.get_current_url()
      assert is_binary(url)
    end
  end
end
