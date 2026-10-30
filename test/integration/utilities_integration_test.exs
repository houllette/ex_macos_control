defmodule ExMacOSControl.UtilitiesIntegrationTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Automation, Calendar, ImageEvents, Messages, OSAScriptAdapter, Terminal, TestHelpers, Wait}
  @moduletag :integration
  @moduletag :desktop

  unless Enum.any?(ExUnit.configuration()[:include], &(&1 in [:desktop, {:desktop, true}])) do
    @moduletag skip: "Requires --include desktop (uses Image Events and creates its own Terminal window)"
  end

  setup do
    TestHelpers.skip_unless_integration()

    ExMacOSControl.DesktopSession.start(
      apps: ["com.apple.iCal", "com.apple.MobileSMS", "com.apple.imageevents", "com.apple.Terminal"]
    )

    original = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)
    on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, original) end)
    directory = Path.expand("tmp/utilities-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "image transformations produce the expected files and retain the source", %{directory: directory} do
    source = Path.join(directory, "source 雪.png")

    data =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAYAAAD/Rn+7AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAKKADAAQAAAABAAAAFAAAAAA9/xERAAAAJklEQVRIDe3QMQEAAADCoPVPbQwfiEBhwIABAwYMGDBgwICB38AADJQAAbDKUmwAAAAASUVORK5CYII="
      )

    File.write!(source, data)
    assert {:ok, %{dimensions: [40, 20], file_type: "PNG"}} = ImageEvents.info(source)

    for {name, transform, dimensions, format} <- [
          {"scale.png", &ImageEvents.scale(&1, &2, 10), [10, 5], "PNG"},
          {"rotate.png", &ImageEvents.rotate(&1, &2, 90), [20, 40], "PNG"},
          {"crop.png", &ImageEvents.crop(&1, &2, [10, 10]), [10, 10], "PNG"},
          {"flip.png", &ImageEvents.flip(&1, &2, :horizontal), [40, 20], "PNG"},
          {"convert.jpg", &ImageEvents.convert(&1, &2, "JPEG"), [40, 20], "JPEG"}
        ] do
      destination = Path.join(directory, name)
      assert :ok = transform.(source, destination)
      assert {:ok, %{dimensions: ^dimensions, file_type: ^format}} = ImageEvents.info(destination)
      assert File.read!(source) == data
      assert {:error, _} = transform.(source, destination)
    end
  end

  test "Terminal commands create a window and can then target its existing tab", %{directory: directory} do
    assert {:ok, before} = Terminal.list_sessions()
    original_ids = MapSet.new(before, & &1.window_id)
    marker = Path.join(directory, "first")
    second = Path.join(directory, "second")

    assert :ok = Terminal.do_script("printf first > '#{marker}'")
    assert :ok = Wait.until(fn -> File.exists?(marker) end, timeout: 5000)
    assert {:ok, after_sessions} = Terminal.list_sessions()
    assert [session] = Enum.reject(after_sessions, &MapSet.member?(original_ids, &1.window_id))
    assert {:ok, %{text: text}} = Terminal.read_session(session.window_id, session.tab_index)
    assert text =~ "printf first"

    on_exit(fn ->
      Automation.action("com.apple.Terminal", "app.close(byId(app.windows,input.id),{saving:'no'});", %{
        id: session.window_id
      })
    end)

    assert :ok =
             Terminal.do_script("printf second > '#{second}'",
               window_id: session.window_id,
               tab_index: session.tab_index
             )

    assert :ok = Wait.until(fn -> File.exists?(second) end, timeout: 5000)
    assert File.read!(second) == "second"
    assert {:error, _} = Terminal.do_script("must not execute", new_tab: true)
  end

  test "Calendar discovery returns IDs that resolve to the same calendars" do
    assert {:ok, calendars} = Calendar.list_calendars(timeout: 5000)

    for calendar <- calendars do
      assert is_binary(calendar.id) and calendar.id != ""

      assert {:ok, true} =
               Automation.query(
                 "com.apple.iCal",
                 "return byId(app.calendars,input.id).name()===input.name;",
                 %{id: calendar.id, name: calendar.name},
                 timeout: 5000
               )
    end
  end

  test "Messages account discovery tolerates unavailable service type properties" do
    assert {:ok, accounts} = Messages.list_accounts(timeout: 5000)

    for account <- accounts do
      assert is_binary(account.id)
      assert is_boolean(account.enabled)
      assert is_nil(account.service_type) or is_binary(account.service_type)
    end
  end
end
