defmodule ExMacOSControl.SafariTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.Error
  alias ExMacOSControl.Safari

  setup :verify_on_exit!

  describe "open_url/1" do
    test "opens URL successfully in new tab" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Safari"
        assert script =~ "activate"
        assert script =~ "https://example.com"
        assert script =~ "make new tab"
        {:ok, ""}
      end)

      assert :ok = Safari.open_url("https://example.com")
    end

    test "handles Safari errors" do
      error = Error.execution_error("Safari error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Safari.open_url("https://example.com")
    end

    test "escapes quotes in URLs" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert :ok = Safari.open_url("https://example.com?q=\\\"test\\\"")
    end
  end

  describe "get_current_url/0" do
    test "returns current tab URL" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Safari"
        assert script =~ "current tab"
        assert script =~ "front window"
        {:ok, "https://example.com"}
      end)

      assert {:ok, "https://example.com"} = Safari.get_current_url()
    end

    test "returns empty string when no windows" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "count of windows"
        {:ok, ""}
      end)

      assert {:ok, ""} = Safari.get_current_url()
    end

    test "handles execution errors" do
      error = Error.execution_error("Safari not available")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Safari.get_current_url()
    end

    test "trims whitespace from URL" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "  https://example.com  \n"}
      end)

      assert {:ok, "https://example.com"} = Safari.get_current_url()
    end
  end

  describe "execute_javascript/1" do
    test "executes JavaScript and returns result" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Safari"
        assert script =~ "do JavaScript"
        assert script =~ "2 + 2"
        assert script =~ "current tab"
        {:ok, "4"}
      end)

      assert {:ok, "4"} = Safari.execute_javascript("2 + 2")
    end

    test "handles JavaScript execution errors" do
      error = Error.execution_error("JavaScript execution failed")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Safari.execute_javascript("invalid.script")
    end

    test "escapes quotes in JavaScript" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, "result"}
      end)

      assert {:ok, "result"} = Safari.execute_javascript("alert(\\\"test\\\")")
    end

    test "returns document title" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "document.title"
        {:ok, "Example Domain"}
      end)

      assert {:ok, "Example Domain"} = Safari.execute_javascript("document.title")
    end
  end

  describe "list_tabs/0" do
    test "returns list of URLs" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Safari"
        assert script =~ "windows"
        assert script =~ "tabs"
        {:ok, "https://example.com, https://google.com, https://github.com"}
      end)

      assert {:ok, urls} = Safari.list_tabs()
      assert urls == ["https://example.com", "https://google.com", "https://github.com"]
    end

    test "returns empty list when no tabs" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, []} = Safari.list_tabs()
    end

    test "parses comma-separated URLs correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "https://example.com,https://google.com"}
      end)

      assert {:ok, urls} = Safari.list_tabs()
      assert urls == ["https://example.com", "https://google.com"]
    end

    test "trims whitespace from URLs" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, " https://example.com , https://google.com  "}
      end)

      assert {:ok, urls} = Safari.list_tabs()
      assert urls == ["https://example.com", "https://google.com"]
    end

    test "handles single tab" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "https://example.com"}
      end)

      assert {:ok, ["https://example.com"]} = Safari.list_tabs()
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to list tabs")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Safari.list_tabs()
    end
  end

  describe "close_tab/1" do
    test "closes tab at index" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Safari"
        assert script =~ "close tab 2"
        assert script =~ "front window"
        {:ok, ""}
      end)

      assert :ok = Safari.close_tab(2)
    end

    test "handles invalid index" do
      error = Error.execution_error("Tab index out of bounds")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Safari.close_tab(999)
    end

    test "handles first tab" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "close tab 1"
        {:ok, ""}
      end)

      assert :ok = Safari.close_tab(1)
    end

    test "handles execution errors" do
      error = Error.execution_error("Failed to close tab")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Safari.close_tab(1)
    end
  end
end
