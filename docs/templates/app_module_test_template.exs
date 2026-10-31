defmodule ExMacOSControl.AppNameTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{AdapterMock, AppName, Error}
  setup :verify_on_exit!

  test "addresses the app by bundle ID and preserves execution options" do
    expect(AdapterMock, :run_javascript, fn script, opts ->
      assert script == "Application('com.example.AppName').name()"
      assert opts[:timeout] == 5_000
      {:ok, "AppName"}
    end)

    assert {:ok, "AppName"} = AppName.name(timeout: 5_000)
  end

  test "preserves structured errors without retry" do
    error = Error.permission_denied("Automation denied")
    expect(AdapterMock, :run_javascript, fn _script, _opts -> {:error, error} end)
    assert {:error, ^error} = AppName.name(timeout: 5_000)
  end
end
