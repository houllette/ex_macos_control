defmodule ExMacOSControl.Safari do
  @moduledoc """
  Automation helpers for Safari browser.

  Provides functions to control Safari including navigation, JavaScript execution,
  and tab management. This module is a thin wrapper over AppleScript calls to Safari,
  providing a convenient Elixir API for common browser automation tasks.

  ## Examples

      # Open URL in new tab
      :ok = ExMacOSControl.Safari.open_url("https://example.com")

      # Get current tab URL
      {:ok, url} = ExMacOSControl.Safari.get_current_url()
      # => {:ok, "https://example.com"}

      # Execute JavaScript in current tab
      {:ok, result} = ExMacOSControl.Safari.execute_javascript("document.title")
      # => {:ok, "Example Domain"}

      # List all tabs
      {:ok, urls} = ExMacOSControl.Safari.list_tabs()
      # => {:ok, ["https://example.com", "https://google.com"]}

      # Close a tab by index (1-based)
      :ok = ExMacOSControl.Safari.close_tab(2)

  ## Permissions

  This module requires automation permission for Safari. On first use,
  macOS may prompt the user to grant permission in:

  System Settings → Privacy & Security → Automation

  (Or System Preferences → Security & Privacy → Privacy → Automation on older macOS)

  ## JavaScript Execution Requirement

  To use `execute_javascript/1`, you must enable "Allow JavaScript from Apple Events"
  in Safari:

  1. Open Safari
  2. Go to Safari → Settings (or Preferences)
  3. Click the "Advanced" tab
  4. Check "Show features for web developers" (if not already checked)
  5. Go to the "Developer" tab (newly visible)
  6. Check "Allow JavaScript from Apple Events"

  Without this setting, `execute_javascript/1` will return an error.

  ## Notes

  - Safari must be installed (standard on macOS)
  - Most operations will launch Safari if it's not already running
  - Tab indices are 1-based (not 0-based), following AppleScript conventions
  - JavaScript execution happens in the current tab of the front window
  - URL opening creates new tabs in the front window
  - If no Safari windows exist, `open_url/1` will create one
  """

  alias ExMacOSControl.Error

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Opens a URL in a new tab in Safari.

  Activates Safari and opens the specified URL in a new tab. If Safari is not
  running, it will be launched. If no Safari windows exist, a new window will
  be created automatically.

  ## Parameters

  - `url` - The URL to open (should include protocol, e.g., "https://example.com")

  ## Returns

  - `:ok` - URL was opened successfully
  - `{:error, error}` - If Safari is not available or another error occurs

  ## Examples

      ExMacOSControl.Safari.open_url("https://example.com")
      # => :ok

      ExMacOSControl.Safari.open_url("https://github.com/elixir-lang/elixir")
      # => :ok

  """
  @spec open_url(String.t()) :: :ok | {:error, Error.t()}
  def open_url(url) do
    script = """
    tell application "Safari"
      activate
      if (count of windows) = 0 then
        make new document with properties {URL:"#{escape_quotes(url)}"}
      else
        tell window 1
          set current tab to (make new tab with properties {URL:"#{escape_quotes(url)}"})
        end tell
      end if
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, _output} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the URL of the current tab in Safari.

  Returns the URL of the current tab in the frontmost Safari window.
  If no Safari windows are open, returns an empty string.

  ## Returns

  - `{:ok, url}` - The URL of the current tab
  - `{:ok, ""}` - If no Safari windows are open
  - `{:error, error}` - If an error occurs

  ## Examples

      ExMacOSControl.Safari.get_current_url()
      # => {:ok, "https://example.com"}

      # When no windows are open
      ExMacOSControl.Safari.get_current_url()
      # => {:ok, ""}

  """
  @spec get_current_url() :: {:ok, String.t()} | {:error, Error.t()}
  def get_current_url do
    script = """
    tell application "Safari"
      if (count of windows) > 0 then
        return URL of current tab of front window
      else
        return ""
      end if
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        url = String.trim(output)
        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Executes JavaScript in the current tab of Safari.

  Executes the provided JavaScript code in the current tab of the frontmost
  Safari window. Returns the result of the JavaScript execution as a string.

  ## Parameters

  - `script` - The JavaScript code to execute

  ## Returns

  - `{:ok, result}` - The result of the JavaScript execution as a string
  - `{:error, error}` - If no windows are open or execution fails

  ## Examples

      ExMacOSControl.Safari.execute_javascript("2 + 2")
      # => {:ok, "4"}

      ExMacOSControl.Safari.execute_javascript("document.title")
      # => {:ok, "Example Domain"}

      ExMacOSControl.Safari.execute_javascript("window.location.href")
      # => {:ok, "https://example.com/"}

  ## Notes

  - The current tab must have a page loaded for JavaScript execution to work
  - Some JavaScript operations may require the page to be fully loaded
  - Results are always returned as strings
  """
  @spec execute_javascript(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def execute_javascript(script) do
    applescript = """
    tell application "Safari"
      do JavaScript "#{escape_quotes(script)}" in current tab of front window
    end tell
    """

    case adapter().run_applescript(applescript) do
      {:ok, output} ->
        {:ok, output}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists URLs of all tabs in all Safari windows.

  Returns a list of URLs for all open tabs across all Safari windows.
  If no tabs are open, returns an empty list.

  ## Returns

  - `{:ok, urls}` - List of URLs as strings
  - `{:ok, []}` - If no tabs are open
  - `{:error, error}` - If an error occurs

  ## Examples

      ExMacOSControl.Safari.list_tabs()
      # => {:ok, ["https://example.com", "https://google.com", "https://github.com"]}

      # When no tabs are open
      ExMacOSControl.Safari.list_tabs()
      # => {:ok, []}

  ## Notes

  - Tabs are listed in order: first all tabs from window 1, then window 2, etc.
  - URLs are returned as they appear in Safari (may include fragments, query params, etc.)
  """
  @spec list_tabs() :: {:ok, [String.t()]} | {:error, Error.t()}
  def list_tabs do
    script = """
    tell application "Safari"
      set urlList to {}
      repeat with w in windows
        repeat with t in tabs of w
          set end of urlList to URL of t
        end repeat
      end repeat
      return urlList as text
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        urls = parse_url_list(output)
        {:ok, urls}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes a tab in Safari by its index.

  Closes the tab at the specified index (1-based) in the frontmost Safari window.
  Tab indices follow AppleScript conventions where 1 is the first tab.

  ## Parameters

  - `index` - The 1-based index of the tab to close (1 is the first tab)

  ## Returns

  - `:ok` - Tab was closed successfully
  - `{:error, error}` - If the index is out of bounds or no windows are open

  ## Examples

      ExMacOSControl.Safari.close_tab(1)
      # => :ok

      ExMacOSControl.Safari.close_tab(2)
      # => :ok

      # Index out of bounds
      ExMacOSControl.Safari.close_tab(999)
      # => {:error, %ExMacOSControl.Error{type: :execution_error, ...}}

  ## Notes

  - Tab indices are 1-based (1 is the first tab, 2 is the second, etc.)
  - Closing the last tab in a window may close the window
  - If the index is out of bounds, Safari will return an error
  """
  @spec close_tab(pos_integer()) :: :ok | {:error, Error.t()}
  def close_tab(index) when is_integer(index) and index > 0 do
    script = """
    tell application "Safari"
      if (count of windows) > 0 then
        if (count of tabs of front window) >= #{index} then
          close tab #{index} of front window
        end if
      end if
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, _output} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Helpers

  # Parses a comma-separated list of URLs from AppleScript output
  @spec parse_url_list(String.t()) :: [String.t()]
  defp parse_url_list(output) do
    output
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Escapes double quotes in strings for AppleScript
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(string) do
    String.replace(string, "\"", "\\\"")
  end
end
