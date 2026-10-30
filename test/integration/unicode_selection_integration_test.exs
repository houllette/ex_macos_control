defmodule ExMacOSControl.UnicodeSelectionIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{Finder, OSAScriptAdapter, Script, SystemEvents}

  @moduletag :integration
  @moduletag :desktop

  unless Enum.any?(ExUnit.configuration()[:include], &(&1 in [:desktop, {:desktop, true}])) do
    @moduletag skip: "Requires --include desktop (creates and closes its own Finder window)"
  end

  test "selection preserves distinct fullwidth and ASCII backslash filenames" do
    original_adapter = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)

    on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, original_adapter) end)

    directory = Path.expand("tmp/unicode-selection-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    paths = Enum.map(["fullwidth＼name.txt", ~S(fullwidth\name.txt)], &Path.join(directory, &1))
    Enum.each(paths, &File.write!(&1, Path.basename(&1)))

    window_ids_script = ~s(tell application "Finder" to get id of every Finder window)
    assert {:ok, original_windows} = OSAScriptAdapter.run_applescript(window_ids_script, timeout: 5000)

    create_script = """
    tell application "Finder"
      activate
      set reviewWindow to make new Finder window to POSIX file "#{Script.escape_string(directory)}"
      return id of reviewWindow
    end tell
    """

    assert {:ok, id_text} = OSAScriptAdapter.run_applescript(create_script, timeout: 5000)
    window_id = String.to_integer(id_text)

    try do
      for path <- paths do
        # The window can exist before Finder has finished loading its items.
        selected? =
          Enum.any?(1..20, fn _ ->
            assert :ok = SystemEvents.reveal_in_finder(path)
            matches? = Finder.get_selection() == {:ok, [path]}
            unless matches?, do: Process.sleep(50)
            matches?
          end)

        assert selected?
        assert {:ok, [^path]} = Finder.get_selection()
        assert {:ok, [^path]} = SystemEvents.get_selected_finder_items()
      end
    after
      close_script = ~s(tell application "Finder" to close Finder window id #{window_id})
      assert {:ok, _} = OSAScriptAdapter.run_applescript(close_script, timeout: 5000)
    end

    assert {:ok, ^original_windows} = OSAScriptAdapter.run_applescript(window_ids_script, timeout: 5000)
  end
end
