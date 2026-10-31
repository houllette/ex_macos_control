defmodule ExMacOSControl.Capture.Staging do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Error, Validation}
  alias ExMacOSControl.Capture.{Files, StagedFiles}
  @block 1_048_576
  @limit 1_073_741_824
  @identity [:inode, :major_device, :minor_device, :type]
  @version @identity ++ [:size, :mtime, :ctime]

  def stage(%Files{} = capture, destination, opts) do
    with :ok <- Automation.options(opts, [:timeout, :max_bytes, :journal, :trace_to, :run_id]),
         :ok <- Automation.required_string(destination, "Staging destination"),
         true <- is_integer(Keyword.get(opts, :max_bytes, @limit)) and Keyword.get(opts, :max_bytes, @limit) > 0,
         {:ok, entries} <- sources(capture.paths, opts[:max_bytes] || @limit) do
      root = Path.expand(destination)
      Composition.run(fn -> stage_effect(capture, root, entries, opts) end, Keyword.drop(opts, [:max_bytes]))
    else
      false -> invalid("max_bytes must be positive")
      error -> error
    end
  end

  def stage(_, _, _), do: invalid("Expected a file capture")

  def verify(%StagedFiles{} = capture, opts) do
    with :ok <- Automation.options(opts, [:timeout]),
         do: Composition.run(fn -> verify_manifest(capture) end, opts)
  end

  def verify(_, _), do: invalid("Expected a staged file capture")

  def cleanup(%StagedFiles{} = capture, opts) do
    with :ok <- Automation.options(opts, [:timeout, :journal, :trace_to, :run_id]),
         do: Composition.run(fn -> cleanup_workflow(capture) end, opts)
  end

  def cleanup(_, _), do: invalid("Expected a staged file capture")

  defp sources(paths, limit) do
    with :ok <- Validation.items(paths),
         :ok <- Validation.all(paths, &Automation.required_string(&1, "Source path")),
         {:ok, entries} <- collect_sources(paths),
         true <- unique_names?(entries),
         true <- Enum.sum(Enum.map(entries, & &1.stat.size)) <= limit do
      {:ok, entries}
    else
      false -> invalid("Source sizes exceed max_bytes or filenames collide")
      error -> error
    end
  end

  defp collect_sources(paths), do: collect(paths, &source/1)

  defp source(path) do
    path = Path.expand(path)

    case File.lstat(path, time: :posix) do
      {:ok, %{type: :regular} = stat} -> {:ok, %{source_path: path, name: Path.basename(path), stat: stat}}
      _ -> invalid("Sources must be existing regular files, without final symlinks")
    end
  end

  defp unique_names?(entries) do
    names = Enum.map(entries, &(&1.name |> String.normalize(:nfd) |> String.downcase()))
    length(Enum.uniq(names)) == length(names)
  end

  defp stage_effect(capture, root, entries, opts) do
    Composition.effect(:stage_file_capture, fn -> create_stage(capture, root, entries, opts) end,
      resource: :file_capture,
      identity: %{path: root}
    )
  end

  defp create_stage(capture, root, entries, opts) do
    case File.mkdir(root) do
      :ok -> populate(capture, root, entries, opts[:max_bytes] || @limit)
      {:error, reason} -> invalid("Staging requires a new directory under an existing parent", reason: reason)
    end
  end

  defp populate(capture, root, sources, limit) do
    result =
      with :ok <- File.chmod(root, 0o700),
           {:ok, root_stat} <- File.lstat(root, time: :posix),
           {:ok, entries} <- copy_sources(sources, root, limit) do
        staged = %StagedFiles{
          id: root,
          root: root,
          paths: Enum.map(entries, & &1.path),
          entries: entries,
          root_identity: identity(root_stat),
          source: capture.source,
          captured_at: capture.captured_at,
          staged_at: DateTime.utc_now()
        }

        with :ok <- verify_manifest(staged), do: {:ok, staged}
      end

    case result do
      {:ok, _} ->
        result

      error ->
        {:error,
         Error.execution_error("File staging did not finish; inspect the private partial directory",
           outcome: :unknown,
           staging_root: root,
           intended_paths: Enum.map(sources, &Path.join(root, &1.name)),
           cause: error
         )}
    end
  end

  defp copy_sources(sources, root, limit) do
    Enum.reduce_while(sources, {:ok, [], limit}, fn source, {:ok, acc, remaining} ->
      case copy_file(source, root, remaining) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc], remaining - entry.size}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries, _} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp copy_file(source, root, remaining) do
    target = Path.join(root, source.name)

    with_file(source.source_path, [:read, :raw, :binary], fn input ->
      with {:ok, before} <- descriptor_stat(input), true <- version(before) == version(source.stat) do
        with_file(target, [:write, :exclusive, :raw, :binary], &copy_open(input, &1, source, target, remaining))
      else
        _ -> invalid("Source identity changed before copying")
      end
    end)
  end

  defp copy_open(input, output, source, target, remaining) do
    with {:ok, digest, size} <- transfer(input, output, remaining),
         :ok <- :file.sync(output),
         {:ok, _} <- :file.position(input, :bof),
         {:ok, second, ^size} <- transfer(input, nil, remaining),
         true <- digest == second,
         {:ok, after_fd} <- descriptor_stat(input),
         {:ok, after_path} <- File.lstat(source.source_path, time: :posix),
         true <- version(source.stat) == version(after_fd) and version(after_fd) == version(after_path),
         :ok <- File.chmod(target, 0o600),
         {:ok, out} <- descriptor_stat(output) do
      {:ok,
       %{
         source_path: source.source_path,
         path: target,
         size: size,
         sha256: digest,
         source_identity: version(source.stat),
         output_identity: version(out)
       }}
    else
      _ -> invalid("Source changed, copy failed, or byte limit was exceeded")
    end
  end

  defp transfer(input, output, remaining), do: transfer(input, output, remaining, :crypto.hash_init(:sha256), 0)

  defp transfer(input, output, remaining, hash, size) do
    if Composition.remaining() == 0 do
      {:error, Error.timeout("Copying files")}
    else
      transfer_block(:file.read(input, @block), input, output, remaining, hash, size)
    end
  end

  defp transfer_block(:eof, _input, _output, _remaining, hash, size),
    do: {:ok, Base.encode16(:crypto.hash_final(hash), case: :lower), size}

  defp transfer_block({:ok, bytes}, input, output, remaining, hash, size) when byte_size(bytes) <= remaining do
    with :ok <- write_block(output, bytes) do
      transfer(input, output, remaining - byte_size(bytes), :crypto.hash_update(hash, bytes), size + byte_size(bytes))
    end
  end

  defp transfer_block(_, _, _, _, _, _), do: invalid("Read failed or byte limit exceeded")

  defp write_block(nil, _bytes), do: :ok

  defp write_block(output, bytes) do
    with :ok <- :file.write(output, bytes) do
      :telemetry.execute([:ex_macos_control, :capture, :copy, :chunk], %{bytes: byte_size(bytes)}, %{})
      :ok
    end
  end

  defp verify_manifest(capture) do
    with :ok <- Validation.items(capture.entries),
         {:ok, root} <- File.lstat(capture.root, time: :posix),
         true <- root.type == :directory and identity(root) == capture.root_identity,
         true <- capture.paths == Enum.map(capture.entries, & &1.path),
         true <- length(Enum.uniq(capture.paths)) == length(capture.paths),
         :ok <- Validation.all(capture.entries, &verify_entry(&1, capture.root)) do
      :ok
    else
      _ -> invalid("Staged files or their directory changed")
    end
  end

  defp verify_entry(entry, root) do
    with true <- Path.dirname(entry.path) == root,
         {:ok, before} <- File.lstat(entry.path, time: :posix),
         true <- before.type == :regular and version(before) == entry.output_identity do
      verify_contents(entry, before)
    else
      _ -> invalid("Staged file identity changed")
    end
  end

  defp verify_contents(entry, before) do
    with_file(entry.path, [:read, :raw, :binary], fn input ->
      with {:ok, opened} <- descriptor_stat(input),
           true <- version(opened) == version(before),
           {:ok, hash, size} <- transfer(input, nil, entry.size),
           {:ok, after_fd} <- descriptor_stat(input),
           {:ok, after_path} <- File.lstat(entry.path, time: :posix),
           true <-
             hash == entry.sha256 and size == entry.size and version(after_fd) == version(before) and
               version(after_path) == version(before),
           do: :ok
    end)
    |> case do
      :ok -> :ok
      _ -> invalid("Staged file contents changed")
    end
  end

  defp cleanup_workflow(capture) do
    with :ok <- verify_manifest(capture),
         {:ok, names} <- File.ls(capture.root),
         true <- Enum.sort(names) == Enum.sort(Enum.map(capture.paths, &Path.basename/1)) do
      Composition.effect(:cleanup_file_capture, fn -> remove_entries(capture) end,
        resource: :file_capture,
        identity: %{path: capture.root}
      )
    else
      _ -> invalid("Cleanup refuses changed or foreign files")
    end
  end

  defp remove_entries(capture) do
    result = with :ok <- Validation.all(capture.entries, &remove_entry(&1, capture.root)), do: File.rmdir(capture.root)

    case result do
      :ok ->
        :ok

      _ ->
        {:error,
         Error.execution_error("File cleanup stopped after dispatch", outcome: :unknown, staging_root: capture.root)}
    end
  end

  defp remove_entry(entry, root) do
    with :ok <- verify_entry(entry, root), do: File.rm(entry.path)
  end

  defp descriptor_stat(fd) do
    with {:ok, record} <- :file.read_file_info(fd, time: :posix), do: {:ok, File.Stat.from_record(record)}
  end

  defp identity(stat), do: Map.take(stat, @identity)
  defp version(stat), do: Map.take(stat, @version)

  defp with_file(path, modes, fun) do
    case File.open(path, modes) do
      {:ok, file} ->
        try do
          fun.(file)
        after
          File.close(file)
        end

      error ->
        error
    end
  end

  defp collect(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, result} -> {:ok, Enum.reverse(result)}
      error -> error
    end
  end

  defp invalid(message, details \\ []),
    do: {:error, Error.execution_error(message, Keyword.put(details, :outcome, :not_started))}
end
