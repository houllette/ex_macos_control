defmodule ExMacOSControl.AppNameIntegrationTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{AppName, OSAScriptAdapter}

  @moduletag :integration
  @moduletag :desktop
  @moduletag skip: "Adapt the placeholder app and prepare an isolated macOS desktop before enabling"

  setup do
    previous = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)
    on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, previous) end)
    :ok
  end

  test "reads the real installed app's name" do
    assert {:ok, "AppName"} = AppName.name(timeout: 5_000)
  end
end
