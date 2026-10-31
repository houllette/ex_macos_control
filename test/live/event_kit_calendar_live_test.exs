defmodule ExMacOSControl.EventKitCalendarLiveTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{CompositionLiveSession, EventKit, LiveEvidence, Wait}
  alias ExMacOSControl.EventKit.Calendar
  @moduletag :personal
  @moduletag eventkit_calendar: true
  @moduletag timeout: 180_000
  @moduletag apps: ["com.apple.iCal"]
  enabled =
    System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1" and
      is_binary(System.get_env("EXMC_EVENTKIT_HELPER"))

  unless enabled, do: @moduletag(skip: "Requires personal opt-in and EXMC_EVENTKIT_HELPER")

  test "absolute Calendar instants survive DST repetition and verified updates", context do
    live = CompositionLiveSession.start(context)
    opts = [helper: System.fetch_env!("EXMC_EVENTKIT_HELPER"), timeout: 60_000]
    assert {:ok, %{"event" => "full_access"}} = EventKit.status(opts)
    assert {:ok, sources} = EventKit.sources(:event, opts)
    source = Enum.find(sources, & &1["default"])
    assert source
    intent = LiveEvidence.intent(live, :eventkit_calendar, %{account_id: source["id"]})

    assert {:ok, calendar} =
             CompositionLiveSession.effect(live, :create_calendar, fn ->
               Calendar.create_calendar(live.marker, source["id"], opts)
             end)

    CompositionLiveSession.own(
      live,
      :eventkit_calendar,
      calendar.id,
      fn -> Calendar.delete_calendar(calendar.ref, opts) end,
      intent_id: intent,
      verify: fn -> with {:ok, rows} <- Calendar.list_calendars(opts), do: Enum.all?(rows, &(&1.id != calendar.id)) end
    )

    assert :ok =
             Wait.until(fn ->
               with {:ok, rows} <- ExMacOSControl.Calendar.list_calendars(limit: 1000),
                    do: Enum.any?(rows, &(&1.name == live.marker))
             end)

    assert {:ok, native_calendars} = ExMacOSControl.Calendar.list_calendars(limit: 1000)
    native = Enum.find(native_calendars, &(&1.name == live.marker))
    first_attrs = attrs(live.marker <> "-sdk-first", "-06:00")
    second_attrs = attrs(live.marker <> "-sdk-second", "-07:00")
    assert {:ok, first} = Calendar.create_event(calendar.ref, first_attrs, opts)
    assert {:ok, second} = Calendar.create_event(calendar.ref, second_attrs, opts)
    assert first.start_at == "2026-11-01T07:30:00.000Z"
    assert second.start_at == "2026-11-01T08:30:00.000Z"
    assert {:ok, events} = Calendar.list_events(calendar.ref, "2026-11-01T00:00:00Z", "2026-11-02T00:00:00Z", opts)
    assert Enum.map(events, & &1.start_at) == [first.start_at, second.start_at]

    assert {:ok, [only_second]} =
             Calendar.list_events(calendar.ref, "2026-11-01T08:15:00Z", "2026-11-01T08:50:00Z", opts)

    assert only_second.ref == second.ref
    assert {:ok, script_reads} = ExMacOSControl.Calendar.list_events(native.id, limit: 1000)
    legacy_fields = fn title, offset -> attrs(title, offset) |> Keyword.delete(:time_zone) end

    assert {:ok, _} =
             ExMacOSControl.Calendar.create_event(native.id, legacy_fields.(live.marker <> "-legacy-first", "-06:00"))

    assert {:ok, _} =
             ExMacOSControl.Calendar.create_event(native.id, legacy_fields.(live.marker <> "-legacy-second", "-07:00"))

    assert {:ok, comparison} = Calendar.list_events(calendar.ref, "2026-11-01T00:00:00Z", "2026-11-02T00:00:00Z", opts)
    sdk_instants = comparison |> Enum.filter(&String.contains?(&1.title, "-sdk-")) |> Enum.map(& &1.start_at)
    legacy_instants = comparison |> Enum.filter(&String.contains?(&1.title, "-legacy-")) |> Enum.map(& &1.start_at)

    CompositionLiveSession.event(live, "dst_comparison", %{
      sdk_instants: sdk_instants,
      legacy_instants: legacy_instants,
      scripted_sdk_instants: Enum.map(script_reads, & &1.start_at)
    })

    assert {:ok, moved} =
             Calendar.update_event(
               first.ref,
               [start_at: "2026-11-01T09:30:00Z", end_at: "2026-11-01T10:00:00Z", body: "verified update"],
               opts
             )

    assert moved.start_at == "2026-11-01T09:30:00.000Z"
    assert moved.time_zone == "America/Denver" and moved.body == "verified update"
    assert :ok = Calendar.delete_event(moved.ref, opts)
    assert {:ok, _} = Calendar.get_event(second.ref, opts)

    CompositionLiveSession.event(live, "verified", %{
      absolute_instants: true,
      explicit_zone: true,
      update: true,
      delete: true
    })
  end

  defp attrs(title, offset),
    do: [
      title: title,
      start_at: "2026-11-01T01:30:00" <> offset,
      end_at: "2026-11-01T01:45:00" <> offset,
      time_zone: "America/Denver"
    ]
end
