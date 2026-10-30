defmodule ExMacOSControl.CompositionsLiveTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{
    Accessibility,
    Automation,
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
  @moduletag timeout: 180_000

  enabled = System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1"
  included = Enum.any?(ExUnit.configuration()[:include], &(&1 in [:personal, {:personal, true}]))

  unless enabled and included,
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

    assert {:ok, id} =
             Live.effect(live, :page_to_note, fn ->
               Safari.with_page(url, [timeout: 30_000], fn page ->
                 with :ok <- Safari.activate_tab(page.window_id, page.tab_index),
                      {:ok, id} <- Workflows.current_page_to_note(folder_id: folder, title: live.marker) do
                   Live.own(live, :note, id, fn -> Notes.delete_note(id) end)
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
    on_exit(fn -> Finder.set_selection(Enum.filter(previous, &File.exists?/1)) end)
    assert :ok = ExMacOSControl.SystemEvents.reveal_in_finder(path)

    assert :ok =
             ExMacOSControl.Wait.until(
               fn ->
                 with {:ok, selection} <- Finder.get_selection(), do: {:ok, selection == [path]}
               end,
               timeout: 5000
             )

    recipient = System.get_env("EXMC_TEST_EMAIL", "fixture@example.invalid")

    assert {:ok, draft} =
             Live.effect(live, :selection_to_draft, fn ->
               Workflows.selection_to_draft(to: recipient, subject: live.marker, body: live.marker)
             end)

    Live.own(live, :draft, draft, fn ->
      Automation.action(
        "com.apple.mail",
        "app.outgoingMessages().filter(function(o){return o.subject()===input.marker;}).forEach(function(o){app.close(o,{saving:'no'});});app.draftsMailbox().messages.whose({subject:input.marker})().forEach(function(o){app.delete(o);});",
        %{id: draft, marker: live.marker}
      )
    end)

    assert {:ok, true} =
             Live.query(
               "com.apple.mail",
               "var values=app.draftsMailbox().messages.whose({subject:input.marker})();if(values.length!==1)return false;var o=values[0];return o.content().indexOf(input.marker)>=0&&o.mailAttachments.length===1;",
               %{id: draft, marker: live.marker}
             )

    Live.event(live, "verified")
  end

  @tag apps: ["com.apple.reminders", "com.apple.iCal"]
  test "Reminder becomes a verified Calendar event before it is completed", %{live: live} do
    assert {:ok, list} = Live.effect(live, :create_list, fn -> Reminders.create_list(live.marker) end)
    Live.own(live, :list, list, fn -> Reminders.delete_list(list) end)
    assert {:ok, calendar} = Live.effect(live, :create_calendar, fn -> Calendar.create_calendar(live.marker) end)
    Live.own(live, :calendar, calendar, fn -> Calendar.delete_calendar(calendar) end)

    assert {:ok, reminder} =
             Live.effect(live, :create_reminder, fn ->
               Reminders.create_reminder(list, title: live.marker, body: live.marker)
             end)

    Live.own(live, :reminder, reminder, fn -> Reminders.delete_reminder(reminder) end)
    start_at = DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second)
    attrs = [start_at: start_at, end_at: DateTime.add(start_at, 3600)]

    assert {:ok, %{event_id: event}} =
             Live.effect(live, :reminder_to_event, fn ->
               Workflows.reminder_to_event(reminder, calendar, attrs, complete_reminder: true)
             end)

    Live.own(live, :event, event, fn -> Calendar.delete_event(calendar, event) end)
    assert {:ok, %{title: title}} = Calendar.get_event(calendar, event)
    assert title == live.marker
    assert {:ok, %{completed: true}} = Reminders.get_reminder(reminder)
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
    assert {:ok, folder} = Live.effect(live, :create_folder, fn -> Notes.create_folder(live.marker) end)
    Live.own(live, :folder, folder, fn -> Notes.delete_folder(folder) end)
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
