defmodule ExMacOSControl.Permissions do
  @moduledoc """
  Provides functions for checking and managing macOS automation permissions.

  macOS requires explicit permissions for automation tasks. This module helps you:
  - Check if permissions are granted
  - Get helpful instructions for granting permissions
  - Open System Preferences to the correct settings

  ## Common Permissions

  ### Accessibility Permission
  Required for UI automation (clicking menu items, pressing keys, etc.)

  ### Automation Permission
  Required for controlling specific applications via AppleScript/JXA

  ### Full Disk Access
  Required for some operations (e.g., reading Messages database)

  ## Examples

      # Check accessibility permission
      case Permissions.check_accessibility() do
        {:ok, :granted} ->
          IO.puts("Accessibility permission granted!")
        {:ok, :not_granted} ->
          IO.puts("Please grant accessibility permission")
          Permissions.show_accessibility_help()
        {:error, reason} ->
          IO.puts("Error checking permission: \#{inspect(reason)}")
      end

      # Check automation permission for a specific app
      case Permissions.check_automation("Safari") do
        {:ok, :granted} -> :ok
        {:ok, :not_granted} ->
          Permissions.show_automation_help("Safari")
      end

      # Open System Preferences to the right pane
      Permissions.open_accessibility_preferences()

  ## macOS Version Differences

  - **Ventura (13.x)**: System Preferences
  - **Sonoma (14.x+)**: System Settings
  - **Sequoia (15.x+)**: System Settings with updated UI

  This module handles version differences automatically.
  """

  alias ExMacOSControl.{Error, Platform}

  @adapter Application.compile_env(
             :ex_macos_control,
             :adapter,
             ExMacOSControl.OSAScriptAdapter
           )

  @doc """
  Checks if accessibility permission is granted for the current application.

  Accessibility permission is required for UI automation operations like:
  - Clicking menu items
  - Sending keystrokes
  - Reading/modifying window properties

  ## Returns

  - `{:ok, :granted}` - Permission is granted
  - `{:ok, :not_granted}` - Permission is not granted
  - `{:error, Error.t()}` - Error checking permission

  ## Examples

      case check_accessibility() do
        {:ok, :granted} ->
          IO.puts("Ready for UI automation!")

        {:ok, :not_granted} ->
          show_accessibility_help()

        {:error, reason} ->
          IO.puts("Error: \#{inspect(reason)}")
      end

  ## How It Works

  Attempts a simple UI automation task. If it succeeds, permission is granted.
  If it fails with a permission error, permission is not granted.
  """
  @spec check_accessibility() :: {:ok, :granted | :not_granted} | {:error, Error.t()}
  def check_accessibility do
    script = """
    tell application "System Events"
      try
        set frontmost to true
        return "granted"
      on error errMsg
        if errMsg contains "not allowed assistive access" then
          return "not_granted"
        else
          error errMsg
        end if
      end try
    end tell
    """

    case @adapter.run_applescript(script) do
      {:ok, "granted"} ->
        {:ok, :granted}

      {:ok, "not_granted"} ->
        {:ok, :not_granted}

      {:error, %Error{message: msg} = error} ->
        if String.contains?(msg, "not allowed") do
          {:ok, :not_granted}
        else
          {:error, error}
        end
    end
  end

  @doc """
  Checks if automation permission is granted for controlling a specific application.

  Automation permission is required to control apps via AppleScript/JXA.

  ## Parameters

  - `app_name` - Name of the application (e.g., "Safari", "Finder")

  ## Returns

  - `{:ok, :granted}` - Permission is granted
  - `{:ok, :not_granted}` - Permission is not granted
  - `{:error, Error.t()}` - Error checking permission

  ## Examples

      case check_automation("Safari") do
        {:ok, :granted} ->
          Safari.open_url("https://example.com")

        {:ok, :not_granted} ->
          show_automation_help("Safari")
      end

  ## How It Works

  Attempts to get a simple property from the target application.
  If it succeeds, permission is granted. If it fails with a permission error,
  permission is not granted.
  """
  @spec check_automation(String.t()) :: {:ok, :granted | :not_granted} | {:error, Error.t()}
  def check_automation(app_name) do
    script = """
    tell application "#{escape_quotes(app_name)}"
      try
        get name
        return "granted"
      on error errMsg
        if errMsg contains "not allowed" or errMsg contains "not authorized" then
          return "not_granted"
        else
          error errMsg
        end if
      end try
    end tell
    """

    case @adapter.run_applescript(script) do
      {:ok, "granted"} ->
        {:ok, :granted}

      {:ok, "not_granted"} ->
        {:ok, :not_granted}

      {:error, %Error{message: msg} = error} ->
        if String.contains?(msg, "not allowed") or String.contains?(msg, "not authorized") do
          {:ok, :not_granted}
        else
          {:error, error}
        end
    end
  end

  @doc """
  Displays helpful instructions for granting accessibility permission.

  Prints step-by-step instructions tailored to the current macOS version.

  ## Examples

      show_accessibility_help()
      # Prints:
      #
      # Accessibility Permission Required
      # ================================
      #
      # To grant accessibility permission:
      #
      # 1. Open System Settings
      # 2. Go to Privacy & Security
      # 3. Click on Accessibility
      # 4. Click the lock icon to make changes
      # 5. Find "Terminal" (or your app name)
      # 6. Enable the checkbox
      #
      # Or run: Permissions.open_accessibility_preferences()

  ## Returns

  `:ok` - Always returns :ok after displaying help
  """
  @spec show_accessibility_help() :: :ok
  def show_accessibility_help do
    {app_name, settings_name} = get_system_info()

    IO.puts("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║        Accessibility Permission Required                      ║
    ╚═══════════════════════════════════════════════════════════════╝

    To enable UI automation, you need to grant accessibility permission.

    Steps to grant permission:

    1. Open #{settings_name}
    2. Go to "Privacy & Security"
    3. Click on "Accessibility" in the left sidebar
    4. Click the lock icon (🔒) to make changes
    5. Find "#{app_name}" in the list
    6. Enable the checkbox next to it

    Quick shortcut:
    Run this command to open the settings directly:

        ExMacOSControl.Permissions.open_accessibility_preferences()

    After granting permission, restart your application.

    """)

    :ok
  end

  @doc """
  Displays helpful instructions for granting automation permission for a specific app.

  ## Parameters

  - `app_name` - Name of the application (e.g., "Safari")

  ## Examples

      show_automation_help("Safari")
      # Prints instructions specific to Safari automation

  ## Returns

  `:ok` - Always returns :ok after displaying help
  """
  @spec show_automation_help(String.t()) :: :ok
  def show_automation_help(app_name) do
    {current_app, settings_name} = get_system_info()

    IO.puts("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║        Automation Permission Required                         ║
    ╚═══════════════════════════════════════════════════════════════╝

    To control #{app_name}, you need to grant automation permission.

    Steps to grant permission:

    1. Open #{settings_name}
    2. Go to "Privacy & Security"
    3. Click on "Automation" in the left sidebar
    4. Find "#{current_app}" in the list
    5. Enable the checkbox next to "#{app_name}"

    Quick shortcut:
    Run this command to open the settings directly:

        ExMacOSControl.Permissions.open_automation_preferences()

    After granting permission, restart your application.

    """)

    :ok
  end

  @doc """
  Opens System Settings/Preferences to the Accessibility pane.

  This provides a quick way to access the accessibility settings.

  ## Examples

      open_accessibility_preferences()
      # Opens System Settings > Privacy & Security > Accessibility

  ## Returns

  - `:ok` - Settings opened successfully
  - `{:error, Error.t()}` - Error opening settings
  """
  @spec open_accessibility_preferences() :: :ok | {:error, Error.t()}
  def open_accessibility_preferences do
    script = """
    tell application "System Settings"
      activate
      delay 0.5
      reveal pane id "com.apple.preference.security"
      delay 0.5
      reveal anchor "Privacy_Accessibility" of pane id "com.apple.preference.security"
    end tell
    """

    case @adapter.run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Opens System Settings/Preferences to the Automation pane.

  This provides a quick way to access the automation settings.

  ## Examples

      open_automation_preferences()
      # Opens System Settings > Privacy & Security > Automation

  ## Returns

  - `:ok` - Settings opened successfully
  - `{:error, Error.t()}` - Error opening settings
  """
  @spec open_automation_preferences() :: :ok | {:error, Error.t()}
  def open_automation_preferences do
    script = """
    tell application "System Settings"
      activate
      delay 0.5
      reveal pane id "com.apple.preference.security"
      delay 0.5
      reveal anchor "Privacy_Automation" of pane id "com.apple.preference.security"
    end tell
    """

    case @adapter.run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks all common permissions and returns a status map.

  This is useful for getting an overview of permission status.

  ## Returns

  A map with permission statuses:
  ```elixir
  %{
    accessibility: :granted | :not_granted | :error,
    safari_automation: :granted | :not_granted | :error,
    finder_automation: :granted | :not_granted | :error,
    # etc.
  }
  ```

  ## Examples

      statuses = check_all()

      Enum.each(statuses, fn {perm, status} ->
        IO.puts("\#{perm}: \#{status}")
      end)

      # Output:
      # accessibility: granted
      # safari_automation: not_granted
      # finder_automation: granted
  """
  @spec check_all() :: map()
  def check_all do
    %{
      accessibility: check_accessibility() |> extract_status(),
      safari_automation: check_automation("Safari") |> extract_status(),
      finder_automation: check_automation("Finder") |> extract_status(),
      mail_automation: check_automation("Mail") |> extract_status(),
      messages_automation: check_automation("Messages") |> extract_status()
    }
  end

  # Private helper functions

  # Get current app name and settings app name based on macOS version
  defp get_system_info do
    case Platform.macos_version() do
      {:ok, version} when version >= 14 ->
        {"Terminal", "System Settings"}

      {:ok, _} ->
        {"Terminal", "System Preferences"}

      {:error, _} ->
        {"Terminal", "System Settings"}
    end
  end

  # Extract status from check result
  defp extract_status({:ok, status}), do: status
  defp extract_status({:error, _}), do: :error

  # Escape quotes in strings
  defp escape_quotes(str) do
    String.replace(str, "\"", "\\\"")
  end
end
