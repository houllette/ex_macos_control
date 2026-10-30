defmodule ExMacOSControl.Composition.Journal do
  @moduledoc """
  Optional private, synced JSONL execution evidence. A step intent is persisted
  before its callback. No app bodies, arguments or arbitrary results are stored.
  Declared resource IDs are retained for observation and manual reconciliation.

  `inspect_run/1` never replays work. Unfinished or uncertain steps require
  reconciliation; acknowledgements do not prove external delivery. Run IDs cannot
  be reused. Journals and their ancestor directories must not be symlinks.
  Inspect a run after its owner has stopped; an active run can also have pending intents.
  """
  import Bitwise
  alias ExMacOSControl.Error

  def open(nil, _run_id), do: {:ok, nil}

  def open(directory, run_id) do
    with true <- is_binary(directory),
         :ok <- safe_ancestors(directory),
         :ok <- private_directory(directory),
         path = Path.join(directory, run_id <> ".jsonl"),
         {:ok, io} <- File.open(path, [:write, :exclusive, :binary, :sync]) do
      case File.chmod(path, 0o600) do
        :ok ->
          {:ok, %{io: io, path: Path.expand(path)}}

        _ ->
          File.close(io)
          failure()
      end
    else
      _ -> failure()
    end
  end

  def append(nil, _event), do: :ok

  def append(journal, event) do
    with :ok <- IO.binwrite(journal.io, Jason.encode!(event) <> "\n"), do: :file.sync(journal.io)
  rescue
    _ -> failure()
  catch
    _, _ -> failure()
  end

  def close(nil), do: :ok
  def close(journal), do: File.close(journal.io)

  def inspect_run(path) do
    with :ok <- safe_ancestors(Path.dirname(path)),
         {:ok, %{type: :regular, mode: mode, size: size}} <- File.lstat(path),
         true <- (mode &&& 0o077) == 0 and size <= 2_097_152,
         {:ok, data} <- File.read(path),
         {:ok, records, truncated} <- decode(data) do
      {:ok, summary(records, truncated)}
    else
      _ -> failure()
    end
  end

  defp decode(data) do
    lines = String.split(data, "\n")
    complete = Enum.drop(lines, -1)

    Enum.reduce_while(complete, {:ok, []}, fn line, {:ok, records} ->
      case Jason.decode(line) do
        {:ok, %{"event" => event} = record} when is_binary(event) -> {:cont, {:ok, [record | records]}}
        _ -> {:halt, failure()}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records), List.last(lines) != ""}
      error -> error
    end
  end

  defp summary(records, truncated) do
    intents = Enum.filter(records, &(&1["event"] == "step_started"))
    finished = Map.new(Enum.filter(records, &(&1["event"] == "step_finished")), &{&1["step_id"], &1})

    pending =
      Enum.filter(intents, fn intent ->
        case finished[intent["step_id"]] do
          %{"outcome" => outcome} -> outcome == "unknown"
          _ -> true
        end
      end)

    last = List.last(records) || %{}

    status = status(last, truncated or pending != [])

    %{
      run_id: last["run_id"],
      status: status,
      pending: pending,
      resources: Enum.flat_map(records, &Map.get(&1, "resources", [])),
      events: records
    }
  end

  defp status(_last, true), do: :needs_reconciliation

  defp status(%{"event" => "run_finished", "outcome" => outcome}, false) when outcome in ["acknowledged", "confirmed"],
    do: :complete

  defp status(%{"event" => "run_finished", "outcome" => outcome}, false) when outcome in ["failed", "not_started"],
    do: :failed

  defp status(_last, false), do: :needs_reconciliation

  defp private_directory(directory) do
    case File.lstat(directory) do
      {:error, :enoent} ->
        with :ok <- File.mkdir_p(directory), do: File.chmod(directory, 0o700)

      {:ok, %{type: :directory, mode: mode}} when (mode &&& 0o077) == 0 ->
        :ok

      _ ->
        failure()
    end
  end

  defp safe_ancestors(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.reduce_while(:ok, fn part, :ok ->
      case File.lstat(part) do
        {:ok, %{type: :directory}} -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        _ -> {:halt, failure()}
      end
    end)
  end

  defp failure,
    do: {:error, Error.execution_error("Execution journal is unavailable, reused or unsafe", outcome: :unknown)}
end
