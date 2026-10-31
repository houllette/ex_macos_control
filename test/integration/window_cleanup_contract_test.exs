defmodule ExMacOSControl.WindowCleanupContractTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.Desktop.Session.Native
  alias ExMacOSControl.OSAScriptAdapter
  setup :verify_on_exit!
  @moduletag :integration

  test "native runner closes only its unchanged, idle, single-tab window" do
    for changes <- [
          %{},
          %{pid: 999},
          %{started: 999},
          %{tty: "other"},
          %{title: "changed"},
          %{extra_tab: true},
          %{busy: true}
        ] do
      result = run_fixture(changes)

      if changes == %{} do
        assert result["ok"] and result["closes"] == 1, inspect(result)
      else
        refute result["ok"]
        assert result["closes"] == 0
      end
    end
  end

  test "closed native window placeholders are accepted without closing anything else" do
    assert %{"ok" => true, "closes" => 0} = run_fixture(%{closed: true})
    assert %{"ok" => true, "closes" => 1} = run_fixture(%{stale_after_close: true})
  end

  test "native UI snapshots resolve app names without launching or reading unmanaged app windows" do
    stub(ExMacOSControl.AdapterMock, :run_javascript, &OSAScriptAdapter.run_javascript/2)
    assert {:ok, snapshot} = Native.snapshot(["Finder"])
    assert snapshot["apps"]["Finder"].bundle_id == "com.apple.finder"
    assert snapshot["apps"]["Finder"]["windows"] == []
  end

  defp run_fixture(changes) do
    defaults = %{
      pid: 10,
      started: 20,
      tty: "/dev/test",
      title: "owned",
      extra_tab: false,
      busy: false,
      closed: false,
      stale_after_close: false
    }

    data = Map.merge(defaults, changes)

    source =
      File.read!("priv/gui/window.js")
      |> String.replace("function run(argv)", "function runFixture(argv)")
      |> String.replace("var app=Application('com.apple.Terminal')", "var app=fixture")
      |> String.replace("delay(", "fixtureDelay(")

    fixture = """
    var config=#{Jason.encode!(data)},state={closed:config.closed,closes:0},captured;
    var tab={tty:function(){return config.tty;},customTitle:function(){return config.title;},busy:function(){return config.busy;}};
    var w={exists:function(){if(state.closed && config.stale_after_close)throw new Error("Can't get object.");return !state.closed;},
      tabs:function(){return config.extra_tab?[tab,{}]:[tab];}};
    var windows=function(){return state.closed?[]:[w];};windows.byId=function(){return w;};
    var fixture={windows:windows,close:function(o){if(o!==w)throw new Error('Wrong target');state.closes++;state.closed=true;}};
    function fixtureDelay(){};
    instance=function(){return {pid:config.pid,started:config.started};};
    read=function(path){return path==='request'?{token:'token',owner:'owner',cleanup:'cleanup',keep_window:false}:
      {token:'token',pid:10,started:20,window_id:42,tty:'/dev/test',title:'owned'};};
    write=function(path,value){captured=value;};
    runFixture(['close','request']);captured.closes=state.closes;JSON.stringify(captured);
    """

    assert {:ok, output} = OSAScriptAdapter.run_javascript(source <> fixture, timeout: 5000)
    Jason.decode!(output)
  end
end
