defmodule ExMacOSControl.BatchEffectsTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Calendar, Composition, Contacts, Error, Mail, Messages, Music, Photos}
  setup :verify_on_exit!

  for family <- [:contacts, :calendar, :music, :photos, :attachments, :messages] do
    test "#{family} retains uncertain mutation intent and acknowledged parent identity" do
      root = Path.expand("tmp/batch-effects-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, store} = Agent.start_link(fn -> 0 end)
      setup_source(unquote(family))

      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
        Agent.update(store, &(&1 + 1))
        {:error, Error.execution_error("write committed before failure")}
      end)

      assert {:error, error} =
               Composition.run(fn -> run_case(unquote(family), root) end, journal: Path.join(root, "journal"))

      assert error.details.outcome == :unknown
      assert error.details.recovery_status == :needs_reconciliation
      assert Agent.get(store, & &1) == 1

      assert {:ok, %{status: :needs_reconciliation, pending: [_]} = journal} =
               Composition.Journal.inspect_run(error.details.journal_path)

      if unquote(family) in [:contacts, :calendar, :music, :photos],
        do: assert(Enum.any?(journal.resources, &(&1["id"] == "parent")))
    end
  end

  defp setup_source(:messages), do: :ok

  defp setup_source(:attachments) do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{attachments: [%{index: 1, name: "fixture.txt"}]})
    end)
  end

  defp setup_source(_family), do: expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("parent") end)

  defp run_case(:contacts, _root),
    do: Contacts.create_with_details([first_name: "Fixture"], emails: [{"self@example.invalid", "work"}])

  defp run_case(:calendar, _root),
    do:
      Calendar.create_event_with_alarms(
        "calendar",
        [title: "Fixture", start_at: "2026-11-01T12:00:00Z", end_at: "2026-11-01T13:00:00Z"],
        [{:display, [trigger_minutes: -10]}]
      )

  defp run_case(:music, _root), do: Music.create_playlist_with_tracks("Fixture", ["track"])

  defp run_case(:photos, root) do
    path = Path.join(root, "input.png")
    File.write!(path, "fixture")
    Photos.import_into_new_album([path], "Fixture")
  end

  defp run_case(:attachments, root), do: Mail.save_attachments("account", "Fixture", 1, root)
  defp run_case(:messages, _root), do: Messages.send_to_chats(["explicit-chat", "must-not-run"], "Fixture")
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
