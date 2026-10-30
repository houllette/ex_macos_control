defmodule ExMacOSControl.AppCompatibilityContractTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Calendar, Messages, OSAScriptAdapter}
  @moduletag :integration
  setup :verify_on_exit!

  test "Calendar recovers a quoted stable ID from a native object reference" do
    id = "quoted\" \\ 雪 )"
    fixture = calendar_fixture(-1700, ~s|Application("Calendar").calendars.byId(#{Jason.encode!(id)})|)
    {source, opts} = capture(&Calendar.list_calendars/0)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
    assert %{"result" => [%{"id" => ^id, "name" => "Synthetic", "writable" => true}]} = Jason.decode!(output)
  end

  test "Calendar does not hide permission failures or invent IDs from names" do
    {source, opts} = capture(&Calendar.list_calendars/0)

    for {number, spec} <- [
          {-1743, ~s|Application("Calendar").calendars.byName("denied")|},
          {-10_000, ~s|Application("Calendar").calendars.byName("ambiguous")|}
        ] do
      assert {:error, _} = OSAScriptAdapter.run_javascript(calendar_fixture(number, spec) <> source, opts)
    end
  end

  test "Messages accounts retain supported service types and mark unavailable ones as null" do
    fixture = """
    var fixture={accounts:function(){return [
      {id:function(){return 'legacy';},description:function(){return null;},enabled:function(){return false;},
       serviceType:function(){var e=new Error('unavailable');e.errorNumber=-10000;throw e;}},
      {id:function(){return 'current';},description:function(){return 'Synthetic';},enabled:function(){return true;},
       serviceType:function(){return 'iMessage';}}
    ];}};
    """

    {source, opts} = capture(&Messages.list_accounts/0)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)

    assert %{"result" => [%{"service_type" => nil}, %{"service_type" => "iMessage"}]} = Jason.decode!(output)
  end

  test "Messages does not hide permission failures in service type reads" do
    fixture = """
    var fixture={accounts:function(){return [
      {id:function(){return 'id';},description:function(){return 'Synthetic';},enabled:function(){return true;},
       serviceType:function(){var e=new Error('denied');e.errorNumber=-1743;throw e;}}
    ];}};
    """

    {source, opts} = capture(&Messages.list_accounts/0)
    assert {:error, _} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
  end

  defp capture(call) do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      send(self(), {:source, source, opts})
      {:ok, ~s({"exmc":1,"result":[]})}
    end)

    call.()
    assert_receive {:source, source, opts}

    source =
      source
      |> String.replace(
        "var app = input.__bundle_id ? Application(input.__bundle_id) : Application.currentApplication();",
        "var app = fixture;"
      )
      |> String.replace("Automation.getDisplayString(o)", "fixtureDisplayString(o)")

    refute source =~ "Application("
    {source, opts}
  end

  defp calendar_fixture(number, spec) do
    """
    var fixtureDisplayString=function(){return #{Jason.encode!(spec)};};
    var fixture={calendars:function(){return [{
      calendarIdentifier:function(){var e=new Error('unavailable');e.errorNumber=#{number};throw e;},
      name:function(){return 'Synthetic';},writable:function(){return true;}
    }];}};
    """
  end
end
