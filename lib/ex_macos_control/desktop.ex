defmodule ExMacOSControl.Desktop do
  @moduledoc """
  Cooperative host-wide serialization for focus-sensitive desktop work.

  `with_lock/2` uses a loopback socket on port 41051 shared by participating
  library callers, including other BEAM instances. It is reentrant in the same
  process and released on exceptions or process exit. It cannot prevent a human
  or unrelated application from changing focus. Waiting consumes the deadline.
  """
  alias ExMacOSControl.{Composition, Error}
  @key {__MODULE__, :locked}

  def with_lock(fun, opts \\ []) when is_function(fun, 0) do
    Composition.run(fn -> lock(fun) end, opts)
  end

  defp lock(fun) do
    cond do
      Process.get(@key, false) -> fun.()
      Composition.remaining() == 0 -> {:error, Error.timeout("Waiting for desktop lock", outcome: :not_started)}
      true -> acquire(fun)
    end
  end

  defp acquire(fun) do
    case :gen_tcp.listen(41_051, [:binary, active: false, ip: {127, 0, 0, 1}]) do
      {:ok, socket} ->
        Process.put(@key, true)

        try do
          fun.()
        after
          Process.delete(@key)
          :gen_tcp.close(socket)
        end

      {:error, :eaddrinuse} ->
        Process.sleep(min(25, Composition.remaining()))
        lock(fun)

      {:error, reason} ->
        {:error, Error.execution_error("Unable to acquire desktop lock", reason: reason)}
    end
  end
end
