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

  alias ExMacOSControl.{Error, ScriptOutput}

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
        set end of paths to {POSIX path of (anItem as alias)}
      end repeat
      return my exmc_encode_rows(paths)
    end tell
    #{ScriptOutput.handlers()}
    """

    case ExMacOSControl.run_applescript(script) do
      {:ok, output} ->
        with {:ok, rows} <- ScriptOutput.decode(output, 1) do
          {:ok, List.flatten(rows)}
        end

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
      open POSIX file "#{ExMacOSControl.Script.escape_string(path)}"
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
      make new Finder window to POSIX file "#{ExMacOSControl.Script.escape_string(path)}"
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
        else
          error "No Finder windows are open" number -1728
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

  # Convert view atom to AppleScript view name
  defp view_to_applescript(:icon), do: "icon view"
  defp view_to_applescript(:list), do: "list view"
  defp view_to_applescript(:column), do: "column view"
  # Note: "gallery view" is the name on macOS 10.15+, but "flow view" on older versions
  # We use "flow view" for broader compatibility
  defp view_to_applescript(:gallery), do: "flow view"

  # Validate view mode
  defp valid_view?(view), do: view in [:icon, :list, :column, :gallery]

  @doc "Lists Finder windows with IDs, bounds and target URLs."
  def list_windows(opts \\ []),
    do:
      ExMacOSControl.Resources.list(
        "com.apple.finder",
        "app.finderWindows",
        [id: "o.id()", name: "o.name()", bounds: "o.bounds()", url: "o.target().url()"],
        %{},
        opts
      )

  def get_frontmost_window(opts \\ []) do
    ExMacOSControl.Automation.query(
      "com.apple.finder",
      "if(app.finderWindows.length===0)return null;var o=app.finderWindows[0];return {id:o.id(),name:o.name(),bounds:o.bounds(),url:o.target().url()};",
      %{},
      opts
    )
  end

  def get_window_bounds(id, opts \\ []),
    do:
      ExMacOSControl.Automation.query(
        "com.apple.finder",
        "return byId(app.finderWindows,input.id).bounds();",
        %{id: id},
        opts
      )

  def get_window_position(id, opts \\ []),
    do:
      ExMacOSControl.Automation.query(
        "com.apple.finder",
        "return byId(app.finderWindows,input.id).bounds().slice(0,2);",
        %{id: id},
        opts
      )

  def set_window_target(id, path, opts \\ []) when is_integer(id) do
    file_action(
      path,
      ~s|set target of Finder window id #{id} to POSIX file "#{ExMacOSControl.Script.escape_string(path)}"|,
      opts
    )
  end

  def rename(path, name, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.required_string(name, "File name"),
         false <- String.contains?(name, "/") do
      file_action(
        path,
        ~s|set name of (POSIX file "#{ExMacOSControl.Script.escape_string(path)}" as alias) to "#{ExMacOSControl.Script.escape_string(name)}"|,
        opts
      )
    else
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("File name must be a single path component")}
    end
  end

  def copy(path, destination, opts \\ []), do: transfer("duplicate", path, destination, opts)
  def move(path, destination, opts \\ []), do: transfer("move", path, destination, opts)

  def move_to_trash(path, opts \\ []),
    do: ExMacOSControl.with_options(opts, fn -> ExMacOSControl.SystemEvents.trash_file(path) end)

  def create_folder(parent, name, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.required_string(name, "Folder name"),
         true <- File.dir?(parent) and not String.contains?(name, "/"),
         false <- File.exists?(Path.join(parent, name)) do
      file_action(
        parent,
        ~s|make new folder at POSIX file "#{ExMacOSControl.Script.escape_string(Path.expand(parent))}" with properties {name:"#{ExMacOSControl.Script.escape_string(name)}"}|,
        opts
      )
    else
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("Parent must exist and folder must be new")}
    end
  end

  def set_selection(paths, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:timeout, :max_output_bytes]),
         true <- is_list(paths) and Enum.all?(paths, &(is_binary(&1) and File.exists?(&1))) do
      script = """
      on run argv
        set selectedItems to {}
        repeat with p in argv
          set end of selectedItems to (POSIX file (contents of p) as alias)
        end repeat
        tell application "Finder" to set selection to selectedItems
      end run
      """

      execution =
        opts
        |> ExMacOSControl.Automation.execution_options()
        |> Keyword.put_new(:timeout, 30_000)
        |> Keyword.put(:args, Enum.map(paths, &Path.expand/1))

      case ExMacOSControl.run_applescript(script, execution) do
        {:ok, _} -> :ok
        error -> error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("Selection must contain existing paths")}
    end
  end

  def metadata(path, opts \\ []) do
    if is_binary(path) and File.exists?(path) do
      ExMacOSControl.Automation.query(
        nil,
        "ObjC.import('Foundation');var a=$.NSFileManager.defaultManager.attributesOfItemAtPathError($(input.path),null);if(!a)throw new Error('Metadata unavailable');return {path:input.path,size:ObjC.unwrap(a.objectForKey($.NSFileSize)),created_at:iso(ObjC.unwrap(a.objectForKey($.NSFileCreationDate))),modified_at:iso(ObjC.unwrap(a.objectForKey($.NSFileModificationDate)))};",
        %{path: Path.expand(path)},
        opts
      )
    else
      {:error, Error.not_found("File not found")}
    end
  end

  def list_volumes(opts \\ []),
    do:
      ExMacOSControl.Resources.list(
        "com.apple.finder",
        "app.disks",
        [name: "o.name()", url: "o.url()", capacity: "o.capacity()", free_space: "o.freeSpace()"],
        %{},
        opts
      )

  def eject(path, opts \\ []),
    do: file_action(path, ~s|eject (POSIX file "#{ExMacOSControl.Script.escape_string(path)}" as alias)|, opts)

  def get_selection(opts), do: ExMacOSControl.with_options(opts, &get_selection/0)
  def get_current_folder(opts), do: ExMacOSControl.with_options(opts, &get_current_folder/0)
  def open_location(path, opts), do: ExMacOSControl.with_options(opts, fn -> open_location(path) end)
  def new_window(path, opts), do: ExMacOSControl.with_options(opts, fn -> new_window(path) end)
  def set_view(view, opts), do: ExMacOSControl.with_options(opts, fn -> set_view(view) end)

  @doc "Captures a non-empty selection once and passes it to a tagged-result callback under a shared deadline."
  defdelegate with_selection(fun, opts \\ []), to: ExMacOSControl.Finder.Compositions
  @doc "Maps the captured selection sequentially, reporting completed results on failure."
  defdelegate map_selection(fun, opts \\ []), to: ExMacOSControl.Finder.Compositions
  defdelegate copy_selection(destination, opts \\ []), to: ExMacOSControl.Finder.Compositions
  defdelegate move_selection(destination, opts \\ []), to: ExMacOSControl.Finder.Compositions
  @doc "Copies a batch after checking every destination for collisions; returns resulting paths."
  defdelegate copy_files(paths, destination, opts \\ []), to: ExMacOSControl.Finder.Compositions
  @doc "Moves a batch once, stopping on the first failure; completed paths are available in error details."
  defdelegate move_files(paths, destination, opts \\ []), to: ExMacOSControl.Finder.Compositions
  defdelegate capture_selection(opts \\ []), to: ExMacOSControl.Capture, as: :selection

  defp transfer(command, path, destination, opts) do
    if is_binary(path) and is_binary(destination) and File.exists?(path) and File.dir?(destination) and
         not File.exists?(Path.join(destination, Path.basename(path))) do
      file_action(
        path,
        ~s|#{command} (POSIX file "#{ExMacOSControl.Script.escape_string(Path.expand(path))}" as alias) to (POSIX file "#{ExMacOSControl.Script.escape_string(Path.expand(destination))}" as alias) without replacing|,
        opts
      )
    else
      {:error, Error.execution_error("Source and destination must exist and destination item must be new")}
    end
  end

  defp file_action(path, command, opts) do
    if is_binary(path) and File.exists?(path) do
      execute_file_action(command, opts)
    else
      {:error, Error.not_found("File not found")}
    end
  end

  defp execute_file_action(command, opts) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:timeout, :max_output_bytes]) do
      execution = opts |> ExMacOSControl.Automation.execution_options() |> Keyword.put_new(:timeout, 30_000)

      ExMacOSControl.with_options(execution, fn -> run_file_command(command) end)
    end
  end

  defp run_file_command(command) do
    case ExMacOSControl.run_applescript("tell application \"Finder\"\n#{command}\nend tell") do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
