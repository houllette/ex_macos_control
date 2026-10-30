defmodule ExMacOSControl.Composition.Trace do
  @moduledoc false
  alias ExMacOSControl.Composition
  alias ExMacOSControl.Composition.{Context, Journal}

  def id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  def emit(context, event, attributes \\ %{}) do
    record = Map.merge(attributes, %{event: event, run_id: context.run_id, at: DateTime.to_iso8601(DateTime.utc_now())})

    with :ok <- Journal.append(context.journal, record) do
      if context.trace_to, do: send(context.trace_to, {:ex_macos_control, record})
      :telemetry.execute([:ex_macos_control, :composition, event], %{}, record)
      :ok
    end
  end

  def run(_context, fun, false), do: fun.()

  def run(context, fun, true) do
    started = System.monotonic_time()

    try do
      with :ok <- emit(context, :run_started) do
        result = fun.()

        case emit(context, :run_finished, %{outcome: outcome(result), duration: System.monotonic_time() - started}) do
          :ok -> result
          error -> error
        end
      end
    catch
      kind, reason ->
        emit(context, :run_finished, %{outcome: :unknown, exception_kind: kind})
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      Journal.close(context.journal)
    end
  end

  def step(nil, _name, fun, _kind, _resource), do: Composition.guard(fun)

  def step(context, name, fun, kind, resource) do
    span = id()
    metadata = %{step_id: span, parent_step_id: context.span_id, step: label(name), kind: kind}

    with :ok <- emit(context, :step_started, metadata) do
      invoke(context, name, fun, kind, resource, metadata)
    end
  end

  defp invoke(context, name, fun, kind, resource, metadata) do
    started = System.monotonic_time()

    try do
      result = Context.in_span(metadata.step_id, fn -> Composition.guard(fun) end)
      outcome = if kind == :verification and result == :ok, do: :confirmed, else: outcome(result)

      ending =
        Map.merge(metadata, %{
          outcome: outcome,
          duration: System.monotonic_time() - started,
          resources: if(kind == :effect, do: resources(name, result, resource), else: [])
        })

      case emit(context, :step_finished, ending) do
        :ok -> result
        {:error, error} -> {:error, %{error | details: Map.put(error.details, :acknowledged_result, result)}}
      end
    catch
      kind, reason ->
        emit(context, :step_finished, Map.merge(metadata, %{outcome: :unknown, exception_kind: kind}))
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  def outcome({:error, %{details: %{outcome: :not_started}}}), do: :not_started
  def outcome({:error, %{details: %{outcome: :unknown}}}), do: :unknown
  def outcome({:error, _}), do: :failed
  def outcome(_), do: :acknowledged

  defp label(value) when is_atom(value), do: Atom.to_string(value)
  defp label(value) when is_integer(value), do: value
  defp label(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&label/1)
  defp label(_), do: "[redacted]"

  defp resources(_name, {:ok, value}, type)
       when is_atom(type) and not is_nil(type) and (is_binary(value) or is_integer(value)),
       do: [%{type: type, id: value}]

  defp resources({name, _index}, result, nil), do: resources(name, result, nil)

  defp resources(:open_page, {:ok, %{window_id: id, tab_index: index}}, nil),
    do: [%{type: :safari_page, window_id: id, tab_index: index}]

  defp resources(name, {:ok, value}, nil)
       when name in [
              :create_note,
              :create_event,
              :create_draft,
              :create_reminder,
              :create_contact,
              :create_album,
              :create_playlist
            ] and (is_binary(value) or is_integer(value)),
       do: [%{type: name, id: value}]

  defp resources(_name, _result, _resource), do: []
end
