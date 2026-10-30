defmodule ExMacOSControl.Composition do
  @moduledoc """
  Shared deadlines and recoverable errors for ordinary Elixir compositions.

  `run/2` gives all steps one monotonic time budget (30 seconds by default).
  Nested runs cannot extend an enclosing deadline. Callbacks execute in the
  caller process; arbitrary Elixir code is cooperative, not forcibly cancelled.
  Child processes do not inherit the scope.

  `step/2` never retries. Errors retain their original type and outcome, and add
  `details.composition` with the failed step and acknowledged completed results.
  These results can contain private application data. Effects are not rolled back.
  `Retry.with_retry/2` requires explicit idempotence to retry composition timeouts.

  Scoped resources receive a separate, bounded five-second cleanup budget, even
  after work times out. Cleanup failures are reported with the resource identity.
  Exceptions and throws from callbacks are re-raised after cleanup.
  """
  alias ExMacOSControl.{Automation, Error}

  @key {__MODULE__, :context}
  @execution [:timeout, :max_output_bytes]

  @doc "Runs a composition with a finite shared deadline and restores the enclosing scope."
  def run(fun, opts \\ []) when is_function(fun, 0) do
    with :ok <- Automation.options(opts, @execution),
         effective = ExMacOSControl.execution_options(opts),
         timeout = Keyword.get(effective, :timeout, 30_000),
         true <- is_integer(timeout) and timeout >= 0 do
      previous = Process.get(@key)
      deadline = System.monotonic_time(:millisecond) + timeout
      deadline = if previous, do: min(deadline, previous.deadline), else: deadline
      Process.put(@key, %{deadline: deadline, completed: []})

      try do
        ExMacOSControl.with_options(Keyword.take(effective, @execution), fun)
      after
        restore(previous)
      end
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Compositions require a finite non-negative timeout")
    end
  end

  @doc "Executes one named step, stopping before dispatch if the shared budget is exhausted."
  def step(name, fun) when is_function(fun, 0) do
    result = guard(fun)

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
  def validate_items(items) do
    if is_list(items) and items != [] and length(items) <= 1000,
      do: :ok,
      else: Automation.invalid("Items must be a non-empty list of at most 1000 entries")
  end

  @doc false
  def validate_all(items, validator) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validator.(item) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  def html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
    |> String.replace("\n", "<br>")
  end

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

    {:error, %{error | details: details}}
  end

  defp cleanup(fun) do
    previous = Process.get(@key)
    Process.delete(@key)

    try do
      run(fn -> step(:cleanup, fun) end, timeout: 5000)
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
