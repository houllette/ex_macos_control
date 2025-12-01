defmodule ExMacOSControl.Finder do
  @moduledoc """
  Automation helpers for macOS Finder.

  Provides functions to control Finder windows, navigate folders, manage
  selections, and configure view settings.

  ## Examples

      # Get selected files
      {:ok, files} = ExMacOSControl.Finder.get_selection()
      # => {:ok, ["/Users/me/file.txt"]}

      # Open Finder at location
      :ok = ExMacOSControl.Finder.open_location("/Users/me/Documents")

      # Create new window
      :ok = ExMacOSControl.Finder.new_window("/Applications")

      # Get current folder
      {:ok, path} = ExMacOSControl.Finder.get_current_folder()
      # => {:ok, "/Users/me/Documents"}

      # Set view mode
      :ok = ExMacOSControl.Finder.set_view(:list)

  ## View Modes

  Supported view modes:
  - `:icon` - Icon view
  - `:list` - List view
  - `:column` - Column view
  - `:gallery` - Gallery/Flow view (called "flow view" on older macOS, "gallery view" on newer)

  ## Notes

  - Finder is always running on macOS
  - Some operations require Finder to be activated
  - Paths should be POSIX format (e.g., "/Users/me/Documents")

  ## Permissions

  This module requires:
  - Automation permissions for Finder

  See the Permissions guide for setup instructions.
  """

  alias ExMacOSControl.Error

  @doc """
  Get the list of currently selected files/folders in Finder.

  Returns a list of POSIX paths for all currently selected items in the
  frontmost Finder window. If no items are selected, returns an empty list.

  ## Returns

  - `{:ok, paths}` - List of POSIX paths to selected items
  - `{:error, error}` - If Finder is not available or an error occurs

  ## Examples

      # With selected files
      ExMacOSControl.Finder.get_selection()
      # => {:ok, ["/Users/me/file.txt", "/Users/me/file2.txt"]}

      # With no selection
      ExMacOSControl.Finder.get_selection()
      # => {:ok, []}
  """
  @spec get_selection() :: {:ok, [String.t()]} | {:error, Error.t()}
  def get_selection do
    script = """
    tell application "Finder"
      set selectedItems to selection
      set paths to {}
      repeat with anItem in selectedItems
        set end of paths to POSIX path of (anItem as alias)
      end repeat
      return paths as text
    end tell
    """

    case ExMacOSControl.run_applescript(script) do
      {:ok, output} ->
        {:ok, parse_paths(output)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Open Finder at a specific location.

  Opens a Finder window at the specified path and activates Finder
  (brings it to the front). If a Finder window is already open at this
  location, it will be brought to the front.

  ## Parameters

  - `path` - POSIX path to the folder to open (e.g., "/Users/me/Documents")

  ## Returns

  - `:ok` - Successfully opened the location
  - `{:error, error}` - If the path doesn't exist or is invalid

  ## Examples

      ExMacOSControl.Finder.open_location("/Users/me/Documents")
      # => :ok

      ExMacOSControl.Finder.open_location("/nonexistent/path")
      # => {:error, %ExMacOSControl.Error{...}}
  """
  @spec open_location(String.t()) :: :ok | {:error, Error.t()}
  def open_location(path) do
    script = """
    tell application "Finder"
      activate
      open POSIX file "#{path}"
    end tell
    """

    case ExMacOSControl.run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Open a new Finder window at specified path.

  Creates a new Finder window at the specified location and activates
  Finder. This always creates a new window, even if a window at this
  location already exists.

  ## Parameters

  - `path` - POSIX path to the folder to open (e.g., "/Applications")

  ## Returns

  - `:ok` - Successfully created the new window
  - `{:error, error}` - If the path doesn't exist or is invalid

  ## Examples

      ExMacOSControl.Finder.new_window("/Applications")
      # => :ok

      ExMacOSControl.Finder.new_window("/invalid/path")
      # => {:error, %ExMacOSControl.Error{...}}
  """
  @spec new_window(String.t()) :: :ok | {:error, Error.t()}
  def new_window(path) do
    script = """
    tell application "Finder"
      activate
      make new Finder window to POSIX file "#{path}"
    end tell
    """

    case ExMacOSControl.run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the path of the current Finder window's folder.

  Returns the POSIX path of the folder shown in the frontmost Finder window.
  If no Finder windows are open, returns an empty string.

  ## Returns

  - `{:ok, path}` - POSIX path to the current folder
  - `{:ok, ""}` - If no Finder windows are open
  - `{:error, error}` - If an error occurs

  ## Examples

      # With a Finder window open
      ExMacOSControl.Finder.get_current_folder()
      # => {:ok, "/Users/me/Documents"}

      # With no Finder windows
      ExMacOSControl.Finder.get_current_folder()
      # => {:ok, ""}
  """
  @spec get_current_folder() :: {:ok, String.t()} | {:error, Error.t()}
  def get_current_folder do
    script = """
    tell application "Finder"
      if (count of Finder windows) > 0 then
        set currentFolder to target of front Finder window as alias
        return POSIX path of currentFolder
      else
        return ""
      end if
    end tell
    """

    case ExMacOSControl.run_applescript(script) do
      {:ok, output} ->
        {:ok, String.trim(output)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Set the view mode for the current Finder window.

  Changes the view mode of the frontmost Finder window to the specified
  view. The window must be open for this operation to succeed.

  ## Parameters

  - `view` - View mode atom: `:icon`, `:list`, `:column`, or `:gallery`

  ## Returns

  - `:ok` - Successfully changed the view mode
  - `{:error, error}` - If no windows are open, invalid view mode, or other error

  ## Examples

      ExMacOSControl.Finder.set_view(:icon)
      # => :ok

      ExMacOSControl.Finder.set_view(:list)
      # => :ok

      ExMacOSControl.Finder.set_view(:invalid)
      # => {:error, %ExMacOSControl.Error{...}}
  """
  @spec set_view(:icon | :list | :column | :gallery) :: :ok | {:error, Error.t()}
  def set_view(view) do
    if valid_view?(view) do
      applescript_view = view_to_applescript(view)

      script = """
      tell application "Finder"
        if (count of Finder windows) > 0 then
          set current view of front Finder window to #{applescript_view}
        end if
      end tell
      """

      case ExMacOSControl.run_applescript(script) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error,
       Error.execution_error("Invalid view mode",
         view: view,
         valid: [:icon, :list, :column, :gallery]
       )}
    end
  end

  # Parse comma-separated path list from AppleScript output
  defp parse_paths(""), do: []

  defp parse_paths(output) do
    output
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Convert view atom to AppleScript view name
  defp view_to_applescript(:icon), do: "icon view"
  defp view_to_applescript(:list), do: "list view"
  defp view_to_applescript(:column), do: "column view"
  # Note: "gallery view" is the name on macOS 10.15+, but "flow view" on older versions
  # We use "flow view" for broader compatibility
  defp view_to_applescript(:gallery), do: "flow view"

  # Validate view mode
  defp valid_view?(view), do: view in [:icon, :list, :column, :gallery]
end
