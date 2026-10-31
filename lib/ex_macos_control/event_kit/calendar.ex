defmodule ExMacOSControl.EventKit.Calendar do
  @moduledoc """
  Optional EventKit calendars and events with absolute timestamps. Supply a
  DateTime or ISO8601 string including an offset; naive wall times are rejected.
  time_zone is an explicit IANA zone (default Etc/UTC). EventKit references
  include the calendar and occurrence identity and cannot use Apple-event IDs.
  Reads require a bounded range. Writes are independently read back and never replayed.
  """
  alias ExMacOSControl.{Automation, Composition, Error, EventKit}
  alias ExMacOSControl.EventKit.Reference
  @options [:helper, :timeout, :max_output_bytes, :journal, :trace_to, :run_id]
  @fields [:title, :body, :location, :url, :start_at, :end_at, :all_day, :time_zone]

  def list_calendars(opts \\ []) do
    with {:ok, raw} <- EventKit.request("calendars", %{entity: "event"}, opts), do: EventKit.records(raw)
  end

  def create_calendar(name, source_id, opts \\ []) do
    with :ok <- Automation.required_string(name, "Calendar name"),
         :ok <- Automation.required_string(source_id, "Source ID"),
         :ok <- options(opts) do
      Composition.run(fn -> create_container(name, source_id, opts) end, EventKit.execution(opts))
    end
  end

  defp create_container(name, source_id, opts) do
    Composition.effect(
      :create_eventkit_calendar,
      fn ->
        with {:ok, raw} <- request("create_calendar", %{entity: "event", name: name, source_id: source_id}, opts),
             do: decode(raw, :calendar)
      end,
      resource: :eventkit_calendar,
      identity: %{account_id: source_id}
    )
  end

  def delete_calendar(ref, opts \\ []) do
    with :ok <- Reference.validate(ref, :calendar), :ok <- options(opts) do
      Composition.run(fn -> delete_container(ref, opts) end, EventKit.execution(opts))
    end
  end

  defp delete_container(ref, opts) do
    with :ok <-
           Composition.effect(
             :delete_eventkit_calendar,
             fn -> delete_native("delete_calendar", %{entity: "event", ref: Reference.wire(ref)}, opts) end,
             resource: :eventkit_calendar,
             identity: %{id: ref.id}
           ),
         do: Composition.verify(:eventkit_calendar_absent, &container_absent?(ref, opts, &1))
  end

  defp container_absent?(ref, opts, remaining) do
    with {:ok, rows} <- list_calendars(Keyword.put(helper(opts), :timeout, remaining)),
         do: Enum.all?(rows, &(&1.id != ref.id))
  end

  def list_events(calendar, from, to, opts \\ []) do
    with :ok <- Reference.validate(calendar, :calendar),
         :ok <- options(opts),
         {:ok, from} <- absolute(from),
         {:ok, to} <- absolute(to),
         :ok <- interval(from, to),
         {:ok, raw} <- EventKit.request("events", %{calendar: Reference.wire(calendar), from: from, to: to}, opts),
         do: EventKit.records(raw)
  end

  def get_event(ref, opts \\ []) do
    with :ok <- event_ref(ref),
         {:ok, raw} <- EventKit.request("get_event", %{ref: Reference.wire(ref)}, opts),
         do: decode(raw, :event)
  end

  def create_event(calendar, attrs, opts \\ []) do
    with :ok <- Reference.validate(calendar, :calendar), :ok <- options(opts), {:ok, attrs} <- attributes(attrs) do
      Composition.run(
        fn -> write_event("create_event", %{calendar: Reference.wire(calendar)}, attrs, calendar.id, opts) end,
        EventKit.execution(opts)
      )
    end
  end

  def update_event(ref, attrs, opts \\ []) do
    with :ok <- event_ref(ref), :ok <- options(opts), :ok <- Automation.options(attrs, @fields) do
      Composition.run(fn -> update_workflow(ref, attrs, opts) end, EventKit.execution(opts))
    end
  end

  defp update_workflow(ref, attrs, opts) do
    with {:ok, current} <- get_event(ref, helper(opts)),
         {:ok, merged} <- attributes(Keyword.merge(Map.to_list(Map.take(current, @fields)), attrs)),
         do: write_event("update_event", %{ref: Reference.wire(ref)}, merged, ref.calendar_id, opts)
  end

  defp write_event(operation, args, attrs, calendar_id, opts) do
    with {:ok, item} <-
           Composition.effect(
             :save_eventkit_event,
             fn -> save_native(operation, Map.put(args, :attributes, attrs), calendar_id, opts) end,
             resource: :eventkit_event,
             identity: %{calendar_id: calendar_id}
           ),
         :ok <- Composition.verify(:eventkit_event_fields, &matches?(item.ref, attrs, opts, &1)),
         do: {:ok, item}
  end

  defp save_native(operation, args, calendar_id, opts) do
    with {:ok, raw} <- request(operation, args, opts), {:ok, item} <- decode(raw, :event) do
      if item.ref.calendar_id == calendar_id, do: {:ok, item}, else: bad_ack()
    end
  end

  def delete_event(ref, opts \\ []) do
    with :ok <- event_ref(ref), :ok <- options(opts) do
      Composition.run(fn -> delete_workflow(ref, opts) end, EventKit.execution(opts))
    end
  end

  defp delete_workflow(ref, opts) do
    with :ok <-
           Composition.effect(
             :delete_eventkit_event,
             fn -> delete_native("delete_event", %{ref: Reference.wire(ref)}, opts) end,
             resource: :eventkit_event,
             identity: %{id: ref.id, calendar_id: ref.calendar_id}
           ),
         do: Composition.verify(:eventkit_event_absent, &absent?(ref, opts, &1))
  end

  defp absent?(ref, opts, remaining) do
    case get_event(ref, Keyword.put(helper(opts), :timeout, remaining)) do
      {:error, %Error{type: :not_found}} -> true
      {:ok, _} -> false
      error -> error
    end
  end

  defp matches?(ref, attrs, opts, remaining) do
    with {:ok, row} <- get_event(ref, Keyword.put(helper(opts), :timeout, remaining)),
         do: Enum.all?(attrs, fn {key, value} -> equivalent?(key, row[key], value) end)
  end

  defp equivalent?(key, actual, expected) when key in [:start_at, :end_at] do
    with {:ok, left} <- absolute(actual), {:ok, right} <- absolute(expected), do: left == right
  end

  defp equivalent?(_key, actual, expected), do: actual == expected

  defp attributes(attrs) do
    with :ok <- Automation.options(attrs, @fields),
         :ok <- Automation.required_string(attrs[:title], "Event title"),
         {:ok, start_at} <- absolute(attrs[:start_at]),
         {:ok, end_at} <- absolute(attrs[:end_at]),
         :ok <- interval(start_at, end_at) do
      result = Map.merge(%{body: "", location: "", url: "", all_day: false, time_zone: "Etc/UTC"}, Map.new(attrs))

      if Enum.all?([:body, :location, :url, :time_zone], &is_binary(result[&1])) and is_boolean(result.all_day),
        do: {:ok, Map.merge(result, %{start_at: start_at, end_at: end_at})},
        else: EventKit.invalid("Invalid event fields")
    end
  end

  @doc false
  def absolute(%DateTime{} = value), do: canonical(value)

  def absolute(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, value, _} -> canonical(value)
      _ -> EventKit.invalid("Expected an absolute ISO8601 timestamp with offset")
    end
  end

  def absolute(_), do: EventKit.invalid("Expected a DateTime or absolute ISO8601 timestamp with offset")

  defp canonical(value),
    do: {:ok, value |> DateTime.to_unix(:millisecond) |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()}

  defp interval(from, to) do
    {:ok, start, _} = DateTime.from_iso8601(from)
    {:ok, finish, _} = DateTime.from_iso8601(to)
    seconds = DateTime.diff(finish, start, :millisecond)

    if seconds > 0 and seconds <= 366 * 86_400_000,
      do: :ok,
      else: EventKit.invalid("Interval must be positive and at most 366 days")
  end

  defp event_ref(ref) do
    with :ok <- Reference.validate(ref, :event),
         {:ok, _} <- absolute(ref.start_at),
         {:ok, _} <- absolute(ref.occurrence_at),
         do: :ok
  end

  defp decode(raw, kind) do
    with {:ok, row} <- EventKit.record(raw) do
      if row.ref.kind == kind, do: {:ok, row}, else: bad_ack()
    end
  end

  defp delete_native(operation, args, opts) do
    case request(operation, args, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
      _ -> bad_ack()
    end
  end

  defp bad_ack, do: {:error, Error.execution_error("Unexpected EventKit event acknowledgement", outcome: :unknown)}
  defp request(operation, args, opts), do: EventKit.request(operation, args, helper(opts))
  defp helper(opts), do: Keyword.take(opts, [:helper])
  defp options(opts), do: Automation.options(opts, @options)
end
