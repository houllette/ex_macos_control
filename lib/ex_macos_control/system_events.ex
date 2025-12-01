defmodule ExMacOSControl.SystemEvents do
  @moduledoc """
  Automation helpers for macOS System Events.

  Provides process management capabilities including listing, launching, quitting,
  and checking existence of application processes.

  This module is a thin wrapper over AppleScript calls to System Events, providing
  a convenient Elixir API for common process management tasks.

  ## Permissions

  This module requires automation permission for System Events. On first use,
  macOS may prompt the user to grant permission in:

  System Settings → Privacy & Security → Automation

  (Or System Preferences → Security & Privacy → Privacy → Automation on older macOS)

  ## Examples

      # List all running processes
      {:ok, processes} = ExMacOSControl.SystemEvents.list_processes()
      # => {:ok, ["Safari", "Finder", "Terminal", ...]}

      # Check if an app is running
      {:ok, true} = ExMacOSControl.SystemEvents.process_exists?("Safari")

      # Launch an application
      :ok = ExMacOSControl.SystemEvents.launch_application("Safari")

      # Quit an application
      :ok = ExMacOSControl.SystemEvents.quit_application("Safari")

  ## Notes

  - All functions delegate to AppleScript via System Events
  - Applications may prompt for quit confirmation dialogs
  - Some applications (like Finder) cannot be quit via normal methods
  - Application names are case-sensitive
  - `launch_application/1` will bring an already-running app to the front
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
end
