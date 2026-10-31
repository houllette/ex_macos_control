defmodule ExMacOSControl.VerifiedHandoffsTest do
  use ExUnit.Case, async: true
  import Mox
  import ExMacOSControl.TestHelpers, only: [script_output: 1]
  alias ExMacOSControl.Composition.Journal
  alias ExMacOSControl.{Error, Finder, Mail}
  alias ExMacOSControl.Mail.Draft
  setup :verify_on_exit!

  test "saved draft identity is discovered after one creation rather than reusing its transient ID" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{ids: [1], pid: 42}) end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, _ ->
      refute source =~ "send newMessage"
      {:ok, "999"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["before"] == [1]
      assert input(opts)["recipients"] == ["self@example.invalid"]
      response([])
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response([%{id: 2, message_id: "saved-message"}]) end)

    assert {:ok, %Draft{id: 2, outgoing_id: "999", message_id: "saved-message", mail_pid: 42} = draft} =
             Mail.create_verified_draft(to: "self@example.invalid", subject: "Title", body: "Body")

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["id"] == 2
      assert input(opts)["message_id"] == "saved-message"
      response(%{id: 2, subject: "Title", content: "Body", attachments: []})
    end)

    assert {:ok, %{id: 2}} = Mail.get_draft(draft)
  end

  test "ambiguous saved drafts fail rather than selecting or deleting a candidate" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{ids: [], pid: 42}) end)
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, "999"} end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response([%{id: 2}, %{id: 3}]) end)

    assert {:error, %Error{message: message}} =
             Mail.create_verified_draft(to: "self@example.invalid", subject: "Title", body: "Body")

    assert message =~ "refusing to guess"
  end

  test "a create timeout is returned without creating again or guessing a saved ID" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{ids: [], pid: 42}) end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ ->
      {:error, Error.timeout("save", outcome: :unknown)}
    end)

    assert {:error, %Error{details: %{outcome: :unknown}}} =
             Mail.create_verified_draft(to: "self@example.invalid", subject: "Title", body: "Body")
  end

  test "Finder selection is dispatched once and observed before returning its capture" do
    directory = Path.expand("tmp/verified-selection-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "quoted\" 雪.txt")
    File.write!(path, "source")
    on_exit(fn -> File.rm_rf(directory) end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, opts ->
      refute source =~ path
      assert opts[:args] == [path]
      {:ok, ""}
    end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, script_output([])} end)
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, script_output([[path]])} end)
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, script_output([[path]])} end)
    assert {:ok, %{paths: [^path]}} = Finder.select_and_capture([path])
  end

  test "invalid file inputs and incomplete drafts fail before dispatch" do
    assert {:error, %Error{}} = Finder.select_and_capture(["/not/a/file"])
    assert {:error, %Error{}} = Mail.create_verified_draft(to: [], subject: "Title", body: "Body")
  end

  test "attachment verification freezes file metadata before creation even if the source disappears" do
    root = Path.expand("tmp/draft-attachment-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    path = Path.join(root, "fixture.txt")
    File.write!(path, "abc")
    on_exit(fn -> File.rm_rf!(root) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{ids: [], pid: 42}) end)

    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ ->
      File.rm!(path)
      {:ok, "999"}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["attachments"] == [%{"name" => "fixture.txt", "size" => 3}]
      response([%{id: 2, message_id: "saved"}])
    end)

    assert {:ok, %Draft{id: 2}} =
             Mail.create_verified_draft(to: "self@example.invalid", subject: "Title", body: "Body", attachments: [path])

    assert {:error, _} =
             Mail.create_verified_draft(to: "self@example.invalid", subject: "Title", body: "Body", attachments: nil)
  end

  test "invalid process or message identities reject a draft before creating its compose object" do
    for snapshot <- [%{ids: [], pid: nil}, %{ids: [%{invalid: true}], pid: 42}] do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(snapshot) end)

      assert {:error, %{details: %{outcome: :not_started}}} =
               Mail.create_verified_draft(to: "self@example.invalid", subject: "Title", body: "Body")
    end
  end

  test "draft deletion dispatches once and independently observes both representations" do
    draft = %Draft{id: 2, outgoing_id: "999", mail_pid: 42, subject: "Title", created_at: DateTime.utc_now()}

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert input(opts)["mail_pid"] == 42
      assert source =~ "app.close(matches[0],{saving:'no'})"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, 2, fn source, _ ->
      refute source =~ "app.close"
      seen = Process.get(:draft_absence_reads, 0)
      Process.put(:draft_absence_reads, seen + 1)
      response(seen == 1)
    end)

    assert :ok = Mail.delete_draft(draft)
  end

  test "an uncertain compose discard retains process and both native identities without replay" do
    root = Path.expand("tmp/draft-discard-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, state} = Agent.start_link(fn -> %{saved: true, outgoing: true, mutations: 0} end)
    draft = %Draft{id: 2, outgoing_id: "999", mail_pid: 42, subject: "Title", created_at: DateTime.utc_now()}

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      Agent.update(state, &%{&1 | saved: false, outgoing: false, mutations: &1.mutations + 1})
      {:error, Error.timeout("discard reply lost", outcome: :unknown)}
    end)

    assert {:error, error} = Mail.delete_draft(draft, journal: Path.join(root, "journal"))
    assert Agent.get(state, & &1) == %{saved: false, outgoing: false, mutations: 1}
    assert {:ok, summary} = Journal.inspect_run(error.details.journal_path)

    assert Enum.any?(
             summary.pending,
             &(get_in(&1, ["resource", "identity"]) == %{"id" => 2, "outgoing_id" => "999", "application_pid" => 42})
           )
  end

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
