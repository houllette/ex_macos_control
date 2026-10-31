defmodule ExMacOSControl.EventKit.Reminders do
  @moduledoc """
  Optional EventKit lists and verified reminder batches. References are local
  EventKit identities, separate from Apple-event reminder URLs. Batches preserve
  acknowledged IDs and never replay uncertain writes. Supported fields are
  title, body and priority; completion is independently read back.
  """
  alias ExMacOSControl.{Automation, Composition, EventKit, Validation}
  alias ExMacOSControl.EventKit.Reference
  @options [:helper, :timeout, :max_output_bytes, :journal, :trace_to, :run_id]

  def list_lists(opts \\ []) do
    with {:ok, raw} <- EventKit.request("calendars", %{entity: "reminder"}, opts), do: EventKit.records(raw)
  end

  def create_list(name, source_id, opts \\ []) do
    with :ok <- Automation.required_string(name, "List name"),
         :ok <- Automation.required_string(source_id, "Source ID"),
         :ok <- Automation.options(opts, @options) do
      Composition.run(fn -> create_list_workflow(name, source_id, opts) end, EventKit.execution(opts))
    end
  end

  defp create_list_workflow(name, source_id, opts) do
    Composition.effect(:create_eventkit_list, fn -> create_list_native(name, source_id, opts) end,
      resource: :eventkit_list,
      identity: %{account_id: source_id}
    )
  end

  defp create_list_native(name, source_id, opts) do
    with {:ok, raw} <-
           EventKit.request("create_calendar", %{entity: "reminder", name: name, source_id: source_id}, helper(opts)),
         do: EventKit.record(raw)
  end

  def delete_list(ref, opts \\ []) do
    with :ok <- Reference.validate(ref, :reminder_list), :ok <- Automation.options(opts, @options) do
      Composition.run(fn -> delete_list_workflow(ref, opts) end, EventKit.execution(opts))
    end
  end

  defp delete_list_workflow(ref, opts) do
    with :ok <-
           Composition.effect(:delete_eventkit_list, fn -> delete_list_native(ref, opts) end,
             resource: :eventkit_list,
             identity: %{id: ref.id}
           ),
         do: Composition.verify(:eventkit_list_absent, &list_absent?(ref, opts, &1))
  end

  defp delete_list_native(ref, opts) do
    case EventKit.request("delete_calendar", %{entity: "reminder", ref: Reference.wire(ref)}, helper(opts)) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
      _ -> {:error, ExMacOSControl.Error.execution_error("Invalid delete acknowledgement", outcome: :unknown)}
    end
  end

  defp list_absent?(ref, opts, remaining) do
    with {:ok, lists} <- list_lists(Keyword.put(helper(opts), :timeout, remaining)),
         do: Enum.all?(lists, &(&1.id != ref.id))
  end

  def list_reminders(list, opts \\ []) do
    with :ok <- Reference.validate(list, :reminder_list),
         {:ok, raw} <- EventKit.request("reminders", %{list: Reference.wire(list)}, opts),
         do: EventKit.records(raw)
  end

  def get_reminder(ref, opts \\ []) do
    with :ok <- Reference.validate(ref, :reminder),
         {:ok, raw} <- EventKit.request("get_reminder", %{ref: Reference.wire(ref)}, opts),
         do: EventKit.record(raw)
  end

  def create_reminder(list, attrs, opts \\ []) do
    with {:ok, [item]} <- create_many(list, [attrs], opts), do: {:ok, item}
  end

  def create_many(list, items, opts \\ []) do
    with :ok <- Reference.validate(list, :reminder_list),
         :ok <- Validation.items(items),
         :ok <- Validation.all(items, &validate_attrs/1),
         :ok <- batch_options(opts) do
      Composition.run(fn -> create_chunks(list, items, opts) end, EventKit.execution(opts))
    end
  end

  def complete_many(refs, opts \\ []) do
    with :ok <- Validation.items(refs),
         :ok <- Validation.all(refs, &Reference.validate(&1, :reminder)),
         true <- length(Enum.uniq_by(refs, & &1.id)) == length(refs),
         :ok <- batch_options(opts) do
      Composition.run(fn -> complete_chunks(refs, opts) end, EventKit.execution(opts))
    else
      false -> EventKit.invalid("Reminder references must be distinct")
      error -> error
    end
  end

  defp create_chunks(list, items, opts) do
    flatten(
      Composition.map(
        Enum.chunk_every(items, opts[:batch_size] || 100),
        :create_eventkit_chunk,
        &create_chunk(list, &1, opts)
      )
    )
  end

  defp complete_chunks(refs, opts) do
    flatten(
      Composition.map(
        reference_chunks(refs, opts[:batch_size] || 100),
        :complete_eventkit_chunk,
        &complete_chunk(&1, opts)
      )
    )
  end

  defp flatten({:ok, chunks}), do: {:ok, List.flatten(chunks)}
  defp flatten(error), do: error

  defp create_chunk(list, attrs, opts) do
    arguments = %{list: Reference.wire(list), items: Enum.map(attrs, &Map.new/1)}

    with {:ok, items} <-
           EventKit.effect_records(
             :create_eventkit_reminders,
             "create_reminders",
             arguments,
             :eventkit_reminder,
             %{calendar_id: list.id},
             opts
           ),
         :ok <- valid_created(items, attrs, list),
         :ok <- Composition.verify(:created_eventkit_reminders, &created?(items, attrs, opts, &1)),
         do: {:ok, items}
  end

  defp complete_chunk(refs, opts) do
    with {:ok, items} <-
           EventKit.effect_records(
             :complete_eventkit_reminders,
             "complete_reminders",
             %{refs: Enum.map(refs, &Reference.wire/1)},
             :eventkit_reminder,
             %{ids: Enum.map(refs, & &1.id), calendar_id: hd(refs).calendar_id},
             opts
           ),
         true <- Enum.map(items, & &1.id) == Enum.map(refs, & &1.id),
         :ok <- Composition.verify(:completed_eventkit_reminders, &completed?(refs, opts, &1)) do
      {:ok, items}
    else
      false -> {:error, ExMacOSControl.Error.execution_error("Unexpected completion identities", outcome: :unknown)}
      error -> error
    end
  end

  defp valid_created(items, attrs, list) do
    if length(items) == length(attrs) and length(Enum.uniq_by(items, & &1.id)) == length(items) and
         Enum.all?(items, &(&1.ref.kind == :reminder and &1.ref.calendar_id == list.id)),
       do: :ok,
       else: {:error, ExMacOSControl.Error.execution_error("Unexpected created reminder identities", outcome: :unknown)}
  end

  defp created?(items, attrs, opts, remaining) do
    with {:ok, actual} <- read_many(Enum.map(items, & &1.ref), opts, remaining) do
      Enum.map(actual, & &1.id) == Enum.map(items, & &1.id) and
        Enum.zip(actual, attrs)
        |> Enum.all?(fn {row, expected} ->
          row.title == expected[:title] and row.body == Keyword.get(expected, :body, "") and
            row.priority == Keyword.get(expected, :priority, 0)
        end)
    end
  end

  defp completed?(refs, opts, remaining) do
    with {:ok, actual} <- read_many(refs, opts, remaining),
         do: Enum.map(actual, & &1.id) == Enum.map(refs, & &1.id) and Enum.all?(actual, & &1.completed)
  end

  defp read_many(refs, opts, remaining) do
    with {:ok, raw} <-
           EventKit.request(
             "get_reminders",
             %{refs: Enum.map(refs, &Reference.wire/1)},
             Keyword.put(helper(opts), :timeout, remaining)
           ),
         do: EventKit.records(raw)
  end

  defp validate_attrs(attrs) do
    with :ok <- Automation.options(attrs, [:title, :body, :priority]),
         :ok <- Automation.required_string(attrs[:title], "Reminder title") do
      if is_binary(Keyword.get(attrs, :body, "")) and Keyword.get(attrs, :priority, 0) in 0..9,
        do: :ok,
        else: EventKit.invalid("Invalid reminder body or priority")
    end
  end

  defp batch_options(opts) do
    with :ok <- Automation.options(opts, @options ++ [:batch_size]) do
      if Keyword.get(opts, :batch_size, 100) in 1..1000,
        do: :ok,
        else: EventKit.invalid("batch_size must be 1 through 1000")
    end
  end

  defp helper(opts), do: Keyword.take(opts, [:helper])

  defp reference_chunks(refs, size),
    do: refs |> Enum.chunk_by(& &1.calendar_id) |> Enum.flat_map(&Enum.chunk_every(&1, size))
end
