defmodule ExMacOSControl.CaptureTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Capture, Notes, Reminders, Safari}
  alias ExMacOSControl.Capture.{Event, Files, Message, Page, Text}
  setup :verify_on_exit!

  test "pure rendering preserves provenance and chooses selected page text" do
    page = page()
    assert Capture.render(page) == "https://example.invalid\n\nSelected <text>"
    assert Capture.render(%{page | selection: "  "}) == "https://example.invalid\n\nFull text"
    assert Capture.render(page, :html) == "<p>https://example.invalid<br><br>Selected &lt;text&gt;</p>"
    assert Capture.title(%{page | title: ""}) == page.url
    assert Capture.source(page) == %{app: :safari, window_id: 42, tab_index: 2}
    assert Capture.files(page) == []
  end

  test "file captures retain paths without reading or copying the files" do
    paths = ["/not/present/one", "/not/present/two"]
    capture = %Files{paths: paths, source: %{app: :finder}, captured_at: DateTime.utc_now()}
    assert Capture.files(capture) == paths
    assert Capture.render(capture) == Enum.join(paths, "\n")
  end

  test "message and event formatting is independent of app state" do
    message = %Message{
      subject: "Question",
      sender: "Sender",
      content: "<body>",
      source: %{id: 1},
      captured_at: DateTime.utc_now()
    }

    assert Capture.render(message) == "From: Sender\nSubject: Question\n\n<body>"

    event = %Event{
      title: "Meeting",
      start_at: "start",
      end_at: "end",
      location: "Office",
      description: "Agenda",
      url: "url",
      source: %{id: "event"},
      captured_at: DateTime.utc_now()
    }

    assert Capture.render(event) == "start – end\nOffice\nAgenda\nurl"
  end

  test "one capture can feed independent destinations without rereading Safari" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{window_id: 42, tab_index: 2, url: "https://example.invalid"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{title: "Page", text: "Full text", selection: "Selected <text>", url: "https://example.invalid"})
    end)

    assert {:ok, capture} = Safari.capture_current()
    assert %Page{source: %{window_id: 42, tab_index: 2}} = capture

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["body"] =~ "&lt;text&gt;"
      response("note")
    end)

    assert {:ok, "note"} = Notes.create_from(capture, folder_id: "folder")

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["body"] == "https://example.invalid\n\nSelected <text>"
      response("reminder")
    end)

    assert {:ok, "reminder"} = Reminders.create_from("list", capture)
  end

  test "destination overrides do not mutate the captured source" do
    capture = %Text{title: "Original", text: "Body", source: %{app: :clipboard}, captured_at: DateTime.utc_now()}

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["name"] == "Override"
      response("note")
    end)

    assert {:ok, "note"} = Notes.create_from(capture, title: "Override")
    assert capture.title == "Original"
  end

  defp page,
    do: %Page{
      title: "Page",
      url: "https://example.invalid",
      text: "Full text",
      selection: "Selected <text>",
      source: %{app: :safari, window_id: 42, tab_index: 2},
      captured_at: DateTime.utc_now()
    }

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
