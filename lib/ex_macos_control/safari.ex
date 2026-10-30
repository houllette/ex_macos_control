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

  alias ExMacOSControl.{Error, ScriptOutput}

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    ExMacOSControl
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
          if URL of t is not missing value then set end of urlList to {URL of t}
        end repeat
      end repeat
      return my exmc_encode_rows(urlList)
    end tell
    #{ScriptOutput.handlers()}
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        with {:ok, rows} <- ScriptOutput.decode(output, 1) do
          {:ok, List.flatten(rows)}
        end

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
        else
          error "Tab index is out of bounds" number -1719
        end if
      else
        error "No Safari windows are open" number -1728
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

  # Escapes double quotes in strings for AppleScript
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(string) do
    ExMacOSControl.Script.escape_string(string)
  end

  @doc "Lists windows by Safari ID; tab indices are local to each window."
  def list_windows(opts \\ []),
    do:
      ExMacOSControl.Resources.list(
        "com.apple.Safari",
        "app.windows",
        [id: "o.id()", name: "o.name()", bounds: "o.bounds()"],
        %{},
        opts
      )

  def tabs(window_id, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- ExMacOSControl.Automation.page(opts) do
      ExMacOSControl.Automation.query(
        "com.apple.Safari",
        "return page(byId(app.windows,input.window_id).tabs()).map(function(o,i){return {window_id:input.window_id,tab_index:input.offset+i+1,title:o.name(),url:o.url()};});",
        Map.put(paging, :window_id, window_id),
        ExMacOSControl.Automation.execution_options(opts)
      )
    end
  end

  def execute_javascript_in(window_id, index, code, opts \\ []) when is_binary(code),
    do: tab_query(window_id, index, "return app.doJavaScript(input.code,{in:t});", %{code: code}, opts)

  def get_source(window_id, index, opts \\ []), do: tab_query(window_id, index, "return t.source();", %{}, opts)
  def get_text(window_id, index, opts \\ []), do: tab_query(window_id, index, "return t.text();", %{}, opts)

  def get_tab(window_id, index, opts \\ []),
    do:
      tab_query(
        window_id,
        index,
        "return {window_id:input.window_id,tab_index:input.index,title:t.name(),url:t.url()};",
        %{},
        opts
      )

  def navigate(window_id, index, url, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.required_string(url, "URL"),
         do: tab_action(window_id, index, "t.url=input.url;", %{url: url}, opts)
  end

  def activate_tab(window_id, index, opts \\ []),
    do: tab_action(window_id, index, "w.currentTab=t;w.index=1;app.activate();", %{}, opts)

  def close_tab_in(window_id, index, opts \\ []), do: tab_action(window_id, index, "app.close(t);", %{}, opts)

  def wait_for_load(window_id, index, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:timeout, :interval, :max_output_bytes]) do
      ExMacOSControl.Wait.until(
        fn remaining -> loaded?(window_id, index, remaining, opts) end,
        Keyword.take(opts, [:timeout, :interval])
      )
    end
  end

  def add_reading_list(url, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:title, :preview, :timeout, :max_output_bytes]),
         :ok <- ExMacOSControl.Automation.required_string(url, "URL") do
      ExMacOSControl.Automation.action(
        "com.apple.Safari",
        "var options={};if(input.title!==null)options.withTitle=input.title;if(input.preview!==null)options.andPreviewText=input.preview;app.addReadingListItem(input.url,options);",
        %{url: url, title: opts[:title], preview: opts[:preview]},
        ExMacOSControl.Automation.execution_options(opts)
      )
    end
  end

  def open_url(url, opts), do: ExMacOSControl.with_options(opts, fn -> open_url(url) end)
  def get_current_url(opts), do: ExMacOSControl.with_options(opts, &get_current_url/0)
  def execute_javascript(code, opts), do: ExMacOSControl.with_options(opts, fn -> execute_javascript(code) end)
  def list_tabs(opts), do: ExMacOSControl.with_options(opts, &list_tabs/0)
  def close_tab(index, opts), do: ExMacOSControl.with_options(opts, fn -> close_tab(index) end)

  defp tab_action(window_id, index, body, params, opts) do
    case tab_query(window_id, index, body <> "return true;", params, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("Safari did not acknowledge operation")}
    end
  end

  defp tab_query(window_id, index, body, params, opts) when is_integer(index) and index > 0 do
    ExMacOSControl.Automation.query(
      "com.apple.Safari",
      "var w=byId(app.windows,input.window_id),t=w.tabs[input.index-1];if(!t.exists())throw new Error('Tab not found');#{body}",
      Map.merge(params, %{window_id: window_id, index: index}),
      opts
    )
  end

  defp tab_query(_, _, _, _, _), do: {:error, Error.execution_error("Tab index must be positive")}

  defp loaded?(window_id, index, remaining, opts) do
    case execute_javascript_in(window_id, index, "document.readyState",
           timeout: remaining,
           max_output_bytes:
             Keyword.get(ExMacOSControl.Automation.execution_options(opts), :max_output_bytes, 10_485_760)
         ) do
      {:ok, state} -> {:ok, state == "complete"}
      error -> error
    end
  end
end
