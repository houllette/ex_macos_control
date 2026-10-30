defmodule ExMacOSControl.WorkflowsTest do
  use ExUnit.Case, async: true
  import Mox
  import ExMacOSControl.TestHelpers, only: [script_output: 1]
  alias ExMacOSControl.{Error, Workflows}
  setup :verify_on_exit!

  test "page capture freezes the target, chooses selected text and creates escaped HTML" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{window_id: 42, tab_index: 2, url: "https://example.invalid"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["window_id"] == 42
      assert input(opts)["tab_index"] == 2
      response(%{title: "Title", url: "https://example.invalid", selection: "<selected>", text: "other text"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["folder_id"] == "folder"
      assert input(opts)["properties"]["name"] == "Title"
      assert input(opts)["properties"]["body"] == "<p>https://example.invalid<br><br>&lt;selected&gt;</p>"
      response("note")
    end)

    assert {:ok, "note"} = Workflows.current_page_to_note(folder_id: "folder")
  end

  test "Finder selection becomes draft attachments without sending", %{test: name} do
    directory = Path.expand("tmp/workflow-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    file = Path.join(directory, "quoted\" 雪.txt")
    File.write!(file, "contents")
    on_exit(fn -> File.rm_rf(directory) end)
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, script_output([[file]])} end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, opts ->
      refute source =~ "send newMessage"
      assert source =~ "save"
      assert source =~ "quoted\\\" 雪.txt"
      assert opts[:timeout] in 1..1000
      {:ok, "draft-id"}
    end)

    assert {:ok, "draft-id"} =
             Workflows.selection_to_draft([to: "person@example.invalid", subject: "Files", body: "Attached"],
               timeout: 1000
             )
  end

  test "empty selection never invokes a destination" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, script_output([])} end)

    assert {:error, %Error{}} =
             Workflows.selection_to_draft(to: "person@example.invalid", subject: "Files", body: "Attached")
  end

  test "clipboard capture preserves Unicode and writes a reminder with explicit destination" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("Clipboard 雪") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["list_id"] == "list"
      assert input(opts)["properties"] == %{"name" => "Follow up", "body" => "Clipboard 雪", "flagged" => false}
      response("reminder")
    end)

    assert {:ok, "reminder"} = Workflows.clipboard_to_reminder("list", "Follow up", flagged: false)
  end

  test "Mail handoff uses message content without modifying source flags" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{subject: "Subject", sender: "Sender", content: "Body <text>"})
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["body"] =~ "From: Sender"
      assert input(opts)["properties"]["body"] =~ "Body &lt;text&gt;"
      response("note")
    end)

    assert {:ok, "note"} = Workflows.message_to_note("account", "INBOX", 12)
  end

  test "event handoff defaults due date to event start, preserving timezone-aware input" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{
        title: "Meeting",
        start_at: "2026-10-30T12:00:00Z",
        end_at: "2026-10-30T13:00:00Z",
        location: "Office",
        description: "Agenda",
        url: "https://example.invalid"
      })
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["properties"]["dueDate"] == "2026-10-30T12:00:00Z"
      assert input(opts)["properties"]["body"] =~ "Agenda"
      response("reminder")
    end)

    assert {:ok, "reminder"} = Workflows.event_to_reminder("calendar", "event", "list")
  end

  test "failed event creation never completes the source reminder" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{title: "Task", body: "Description"}) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:error, Error.timeout("create", outcome: :unknown)}
    end)

    attrs = [start_at: "2026-10-30T12:00:00Z", end_at: "2026-10-30T13:00:00Z"]

    assert {:error, %Error{details: %{outcome: :unknown}}} =
             Workflows.reminder_to_event("reminder", "calendar", attrs, complete_reminder: true)
  end

  test "failed reminder completion preserves created event for recovery" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{title: "Task", body: "Description"}) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("event-id") end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> {:error, Error.permission_denied("complete")} end)
    attrs = [start_at: "2026-10-30T12:00:00Z", end_at: "2026-10-30T13:00:00Z"]
    assert {:error, error} = Workflows.reminder_to_event("reminder", "calendar", attrs, complete_reminder: true)
    assert Enum.any?(error.details.composition.completed, &(&1.step == :create_event and &1.result == "event-id"))
  end

  test "invalid workflow options cannot trigger captures or writes" do
    assert {:error, %Error{}} = Workflows.current_page_to_note(unknown: true)
    assert {:error, %Error{}} = Workflows.current_page_to_reminder("", [])
    assert {:error, %Error{}} = Workflows.reminder_to_event("id", "cal", [], complete_reminder: "true")
    assert {:error, %Error{}} = Workflows.selection_to_draft(to: "x", attachments: ["override"])
  end

  test "clipboard messages target one explicit chat and never retry an uncertain send" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response("Hello 雪") end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["id"] == "chat"
      assert input(opts)["text"] == "Hello 雪"
      {:error, Error.timeout("send", outcome: :unknown)}
    end)

    assert {:error, %Error{details: %{outcome: :unknown}}} = Workflows.clipboard_to_chat("chat")
  end

  test "persistent workspaces return opened page targets and resolved applications" do
    directory = Path.expand("tmp/workspace-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      response(%{bundle_id: "com.example.app", path: "/Applications/Synthetic.app", running: true, pid: 42})
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, _ ->
      assert source =~ "Finder"
      {:ok, ""}
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, opts ->
      assert opts[:args] == ["https://example.invalid"]
      {:ok, "42"}
    end)

    assert {:ok, %{folder: ^directory, applications: [%{pid: 42}], pages: [%{window_id: 42, owned: true}]}} =
             Workflows.open_workspace(directory, applications: ["Synthetic"], urls: ["https://example.invalid"])
  end

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
