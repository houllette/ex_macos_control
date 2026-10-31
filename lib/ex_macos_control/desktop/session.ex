defmodule ExMacOSControl.Desktop.Session do
  @moduledoc """
  Scopes application support windows around a callback. Only windows captured
  immediately after this scope starts an app (or establishes Calendar/Reminders
  UI readiness) are owned. Existing windows and document applications are kept.
  No app is quit. Cleanup runs after success, errors and exceptions, with its own
  bounded budget. keep_windows: true explicitly retains acquired support windows.
  """
  alias ExMacOSControl.{Automation, Composition, Desktop, Error, Validation}
  alias ExMacOSControl.Desktop.Session.Native
  @options [:timeout, :max_output_bytes, :journal, :trace_to, :run_id, :keep_windows]

  @callback snapshot([String.t()]) :: {:ok, map()} | {:error, Error.t()}
  @callback prepare(String.t(), map()) :: {:ok, [map()]} | {:error, Error.t()}
  @callback close(map()) :: :ok | {:error, Error.t()}
  @callback restore(map()) :: :ok | {:error, Error.t()}

  def with_apps(identities, fun, opts \\ []) when is_function(fun, 0) do
    with :ok <- Automation.options(opts, @options),
         :ok <- validate_apps(identities),
         true <- is_boolean(Keyword.get(opts, :keep_windows, false)) do
      run_scope(identities, fun, opts)
    else
      false -> Automation.invalid("keep_windows must be a boolean")
      error -> error
    end
  end

  defp run_scope([], fun, opts), do: Composition.run(fun, Keyword.delete(opts, :keep_windows))

  defp run_scope(identities, fun, opts),
    do: Desktop.with_lock(fn -> scope(identities, fun, opts) end, Keyword.delete(opts, :keep_windows))

  defp scope(identities, fun, opts) do
    backend = Application.get_env(:ex_macos_control, :desktop_session_backend) || Native

    with {:ok, before} <- backend.snapshot(Enum.uniq(identities)) do
      key = make_ref()
      Process.put(key, [])

      try do
        Composition.resource(
          before,
          fn _ -> acquire(backend, identities, before, key, fun) end,
          fn _ -> finish(backend, before, Process.get(key), opts) end,
          trace_usage: false
        )
      after
        Process.delete(key)
      end
    end
  end

  defp acquire(backend, identities, before, key, fun) do
    with :ok <- Validation.all(Enum.uniq(identities), &prepare_one(backend, &1, before, key)), do: fun.()
  end

  defp prepare_one(backend, identity, before, key) do
    with {:ok, windows} <- backend.prepare(identity, before) do
      Process.put(key, Enum.reverse(windows) ++ Process.get(key))
      :ok
    end
  end

  defp finish(backend, before, windows, opts) do
    # Try every cleanup, even when a preceding window fails ownership validation.
    results = if opts[:keep_windows], do: [], else: Enum.map(windows, &safe_cleanup(fn -> backend.close(&1) end))
    restored = safe_cleanup(fn -> backend.restore(before) end)
    failures = Enum.reject(results ++ [restored], &(&1 == :ok))

    if failures == [],
      do: :ok,
      else:
        {:error,
         Error.execution_error("Application UI cleanup needs attention", cleanup_errors: failures, windows: windows)}
  end

  defp safe_cleanup(fun) do
    fun.()
  catch
    kind, _reason -> {:error, Error.execution_error("UI cleanup raised", kind: kind)}
  end

  defp validate_apps([]), do: :ok

  defp validate_apps(identities) do
    with :ok <- Validation.items(identities),
         do: Validation.all(identities, &Automation.required_string(&1, "Application bundle ID"))
  end
end
