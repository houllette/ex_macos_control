defmodule ExMacOSControl.EventKitCalendarTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.Composition.Journal
  alias ExMacOSControl.EventKit.{Calendar, Reference}

  setup do
    root = Path.expand("tmp/eventkit-calendar-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    helper = Path.join(root, "helper")
    File.cp!("test/support/fixtures/eventkit_helper.py", helper)
    File.chmod!(helper, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      opts: [helper: helper, journal: Path.join(root, "journal")],
      calendar: %Reference{kind: :calendar, id: "calendar"}
    }
  end

  test "repeated wall times retain distinct absolute instants and explicit zone", %{opts: opts, calendar: calendar} do
    assert {:ok, first} = Calendar.create_event(calendar, attrs("-06:00"), opts)
    assert {:ok, second} = Calendar.create_event(calendar, attrs("-07:00"), opts)
    assert first.start_at == "2026-11-01T07:30:00.000Z"
    assert second.start_at == "2026-11-01T08:30:00.000Z"
    assert first.time_zone == "America/Denver"
    assert {:ok, rows} = Calendar.list_events(calendar, "2026-11-01T00:00:00Z", "2026-11-02T00:00:00Z", opts)
    assert length(rows) == 2
    assert {:ok, [^second]} = Calendar.list_events(calendar, "2026-11-01T08:15:00Z", "2026-11-01T08:50:00Z", opts)

    assert {:ok, updated} =
             Calendar.update_event(
               first.ref,
               [title: "updated", start_at: "2026-11-01T09:30:00Z", end_at: "2026-11-01T10:00:00Z"],
               opts
             )

    assert updated.title == "updated" and updated.time_zone == "America/Denver"
    assert {:error, %{type: :not_found}} = Calendar.get_event(first.ref, opts)
    assert :ok = Calendar.delete_event(updated.ref, opts)
    assert {:ok, ^second} = Calendar.get_event(second.ref, opts)
  end

  test "naive timestamps, unbounded reads and other backend identities dispatch nothing", %{
    opts: opts,
    root: root,
    calendar: calendar
  } do
    assert {:error, _} =
             Calendar.create_event(calendar, Keyword.put(attrs("-06:00"), :start_at, ~N[2026-11-01 01:30:00]), opts)

    assert {:error, _} = Calendar.list_events(calendar, "2026-01-01T00:00:00Z", "2028-01-01T00:00:00Z", opts)
    assert {:error, _} = Calendar.get_event("apple-event-id", opts)
    refute File.exists?(Path.join(root, "state.json"))
  end

  test "lost reply after persistence is journaled and never replayed", %{root: root, opts: opts, calendar: calendar} do
    File.write!(Path.join(root, "mode"), "lost_reply")
    assert {:error, error} = Calendar.create_event(calendar, attrs("-06:00"), opts)
    assert error.details.recovery_status == :needs_reconciliation
    assert Jason.decode!(File.read!(Path.join(root, "state.json")))["mutations"] == 1
    assert {:ok, %{pending: [_ | _]}} = Journal.inspect_run(error.details.journal_path)
  end

  test "a response from the wrong calendar remains uncertain", %{root: root, opts: opts, calendar: calendar} do
    File.write!(Path.join(root, "mode"), "wrong_event_calendar")
    assert {:error, error} = Calendar.create_event(calendar, attrs("-06:00"), opts)
    assert error.details.recovery_status == :needs_reconciliation
    assert {:ok, %{pending: [_ | _]}} = Journal.inspect_run(error.details.journal_path)
  end

  test "recurrence is bounded and edits require an explicit supported scope", %{
    opts: opts,
    root: root,
    calendar: calendar
  } do
    assert {:error, _} = Calendar.create_event(calendar, attrs("-06:00") ++ [recurrence: [frequency: :daily]], opts)
    refute File.exists?(Path.join(root, "state.json"))

    assert {:ok, event} =
             Calendar.create_event(calendar, attrs("-06:00") ++ [recurrence: [frequency: :daily, count: 3]], opts)

    assert event.recurrence
    assert {:error, %{details: %{outcome: :not_started}}} = Calendar.delete_event(event.ref, opts)
    assert {:error, _} = Calendar.update_event(event.ref, [title: "no implicit span"], opts)
    assert {:error, _} = Calendar.delete_event(event.ref, Keyword.put(opts, :scope, :series))
    assert Jason.decode!(File.read!(Path.join(root, "state.json")))["mutations"] == 1
    assert :ok = Calendar.delete_event(event.ref, Keyword.put(opts, :scope, :occurrence))
  end

  defp attrs(offset),
    do: [
      title: "DST",
      start_at: "2026-11-01T01:30:00" <> offset,
      end_at: "2026-11-01T01:45:00" <> offset,
      time_zone: "America/Denver"
    ]
end
