defmodule ExMacOSControl.Validation do
  @moduledoc false
  alias ExMacOSControl.Error

  def items(items) do
    if is_list(items) and items != [] and length(items) <= 1000,
      do: :ok,
      else: {:error, Error.execution_error("Items must be a non-empty list of at most 1000 entries")}
  end

  def all(items, validator) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validator.(item) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
