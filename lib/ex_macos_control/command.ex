defmodule ExMacOSControl.Command do
  @moduledoc """
  Runs a command with separate stdout/stderr, a deadline and an output limit.

  A timeout terminates the owned process group. An Apple event already delivered
  to another application cannot be recalled; timeout errors mark that outcome as
  unknown. Commands and arguments are never interpolated into shell source.
  """

  alias ExMacOSControl.Error

  @default_limit 10_485_760
  @type result :: %{stdout: binary(), stderr: binary(), exit_status: non_neg_integer()}
  @type option ::
          {:timeout, non_neg_integer() | :infinity | nil} | {:max_output_bytes, pos_integer()} | {:input, binary()}

  @spec run(String.t(), [String.t()], [option()]) :: {:ok, result()} | {:error, Error.t()}
  def run(command, args, opts \\ []) do
    owner = self()

    {worker, monitor} =
      spawn_monitor(fn ->
        owner_ref = Process.monitor(owner)
        result = run_owned(command, args, opts, owner_ref)
        send(owner, {self(), result})
      end)

    receive do
      {^worker, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, _reason} ->
        invalid("Command worker terminated")
    end
  end

  defp run_owned(command, args, opts, owner_ref) do
    with :ok <- validate(command, args, opts),
         {:ok, executable} <- executable(command),
         {:ok, directory} <- temporary_directory() do
      try do
        execute(executable, args, opts, Path.join(directory, "stderr"), owner_ref)
      after
        File.rm_rf(directory)
      end
    end
  end

  defp validate(command, args, opts) do
    cond do
      not valid_command?(command, args) ->
        invalid("Command and arguments must be strings without NUL bytes")

      not valid_options?(opts) ->
        invalid("Command options must be a keyword list")

      not is_binary(Keyword.get(opts, :input, "")) ->
        invalid("Command input must be binary data")

      not valid_timeout?(Keyword.get(opts, :timeout)) ->
        invalid("Timeout must be a non-negative integer, :infinity, or nil")

      not valid_limit?(Keyword.get(opts, :max_output_bytes, @default_limit)) ->
        invalid("max_output_bytes must be a positive integer")

      true ->
        :ok
    end
  end

  defp valid_command?(command, args), do: valid_string?(command) and is_list(args) and Enum.all?(args, &valid_string?/1)

  defp valid_options?(opts),
    do: is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- [:timeout, :max_output_bytes, :input] == []

  defp valid_limit?(value), do: is_integer(value) and value > 0

  defp valid_string?(value), do: is_binary(value) and not String.contains?(value, <<0>>)
  defp valid_timeout?(value), do: value in [nil, :infinity] or (is_integer(value) and value >= 0)

  defp executable(command) do
    case System.find_executable(command) do
      nil -> {:error, Error.execution_error("Unable to execute #{command}", reason: :enoent, command: command)}
      path -> {:ok, path}
    end
  end

  defp temporary_directory do
    root = Application.get_env(:ex_macos_control, :temporary_directory, System.tmp_dir!())
    path = Path.join(root, "exmc-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false))

    with :ok <- File.mkdir_p(root),
         :ok <- File.mkdir(path),
         :ok <- File.chmod(path, 0o700) do
      {:ok, path}
    else
      {:error, reason} -> {:error, Error.execution_error("Unable to create command workspace", reason: reason)}
    end
  end

  defp execute(executable, args, opts, stderr_path, owner_ref) do
    helper = :ex_macos_control |> :code.priv_dir() |> to_string() |> Path.join("command_runner.sh")
    input_path = Path.join(Path.dirname(stderr_path), "stdin")
    File.write!(input_path, Keyword.get(opts, :input, ""))

    port =
      Port.open({:spawn_executable, "/bin/bash"}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        {:args, [helper, stderr_path, input_path, executable | args]}
      ])

    timeout = Keyword.get(opts, :timeout)
    deadline = if timeout in [nil, :infinity], do: :infinity, else: now_ms() + timeout

    state = %{
      port: port,
      owner_ref: owner_ref,
      stderr: stderr_path,
      deadline: deadline,
      limit: Keyword.get(opts, :max_output_bytes, @default_limit)
    }

    try do
      collect(state, [], 0, timeout)
    after
      terminate(port)
    end
  rescue
    error in [ArgumentError, ErlangError] ->
      {:error, Error.execution_error("Unable to start command", reason: inspect(error.__struct__))}
  end

  defp collect(state, chunks, size, timeout) do
    cond do
      size + file_size(state.stderr) > state.limit ->
        invalid("Command output exceeded max_output_bytes")

      state.deadline != :infinity and now_ms() >= state.deadline ->
        {:error, Error.timeout("Script execution", timeout: timeout, outcome: :unknown)}

      true ->
        receive_output(state, chunks, size, timeout)
    end
  end

  defp receive_output(%{port: port, owner_ref: owner_ref} = state, chunks, size, timeout) do
    receive do
      {:DOWN, ^owner_ref, :process, _pid, _reason} ->
        invalid("Command caller exited")

      {^port, {:data, data}} ->
        collect(state, [data | chunks], size + byte_size(data), timeout)

      {^port, {:exit_status, status}} ->
        if size + file_size(state.stderr) <= state.limit do
          stderr = read_stderr(state.stderr)
          {:ok, %{stdout: chunks |> Enum.reverse() |> IO.iodata_to_binary(), stderr: stderr, exit_status: status}}
        else
          invalid("Command output exceeded max_output_bytes")
        end
    after
      10 -> collect(state, chunks, size, timeout)
    end
  end

  defp terminate(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("/bin/kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
        await_exit(port, pid)

      nil ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp await_exit(port, pid) do
    receive do
      {^port, {:exit_status, _}} -> :ok
      {^port, {:data, _}} -> await_exit(port, pid)
    after
      200 ->
        System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
        if Port.info(port), do: Port.close(port)
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      _ -> 0
    end
  end

  defp read_stderr(path) do
    case File.read(path) do
      {:ok, data} -> data
      _ -> ""
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp invalid(message), do: {:error, Error.execution_error(message)}
end
