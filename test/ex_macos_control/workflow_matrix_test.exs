defmodule ExMacOSControl.WorkflowMatrixTest do
  use ExUnit.Case, async: false
  import Mox
  alias ExMacOSControl.Workflows
  setup :verify_on_exit!

  @cases ~w(selection_to_shortcut selection_to_draft selection_to_verified_draft selection_to_chat
    current_page_to_chat clipboard_to_chat selection_to_album selection_to_images current_page_to_note
    current_page_to_reminder current_page_to_draft clipboard_to_note clipboard_to_reminder clipboard_to_shortcut
    shortcut_to_clipboard message_to_note message_to_reminder event_to_note event_to_reminder note_to_reminder
    reminder_to_event open_workspace)a

  setup do
    root = Path.expand("tmp/workflow-matrix-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    path = Path.join(root, "fixture.png")
    File.write!(path, "source")
    cli = Path.join(root, "shortcuts")
    File.write!(cli, "#!/bin/sh\nprintf 'fixture output'\n")
    File.chmod!(cli, 0o700)
    previous = System.get_env("PATH")
    System.put_env("PATH", root <> ":" <> previous)

    on_exit(fn ->
      System.put_env("PATH", previous)
      File.rm_rf!(root)
    end)

    {:ok, state} = Agent.start_link(fn -> [] end)

    stub(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      input = Jason.decode!(hd(opts[:args]))
      Agent.update(state, &[{:javascript, input} | &1])
      response(query(input, source))
    end)

    stub(ExMacOSControl.AdapterMock, :run_applescript, fn source, _opts ->
      Agent.update(state, &[{:applescript, source} | &1])

      cond do
        source =~ "selection" -> {:ok, ExMacOSControl.TestHelpers.script_output([[path]])}
        source =~ "outgoing message" -> {:ok, "999"}
        source =~ "make new document" -> {:ok, "42"}
        source =~ "Finder window" -> {:ok, ""}
        true -> flunk("Unexpected AppleScript in public workflow matrix")
      end
    end)

    %{root: root, path: path, state: state}
  end

  test "matrix includes every public workflow" do
    exports = Workflows.__info__(:functions) |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    assert exports == Enum.sort(@cases)
  end

  for name <- @cases do
    test "public workflow #{name} captures once and targets explicit destinations", context do
      name = unquote(name)
      result = apply(Workflows, name, arguments(name, context))
      assert result == :ok or match?({:ok, _}, result), inspect(result)
      calls = Agent.get(context.state, &Enum.reverse/1)
      assert calls != []

      assert Enum.count(calls, fn
               {:applescript, source} -> source =~ "selection"
               _ -> false
             end) <= 1

      assert Enum.count(calls, fn
               {:javascript, %{"__bundle_id" => "com.apple.Safari", "code" => _}} -> true
               _ -> false
             end) <= 1

      verify_destination(calls, name)
      assert File.read!(context.path) == "source"
    end
  end

  defp arguments(name, _context)
       when name in [:selection_to_draft, :selection_to_verified_draft, :current_page_to_draft],
       do: [[to: "self@example.invalid", subject: "Title", body: "Body"]]

  defp arguments(name, _context) when name in [:selection_to_chat, :current_page_to_chat, :clipboard_to_chat],
    do: ["explicit-chat"]

  defp arguments(name, _context) when name in [:selection_to_shortcut, :clipboard_to_shortcut], do: ["fixture-only"]
  defp arguments(:selection_to_album, _), do: ["owned-album"]

  defp arguments(:selection_to_images, context) do
    output = Path.join(context.root, "out")
    File.mkdir!(output)
    [output, [scale: 16]]
  end

  defp arguments(:current_page_to_note, _), do: [[folder_id: "explicit-folder"]]
  defp arguments(:current_page_to_reminder, _), do: ["explicit-list"]
  defp arguments(:clipboard_to_note, _), do: ["Title", [folder_id: "explicit-folder"]]
  defp arguments(:clipboard_to_reminder, _), do: ["explicit-list", "Title"]
  defp arguments(:shortcut_to_clipboard, _), do: ["fixture-only", "input"]
  defp arguments(:message_to_note, _), do: ["explicit-account", "Fixture", 1, [folder_id: "explicit-folder"]]
  defp arguments(:message_to_reminder, _), do: ["explicit-account", "Fixture", 1, "explicit-list"]
  defp arguments(:event_to_note, _), do: ["explicit-calendar", "event", [folder_id: "explicit-folder"]]
  defp arguments(:event_to_reminder, _), do: ["explicit-calendar", "event", "explicit-list"]
  defp arguments(:note_to_reminder, _), do: ["note", "explicit-list"]

  defp arguments(:reminder_to_event, _),
    do: ["reminder", "explicit-calendar", [start_at: "2026-11-01T12:00:00Z", end_at: "2026-11-01T13:00:00Z"]]

  defp arguments(:open_workspace, context),
    do: [context.root, [applications: ["com.apple.Notes"], urls: ["https://fixture.invalid"]]]

  defp query(%{"__bundle_id" => "com.apple.Safari", "code" => _}, _),
    do: %{title: "Title", url: "https://fixture.invalid", text: "Body", selection: "Selected"}

  defp query(%{"__bundle_id" => "com.apple.Safari"}, _),
    do: %{window_id: 42, tab_index: 1, url: "https://fixture.invalid"}

  defp query(%{"__bundle_id" => "com.apple.MobileSMS", "id" => "explicit-chat"}, _), do: true
  defp query(%{"__bundle_id" => "com.apple.Notes", "properties" => _}, _), do: "note"
  defp query(%{"__bundle_id" => "com.apple.Notes", "id" => "note"}, _), do: %{title: "Title", plaintext: "Body"}
  defp query(%{"__bundle_id" => "com.apple.reminders", "properties" => _}, _), do: "reminder"
  defp query(%{"__bundle_id" => "com.apple.reminders", "id" => "reminder"}, _), do: %{title: "Title", body: "Body"}
  defp query(%{"__bundle_id" => "com.apple.iCal", "properties" => _}, _), do: "event"

  defp query(%{"__bundle_id" => "com.apple.iCal"}, _),
    do: %{
      title: "Title",
      start_at: "2026-11-01T12:00:00Z",
      end_at: "2026-11-01T13:00:00Z",
      location: "Office",
      description: "Body",
      url: "https://fixture.invalid"
    }

  defp query(%{"__bundle_id" => "com.apple.Photos", "paths" => _}, _), do: ["photo"]
  defp query(%{"__bundle_id" => "com.apple.Photos"}, _), do: "album"
  defp query(%{"__bundle_id" => "com.apple.imageevents"}, _), do: true
  defp query(%{"__bundle_id" => "com.apple.mail", "before" => _}, _), do: [%{id: 7, message_id: "saved"}]
  defp query(%{"__bundle_id" => "com.apple.mail", "subject" => _}, _), do: %{ids: [], pid: 42}

  defp query(%{"__bundle_id" => "com.apple.mail", "id" => _}, _),
    do: %{subject: "Title", sender: "self@example.invalid", content: "Body"}

  defp query(%{"identity" => identity}, _), do: %{bundle_id: identity, path: "/fixture.app", running: true, pid: 42}

  defp query(%{"__bundle_id" => nil}, source) do
    cond do
      source =~ "theClipboard" -> "Clipboard"
      source =~ "setTheClipboardTo" -> true
      true -> flunk("Unexpected nil application query")
    end
  end

  defp verify_destination(calls, name) do
    for {:javascript, input} <- calls do
      if input["list_id"], do: assert(input["list_id"] == "explicit-list")
      if input["calendar_id"], do: assert(input["calendar_id"] == "explicit-calendar")
      if input["folder_id"], do: assert(input["folder_id"] == "explicit-folder")
      if input["account_id"], do: assert(input["account_id"] == "explicit-account")
    end

    if name in [:selection_to_chat, :current_page_to_chat, :clipboard_to_chat] do
      assert Enum.count(calls, fn
               {:javascript, %{"__bundle_id" => "com.apple.MobileSMS", "id" => "explicit-chat"}} -> true
               _ -> false
             end) == 1
    end
  end

  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
