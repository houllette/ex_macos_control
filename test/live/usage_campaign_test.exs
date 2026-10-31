defmodule ExMacOSControl.UsageCampaignTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{
    Calendar,
    Capture,
    Composition,
    Contacts,
    Finder,
    ImageEvents,
    Mail,
    Notes,
    Reminders,
    Safari,
    UsageUtilities
  }

  alias ExMacOSControl.CompositionLiveSession, as: Live
  alias ExMacOSControl.LiveEvidence, as: Evidence
  @moduletag :personal
  @moduletag timeout: 600_000
  enabled = System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1"
  unless enabled, do: @moduletag(skip: "Requires personal qualification opt-in")

  setup context do
    {:ok, live: Live.start(context)}
  end

  @tag utility: true
  @tag apps: ["com.apple.Safari", "com.apple.Notes", "com.apple.reminders", "com.apple.mail"]
  test "research utility reuses a capture across destinations after closing its source", %{live: live} do
    folder = folder(live)
    list = list(live)

    Enum.each(1..repeats(), fn index ->
      Live.event(live, "iteration_started", %{iteration: index})
      html = Path.join(live.root, "page-#{index}.html")
      body = "#{live.marker}-#{index} 雪 <escaped>"

      File.write!(
        html,
        "<html><head><meta charset='UTF-8'><title></title></head><body>#{String.replace(body, "<escaped>", "&lt;escaped&gt;")}</body></html>"
      )

      url = "file://" <> URI.encode(html)
      assert {:ok, capture} = Safari.with_page(url, fn page -> Capture.page(page) end)
      intents = Map.new([:note, :reminder, :draft], &{&1, Evidence.intent(live, &1)})

      assert {:ok, result} =
               Live.effect(live, :research_utility, fn ->
                 UsageUtilities.research(capture, folder, list, to: recipient(), subject: "#{live.marker}-#{index}")
               end)

      own_note(live, result.note, folder, intents.note)
      own_reminder(live, result.reminder, list, intents.reminder)
      own_draft(live, result.draft, intents.draft)
      assert {:ok, note} = Notes.get_note(result.note)
      assert note.plaintext =~ body and note.plaintext =~ url
      assert {:ok, reminder} = Reminders.get_reminder(result.reminder, list_id: list)
      assert reminder.title == url and reminder.body =~ url
      assert {:ok, saved} = Mail.get_draft(result.draft)
      assert saved.content =~ url
      Live.event(live, "iteration_verified", %{iteration: index})
    end)

    Live.event(live, "verified", %{repeats: repeats()})
  end

  @tag utility: true
  @tag apps: ["com.apple.finder", "com.apple.imageevents", "com.apple.mail"]
  test "file preparation copies and transforms owned images before drafting their outputs", %{live: live} do
    source = Path.join(live.root, "source.png")
    png = png()
    File.write!(source, png)

    Enum.each(1..repeats(), fn index ->
      Live.event(live, "iteration_started", %{iteration: index})
      staging = Path.join(live.root, "staging-#{index}")
      output = Path.join(live.root, "output-#{index}")
      File.mkdir!(staging)
      File.mkdir!(output)
      intent = Evidence.intent(live, :draft)

      assert {:ok, result} =
               Live.effect(live, :file_preparation, fn ->
                 UsageUtilities.prepare_files([source], staging, output,
                   to: recipient(),
                   subject: "#{live.marker}-#{index}",
                   body: live.marker
                 )
               end)

      own_draft(live, result.draft, intent)
      assert Enum.map(result.copies, &File.read!/1) == [png]
      assert File.read!(source) == png
      assert [transformed] = result.outputs
      assert {:ok, %{dimensions: [16, 16]}} = ImageEvents.info(transformed)
      assert {:ok, %{attachments: [attachment]}} = Mail.get_draft(result.draft)
      assert attachment.size == File.stat!(transformed).size
      saved_path = Path.join(live.root, "saved-attachment-#{index}.png")
      refute File.exists?(saved_path)

      assert {:ok, true} =
               Live.effect(live, :save_owned_draft_attachment, fn ->
                 Live.query(
                   "com.apple.mail",
                   """
                   var o=app.draftsMailbox().messages.byId(input.id);
                   if(o.subject()!==input.subject || (input.message_id && o.messageId()!==input.message_id))throw new Error('Draft identity changed');
                   var attachments=o.mailAttachments();if(attachments.length!==1)throw new Error('Attachment count changed');
                   app.save(attachments[0],{in:Path(input.path)});return true;
                   """,
                   %{
                     id: result.draft.id,
                     subject: result.draft.subject,
                     message_id: result.draft.message_id,
                     path: saved_path
                   }
                 )
               end)

      assert File.read!(saved_path) == File.read!(transformed)
      Live.event(live, "iteration_verified", %{iteration: index})
    end)

    Live.event(live, "verified", %{repeats: repeats()})
  end

  @tag utility: true
  @tag apps: ["com.apple.reminders", "com.apple.iCal"]
  test "scheduling utility verifies UTC-equivalent offset dates before source completion", %{live: live} do
    list = list(live)
    calendar = calendar(live)

    Enum.each(1..repeats(), fn index ->
      Live.event(live, "iteration_started", %{iteration: index})

      assert {:ok, reminder} =
               Live.create(
                 live,
                 :reminder,
                 fn -> Reminders.create_reminder(list, title: "#{live.marker}-#{index}", body: live.marker) end,
                 &Reminders.delete_reminder(&1, list_id: list),
                 &reminder_absent(list, &1)
               )

      intent = Evidence.intent(live, :event, %{calendar_id: calendar})
      attrs = [start_at: "2026-11-01T00:30:00-06:00", end_at: "2026-11-01T02:30:00-07:00"]

      assert {:ok, %{event_id: event}} =
               Live.effect(live, :scheduling, fn ->
                 UsageUtilities.schedule(reminder, calendar, attrs, list_id: list)
               end)

      own_event(live, event, calendar, intent)
      assert {:ok, value} = Calendar.get_event(calendar, event)
      assert {:ok, actual, _} = DateTime.from_iso8601(value.start_at)
      assert DateTime.compare(actual, ~U[2026-11-01 06:30:00Z]) == :eq
      assert {:ok, %{completed: true}} = Reminders.get_reminder(reminder, list_id: list)
      Live.event(live, "iteration_verified", %{iteration: index})
    end)

    Live.event(live, "verified", %{repeats: repeats()})
  end

  @tag apps: ["com.apple.reminders", "com.apple.finder"]
  @tag large_batch: true
  @tag timeout: 900_000
  test "one, ten and one hundred item batches preserve files and independently observable reminders", %{live: live} do
    list = list(live)

    Enum.each([1, 10, 100], fn count ->
      source = Path.join(live.root, "batch-#{count}")
      output = source <> "-out"
      File.mkdir!(source)
      File.mkdir!(output)

      paths =
        Enum.map(1..count, fn index ->
          path = Path.join(source, "#{index}.txt")
          File.write!(path, "#{index}")
          path
        end)

      assert {:ok, copies} =
               Live.effect(live, :copy_batch, fn -> Finder.copy_files(paths, output, timeout: 180_000) end,
                 timeout: 180_000
               )

      assert Enum.map(copies, &File.read!/1) == Enum.map(paths, &File.read!/1)
      items = Enum.map(1..count, &[title: "#{live.marker}-#{count}-#{&1}"])

      assert {:ok, ids} =
               Live.effect(live, :reminder_batch, fn -> Reminders.create_many(list, items, timeout: 600_000) end,
                 timeout: 600_000
               )

      assert length(ids) == count and length(Enum.uniq(ids)) == count
      assert {:ok, values} = Reminders.list_reminders(list, limit: 1000)
      assert MapSet.subset?(MapSet.new(ids), MapSet.new(values, & &1.id))

      assert {:ok, ^ids} =
               Live.effect(
                 live,
                 :complete_batch,
                 fn -> Reminders.complete_many(ids, list_id: list, timeout: 240_000) end,
                 timeout: 240_000
               )

      assert {:ok, completed} = Reminders.list_reminders(list, limit: 1000)
      assert Enum.all?(Enum.filter(completed, &(&1.id in ids)), & &1.completed)
    end)

    Live.event(live, "verified", %{batch_sizes: [1, 10, 100]})
  end

  @tag apps: ["com.apple.Safari"]
  @tag final_live: true
  test "real DOM edits handle delayed controls, ambiguity, same-URL reload and stale windows", %{live: live} do
    html = Path.join(live.root, "form.html")

    File.write!(html, """
    <html><body><textarea id="field" disabled></textarea><pre id="display"></pre><span id="count">0</span>
    <button class="duplicate" onclick="document.querySelector('#count').textContent='bad'">one</button>
    <button class="duplicate">two</button><span id="existing">ready</span>
    <script>setTimeout(()=>document.querySelector('#field').disabled=false,200);
    document.querySelector('#field').oninput=e=>document.querySelector('#display').textContent=e.target.value;</script></body></html>
    """)

    url = "file://" <> URI.encode(html)

    assert :ok =
             Safari.with_page(url, fn page ->
               value = "quotes\" 雪\nsecond line"
               assert :ok = Safari.fill(page, "#field", value)
               assert {:ok, ^value} = Safari.text(page, "#display")
               assert {:error, _} = Safari.click(page, ".duplicate")
               assert {:ok, "0"} = Safari.text(page, "#count")
               assert :ok = Safari.navigate_and_wait(page, url)
               assert {:ok, ""} = Safari.text(page, "#display")
               assert :ok = Safari.close_page(page)
               assert {:error, _} = Safari.fill(page, "#field", "must not reach another window")
               :ok
             end)

    Live.event(live, "verified")
  end

  @tag final_live: true
  test "a real native file write followed by an error requires observation and no replay", %{live: live} do
    path = Path.join(live.root, "persisted.txt")
    intent = Evidence.intent(live, :file, %{path: path})
    Live.own(live, :file, path, fn -> File.rm(path) end, intent_id: intent, verify: fn -> not File.exists?(path) end)

    source = """
    function run(argv){ObjC.import('Foundation');var path=argv[0];
      $('persisted').writeToFileAtomicallyEncodingError($(path),true,$.NSUTF8StringEncoding,null);
      throw new Error('fixture failed after persistence');}
    """

    assert {:error, error} =
             Live.effect(live, :partial_native_write, fn -> ExMacOSControl.run_javascript(source, args: [path]) end,
               expect_error: true
             )

    assert File.read!(path) == "persisted"
    assert error.details.outcome == :unknown
    assert {:ok, %{status: :needs_reconciliation}} = Composition.Journal.inspect_run(error.details.journal_path)
    Live.event(live, "verified", %{expected_unknown: true, journal: error.details.journal_path})
  end

  @tag apps: ["com.apple.reminders", "com.apple.iCal"]
  @tag final_live: true
  test "ambiguous repeated-hour dates are confirmed or safely refused before completing the source", %{live: live} do
    list = list(live)
    calendar = calendar(live)

    assert {:ok, reminder} =
             Live.create(
               live,
               :reminder,
               fn -> Reminders.create_reminder(list, title: live.marker) end,
               &Reminders.delete_reminder(&1, list_id: list),
               &reminder_absent(list, &1)
             )

    attrs = [start_at: "2026-11-01T01:30:00-06:00", end_at: "2026-11-01T01:30:00-07:00"]
    intent = Evidence.intent(live, :event, %{calendar_id: calendar})

    result =
      Live.effect(live, :ambiguous_dates, fn -> UsageUtilities.schedule(reminder, calendar, attrs, list_id: list) end,
        expect_error: true,
        timeout: 8000
      )

    case result do
      {:ok, %{event_id: event}} ->
        own_event(live, event, calendar, intent)
        assert {:ok, %{completed: true}} = Reminders.get_reminder(reminder, list_id: list)
        Live.event(live, "verified", %{ambiguous_dates: :confirmed})

      {:error, error} ->
        assert %{event_id: event, observed: observed} = error.details.event_verification
        assert is_map(observed)
        own_event(live, event, calendar, intent)
        assert {:ok, %{completed: false}} = Reminders.get_reminder(reminder, list_id: list)
        Live.event(live, "verified", %{ambiguous_dates: :safe_refusal})
    end
  end

  @tag apps: ["com.apple.iCal"]
  @tag final_live: true
  test "all-day recurring Calendar captures retain native semantic fields", %{live: live} do
    calendar = calendar(live)

    assert {:ok, event} =
             Live.effect(live, :create_recurring_event, fn ->
               Composition.effect(
                 :create_event,
                 fn ->
                   Calendar.create_event(calendar,
                     title: live.marker,
                     start_at: "2026-11-02T07:00:00Z",
                     end_at: "2026-11-03T07:00:00Z",
                     all_day: true,
                     recurrence: "FREQ=DAILY;COUNT=2"
                   )
                 end,
                 resource: :event,
                 identity: %{calendar_id: calendar}
               )
             end)

    assert {:ok, original} = Calendar.get_event(calendar, event)
    assert {:ok, %Capture.Event{all_day: true} = capture} = Capture.event(calendar, event)
    assert capture.recurrence =~ "FREQ=DAILY"
    assert capture.recurrence == original.recurrence
    assert capture.start_at == original.start_at and capture.end_at == original.end_at

    deletion =
      Live.effect(
        live,
        :delete_recurring_event,
        fn ->
          Composition.effect(:delete_event, fn -> Calendar.delete_event(calendar, event) end,
            resource: :event,
            identity: %{calendar_id: calendar, id: event}
          )
        end,
        expect_error: true
      )

    assert {:ok, remaining} = Calendar.list_events(calendar, limit: 1000)
    present = Enum.any?(remaining, &(&1.id == event))

    outcome =
      case deletion do
        :ok ->
          refute present
          :confirmed

        {:error, error} ->
          assert error.details.outcome == :unknown
          if present, do: :uncertain_remaining, else: :uncertain_absent
      end

    # The owned calendar is the cleanup boundary for a recurring series.
    Live.event(live, "verified", %{recurring_delete: outcome})
  end

  @tag apps: ["com.apple.reminders"]
  @tag final_live: true
  test "scoped completion refuses missing IDs and preserves an unselected reminder", %{live: live} do
    list = list(live)

    assert {:ok, [first, untouched, last]} =
             Live.effect(live, :create_scoped_targets, fn ->
               Reminders.create_many(list, for(i <- 1..3, do: [title: "#{live.marker}-#{i}"]))
             end)

    assert {:error, %{type: :not_found, details: %{outcome: :not_started}}} =
             Live.effect(
               live,
               :missing_target,
               fn ->
                 Reminders.complete_many([first, "x-apple-reminder://#{live.marker}-missing"], list_id: list)
               end,
               expect_error: true
             )

    assert {:ok, before} = Reminders.list_reminders(list)
    assert Enum.all?(before, &(not &1.completed))

    assert {:ok, [^first, ^last]} =
             Live.effect(live, :complete_exact_targets, fn ->
               Reminders.complete_many([first, last], list_id: list)
             end)

    assert {:ok, after_values} = Reminders.list_reminders(list)
    assert Map.new(after_values, &{&1.id, &1.completed}) == %{first => true, untouched => false, last => true}
    Live.event(live, "verified")
  end

  @tag apps: ["com.apple.AddressBook"]
  @tag final_live: true
  test "contact composition creates details in an owned group and preserves exact identity", %{live: live} do
    email = String.downcase(live.marker) <> "@example.invalid"

    assert {:ok, group} =
             Live.create(
               live,
               :group,
               fn -> Contacts.create_group(live.marker) end,
               &Contacts.delete_group/1,
               &Live.absent("com.apple.AddressBook", "groups", &1)
             )

    assert {:ok, contact} =
             Live.create(
               live,
               :contact,
               fn ->
                 Contacts.create_with_details([first_name: live.marker, note: live.marker],
                   emails: [{email, "work"}],
                   phones: [{"5550100", "mobile"}],
                   group_ids: [group]
                 )
               end,
               &Contacts.delete_contact/1,
               &Live.absent("com.apple.AddressBook", "people", &1)
             )

    assert {:ok, value} = Contacts.get_contact(contact)
    assert value.first_name == live.marker
    assert Enum.any?(value.emails, &(&1.value == email))
    assert Enum.any?(value.phones, &(&1.value == "5550100"))

    assert {:ok, true} =
             Live.query(
               "com.apple.AddressBook",
               "return app.groups.byId(input.group).people.id().indexOf(input.id)>=0;",
               %{group: group, id: contact}
             )

    Live.event(live, "verified")
  end

  defp repeats do
    System.get_env("EXMC_CAMPAIGN_REPEATS", "1") |> String.to_integer() |> max(1) |> min(10)
  end

  defp recipient, do: System.fetch_env!("EXMC_TEST_EMAIL")

  defp png,
    do: Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII=")

  defp folder(live) do
    {:ok, id} =
      Live.create(
        live,
        :folder,
        fn -> Notes.create_folder(live.marker) end,
        &Notes.delete_folder/1,
        &Live.absent("com.apple.Notes", "folders", &1)
      )

    id
  end

  defp list(live) do
    {:ok, id} =
      Live.create(
        live,
        :list,
        fn -> Reminders.create_list(live.marker) end,
        &Reminders.delete_list/1,
        &Live.absent("com.apple.reminders", "lists", &1)
      )

    id
  end

  defp calendar(live) do
    {:ok, id} =
      Live.create(
        live,
        :calendar,
        fn -> Calendar.create_calendar(live.marker) end,
        &Calendar.delete_calendar/1,
        fn id -> with {:ok, values} <- Calendar.list_calendars(limit: 1000), do: Enum.all?(values, &(&1.id != id)) end
      )

    id
  end

  defp own_note(live, id, folder, intent),
    do:
      Live.own(live, :note, id, fn -> Notes.delete_note(id) end,
        intent_id: intent,
        verify: fn ->
          Live.query("com.apple.Notes", "return !app.folders.byId(input.parent).notes.byId(input.id).exists();", %{
            parent: folder,
            id: id
          })
        end
      )

  defp own_reminder(live, id, list, intent),
    do:
      Live.own(live, :reminder, id, fn -> Reminders.delete_reminder(id, list_id: list) end,
        intent_id: intent,
        verify: fn -> reminder_absent(list, id) end
      )

  defp reminder_absent(list, id),
    do:
      Live.query("com.apple.reminders", "return app.lists.byId(input.list).reminders.id().indexOf(input.id)<0;", %{
        list: list,
        id: id
      })

  defp own_draft(live, draft, intent),
    do:
      Live.own(live, :draft, draft.id, fn -> Mail.delete_draft(draft) end,
        intent_id: intent,
        verify: fn ->
          Live.query("com.apple.mail", "return !app.draftsMailbox().messages.byId(input.id).exists();", %{id: draft.id})
        end
      )

  defp own_event(live, id, calendar, intent),
    do:
      Live.own(live, :event, id, fn -> Calendar.delete_event(calendar, id) end,
        intent_id: intent,
        verify: fn ->
          with {:ok, values} <- Calendar.list_events(calendar, limit: 1000), do: Enum.all?(values, &(&1.id != id))
        end
      )
end
