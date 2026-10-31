defmodule ExMacOSControl.EventKitLiveTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{CompositionLiveSession, EventKit, LiveEvidence, Wait}
  alias ExMacOSControl.EventKit.Reminders
  @moduletag :personal
  @moduletag eventkit: true
  @moduletag timeout: 180_000
  @moduletag apps: ["com.apple.reminders"]
  enabled =
    System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1" and
      is_binary(System.get_env("EXMC_EVENTKIT_HELPER"))

  unless enabled, do: @moduletag(skip: "Requires personal opt-in and EXMC_EVENTKIT_HELPER")

  test "EventKit creates and completes 1, 10 and 100 reminders with independent app readback", context do
    live = CompositionLiveSession.start(context)
    opts = [helper: System.fetch_env!("EXMC_EVENTKIT_HELPER"), timeout: 60_000]
    assert {:ok, %{"reminder" => "full_access"}} = EventKit.status(opts)
    assert {:ok, sources} = EventKit.sources(:reminder, opts)
    source = Enum.find(sources, & &1["default"])
    assert source
    intent = LiveEvidence.intent(live, :eventkit_list, %{account_id: source["id"]})

    assert {:ok, list} =
             CompositionLiveSession.effect(live, :create_eventkit_fixture, fn ->
               Reminders.create_list(live.marker, source["id"], opts)
             end)

    CompositionLiveSession.own(live, :eventkit_list, list.id, fn -> Reminders.delete_list(list.ref, opts) end,
      intent_id: intent,
      verify: fn -> with {:ok, rows} <- Reminders.list_lists(opts), do: Enum.all?(rows, &(&1.id != list.id)) end
    )

    assert :ok =
             Wait.until(fn ->
               with {:ok, rows} <- ExMacOSControl.Reminders.list_lists(limit: 1000),
                    do: Enum.any?(rows, &(&1.name == live.marker))
             end)

    assert {:ok, native_lists} = ExMacOSControl.Reminders.list_lists(limit: 1000)
    native = Enum.find(native_lists, &(&1.name == live.marker))
    assert {:ok, sentinel} = Reminders.create_reminder(list.ref, [title: live.marker <> "-untouched"], opts)

    Enum.reduce([1, 10, 100], 0, fn count, previous ->
      assert {:ok, created} =
               CompositionLiveSession.effect(
                 live,
                 :create_eventkit_batch,
                 fn ->
                   Reminders.create_many(list.ref, Enum.map(1..count, &[title: "#{live.marker}-#{count}-#{&1}"]), opts)
                 end,
                 timeout: 60_000
               )

      refs = Enum.map(created, & &1.ref)

      assert {:ok, completed} =
               CompositionLiveSession.effect(
                 live,
                 :complete_eventkit_batch,
                 fn -> Reminders.complete_many(refs, opts) end,
                 timeout: 60_000
               )

      assert Enum.all?(completed, & &1.completed)
      assert {:ok, %{completed: false}} = Reminders.get_reminder(sentinel.ref, opts)
      total = previous + count

      assert :ok =
               Wait.until(
                 fn ->
                   with {:ok, rows} <- ExMacOSControl.Reminders.list_reminders(native.id, limit: 1000),
                        do: length(rows) == total + 1 and Enum.count(rows, & &1.completed) == total
                 end,
                 timeout: 15_000
               )

      total
    end)

    CompositionLiveSession.event(live, "verified", %{batch_sizes: [1, 10, 100]})
  end
end
