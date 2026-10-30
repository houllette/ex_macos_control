defmodule ExMacOSControl.ApplicationsTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Applications, Error}
  setup :verify_on_exit!

  test "already-running applications are neither launched nor activated" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["identity"] == "com.example.app"
      response(app(true))
    end)

    assert {:ok, %{pid: 42, running: true}} = Applications.ensure_running("com.example.app")
  end

  test "launch is performed once, followed by observed process readiness" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(app(false)) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ ".launch()"
      assert input(opts)["id"] == "com.example.app"
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(app(true)) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(app(true)) end)
    assert {:ok, %{pid: 42}} = Applications.ensure_running("Synthetic")
  end

  test "foreground callbacks restore the previous PID after exceptions" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(7) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(app(true)) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["pid"] == 42
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(42) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["pid"] == 7
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(7) end)

    assert_raise RuntimeError, "callback", fn ->
      Applications.with_frontmost("Synthetic", fn %{pid: 42} -> raise "callback" end)
    end
  end

  test "an uncertain activation still restores previous focus and never runs user work" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(7) end)
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(app(true)) end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:error, Error.timeout("activation", outcome: :unknown)}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      assert input(opts)["pid"] == 7
      response(true)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(7) end)

    assert {:error, %Error{type: :timeout}} =
             Applications.with_frontmost("Synthetic", fn _ -> flunk("activation failed") end)
  end

  test "quit is a no-op when the app is absent and invalid input does not dispatch" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(app(false)) end)
    assert :ok = Applications.quit_if_running("Synthetic")
    assert {:error, %Error{}} = Applications.ensure_running("")
  end

  defp app(running),
    do: %{bundle_id: "com.example.app", path: "/Applications/Synthetic.app", running: running, pid: if(running, do: 42)}

  defp input(opts), do: opts[:args] |> hd() |> Jason.decode!()
  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
