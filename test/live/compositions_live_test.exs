defmodule ExMacOSControl.CompositionsLiveTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{
    Accessibility,
    Calendar,
    Finder,
    ImageEvents,
    Notes,
    Reminders,
    Safari,
    Workflows
  }

  alias ExMacOSControl.CompositionLiveSession, as: Live
  @moduletag :personal
  @moduletag final_live: true
  @moduletag timeout: 180_000

  enabled = System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1"

  unless enabled,
    do: @moduletag(skip: "Requires --include personal and both EXMC_LIVE_TESTS/EXMC_PERSONAL_TESTS=1")

  setup context do
    {:ok, live: Live.start(context)}
  end

  @tag apps: ["com.apple.Safari", "com.apple.Notes"]
  test "Safari capture creates a verified Note and closes its owned page", %{live: live} do
    folder = notes_folder(live)
    html = Path.join(live.root, "page.html")
    File.write!(html, "<html><head><title>#{live.marker}</title></head><body><h1>#{live.marker}</h1></body></html>")
    url = "file://" <> URI.encode(html)

    note_intent = ExMacOSControl.LiveEvidence.intent(live, :note, %{parent_id: folder})

    assert {:ok, id} =
             Live.effect(live, :page_to_note, fn ->
               Safari.with_page(url, [timeout: 30_000], fn page ->
                 with :ok <- Safari.activate_tab(page.window_id, page.tab_index),
                      {:ok, id} <- Workflows.current_page_to_note(folder_id: folder, title: live.marker) do
                   Live.own(live, :note, id, fn -> Notes.delete_note(id) end,
                     intent_id: note_intent,
                     verify: fn ->
                       Live.query(
                         "com.apple.Notes",
                         "return !app.folders.byId(input.parent).notes.byId(input.id).exists();",
                         %{parent: folder, id: id}
                       )
                     end
                   )

                   {:ok, id}
                 end
               end)
             end)

    assert {:ok, note} = Notes.get_note(id)
    assert note.folder_id == folder
    assert note.plaintext =~ live.marker
    assert note.plaintext =~ url
    Live.event(live, "verified")
  end

  @tag apps: ["com.apple.mail"]
  @tag finder: true
  test "Finder selection becomes a verified Mail draft without sending", %{live: live} do
    path = Path.join(live.desktop, live.marker <> ".txt")
    File.write!(path, live.marker)
    assert {:ok, previous} = Finder.get_selection()

    on_exit(fn ->
      case Finder.get_selection() do
        {:ok, [^path]} -> assert :ok = Finder.set_selection(Enum.filter(previous, &File.exists?/1))
        _ -> Live.event(live, "restoration_skipped", %{scope: :finder_selection})
      end
    end)

    assert {:ok, capture} = Finder.select_and_capture([path])
    assert capture.paths == [path]

    recipient = System.get_env("EXMC_TEST_EMAIL", "fixture@example.invalid")

    draft_intent = ExMacOSControl.LiveEvidence.intent(live, :draft)

    assert {:ok, draft} =
             Live.effect(live, :selection_to_draft, fn ->
               Workflows.selection_to_verified_draft(to: recipient, subject: live.marker, body: live.marker)
             end)

    Live.own(live, :draft, draft.id, fn -> ExMacOSControl.Mail.delete_draft(draft) end,
      intent_id: draft_intent,
      verify: fn ->
        Live.query("com.apple.mail", "return !app.draftsMailbox().messages.byId(input.id).exists();", %{id: draft.id})
      end
    )

    assert {:ok, saved} = ExMacOSControl.Mail.get_draft(draft)
    assert saved.id == draft.id
    assert saved.subject == live.marker
    assert saved.content =~ live.marker
    assert length(saved.attachments) == 1

    Live.event(live, "verified")
  end

  @tag apps: ["com.apple.reminders", "com.apple.iCal"]
  test "Reminder becomes a verified Calendar event before it is completed", %{live: live} do
    assert {:ok, list} =
             Live.create(
               live,
               :list,
               fn -> Reminders.create_list(live.marker) end,
               &Reminders.delete_list/1,
               &Live.absent("com.apple.reminders", "lists", &1)
             )

    assert {:ok, calendar} =
             Live.create(
               live,
               :calendar,
               fn -> Calendar.create_calendar(live.marker) end,
               &Calendar.delete_calendar/1,
               fn id ->
                 with {:ok, values} <- Calendar.list_calendars(limit: 1000), do: Enum.all?(values, &(&1.id != id))
               end
             )

    assert {:ok, reminder} =
             Live.create(
               live,
               :reminder,
               fn -> Reminders.create_reminder(list, title: live.marker, body: live.marker) end,
               &Reminders.delete_reminder(&1, list_id: list),
               fn id ->
                 Live.query(
                   "com.apple.reminders",
                   "return app.lists.byId(input.list).reminders.id().indexOf(input.id)<0;",
                   %{list: list, id: id}
                 )
               end,
               %{parent_id: list}
             )

    date = DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.to_date()
    start_at = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
    attrs = [start_at: start_at, end_at: DateTime.add(start_at, 3600)]

    event_intent = ExMacOSControl.LiveEvidence.intent(live, :event, %{calendar_id: calendar})

    assert {:ok, %{event_id: event}} =
             Live.effect(live, :reminder_to_event, fn ->
               Workflows.reminder_to_event(reminder, calendar, attrs,
                 complete_reminder: true,
                 verify_event: true,
                 list_id: list
               )
             end)

    Live.own(live, :event, event, fn -> Calendar.delete_event(calendar, event) end,
      intent_id: event_intent,
      verify: fn -> with {:ok, values} <- Calendar.list_events(calendar), do: Enum.all?(values, &(&1.id != event)) end
    )

    assert {:ok, %{title: title}} = Calendar.get_event(calendar, event)
    assert title == live.marker
    assert {:ok, %{completed: true}} = Reminders.get_reminder(reminder, list_id: list)
    Live.event(live, "verified")
  end

  test "Accessibility fills an owned native dialog and verifies its returned text", %{live: live} do
    task =
      Task.async(fn ->
        ExMacOSControl.StandardAdditions.dialog(live.marker,
          title: live.marker,
          default_answer: "original",
          buttons: ["OK"],
          timeout: 30_000
        )
      end)

    key = make_ref()

    try do
      assert :ok =
               ExMacOSControl.Wait.until(
                 fn _remaining ->
                   with {:ok, pids} <-
                          Live.query(
                            "com.apple.systemevents",
                            "var ps=app.processes.whose({name:'osascript'}),r=[];for(var i=0;i<ps.length;i++){if(ps[i].windows.byName(input.title).exists())r.push(ps[i].unixId());}return r;",
                            %{title: live.marker}
                          ) do
                     case pids do
                       [pid] ->
                         Process.put(key, pid)
                         true

                       [] ->
                         false

                       _ ->
                         flunk("Ambiguous owned dialog")
                     end
                   end
                 end,
                 timeout: 10_000
               )

      pid = Process.get(key)
      window = [%{role: "AXWindow", title: live.marker}]
      assert {:ok, tree} = Accessibility.tree(pid, path: window, depth: 5)
      assert :ok = Accessibility.fill(pid, window ++ text_path(tree), live.marker)
      assert :ok = Accessibility.click(pid, window ++ [%{role: "AXButton", title: "OK"}])
      assert {:ok, %{text: text}} = Task.await(task, 5000)
      assert text == live.marker
      Live.event(live, "verified")
    after
      Process.delete(key)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end
  end

  @tag apps: ["com.apple.imageevents"]
  test "Image batch produces verified files without changing the originals", %{live: live} do
    input = Path.join(live.root, "source.png")
    png = Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII=")
    File.write!(input, png)
    output = Path.join(live.root, "output")
    File.mkdir_p!(output)

    assert {:ok, [path]} =
             Live.effect(live, :process_images, fn ->
               ImageEvents.process_many([input], output, scale: 16, rotate: 90)
             end)

    assert File.regular?(path)
    assert {:ok, %{dimensions: [16, 16]}} = ImageEvents.info(path)
    assert File.read!(input) == png
    Live.event(live, "verified")
  end

  defp notes_folder(live) do
    assert {:ok, folder} =
             Live.create(
               live,
               :folder,
               fn -> Notes.create_folder(live.marker) end,
               &Notes.delete_folder/1,
               &Live.absent("com.apple.Notes", "folders", &1)
             )

    folder
  end

  defp text_path(node) do
    paths =
      Enum.flat_map(node.children, fn child ->
        selector = %{role: child.role}

        selector =
          if is_binary(child.title) and child.title != "", do: Map.put(selector, :title, child.title), else: selector

        if child.role in ["AXTextArea", "AXTextField"],
          do: [[selector]],
          else: Enum.map(text_paths(child), &[selector | &1])
      end)

    assert [path] = paths, "Expected one editable text area in the owned window"
    path
  end

  defp text_paths(%{role: role}) when role in ["AXTextArea", "AXTextField"], do: [[]]

  defp text_paths(node),
    do: Enum.flat_map(node.children, fn child -> Enum.map(text_paths(child), &[%{role: child.role} | &1]) end)
end
