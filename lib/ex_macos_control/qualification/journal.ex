defmodule ExMacOSControl.Qualification.Journal do
  @moduledoc false
  import Bitwise
  alias ExMacOSControl.Automation

  def open(workspace, run_id) do
    root = Path.join(workspace, "tmp/qualification")

    with true <- is_binary(run_id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, run_id),
         :ok <- private_directory(root),
         :ok <- resolved_history(root),
         path = Path.join(root, run_id),
         :ok <- File.mkdir(path),
         :ok <- File.chmod(path, 0o700),
         {:ok, io} <- File.open(Path.join(path, "events.jsonl"), [:write, :exclusive, :binary, :sync]),
         :ok <- File.chmod(Path.join(path, "events.jsonl"), 0o600) do
      {:ok, %{io: io, path: path, run_id: run_id}}
    else
      _ -> Automation.invalid("Run is reused, unresolved, or the private journal cannot be created")
    end
  end

  def append(journal, event) do
    event = Map.merge(event, %{at: DateTime.to_iso8601(DateTime.utc_now()), run_id: journal.run_id})
    with :ok <- IO.binwrite(journal.io, Jason.encode!(event) <> "\n"), do: :file.sync(journal.io)
  rescue
    _ -> {:error, :journal_io}
  catch
    _, _ -> {:error, :journal_io}
  end

  def close(journal), do: File.close(journal.io)

  def ready(workspace) do
    root = Path.join(workspace, "tmp/qualification")

    with :ok <- no_symlinks(root) do
      case File.lstat(root) do
        {:error, :enoent} -> :ok
        {:ok, %{type: :directory}} -> existing_ready(root)
        _ -> {:error, :unsafe_directory}
      end
    end
  end

  defp existing_ready(root), do: with(:ok <- private_existing(root), do: resolved_history(root))

  defp private_directory(root) do
    with :ok <- no_symlinks(root),
         :ok <- File.mkdir_p(Path.dirname(root)) do
      case File.mkdir(root) do
        :ok -> File.chmod(root, 0o700)
        {:error, :eexist} -> private_existing(root)
        error -> error
      end
    end
  end

  defp private_existing(root) do
    with {:ok, %{type: :directory, mode: mode}} <- File.lstat(root),
         true <- (mode &&& 0o077) == 0 do
      :ok
    else
      _ -> {:error, :unsafe_directory}
    end
  end

  defp no_symlinks(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.reduce_while(:ok, fn part, _ ->
      case File.lstat(part) do
        {:ok, %{type: :directory}} -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        _ -> {:halt, {:error, :unsafe_directory}}
      end
    end)
  end

  defp resolved_history(root) do
    with {:ok, entries} <- File.ls(root),
         true <- Enum.all?(entries, &resolved?(Path.join(root, &1))) do
      :ok
    else
      _ -> {:error, :unresolved_run}
    end
  end

  defp resolved?(path) do
    with {:ok, %{type: :directory}} <- File.lstat(path),
         events = Path.join(path, "events.jsonl"),
         {:ok, %{type: :regular, size: size}} when size <= 1_048_576 <- File.lstat(events),
         {:ok, data} <- File.read(events),
         true <- String.ends_with?(data, "\n"),
         {:ok, records} <- decode_records(data),
         %{"event" => "finished", "status" => "passed"} <- List.last(records) do
      true
    else
      _ -> false
    end
  end

  defp decode_records(data) do
    Enum.reduce_while(String.split(data, "\n", trim: true), {:ok, []}, fn line, {:ok, records} ->
      case Jason.decode(line) do
        {:ok, %{"event" => event} = record} when is_binary(event) -> {:cont, {:ok, records ++ [record]}}
        _ -> {:halt, {:error, :invalid_record}}
      end
    end)
  end
end
