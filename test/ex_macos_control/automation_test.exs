defmodule ExMacOSControl.AutomationTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Automation, Calendar, Contacts, Error, Notes, Photos, Reminders, SystemEvents}
  setup :verify_on_exit!

  test "user data is JSON argv and cannot alter generated app source" do
    text = "\"; throw new Error('injected'); // 雪\n"

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn script, opts ->
      refute script =~ text
      assert [input] = opts[:args]

      assert %{"properties" => %{"name" => ^text, "body" => "<p>body</p>"}, "__bundle_id" => "com.apple.Notes"} =
               Jason.decode!(input)

      assert opts[:timeout] == 1234
      {:ok, Jason.encode!(%{exmc: 1, result: "note-id"})}
    end)

    assert {:ok, "note-id"} = Notes.create_note([title: text, body: "<p>body</p>"], timeout: 1234)
  end

  test "explicit false values and timezone-aware dates survive property mapping" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _script, opts ->
      input = opts[:args] |> hd() |> Jason.decode!()
      assert input["properties"]["completed"] == false
      assert input["properties"]["dueDate"] == "2026-10-30T12:00:00Z"
      assert "dueDate" in input["dates"]
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    assert :ok = Reminders.update_reminder("id", completed: false, due_at: "2026-10-30T12:00:00Z")
  end

  test "writes reject unknown properties and invalid state before invoking the adapter" do
    assert {:error, %Error{}} = Notes.update_note("id", unknown: "ignored?")
    assert {:error, %Error{}} = Reminders.create_reminder("list", title: "x", priority: 10)
    assert {:error, %Error{}} = Reminders.update_reminder("id", due_at: "tomorrow")

    assert {:error, %Error{}} =
             Calendar.create_event("calendar",
               title: "x",
               start_at: "2026-10-30T13:00:00Z",
               end_at: "2026-10-30T12:00:00Z"
             )

    assert {:error, %Error{}} = Contacts.create_contact(note: "no name")
    assert {:error, %Error{}} = Photos.set_favorite("id", "false")
    assert {:error, %Error{}} = Notes.list_notes(limit: 1001)
    assert {:error, %Error{}} = Notes.list_notes(timeout: -1)
    assert {:error, %Error{}} = Notes.list_notes(folder_id: false)
    assert {:error, %Error{}} = Reminders.create_list("List", account_id: 1)
    assert {:error, %Error{}} = Photos.create_album("Album", folder_id: "")
    assert {:error, %Error{}} = Contacts.add_address("contact", unsupported: "value")
    assert {:error, %Error{}} = Notes.create_note(nil)
    assert {:error, %Error{}} = Calendar.create_event("cal", "invalid")
    assert {:error, %Error{}} = Contacts.create_contact("invalid")
    assert {:error, %Error{}} = Reminders.update_reminder("id", nil)
    assert {:error, %Error{}} = SystemEvents.attach_folder_action("missing", "missing")
    assert {:error, %Error{}} = Calendar.create_alarm("cal", "event", :open_file, trigger_minutes: -5)
    assert {:error, %Error{}} = Calendar.create_alarm("cal", "event", :display, [])
    assert {:error, %Error{}} = Calendar.create_alarm("cal", "event", :display, trigger_at: nil)

    assert {:error, %Error{}} =
             Calendar.create_alarm("cal", "event", :display, trigger_minutes: -5, trigger_at: "2026-10-30T12:00:00Z")
  end

  test "Photos creation uses its declared make parameters with an optional parent folder" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn script, opts ->
      assert script =~ "app.make(options)"
      refute script =~ "app.albums.push"
      input = opts[:args] |> hd() |> Jason.decode!()
      assert input["name"] == "Synthetic"
      assert input["type"] == "album"
      assert input["folder_id"] == "parent"
      {:ok, ~s({"exmc":1,"result":"new-album"})}
    end)

    assert {:ok, "new-album"} = Photos.create_album("Synthetic", folder_id: "parent")
  end

  test "folder action attachment keeps path data in argv and leaves global enablement explicit" do
    directory = Path.expand("tmp/folder-action-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    script_path = Path.join(directory, "quoted\" 雪.scpt")
    File.write!(script_path, "synthetic")
    on_exit(fn -> File.rm_rf(directory) end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, opts ->
      refute source =~ directory
      refute source =~ "folder actions enabled"
      assert opts[:args] == [directory, script_path, "false"]
      assert opts[:timeout] == 321
      {:ok, "true"}
    end)

    assert :ok = SystemEvents.attach_folder_action(directory, script_path, enabled: false, timeout: 321)
  end

  test "malformed protocol output produces an error without returning private text" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> {:ok, "private content"} end)
    assert {:error, %Error{message: message, details: %{}}} = Notes.list_accounts()
    refute message =~ "private"
  end

  test "response keys are normalized without creating atoms from untrusted fields" do
    key = "untrusted-#{System.unique_integer([:positive])}"

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:ok, Jason.encode!(%{exmc: 1, result: %{"id" => "id", key => true}})}
    end)

    assert {:ok, %{id: "id"} = result} = Notes.list_accounts()
    assert result[key]
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
  end

  test "nested execution options restore the calling process scope" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn "one", opts ->
      assert opts == [timeout: 1]
      {:ok, "one"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn "two", opts ->
      assert opts == [timeout: 2]
      {:ok, "two"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn "three", opts ->
      assert opts == [timeout: 1]
      {:ok, "three"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn "four" -> {:ok, "four"} end)

    ExMacOSControl.with_options([timeout: 1], fn ->
      ExMacOSControl.run_applescript("one")
      ExMacOSControl.with_options([timeout: 2], fn -> ExMacOSControl.run_applescript("two") end)
      ExMacOSControl.run_applescript("three")
    end)

    assert {:ok, "four"} = ExMacOSControl.run_applescript("four")
    assert {:error, %Error{}} = Automation.options([timeout: false], [:timeout])
  end

  test "typed helpers inherit scoped defaults without replacing an explicit timeout" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert opts[:timeout] == 7
      {:ok, ~s({"exmc":1,"result":[]})}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert opts[:timeout] == 9
      {:ok, ~s({"exmc":1,"result":[]})}
    end)

    ExMacOSControl.with_options([timeout: 7], fn ->
      assert {:ok, []} = Notes.list_accounts()
      assert {:ok, []} = Notes.list_accounts(timeout: 9)
    end)
  end
end
