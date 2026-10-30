defmodule ExMacOSControl.WrapperContractTest do
  use ExUnit.Case, async: false
  import Mox
  @moduletag :integration
  alias ExMacOSControl.{
    Accessibility,
    Calendar,
    Contacts,
    FinalCutPro,
    Finder,
    ImageEvents,
    Mail,
    Messages,
    Music,
    Notes,
    Photos,
    QuickTime,
    Reminders,
    Safari,
    Script,
    Shortcuts,
    StandardAdditions,
    SystemEvents,
    SystemSettings,
    Terminal,
    TV
  }

  setup :verify_on_exit!

  test "generated app scripts compile natively without executing app operations" do
    directory = Path.expand("tmp/wrappers-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    file = Path.join(directory, "source 雪.txt")
    File.write!(file, "synthetic")
    on_exit(fn -> File.rm_rf(directory) end)

    stub(ExMacOSControl.AdapterMock, :run_javascript, fn source, _opts ->
      send(self(), {:source, :javascript, source})
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    stub(ExMacOSControl.AdapterMock, :run_applescript, fn source ->
      send(self(), {:source, :applescript, source})
      {:ok, "true"}
    end)

    stub(ExMacOSControl.AdapterMock, :run_applescript, fn source, _ ->
      send(self(), {:source, :applescript, source})
      {:ok, "true"}
    end)

    calls = [
      fn -> Notes.create_note(title: "quoted\" 雪", body: "<p>x</p>") end,
      fn -> Notes.list_notes(folder_id: "folder") end,
      fn -> Notes.get_note("note") end,
      fn -> Notes.update_note("note", body: "<p>changed</p>") end,
      fn -> Notes.delete_note("note") end,
      fn -> Notes.create_folder("Folder") end,
      fn -> Notes.rename_folder("folder", "Renamed") end,
      fn -> Notes.delete_folder("folder") end,
      fn -> Notes.list_attachments("note") end,
      fn -> Notes.selection() end,
      fn -> Notes.show_note("note", separately: false) end,
      fn -> Calendar.list_calendars() end,
      fn -> Calendar.create_calendar("Synthetic") end,
      fn -> Calendar.rename_calendar("cal", "Renamed") end,
      fn -> Calendar.delete_calendar("cal") end,
      fn -> Calendar.list_events("cal", from: "2026-10-30T00:00:00Z") end,
      fn ->
        Calendar.create_event("cal", title: "Event", start_at: "2026-10-30T01:00:00Z", end_at: "2026-10-30T02:00:00Z")
      end,
      fn -> Calendar.update_event("cal", "event", location: "Here") end,
      fn -> Calendar.delete_event("cal", "event") end,
      fn -> Calendar.list_attendees("cal", "event") end,
      fn -> Calendar.create_alarm("cal", "event", :display, trigger_minutes: -5) end,
      fn -> Calendar.list_alarms("cal", "event", :sound) end,
      fn -> Calendar.delete_alarm("cal", "event", :display, 1) end,
      fn -> Calendar.show_event("cal", "event") end,
      fn -> Calendar.view_date("2026-10-30T12:00:00Z") end,
      fn -> Calendar.switch_view(:month) end,
      fn -> Reminders.create_reminder("list", title: "Reminder") end,
      fn -> Reminders.list_reminders("list") end,
      fn -> Reminders.create_list("Synthetic", account_id: "account") end,
      fn -> Reminders.rename_list("list", "Renamed") end,
      fn -> Reminders.delete_list("list") end,
      fn -> Contacts.create_contact(first_name: "Synthetic") end,
      fn -> Contacts.get_contact("contact") end,
      fn -> Contacts.add_email("contact", "test@example.invalid") end,
      fn -> Contacts.add_address("contact", street: "1 Synthetic St", postal_code: "00000") end,
      fn -> Contacts.rename_group("group", "Renamed") end,
      fn -> Contacts.delete_group("group") end,
      fn -> Contacts.selection() end,
      fn -> Contacts.add_to_group("contact", "group") end,
      fn -> Contacts.remove_from_group("contact", "group") end,
      fn -> Photos.search("synthetic") end,
      fn -> Photos.list_media(album_id: "album") end,
      fn -> Photos.create_album("Synthetic", folder_id: "folder") end,
      fn -> Photos.create_folder("Synthetic") end,
      fn -> Photos.rename_album("album", "Renamed") end,
      fn -> Photos.rename_folder("folder", "Renamed") end,
      fn -> Photos.delete_folder("folder") end,
      fn -> Photos.start_slideshow(["photo"]) end,
      fn -> Photos.pause_slideshow() end,
      fn -> Photos.resume_slideshow() end,
      fn -> Photos.stop_slideshow() end,
      fn -> Photos.import_files([file], album_id: "album") end,
      fn -> Photos.export(["photo"], directory) end,
      fn -> Photos.set_favorite("photo", false) end,
      fn -> Music.state() end,
      fn -> Music.play_track("persistent-id") end,
      fn -> Music.search("synthetic") end,
      fn -> Music.create_playlist("Synthetic") end,
      fn -> Music.add_to_playlist("track", "playlist") end,
      fn -> TV.list_tracks(playlist_id: "playlist") end,
      fn -> QuickTime.list_movies() end,
      fn -> QuickTime.new_recording(:audio) end,
      fn -> QuickTime.trim(1, 0, 2) end,
      fn -> QuickTime.export(1, Path.join(directory, "movie.mov"), "480p") end,
      fn -> ImageEvents.info(file) end,
      fn -> ImageEvents.scale(file, Path.join(directory, "scaled.png"), 100) end,
      fn -> StandardAdditions.clipboard() end,
      fn -> StandardAdditions.set_clipboard("text") end,
      fn -> StandardAdditions.notify("text", title: "title") end,
      fn -> StandardAdditions.dialog("text", default_answer: "answer") end,
      fn -> StandardAdditions.choose_files() end,
      fn -> StandardAdditions.say("text", rate: 100) end,
      fn -> StandardAdditions.set_volume(10) end,
      fn -> StandardAdditions.path_to(:downloads) end,
      fn -> Terminal.do_script("printf test", window_id: 1, tab_index: 1) end,
      fn -> Terminal.read_session(1, 1) end,
      fn -> SystemSettings.list_anchors("pane") end,
      fn -> SystemSettings.reveal("pane", anchor: "anchor") end,
      fn -> Shortcuts.list(folder_id: "folder") end,
      fn -> Messages.send_file("synthetic@example.invalid", file) end,
      fn -> Messages.send_to_chat("chat", "synthetic") end,
      fn -> Messages.list_accounts() end,
      fn ->
        Mail.send_email(
          to: ["test@example.invalid"],
          subject: "Test",
          body: "Test",
          attachments: [file],
          sender: "sender@example.invalid"
        )
      end,
      fn -> Mail.create_draft(to: "test@example.invalid", subject: "Draft", body: "Test") end,
      fn -> Mail.search_messages("account", ["INBOX", "Child"], query: "synthetic", read: false) end,
      fn -> Mail.get_message("account", "INBOX", 1) end,
      fn -> Mail.update_message("account", "INBOX", 1, read: false) end,
      fn -> Finder.rename(file, "new name.txt") end,
      fn -> Finder.copy(file, directory <> "/destination") end,
      fn -> Finder.create_folder(directory, "new folder") end,
      fn -> Finder.set_selection([file]) end,
      fn -> Finder.list_windows() end,
      fn -> Safari.tabs(1) end,
      fn -> Safari.navigate(1, 1, "https://example.invalid") end,
      fn -> Safari.execute_javascript_in(1, 1, "document.title") end,
      fn -> Safari.add_reading_list("https://example.invalid", title: "Title") end,
      fn -> Accessibility.tree("Synthetic", path: [%{role: "AXWindow", index: 1}]) end,
      fn -> Accessibility.set_attribute("Synthetic", [], "AXValue", false) end,
      fn -> Accessibility.press_key_code("Synthetic", 36, using: [:command]) end,
      fn -> Accessibility.click_menu_path("Synthetic", ["File", "Export", "PDF"]) end,
      fn -> SystemEvents.get_window_properties("Synthetic") end,
      fn -> SystemEvents.list_login_items() end,
      fn -> SystemEvents.add_login_item(file) end,
      fn -> SystemEvents.set_dark_mode(true) end,
      fn -> SystemEvents.attach_folder_action(directory, file, enabled: false) end,
      fn -> SystemEvents.detach_folder_action(directory, file) end,
      fn -> SystemEvents.set_folder_action_enabled(directory, false) end,
      fn -> SystemEvents.set_folder_actions_enabled(false) end,
      fn -> FinalCutPro.list_projects("library", "event") end,
      fn -> FinalCutPro.get_sequence("library", "event", "project") end
    ]

    File.mkdir_p!(directory <> "/destination")

    Enum.each(calls, fn call ->
      call.()
      assert_receive {:source, language, source}
      assert :ok = Script.validate(source, language: language), "Failed generated #{language} source:\n#{source}"
    end)
  end
end
