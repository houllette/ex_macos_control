defmodule ExMacOSControl.SystemEvents do
  @moduledoc """
  Automation helpers for macOS System Events.

  Provides process management and UI automation capabilities including listing,
  launching, quitting processes, menu clicking, keystroke simulation, and window
  management.

  This module is a thin wrapper over AppleScript calls to System Events, providing
  a convenient Elixir API for common automation tasks.

  ## Permissions

  **Process Management**: Requires automation permission for System Events. On first use,
  macOS may prompt the user to grant permission in:

  System Settings → Privacy & Security → Automation

  (Or System Preferences → Security & Privacy → Privacy → Automation on older macOS)

  **UI Automation**: Requires Accessibility permission. Enable in:

  System Settings → Privacy & Security → Accessibility

  (Or System Preferences → Security & Privacy → Privacy → Accessibility on older macOS)

  Add Terminal (or your Elixir runtime) to the list of allowed applications.

  ## Examples

      # Process management (from A1)
      {:ok, processes} = ExMacOSControl.SystemEvents.list_processes()
      # => {:ok, ["Safari", "Finder", "Terminal", ...]}

      {:ok, true} = ExMacOSControl.SystemEvents.process_exists?("Safari")

      :ok = ExMacOSControl.SystemEvents.launch_application("Safari")

      :ok = ExMacOSControl.SystemEvents.quit_application("Safari")

      # UI automation (A2)
      :ok = ExMacOSControl.SystemEvents.click_menu_item("Safari", "File", "New Tab")

      :ok = ExMacOSControl.SystemEvents.press_key("Safari", "t")

      :ok = ExMacOSControl.SystemEvents.press_key("Safari", "t", using: [:command])

      {:ok, props} = ExMacOSControl.SystemEvents.get_window_properties("Safari")
      # => {:ok, %{position: [100, 100], size: [800, 600], title: "Google"}}

      :ok = ExMacOSControl.SystemEvents.set_window_bounds("Calculator",
        position: [100, 100],
        size: [400, 500]
      )

  ## Notes

  - All functions delegate to AppleScript via System Events
  - Applications may prompt for quit confirmation dialogs
  - Some applications (like Finder) cannot be quit via normal methods
  - Application names are case-sensitive
  - `launch_application/1` will bring an already-running app to the front
  - UI automation functions require Accessibility permissions
  """

  alias ExMacOSControl.Error

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Lists all running application processes.

  Returns a list of application names currently running on the system.
  The list is obtained via System Events and includes all GUI applications.

  ## Returns

  - `{:ok, processes}` - List of process names as strings
  - `{:error, error}` - If System Events is not available or another error occurs

  ## Examples

      ExMacOSControl.SystemEvents.list_processes()
      # => {:ok, ["Safari", "Finder", "Terminal", "Mail"]}

      # Check if a specific app is in the list
      {:ok, processes} = ExMacOSControl.SystemEvents.list_processes()
      "Safari" in processes
      # => true

  """
  @spec list_processes() :: {:ok, [String.t()]} | {:error, Error.t()}
  def list_processes do
    script = ~s(tell application "System Events" to return name of every application process)

    case adapter().run_applescript(script) do
      {:ok, output} ->
        processes = parse_process_list(output)
        {:ok, processes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a specific process is running.

  ## Parameters

  - `app_name` - The name of the application to check (case-sensitive)

  ## Returns

  - `{:ok, true}` - Process exists and is running
  - `{:ok, false}` - Process does not exist
  - `{:error, error}` - If an error occurs checking the process

  ## Examples

      ExMacOSControl.SystemEvents.process_exists?("Safari")
      # => {:ok, true}

      ExMacOSControl.SystemEvents.process_exists?("NonexistentApp")
      # => {:ok, false}

  """
  @spec process_exists?(String.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def process_exists?(app_name) do
    script = """
    tell application "System Events"
      return exists process "#{escape_quotes(app_name)}"
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        result = parse_boolean(output)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Quits an application gracefully.

  Sends a quit command to the specified application via System Events.
  This is equivalent to selecting "Quit" from the application menu.

  Note: Some applications may display a confirmation dialog before quitting.
  Some system applications (like Finder) cannot be quit.

  ## Parameters

  - `app_name` - The name of the application to quit (case-sensitive)

  ## Returns

  - `:ok` - Application was quit successfully
  - `{:error, error}` - If the application is not found or cannot be quit

  ## Examples

      ExMacOSControl.SystemEvents.quit_application("Calculator")
      # => :ok

      ExMacOSControl.SystemEvents.quit_application("NonexistentApp")
      # => {:error, %ExMacOSControl.Error{type: :not_found, ...}}

  """
  @spec quit_application(String.t()) :: :ok | {:error, Error.t()}
  def quit_application(app_name) do
    script = ~s(tell application "#{escape_quotes(app_name)}" to quit)

    case adapter().run_applescript(script) do
      {:ok, _output} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Launches an application.

  Launches the specified application and brings it to the front.
  If the application is already running, it will be brought to the front.

  ## Parameters

  - `app_name` - The name of the application to launch (case-sensitive)

  ## Returns

  - `:ok` - Application was launched successfully
  - `{:error, error}` - If the application is not found or cannot be launched

  ## Examples

      ExMacOSControl.SystemEvents.launch_application("Safari")
      # => :ok

      ExMacOSControl.SystemEvents.launch_application("Calculator")
      # => :ok

      ExMacOSControl.SystemEvents.launch_application("NonexistentApp")
      # => {:error, %ExMacOSControl.Error{type: :not_found, ...}}

  """
  @spec launch_application(String.t()) :: :ok | {:error, Error.t()}
  def launch_application(app_name) do
    script = ~s(tell application "#{escape_quotes(app_name)}" to activate)

    case adapter().run_applescript(script) do
      {:ok, _output} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Activates an application (alias for `launch_application/1`).

  This is an alias for `launch_application/1` provided for semantic clarity.
  Use this when you want to bring an already-running application to the front,
  or use `launch_application/1` when you're starting an application.

  Both functions have identical behavior: they launch the app if it's not running,
  or bring it to the front if it is.

  ## Parameters

  - `app_name` - The name of the application to activate (case-sensitive)

  ## Returns

  - `:ok` - Application was activated successfully
  - `{:error, error}` - If the application is not found or cannot be activated

  ## Examples

      ExMacOSControl.SystemEvents.activate_application("Safari")
      # => :ok

      # Equivalent to:
      ExMacOSControl.SystemEvents.launch_application("Safari")
      # => :ok

  """
  @spec activate_application(String.t()) :: :ok | {:error, Error.t()}
  def activate_application(app_name) do
    launch_application(app_name)
  end

  @doc """
  Clicks a menu item in an application's menu bar.

  This function requires macOS Accessibility permission. It will click the specified
  menu item through System Events UI automation.

  ## Parameters

  - `app_name` - The name of the application (case-sensitive)
  - `menu_name` - The name of the menu (e.g., "File", "Edit")
  - `menu_item_name` - The name of the menu item to click

  ## Returns

  - `:ok` - Menu item was clicked successfully
  - `{:error, error}` - If the application is not running, menu not found, item not found,
    or Accessibility permission is denied

  ## Examples

      ExMacOSControl.SystemEvents.click_menu_item("Safari", "File", "New Tab")
      # => :ok

      ExMacOSControl.SystemEvents.click_menu_item("TextEdit", "Format", "Make Plain Text")
      # => :ok

  ## Permissions

  Requires Accessibility permission. If not granted, the function will return:

      {:error, %ExMacOSControl.Error{type: :permission_denied, ...}}

  Enable in: System Settings → Privacy & Security → Accessibility

  """
  @spec click_menu_item(String.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def click_menu_item(app_name, menu_name, menu_item_name) do
    script = """
    tell application "System Events"
      tell process "#{escape_quotes(app_name)}"
        click menu item "#{escape_quotes(menu_item_name)}" of menu "#{escape_quotes(menu_name)}" of menu bar 1
      end tell
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
  Sends a keystroke to an application.

  This is the 2-arity version that sends a simple keystroke without modifiers.
  For keystrokes with modifiers (like Command+T), use `press_key/3`.

  ## Parameters

  - `app_name` - The name of the application (case-sensitive)
  - `key` - The key to press (single character)

  ## Returns

  - `:ok` - Keystroke was sent successfully
  - `{:error, error}` - If the application is not running or permission is denied

  ## Examples

      ExMacOSControl.SystemEvents.press_key("TextEdit", "a")
      # => :ok

      ExMacOSControl.SystemEvents.press_key("Safari", "t")
      # => :ok

  ## Permissions

  Requires Accessibility permission. Enable in:
  System Settings → Privacy & Security → Accessibility

  """
  @spec press_key(String.t(), String.t()) :: :ok | {:error, Error.t()}
  def press_key(app_name, key) do
    script = """
    tell application "System Events"
      tell process "#{escape_quotes(app_name)}"
        keystroke "#{escape_quotes(key)}"
      end tell
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
  Sends a keystroke with modifier keys to an application.

  This is the 3-arity version that allows sending keystrokes with modifiers
  like Command, Control, Option, or Shift.

  ## Parameters

  - `app_name` - The name of the application (case-sensitive)
  - `key` - The key to press (single character)
  - `using:` - List of modifier atoms: `:command`, `:control`, `:option`, `:shift`

  ## Returns

  - `:ok` - Keystroke was sent successfully
  - `{:error, error}` - If invalid modifier, application not running, or permission denied

  ## Examples

      # Command+T for new tab in Safari
      ExMacOSControl.SystemEvents.press_key("Safari", "t", using: [:command])
      # => :ok

      # Command+Shift+Q to quit with windows
      ExMacOSControl.SystemEvents.press_key("Safari", "q", using: [:command, :shift])
      # => :ok

      # Control+Option+Space
      ExMacOSControl.SystemEvents.press_key("App", " ", using: [:control, :option])
      # => :ok

  ## Permissions

  Requires Accessibility permission. Enable in:
  System Settings → Privacy & Security → Accessibility

  """
  @spec press_key(String.t(), String.t(), using: [atom()]) :: :ok | {:error, Error.t()}
  def press_key(app_name, key, using: modifiers) when is_list(modifiers) do
    # Validate modifiers
    case validate_modifiers(modifiers) do
      :ok ->
        modifier_string = modifiers_to_applescript(modifiers)

        script = """
        tell application "System Events"
          tell process "#{escape_quotes(app_name)}"
            keystroke "#{escape_quotes(key)}" using {#{modifier_string}}
          end tell
        end tell
        """

        case adapter().run_applescript(script) do
          {:ok, _output} ->
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      {:error, invalid_modifiers} ->
        {:error,
         Error.execution_error("Invalid modifier key(s)",
           modifiers: invalid_modifiers,
           valid: [:command, :control, :option, :shift]
         )}
    end
  end

  @doc """
  Gets properties of an application's front window.

  Returns the position, size, and title of the frontmost window of the specified
  application.

  ## Parameters

  - `app_name` - The name of the application (case-sensitive)

  ## Returns

  - `{:ok, %{position: [x, y], size: [width, height], title: title}}` - Window properties
  - `{:ok, nil}` - If the application has no windows
  - `{:error, error}` - If application not running or permission denied

  ## Examples

      ExMacOSControl.SystemEvents.get_window_properties("Safari")
      # => {:ok, %{position: [100, 100], size: [800, 600], title: "Google"}}

      ExMacOSControl.SystemEvents.get_window_properties("Calculator")
      # => {:ok, %{position: [500, 300], size: [250, 330], title: "Calculator"}}

      # Application with no windows
      ExMacOSControl.SystemEvents.get_window_properties("AppWithNoWindows")
      # => {:ok, nil}

  ## Permissions

  Requires Accessibility permission. Enable in:
  System Settings → Privacy & Security → Accessibility

  """
  @spec get_window_properties(String.t()) ::
          {:ok, %{position: [integer()], size: [integer()], title: String.t()} | nil}
          | {:error, Error.t()}
  def get_window_properties(app_name) do
    script = """
    tell application "System Events"
      tell process "#{escape_quotes(app_name)}"
        if (count of windows) > 0 then
          set w to front window
          set pos to position of w
          set sz to size of w
          set t to title of w
          return (item 1 of pos) & ", " & (item 2 of pos) & ", " & (item 1 of sz) & ", " & (item 2 of sz) & ", " & t
        else
          return ""
        end if
      end tell
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, ""} ->
        {:ok, nil}

      {:ok, output} ->
        case parse_window_properties(output) do
          {:ok, props} -> {:ok, props}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sets the position and size of an application's front window.

  ## Parameters

  - `app_name` - The name of the application (case-sensitive)
  - `position:` - A list with [x, y] coordinates for window position
  - `size:` - A list with [width, height] for window size

  ## Returns

  - `:ok` - Window bounds were set successfully
  - `{:error, error}` - If application not running, no windows, invalid parameters,
    or permission denied

  ## Examples

      ExMacOSControl.SystemEvents.set_window_bounds("Calculator",
        position: [100, 100],
        size: [400, 500]
      )
      # => :ok

      ExMacOSControl.SystemEvents.set_window_bounds("Safari",
        position: [0, 0],
        size: [1920, 1080]
      )
      # => :ok

  ## Permissions

  Requires Accessibility permission. Enable in:
  System Settings → Privacy & Security → Accessibility

  """
  @spec set_window_bounds(String.t(), position: [integer()], size: [integer()]) ::
          :ok | {:error, Error.t()}
  def set_window_bounds(app_name, position: position, size: size) do
    # Validate parameters
    with :ok <- validate_position(position),
         :ok <- validate_size(size) do
      [x, y] = position
      [width, height] = size

      script = """
      tell application "System Events"
        tell process "#{escape_quotes(app_name)}"
          if (count of windows) > 0 then
            set position of front window to {#{x}, #{y}}
            set size of front window to {#{width}, #{height}}
          else
            error "No windows available"
          end if
        end tell
      end tell
      """

      case adapter().run_applescript(script) do
        {:ok, _output} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private Helpers

  # Parses a comma-separated list of processes from AppleScript output
  @spec parse_process_list(String.t()) :: [String.t()]
  defp parse_process_list(output) do
    output
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Parses a boolean result from AppleScript output
  @spec parse_boolean(String.t()) :: boolean()
  defp parse_boolean(output) do
    output
    |> String.trim()
    |> String.downcase()
    |> case do
      "true" -> true
      "false" -> false
      _ -> false
    end
  end

  # Escapes double quotes in application names for AppleScript
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(string) do
    String.replace(string, "\"", "\\\"")
  end

  # Maps Elixir modifier atoms to AppleScript modifier syntax
  @spec modifiers_to_applescript([atom()]) :: String.t()
  defp modifiers_to_applescript(modifiers) do
    Enum.map_join(modifiers, ", ", fn
      :command -> "command down"
      :control -> "control down"
      :option -> "option down"
      :shift -> "shift down"
    end)
  end

  # Validates that all modifiers are valid
  @spec validate_modifiers([atom()]) :: :ok | {:error, [atom()]}
  defp validate_modifiers(modifiers) do
    valid = [:command, :control, :option, :shift]
    invalid = Enum.reject(modifiers, &(&1 in valid))

    if Enum.empty?(invalid) do
      :ok
    else
      {:error, invalid}
    end
  end

  # Parses window properties from AppleScript output
  # Format: "x, y, width, height, title"
  @spec parse_window_properties(String.t()) ::
          {:ok, %{position: [integer()], size: [integer()], title: String.t()}}
          | {:error, Error.t()}
  defp parse_window_properties(output) do
    parts = String.split(output, ", ", parts: 5)

    case parts do
      [x, y, width, height, title] ->
        {:ok,
         %{
           position: [String.to_integer(x), String.to_integer(y)],
           size: [String.to_integer(width), String.to_integer(height)],
           title: String.trim(title)
         }}

      _ ->
        {:error, Error.execution_error("Failed to parse window properties", output: output)}
    end
  end

  # Validates position parameter
  @spec validate_position([integer()]) :: :ok | {:error, Error.t()}
  defp validate_position([_x, _y]), do: :ok

  defp validate_position(_) do
    {:error, Error.execution_error("Invalid position format, expected [x, y]")}
  end

  # Validates size parameter
  @spec validate_size([integer()]) :: :ok | {:error, Error.t()}
  defp validate_size([_width, _height]), do: :ok

  defp validate_size(_) do
    {:error, Error.execution_error("Invalid size format, expected [width, height]")}
  end
end
