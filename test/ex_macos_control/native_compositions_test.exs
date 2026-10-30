defmodule ExMacOSControl.NativeCompositionsTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.{
    Accessibility,
    Calendar,
    Contacts,
    Error,
    Finder,
    ImageEvents,
    Mail,
    Messages,
    Music,
    Notes,
    Photos,
    Reminders
  }

  setup :verify_on_exit!

  setup do
    directory = Path.expand("tmp/compositions-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "text notes escape markup, including quotes and newlines" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["body"] == "<p>&lt;script&gt;&amp;&quot;&#39;<br>雪</p>"
      response("note")
    end)

    assert {:ok, "note"} = Notes.create_text_note("Title", "<script>&\"'\n雪")
  end

  test "batch inputs are validated before creating the first reminder" do
    assert {:error, %Error{}} =
             Reminders.create_many("list", [[title: "valid"], [title: "invalid", due_at: "tomorrow"]])

    assert {:error, %Error{}} = Reminders.create_many("list", [[title: "valid"], [title: "invalid", priority: 99]])
  end

  test "a failed alarm retains the event ID and the first created alarm" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("event") end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(1) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:error, Error.timeout("alarm", outcome: :unknown)}
    end)

    attrs = [title: "Meeting", start_at: "2026-10-30T12:00:00Z", end_at: "2026-10-30T13:00:00Z"]
    alarms = [{:display, [trigger_minutes: -10]}, {:display, [trigger_minutes: -5]}]
    assert {:error, error} = Calendar.create_event_with_alarms("calendar", attrs, alarms)
    assert error.details.outcome == :unknown

    assert error.details.composition.completed == [
             %{step: :create_event, result: "event"},
             %{step: {:create_alarm, 0}, result: 1}
           ]
  end

  test "invalid alarms and contact details cannot leave newly created objects" do
    assert {:error, %Error{}} = Calendar.create_event_with_alarms("cal", [], [{:display, []}])
    assert {:error, %Error{}} = Contacts.create_with_details([first_name: "Someone"], emails: [{"value", ""}])
    assert {:error, %Error{}} = Contacts.create_with_details([first_name: "Someone"], addresses: [[unknown: "x"]])
  end

  test "contact details are attached to the ID returned by creation" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("contact") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["id"] == "contact"
      assert input(opts)["value"] == "someone@example.invalid"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["id"] == "contact"
      assert input(opts)["group_id"] == "group"
      response(true)
    end)

    assert {:ok, "contact"} =
             Contacts.create_with_details([first_name: "Someone"],
               emails: [{"someone@example.invalid", "work"}],
               group_ids: ["group"]
             )
  end

  test "Photos imports target only the newly created album", %{directory: directory} do
    path = Path.join(directory, "image.png")
    File.write!(path, "image")
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("album") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["album_id"] == "album"
      assert input(opts)["paths"] == [path]
      response(["photo"])
    end)

    assert {:ok, %{album_id: "album", media_ids: ["photo"]}} = Photos.import_into_new_album([path], "Album")
  end

  test "playlist population stops at the failed track and retains its new playlist" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("playlist") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["playlist_id"] == "playlist"
      assert input(opts)["track_id"] == "one"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> {:error, Error.execution_error("missing track")} end)
    assert {:error, error} = Music.create_playlist_with_tracks("Playlist", ["one", "two", "three"])
    assert hd(error.details.composition.completed).result == "playlist"
  end

  test "copy batch refuses all collisions before any file is moved", %{directory: directory} do
    source = Path.join(directory, "source.txt")
    File.write!(source, "source")
    assert {:error, %Error{}} = Finder.copy_files([source], directory)
    assert File.read!(source) == "source"
    assert {:error, %Error{}} = Finder.copy_files([source, source], Path.join(directory, "missing"))
  end

  test "attachment output paths cannot escape their destination and duplicates get indices", %{directory: directory} do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{attachments: [%{index: 1, name: "../same.txt"}, %{index: 2, name: "same.txt"}]})
    end)

    for index <- [1, 2] do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
        assert input(opts)["path"] == Path.join(directory, "#{index}-same.txt")
        response(true)
      end)
    end

    assert {:ok, outputs} = Mail.save_attachments("account", "INBOX", 1, directory)
    assert outputs == [Path.join(directory, "1-same.txt"), Path.join(directory, "2-same.txt")]
  end

  test "image batch checks collisions, step arguments and keeps the original files", %{directory: directory} do
    image = Path.join(directory, "image.png")
    File.write!(image, "image")
    assert {:error, %Error{}} = ImageEvents.process_many([image], directory, scale: 100)
    assert {:error, %Error{}} = ImageEvents.process(image, Path.join(directory, "new.png"), crop: [0, 1])

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "finally {app.close(image);}"
      assert input(opts)["steps"] == [["scale", 100], ["rotate", 90]]
      assert input(opts)["format"] == "JPEG"
      response(true)
    end)

    assert {:ok, [output]} = ImageEvents.process_many([image], directory, [scale: 100, rotate: 90], format: "JPEG")
    assert output == Path.join(directory, "image.jpg")
    assert File.read!(image) == "image"
  end

  test "UI fill observes editability, changes AXValue once, then polls its value" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["attribute"] == "AXValue"
      assert input(opts)["value"] == "雪"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(false) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)
    assert :ok = Accessibility.fill("Synthetic", [%{identifier: "field"}], "雪", interval: 1)
  end

  test "already checked checkboxes are observed without toggling" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(1) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(true) end)
    assert :ok = Accessibility.set_checked("Synthetic", [%{identifier: "check"}], true)
  end

  test "message batches stop at an uncertain send and preserve acknowledged chat IDs" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["id"] == "chat-one"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:error, Error.timeout("send", outcome: :unknown)}
    end)

    assert {:error, error} = Messages.send_to_chats(["chat-one", "chat-two", "chat-three"], "Hello")
    assert error.details.outcome == :unknown
    assert error.details.composition.completed == [%{step: {:send_message, 0}, result: "chat-one"}]
  end

  test "create-and-show reports a created note when the display step fails" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("note") end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> {:error, Error.execution_error("show failed")} end)
    assert {:error, error} = Notes.create_and_show(title: "Title")
    assert error.details.composition.completed == [%{step: :create_note, result: "note"}]
  end

  test "note duplication preserves HTML body and honors the destination folder" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{title: "Original", body: "<p><b>HTML</b></p>"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"] == %{"name" => "Copy", "body" => "<p><b>HTML</b></p>"}
      assert input(opts)["folder_id"] == "destination"
      response("copy")
    end)

    assert {:ok, "copy"} = Notes.duplicate_note("original", title: "Copy", folder_id: "destination")
  end

  test "reply drafts quote the original body and save without sending" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{sender: "Someone <someone@example.invalid>", subject: "Question", content: "One\nTwo"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, _ ->
      assert source =~ "someone@example.invalid"
      assert source =~ "Re: Question"
      assert source =~ "> One"
      assert source =~ "save"
      refute source =~ "send newMessage"
      {:ok, "draft"}
    end)

    assert {:ok, "draft"} = Mail.draft_reply("account", "INBOX", 1, body: "Answer")
  end

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
