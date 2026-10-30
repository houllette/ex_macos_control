defmodule ExMacOSControl.TerminalTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Error, Terminal}
  setup :verify_on_exit!

  test "refuses unsupported tab creation and invalid targets before dispatching a shell command" do
    for opts <- [
          [new_tab: true],
          [new_tab: nil],
          [window_id: nil],
          [window_id: false],
          [window_id: -1],
          [window_id: "1"],
          [window_id: 1, tab_index: 0],
          [window_id: 1, tab_index: "1"],
          [tab_index: 1]
        ] do
      assert {:error, %Error{}} = Terminal.do_script("must not run", opts)
    end

    assert {:error, %Error{}} = Terminal.read_session(nil, 1)
    assert {:error, %Error{}} = Terminal.read_session(1, 0)
  end

  test "targets an existing tab and passes shell text only as data" do
    command = "printf '%s' \"quoted 雪\""

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      refute source =~ command
      refute source =~ "doScriptInNewTab"
      assert source =~ "app.doScript(input.command,options)"
      assert opts[:timeout] == 1234

      assert %{"window_id" => 42, "tab_index" => 2, "command" => ^command} =
               opts[:args] |> hd() |> Jason.decode!()

      {:ok, ~s({"exmc":1,"result":true})}
    end)

    assert :ok = Terminal.do_script(command, window_id: 42, tab_index: 2, timeout: 1234)
  end
end
