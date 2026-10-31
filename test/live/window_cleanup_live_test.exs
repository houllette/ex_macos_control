defmodule ExMacOSControl.WindowCleanupLiveTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Automation, CompositionLiveSession, LiveEvidence, Notes, Terminal}
  alias ExMacOSControl.Desktop.Session
  alias ExMacOSControl.Desktop.Session.Native
  @moduletag :personal
  @moduletag window_cleanup: true
  @moduletag timeout: 180_000
  @moduletag apps: ["com.apple.Notes", "com.apple.Terminal"]
  unless System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1",
    do: @moduletag(skip: "Requires personal opt-in")

  defmodule OwnedNotesWindow do
    @behaviour Session
    defdelegate snapshot(ids), to: Native

    def prepare(_identity, before) do
      note = Process.get(:owned_note)

      with :ok <- Notes.show_note(note, separately: true),
           {:ok, after_show} <- Native.snapshot(["com.apple.Notes"]) do
        app = after_show["apps"]["com.apple.Notes"]
        prior = Enum.map(before["apps"]["com.apple.Notes"]["windows"], & &1.id)

        refs =
          app["windows"]
          |> Enum.reject(&(&1.id in prior))
          |> Enum.map(&%{bundle_id: "com.apple.Notes", window_id: &1.id, process: app["process"]})

        if refs == [],
          do: {:error, ExMacOSControl.Error.execution_error("Expected an owned note window")},
          else: {:ok, refs}
      end
    end

    defdelegate close(ref), to: Native
    defdelegate restore(before), to: Native
  end

  test "scoped support windows close after success, failure and exceptions while note data and existing windows survive",
       context do
    live = CompositionLiveSession.start(context)

    assert {:ok, folder} =
             CompositionLiveSession.create(
               live,
               :folder,
               fn -> Notes.create_folder(live.marker) end,
               &Notes.delete_folder/1,
               fn id -> CompositionLiveSession.absent("com.apple.Notes", "folders", id) end
             )

    assert {:ok, note} = Notes.create_text_note(live.marker, "owned window fixture", folder_id: folder)
    intent = LiveEvidence.intent(live, :note, %{parent_id: folder})

    CompositionLiveSession.own(live, :note, note, fn -> Notes.delete_note(note) end,
      intent_id: intent,
      verify: fn ->
        CompositionLiveSession.query(
          "com.apple.Notes",
          "return !app.folders.byId(input.folder).notes.byId(input.note).exists();",
          %{folder: folder, note: note}
        )
      end
    )

    assert {:ok, before} = Native.snapshot(["com.apple.Notes"])
    Process.put(:owned_note, note)
    previous = Application.get_env(:ex_macos_control, :desktop_session_backend)
    Application.put_env(:ex_macos_control, :desktop_session_backend, OwnedNotesWindow)

    try do
      assert {:ok, :value} = Session.with_apps(["com.apple.Notes"], fn -> {:ok, :value} end)

      assert {:error, :callback} = Session.with_apps(["com.apple.Notes"], fn -> {:error, :callback} end)

      assert_raise RuntimeError, "callback", fn ->
        Session.with_apps(["com.apple.Notes"], fn -> raise "callback" end)
      end
    after
      if previous,
        do: Application.put_env(:ex_macos_control, :desktop_session_backend, previous),
        else: Application.delete_env(:ex_macos_control, :desktop_session_backend)
    end

    assert {:ok, after_scope} = Native.snapshot(["com.apple.Notes"])

    assert Enum.map(after_scope["apps"]["com.apple.Notes"]["windows"], & &1.id) |> Enum.sort() ==
             Enum.map(before["apps"]["com.apple.Notes"]["windows"], & &1.id) |> Enum.sort()

    assert {:ok, %{plaintext: text}} = Notes.get_note(note)
    assert text =~ "owned window fixture"

    CompositionLiveSession.event(live, "verified", %{
      success: true,
      failure: true,
      exception: true,
      data_preserved: true,
      existing_windows_preserved: true
    })
  end

  test "managed Terminal commands close by default after command success and failure", context do
    live = CompositionLiveSession.start(context)
    assert {:ok, before} = terminal_ids()
    assert :ok = Terminal.do_script("printf 'owned command'")

    assert {:ok, %{exit_status: 7, stdout: "failed command", window_retained: false}} =
             Terminal.run("printf 'failed command'; exit 7")

    assert {:ok, after_run} = terminal_ids()
    assert Enum.sort(before) == Enum.sort(after_run)

    CompositionLiveSession.event(live, "verified", %{
      successful_command_closed: true,
      failed_command_closed: true,
      existing_terminals_preserved: true
    })
  end

  defp terminal_ids do
    # Closed Terminal windows can remain in the collection until a subsequent
    # window update. Compare user windows separately from known runner windows.
    owned =
      Path.wildcard("tmp/gui-runs/*/owner.json")
      |> Enum.flat_map(fn path ->
        case Jason.decode(File.read!(path)) do
          {:ok, row} -> [row["window_id"]]
          _ -> []
        end
      end)

    Automation.query(
      "com.apple.Terminal",
      "return app.windows.id().filter(function(id){return input.owned.indexOf(id)<0 && app.windows.byId(id).exists();});",
      %{owned: owned}
    )
  end
end
