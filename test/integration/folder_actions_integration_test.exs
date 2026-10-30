defmodule ExMacOSControl.FolderActionsIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{Automation, DesktopSession, OSAScriptAdapter, Script, SystemEvents, TestHelpers}

  @moduletag :integration
  @moduletag :desktop

  unless Enum.any?(ExUnit.configuration()[:include], &(&1 in [:desktop, {:desktop, true}])) do
    @moduletag skip: "Requires --include desktop"
  end

  setup do
    TestHelpers.skip_unless_integration()
    original = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)
    on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, original) end)
    DesktopSession.start()
  end

  test "folder actions round trip paths and honor script enabled state", %{desktop_directory: root} do
    name = "EXMC-QA-folder-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    folder = Path.join(root, name)
    script = Path.join(root, "noop.scpt")
    File.mkdir!(folder)

    assert :ok =
             Script.compile(
               "on adding folder items to watchedFolder after receiving addedItems\nreturn\nend adding folder items to\n",
               script
             )

    on_exit(fn ->
      assert :ok =
               Automation.action(
                 "com.apple.systemevents",
                 "var a=app.folderActions.byName(input.name);if(a.exists()){if(a.path().indexOf(input.owner)<0)throw new Error('Folder ownership differs');app.delete(a);}",
                 %{name: name, owner: Path.basename(root)}
               )
    end)

    assert :ok = SystemEvents.attach_folder_action(folder, script, enabled: false)
    assert %{enabled: false, scripts: [%{enabled: false}]} = own_action(folder)

    assert :ok = SystemEvents.attach_folder_action(folder, script, enabled: true)
    assert %{scripts: [%{enabled: true}]} = own_action(folder)
    assert :ok = SystemEvents.set_folder_action_enabled(folder, true)
    assert %{enabled: true} = own_action(folder)
    assert :ok = SystemEvents.set_folder_action_enabled(folder, false)
    assert %{enabled: false} = own_action(folder)
    assert :ok = SystemEvents.detach_folder_action(folder, script)
    assert %{scripts: []} = own_action(folder)
  end

  defp own_action(folder) do
    assert {:ok, actions} = SystemEvents.list_folder_actions()
    assert [action] = Enum.filter(actions, &(&1.name == Path.basename(folder)))
    assert action.path =~ Path.basename(Path.dirname(folder))
    action
  end
end
