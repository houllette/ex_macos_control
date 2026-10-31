defmodule ExMacOSControl.Composition do
  @moduledoc """
  Shared deadlines and recoverable errors for ordinary Elixir compositions.

  `run/2` gives all steps one monotonic time budget (30 seconds by default).
  Nested runs cannot extend an enclosing deadline. Callbacks execute in the
  caller process; arbitrary Elixir code is cooperative, not forcibly cancelled.
  Child processes require capture_context/0 and with_context/2; join them before
  the originating run returns when sharing a journal.

  Options include trace_to (PID), journal (private directory), and run_id (32 hex
  characters). Trace messages are {:ex_macos_control, event}. Events contain step
  names, timing, outcomes and declared resource IDs, never arbitrary results.
  Journaling failures prevent dispatch; inspect incomplete runs with
  ExMacOSControl.Composition.Journal.inspect_run/1. :acknowledged means a command
  returned successfully; verify/3 records :confirmed after observing state.

  `step/2` never retries. Errors retain their original type and add
  `details.composition` with the failed step and acknowledged completed results.
  These results can contain private application data. Dispatched effect errors
  report outcome :unknown unless explicitly :not_started. Errors include run_id
  and journal_path when available. Effects are not rolled back.
  `Retry.with_retry/2` requires explicit idempotence to retry composition timeouts.

  Scoped resources receive a separate, bounded five-second cleanup budget, even
  after work times out. Cleanup failures are reported with the resource identity.
  Exceptions and throws from callbacks are re-raised after cleanup.
  """
  alias ExMacOSControl.{Automation, Error, Wait}
  alias ExMacOSControl.Composition.{Context, Journal, Trace}

  @key {__MODULE__, :context}
  @execution [:timeout, :max_output_bytes]

  @doc "Runs a composition with a finite shared deadline and restores the enclosing scope."
  def run(fun, opts \\ []) when is_function(fun, 0) do
    with :ok <- Automation.options(opts, @execution ++ [:trace_to, :journal, :run_id]),
         :ok <- trace_options(opts),
         effective = ExMacOSControl.execution_options(Keyword.take(opts, @execution)),
         timeout = Keyword.get(effective, :timeout, 30_000),
         true <- is_integer(timeout) and timeout >= 0 do
      run_scoped(fun, timeout, effective, opts)
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Compositions require a finite non-negative timeout")
    end
  end

  defp run_scoped(fun, timeout, effective, opts) do
    previous = Process.get(@key)
    run_id = if previous, do: previous.run_id, else: Keyword.get(opts, :run_id, Trace.id())

    with {:ok, journal} <- open_journal(previous, opts, run_id) do
      deadline = System.monotonic_time(:millisecond) + timeout

      context = %Context{
        deadline: if(previous, do: min(deadline, previous.deadline), else: deadline),
        run_id: run_id,
        journal: journal,
        trace_to: Keyword.get(opts, :trace_to, previous && previous.trace_to),
        span_id: previous && previous.span_id,
        progress: if(previous, do: previous.progress, else: :atomics.new(2, [])),
        execution: Keyword.take(effective, @execution)
      }

      Process.put(@key, context)

      try do
        Trace.run(
          context,
          fn -> ExMacOSControl.with_options(Keyword.take(effective, @execution), fun) end,
          is_nil(previous)
        )
      after
        restore(previous)
      end
    end
  end

  defp open_journal(nil, opts, run_id), do: Journal.open(opts[:journal], run_id)

  defp open_journal(previous, opts, _run_id) do
    if Keyword.has_key?(opts, :journal) or Keyword.has_key?(opts, :run_id),
      do: Automation.invalid("Nested runs inherit the enclosing journal and run ID"),
      else: {:ok, previous.journal}
  end

  defp trace_options(opts) do
    cond do
      not is_nil(opts[:trace_to]) and not is_pid(opts[:trace_to]) ->
        Automation.invalid("trace_to must be a PID")

      not is_nil(opts[:journal]) and not is_binary(opts[:journal]) ->
        Automation.invalid("journal must be a directory path")

      not is_nil(opts[:run_id]) and not (is_binary(opts[:run_id]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, opts[:run_id])) ->
        Automation.invalid("run_id must contain 32 lowercase hexadecimal characters")

      true ->
        :ok
    end
  end

  @doc "Executes one named step, stopping before dispatch if the shared budget is exhausted."
  def step(name, fun) when is_function(fun, 0) do
    result = Trace.step(Context.current(), name, fun, :operation, nil)
    normalize_step(result, name)
  end

  defp normalize_step(result, name) do
    case result do
      {:error, reason} ->
        annotate(reason, name)

      :ok ->
        remember(name, :ok)
        :ok

      {:ok, value} ->
        remember(name, value)
        {:ok, value}

      _ ->
        annotate(Error.execution_error("Composition steps must return :ok or a tagged result"), name)
    end
  end

  @doc "Executes a named step using a function capture and its argument list."
  def step(name, fun, args) when is_function(fun) and is_list(args), do: step(name, fn -> apply(fun, args) end)

  @doc "Records an effect and optional resource type without retrying its callback."
  def effect(name, fun, opts \\ [])

  def effect(name, fun, opts) when is_function(fun, 0) do
    with :ok <- effect_options(opts) do
      resource = if opts == [], do: nil, else: %{type: opts[:resource], identity: Keyword.get(opts, :identity, %{})}
      Trace.step(Context.current(), name, fun, :effect, resource) |> normalize_step(name)
    end
  end

  def effect(name, fun, args) when is_function(fun) and is_list(args),
    do: effect(name, fn -> apply(fun, args) end)

  @doc """
  Maps mutations sequentially with durable effect intents. Options are resource
  (an atom) and identity (a map or item-to-map function). Identity fields are
  explicitly persisted native IDs/paths; do not include content. All identity
  maps are validated before the first callback. Results are never replayed.
  """
  def map_effects(items, name, fun, opts \\ []) when is_list(items) and is_function(fun, 1) do
    with :ok <- Automation.options(opts, [:resource, :identity]),
         prepared = Enum.map(items, fn item -> {item, identity_options(item, opts)} end),
         :ok <- ExMacOSControl.Validation.all(prepared, fn {_, options} -> effect_options(options) end) do
      if Context.current(),
        do: do_map_effects(prepared, name, fun),
        else: run(&do_map_effects/3, [prepared, name, fun], [])
    end
  end

  defp identity_options(item, opts) do
    case opts[:identity] do
      identity when is_function(identity, 1) -> Keyword.put(opts, :identity, identity.(item))
      _ -> opts
    end
  end

  defp do_map_effects(items, name, fun) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, &reduce_effect(&1, &2, name, fun))
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp reduce_effect({{item, opts}, index}, {:ok, results}, name, fun) do
    case effect({name, index}, fn -> fun.(item) end, opts) do
      :ok -> {:cont, {:ok, [:ok | results]}}
      {:ok, value} -> {:cont, {:ok, [value | results]}}
      error -> {:halt, error}
    end
  end

  defp effect_options(opts) do
    with :ok <- Automation.options(opts, [:resource, :identity]),
         true <- is_nil(opts[:resource]) or is_atom(opts[:resource]),
         true <- valid_identity?(Keyword.get(opts, :identity, %{})) do
      :ok
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Effect resource and native identity are invalid")
    end
  end

  defp valid_identity?(identity) when is_map(identity) do
    map_size(identity) <= 10 and
      Enum.all?(identity, &valid_identity_field?/1)
  end

  defp valid_identity?(_), do: false

  defp valid_identity_field?({:ids, values}) when is_list(values),
    do: length(values) in 1..1000 and Enum.all?(values, &identity_value?/1)

  defp valid_identity_field?({key, value}) do
    key in [
      :id,
      :outgoing_id,
      :application_pid,
      :parent_id,
      :account_id,
      :calendar_id,
      :list_id,
      :window_id,
      :tab_index,
      :path,
      :source_path,
      :index
    ] and
      identity_value?(value)
  end

  defp identity_value?(value), do: is_integer(value) or (is_binary(value) and byte_size(value) <= 4096)

  @doc "Polls observable state and records a confirmed outcome only after the predicate succeeds."
  def verify(name, predicate, opts \\ []) do
    with :ok <- Automation.options(opts, [:timeout, :interval]) do
      run(&verify_state/3, [name, predicate, opts], Keyword.take(opts, [:timeout]))
    end
  end

  defp verify_state(name, predicate, opts) do
    Trace.step(Context.current(), name, fn -> Wait.until(predicate, opts) end, :verification, nil)
    |> normalize_step(name)
  end

  @doc "Captures deadline and tracing context for explicit propagation to a joined Task."
  def capture_context do
    case Context.current() do
      nil -> nil
      context -> %{context | completed: []}
    end
  end

  @doc "Runs under captured context, without inheriting foreground locks or extending deadlines."
  def with_context(%Context{} = context, fun) when is_function(fun, 0) do
    previous = Context.current()
    deadline = if previous, do: min(context.deadline, previous.deadline), else: context.deadline
    Process.put(@key, %{context | deadline: deadline, completed: []})

    try do
      ExMacOSControl.with_options(context.execution, fn -> guard(fun) end)
    after
      restore(previous)
    end
  end

  @doc false
  def run(fun, args, opts) when is_function(fun) and is_list(args), do: run(fn -> apply(fun, args) end, opts)

  @doc "Maps sequentially, stopping at the first error and retaining completed item results."
  def map(items, name, fun) when is_list(items) and is_function(fun, 1) do
    if Process.get(@key), do: do_map(items, name, fun), else: run(&do_map/3, [items, name, fun], [])
  end

  defp do_map(items, name, fun) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, &reduce_item(&1, &2, name, fun))
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp reduce_item({item, index}, {:ok, results}, name, fun) do
    case step({name, index}, fun, [item]) do
      :ok -> {:cont, {:ok, [:ok | results]}}
      {:ok, value} -> {:cont, {:ok, [value | results]}}
      error -> {:halt, error}
    end
  end

  @doc false
  def guard(fun) do
    case remaining() do
      0 -> {:error, Error.timeout("Composition deadline exhausted before dispatch", outcome: :not_started)}
      _ -> fun.()
    end
  end

  @doc false
  def cap_options(opts) do
    case remaining() do
      :infinity -> opts
      remaining -> Keyword.update(opts, :timeout, remaining, &cap_timeout(&1, remaining))
    end
  end

  @doc "Returns remaining milliseconds, or :infinity outside a composition."
  def remaining do
    case Process.get(@key) do
      nil -> :infinity
      context -> max(context.deadline - System.monotonic_time(:millisecond), 0)
    end
  end

  @doc false
  def resource(resource, fun, cleanup) do
    outcome =
      try do
        {:returned, step(:use_resource, fn -> fun.(resource) end)}
      catch
        kind, reason -> {:raised, kind, reason, __STACKTRACE__}
      end

    cleaned = cleanup(fn -> cleanup.(resource) end)
    finish_resource(outcome, cleaned, resource)
  end

  @doc false
  defdelegate validate_items(items), to: ExMacOSControl.Validation, as: :items
  @doc false
  defdelegate validate_all(items, validator), to: ExMacOSControl.Validation, as: :all
  @doc false
  defdelegate html(text), to: ExMacOSControl.HTML, as: :escape

  defp cap_timeout(value, remaining) when is_integer(value), do: min(value, remaining)
  defp cap_timeout(value, remaining) when value in [nil, :infinity], do: remaining
  defp cap_timeout(value, _remaining), do: value

  defp remember(name, value) do
    if context = Process.get(@key) do
      Process.put(@key, %{context | completed: [%{step: name, result: value} | context.completed]})
    end

    :ok
  end

  defp annotate(reason, name) do
    error =
      if match?(%Error{}, reason), do: reason, else: Error.execution_error("Composition step failed", reason: reason)

    context = Process.get(@key, %{completed: []})
    failure = %{step: name, completed: Enum.reverse(context.completed)}

    details =
      Map.update(error.details || %{}, :composition, failure, fn cause -> Map.put(failure, :cause, cause) end)

    details =
      case Context.current() do
        nil -> details
        current -> Map.merge(details, %{run_id: current.run_id, journal_path: current.journal && current.journal.path})
      end

    {:error, %{error | details: details}}
  end

  defp cleanup(fun) do
    previous = Process.get(@key)

    if previous do
      Process.put(@key, %{previous | deadline: System.monotonic_time(:millisecond) + 5000, completed: []})
    end

    try do
      ExMacOSControl.with_options([timeout: 5000], fn -> step(:cleanup, fun) end)
    catch
      kind, _reason -> {:error, Error.execution_error("Resource cleanup raised", kind: kind)}
    after
      restore(previous)
    end
  end

  defp finish_resource({:raised, kind, reason, stack}, _cleaned, _resource),
    do: :erlang.raise(kind, reason, stack)

  defp finish_resource({:returned, result}, :ok, _resource), do: result

  defp finish_resource(outcome, {:ok, _}, resource), do: finish_resource(outcome, :ok, resource)

  defp finish_resource({:returned, {:error, %Error{} = error}}, {:error, cleanup_error}, resource),
    do:
      {:error, %{error | details: Map.merge(error.details || %{}, %{cleanup_error: cleanup_error, resource: resource})}}

  defp finish_resource({:returned, result}, {:error, %Error{} = error}, resource),
    do: {:error, %{error | details: Map.merge(error.details || %{}, %{resource: resource, result: result})}}

  defp restore(nil), do: Process.delete(@key)
  defp restore(previous), do: Process.put(@key, previous)
end
