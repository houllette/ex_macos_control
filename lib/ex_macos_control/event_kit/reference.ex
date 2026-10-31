defmodule ExMacOSControl.EventKit.Reference do
  @moduledoc "An EventKit identity scoped to its entity and calendar. Apple-event IDs are not interchangeable with these references."
  alias ExMacOSControl.Error
  @enforce_keys [:kind, :id]
  defstruct [:kind, :id, :calendar_id, :external_id, :occurrence_at, :start_at, backend: :eventkit]
  @kinds [:calendar, :reminder_list, :event, :reminder]
  @fields [:id, :calendar_id, :external_id, :occurrence_at, :start_at]

  def validate(%__MODULE__{backend: :eventkit, kind: kind, id: id} = ref, expected) do
    if kind in @kinds and (expected == :any or kind == expected) and string?(id) and
         (kind in [:calendar, :reminder_list] or string?(ref.calendar_id)) and
         Enum.all?([ref.external_id, ref.occurrence_at, ref.start_at], &(is_nil(&1) or string?(&1))),
       do: :ok,
       else: invalid()
  end

  def validate(_, _), do: invalid()

  def decode(%{"backend" => "eventkit", "kind" => kind, "id" => _} = data) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == kind)) do
      nil ->
        invalid()

      atom ->
        ref = struct!(__MODULE__, Enum.map(@fields, &{&1, data[Atom.to_string(&1)]}) ++ [kind: atom])
        with :ok <- validate(ref, :any), do: {:ok, ref}
    end
  end

  def decode(_), do: invalid()

  def wire(%__MODULE__{} = ref) do
    ref
    |> Map.from_struct()
    |> Map.put(:backend, "eventkit")
    |> Map.update!(:kind, &Atom.to_string/1)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp string?(value), do: is_binary(value) and byte_size(value) in 1..4096 and not String.contains?(value, <<0>>)

  defp invalid,
    do: {:error, Error.execution_error("Expected a matching, scoped EventKit reference", outcome: :not_started)}
end
