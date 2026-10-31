defmodule ExMacOSControl.Wait do
  @moduledoc "Polls observable state against a monotonic deadline. A one-argument predicate receives the remaining milliseconds."
  alias ExMacOSControl.{Automation, Error}

  def until(predicate, opts \\ []) when is_function(predicate) do
    with :ok <- Automation.options(opts, [:timeout, :interval]),
         effective = ExMacOSControl.execution_options(Keyword.take(opts, [:timeout])),
         timeout = Keyword.get(effective, :timeout, 5000),
         interval = Keyword.get(opts, :interval, 50),
         true <- is_integer(timeout) and timeout >= 0 and is_integer(interval) and interval > 0 do
      poll(predicate, System.monotonic_time(:millisecond) + timeout, interval)
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Wait needs a non-negative timeout and a positive interval")
    end
  end

  defp poll(predicate, deadline, interval) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 or ExMacOSControl.Composition.remaining() == 0 do
      {:error, Error.timeout("Waiting for state", outcome: :not_started)}
    else
      evaluate(predicate, deadline, interval, remaining)
    end
  end

  defp evaluate(predicate, deadline, interval, remaining) do
    result = if is_function(predicate, 1), do: predicate.(remaining), else: predicate.()

    case result do
      true -> :ok
      {:ok, true} -> :ok
      {:error, _} = error -> error
      value when value in [false, {:ok, false}] -> retry(predicate, deadline, interval)
      _ -> Automation.invalid("Wait predicate must return a boolean or a tagged boolean")
    end
  end

  defp retry(predicate, deadline, interval) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, Error.timeout("Waiting for state")}
    else
      Process.sleep(min(interval, remaining))
      poll(predicate, deadline, interval)
    end
  end
end
