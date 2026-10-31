defmodule ExMacOSControl.Finder.Compositions do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Desktop, Finder, Validation}

  def with_selection(fun, opts \\ []) when is_function(fun, 1) do
    Composition.run(
      fn -> do_with_selection(fun) end,
      opts
    )
  end

  def map_selection(fun, opts \\ []) when is_function(fun, 1) do
    with_selection(fn paths -> Composition.map(paths, :selected_file, fun) end, opts)
  end

  def copy_selection(destination, opts \\ []),
    do: with_selection(fn paths -> copy_files(paths, destination) end, opts)

  def move_selection(destination, opts \\ []),
    do: with_selection(fn paths -> move_files(paths, destination) end, opts)

  def copy_files(paths, destination, opts \\ []), do: transfer(paths, destination, :copy, opts)
  def move_files(paths, destination, opts \\ []), do: transfer(paths, destination, :move, opts)

  def select_and_capture(paths, opts \\ []) do
    with :ok <- Validation.items(paths),
         true <- Enum.all?(paths, &(is_binary(&1) and File.exists?(&1))) do
      expected = paths |> Enum.map(&Path.expand/1) |> Enum.uniq() |> Enum.sort()
      Desktop.with_lock(fn -> select_capture(expected) end, opts)
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Selected files must exist")
    end
  end

  defp select_capture(paths) do
    source = """
    on run argv
      set selectedItems to {}
      repeat with p in argv
        set end of selectedItems to (POSIX file (contents of p) as alias)
      end repeat
      tell application "Finder"
        reveal selectedItems
        activate
        set selection to selectedItems
      end tell
    end run
    """

    with {:ok, _} <- Composition.effect(:select_files, &ExMacOSControl.run_applescript/2, [source, [args: paths]]),
         :ok <- Composition.verify(:selected_files, &selection_matches?(paths, &1)),
         {:ok, capture} <- Finder.capture_selection(),
         true <- Enum.sort(capture.paths) == paths do
      {:ok, capture}
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Finder selection changed during capture")
    end
  end

  defp selection_matches?(paths, remaining) do
    with {:ok, selected} <- Finder.get_selection(timeout: remaining), do: {:ok, Enum.sort(selected) == paths}
  end

  defp transfer(paths, destination, operation, opts) do
    with :ok <- Validation.items(paths),
         true <- is_binary(destination) and File.dir?(destination),
         true <- Enum.all?(paths, &(is_binary(&1) and File.exists?(&1))),
         outputs = Enum.map(paths, &Path.join(Path.expand(destination), Path.basename(&1))),
         true <- Enum.uniq(outputs) == outputs and Enum.all?(outputs, &(File.lstat(&1) == {:error, :enoent})) do
      Composition.run(
        fn -> do_transfer(paths, destination, operation, outputs) end,
        opts
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Files and destination must exist; output names must be distinct and new")
    end
  end

  defp do_with_selection(fun) do
    with {:ok, paths} <- Composition.step(:finder_selection, &Finder.get_selection/0),
         :ok <- Validation.items(paths) do
      Composition.step(:use_selection, fn -> fun.(paths) end)
    end
  end

  defp do_transfer(paths, destination, operation, outputs) do
    Composition.map_effects(
      Enum.zip(paths, outputs),
      operation,
      fn {path, output} ->
        with :ok <- apply(Finder, operation, [path, destination]), do: {:ok, output}
      end,
      resource: :file,
      identity: fn {path, output} -> %{source_path: path, path: output} end
    )
  end
end
