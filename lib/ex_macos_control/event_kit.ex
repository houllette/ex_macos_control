defmodule ExMacOSControl.EventKit do
  @moduledoc """
  Optional native Calendar/Reminders transport. Install the helper explicitly with
  install/2, then pass helper: app_path or configure :eventkit_helper. No native
  compiler or permission request is used by ordinary Apple-event APIs.

  status/1 never prompts. authorize/2 explicitly requests full access for one
  entity. Operations never switch backends or replay a failed mutation.
  """
  alias ExMacOSControl.{Automation, Command, Composition, Error}
  alias ExMacOSControl.EventKit.{Installer, Reference}
  @execution [:timeout, :max_output_bytes, :journal, :trace_to, :run_id]
  @operations ~w(status authorize sources calendars create_calendar delete_calendar create_reminders reminders get_reminder get_reminders complete_reminders)
  @types %{
    "execution_error" => :execution_error,
    "permission_denied" => :permission_denied,
    "not_found" => :not_found,
    "timeout" => :timeout
  }
  @fields ~w(title body completed priority name source_id writable start_at end_at all_day time_zone recurrence detached)a

  defdelegate install(destination, opts \\ []), to: Installer
  def status(opts \\ []), do: request("status", %{}, opts)

  def authorize(entity, opts \\ [])

  def authorize(entity, opts) when entity in [:event, :reminder],
    do: request("authorize", %{entity: Atom.to_string(entity)}, opts)

  def authorize(_, _), do: invalid("Entity must be :event or :reminder")

  def sources(entity, opts \\ [])

  def sources(entity, opts) when entity in [:event, :reminder],
    do: request("sources", %{entity: Atom.to_string(entity)}, opts)

  def sources(_, _), do: invalid("Entity must be :event or :reminder")

  @doc false
  def execution(opts), do: Keyword.take(opts, @execution)

  @doc false
  def request(operation, arguments, opts) do
    with :ok <- Automation.options(opts, @execution ++ [:helper]) do
      Composition.run(fn -> request_native(operation, arguments, opts) end, execution(opts))
    end
  end

  defp request_native(operation, arguments, opts) do
    with :ok <- Automation.options(opts, @execution ++ [:helper]),
         true <- operation in @operations,
         {:ok, helper} <- executable(opts),
         id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
         {:ok, input} <- Jason.encode(%{version: 1, request_id: id, operation: operation, arguments: arguments}),
         true <- byte_size(input) <= 1_048_576 do
      call(helper, id, input, opts)
    else
      {:error, %Error{}} = error -> error
      _ -> invalid("Invalid EventKit request or input exceeds 1 MiB")
    end
  end

  defp executable(opts) do
    path = opts[:helper] || Application.get_env(:ex_macos_control, :eventkit_helper)

    path =
      if is_binary(path) and String.ends_with?(path, ".app"),
        do: Path.join(path, "Contents/MacOS/EventKitBridge"),
        else: path

    resolved = if is_binary(path), do: System.find_executable(Path.expand(path))

    if resolved,
      do: {:ok, resolved},
      else: {:error, Error.not_found("Install and explicitly configure the EventKit helper", outcome: :not_started)}
  end

  defp call(helper, id, input, opts) do
    execution = opts |> Keyword.take([:timeout, :max_output_bytes]) |> ExMacOSControl.execution_options()
    execution = execution |> Keyword.put_new(:timeout, 30_000) |> Keyword.put(:input, input)

    case Command.run(helper, [], execution) do
      {:ok, %{exit_status: 0, stdout: stdout}} ->
        decode(stdout, id)

      {:ok, %{exit_status: status}} ->
        {:error, Error.execution_error("EventKit helper exited", exit_status: status, outcome: :unknown)}

      error ->
        error
    end
  end

  defp decode(stdout, id) do
    case Jason.decode(stdout) do
      {:ok, %{"version" => 1, "request_id" => ^id, "ok" => true, "result" => result}} -> {:ok, result}
      {:ok, %{"version" => 1, "request_id" => ^id, "ok" => false, "error" => error}} -> native_error(error)
      _ -> {:error, Error.execution_error("Invalid EventKit acknowledgement", outcome: :unknown)}
    end
  end

  defp native_error(%{"type" => type, "message" => message, "outcome" => outcome} = error)
       when is_binary(message) and outcome in ["unknown", "not_started"] do
    details =
      error
      |> Map.take(["code", "domain"])
      |> Map.put(:outcome, if(outcome == "unknown", do: :unknown, else: :not_started))

    {:error, %Error{type: Map.get(@types, type, :execution_error), message: message, details: details}}
  end

  defp native_error(_), do: {:error, Error.execution_error("Invalid EventKit error acknowledgement", outcome: :unknown)}

  @doc false
  def record(%{"ref" => wire} = row) do
    case Reference.decode(wire) do
      {:ok, ref} ->
        fields =
          for key <- @fields, Map.has_key?(row, Atom.to_string(key)), into: %{}, do: {key, row[Atom.to_string(key)]}

        if valid_record?(ref.kind, fields), do: {:ok, Map.merge(fields, %{ref: ref, id: ref.id})}, else: bad_ack()

      _ ->
        {:error, Error.execution_error("Invalid EventKit resource acknowledgement", outcome: :unknown)}
    end
  end

  def record(_), do: {:error, Error.execution_error("Invalid EventKit resource acknowledgement", outcome: :unknown)}

  defp valid_record?(:reminder, fields),
    do:
      is_binary(fields[:title]) and is_binary(fields[:body]) and is_boolean(fields[:completed]) and
        fields[:priority] in 0..9

  defp valid_record?(kind, fields) when kind in [:calendar, :reminder_list], do: is_binary(fields[:name])

  defp valid_record?(:event, fields),
    do: is_binary(fields[:title]) and is_binary(fields[:start_at]) and is_binary(fields[:end_at])

  defp bad_ack, do: {:error, Error.execution_error("Invalid EventKit resource acknowledgement", outcome: :unknown)}

  @doc false
  def records(rows) when is_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case record(row) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  def records(_), do: {:error, Error.execution_error("Invalid EventKit resource list", outcome: :unknown)}

  @doc false
  def effect_records(name, operation, arguments, type, identity, opts) do
    key = make_ref()

    try do
      with {:ok, _} <-
             Composition.effect(
               name,
               fn ->
                 with {:ok, raw} <- request(operation, arguments, Keyword.take(opts, [:helper])),
                      {:ok, values} <- records(raw),
                      :ok <- match_records(values, arguments, identity) do
                   Process.put(key, values)
                   {:ok, Enum.map(values, & &1.id)}
                 end
               end,
               resource: type,
               identity: identity
             ),
           do: {:ok, Process.get(key)}
    after
      Process.delete(key)
    end
  end

  @doc false
  def invalid(message), do: {:error, Error.execution_error(message, outcome: :not_started)}

  defp expected_ids?(_ids, nil), do: true
  defp expected_ids?(ids, expected), do: ids == expected
  defp expected_calendar?(_values, nil), do: true
  defp expected_calendar?(values, expected), do: Enum.all?(values, &(&1.ref.calendar_id == expected))

  defp match_records(values, arguments, identity) do
    expected = arguments[:items] || arguments[:refs] || []
    ids = Enum.map(values, & &1.id)

    valid =
      length(values) == length(expected) and length(Enum.uniq(ids)) == length(ids) and
        Enum.all?(values, &(&1.ref.kind == :reminder)) and expected_ids?(ids, identity[:ids]) and
        expected_calendar?(values, identity[:calendar_id])

    if valid, do: :ok, else: bad_ack()
  end
end
