defmodule ExMacOSControl.AppCompatibilityContractTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.{
    Accessibility,
    Calendar,
    Media,
    Messages,
    OSAScriptAdapter,
    QualificationFixture,
    QuickTime,
    Terminal
  }

  alias ExMacOSControl.Qualification.Native
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

  test "Calendar reads events by stable ID without an unsupported UID filter" do
    for call <- [
          fn -> Calendar.get_event("calendar", "event") end,
          fn -> Calendar.list_attendees("calendar", "event") end
        ] do
      {source, opts} = capture(call)
      assert {:ok, output} = OSAScriptAdapter.run_javascript(mutable_calendar_fixture() <> source, opts)
      assert %{"exmc" => 1} = Jason.decode!(output)
    end
  end

  test "Calendar mutations use indexed native references and verify event removal" do
    for call <- [fn -> Calendar.delete_calendar("calendar") end, fn -> Calendar.delete_event("calendar", "event") end] do
      {source, opts} = capture(call)
      assert {:ok, output} = OSAScriptAdapter.run_javascript(mutable_calendar_fixture() <> source, opts)
      assert %{"result" => true} = Jason.decode!(output)
    end

    {source, opts} = capture(fn -> Calendar.delete_event("calendar", "event") end)

    assert {:error, error} =
             OSAScriptAdapter.run_javascript(mutable_calendar_fixture(true) <> source, opts)

    assert error.message =~ "Calendar did not delete the event"
  end

  test "Music and TV create user playlists with the native make command" do
    fixture = """
    var fixture={make:function(options){
      if(options.new!=='userPlaylist'||options.withProperties.name!=='Synthetic')throw new Error('Invalid playlist creation');
      return {persistentID:function(){return 'persistent';}};
    }};
    """

    for bundle <- ["com.apple.Music", "com.apple.TV"] do
      {source, opts} = capture(fn -> Media.create_playlist(bundle, "Synthetic", []) end)
      assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
      assert %{"result" => "persistent"} = Jason.decode!(output)
    end
  end

  test "QuickTime screen recording accepts a native handoff without a document" do
    {source, opts} = capture(fn -> QuickTime.new_recording(:screen) end)

    assert {:ok, output} =
             OSAScriptAdapter.run_javascript("var fixture={newScreenRecording:function(){}};" <> source, opts)

    assert %{"result" => nil} = Jason.decode!(output)
  end

  test "Terminal session discovery skips native windows without a tab collection" do
    fixture = """
    var fixture={windows:function(){return [
      {id:function(){return 1;},tabs:function(){return null;}},
      {id:function(){return 2;},tabs:function(){return [
        {customTitle:function(){return 'Synthetic';},busy:function(){return false;}}
      ];}}
    ];}};
    """

    {source, opts} = capture(&Terminal.list_sessions/0)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
    assert %{"result" => [%{"window_id" => 2, "tab_index" => 1, "title" => "Synthetic"}]} = Jason.decode!(output)
  end

  test "Notes ownership rejects matching titles when a global ID resolves outside the fixture folder" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))
    context = %{id: "note", marker: "EXMC-QA-run"}

    for {container, expected} <- [{"qa-folder", true}, {"another-folder", false}] do
      {source, opts} = capture(fn -> Native.observe(:notes_get, manifest, context, []) end)
      assert {:ok, output} = OSAScriptAdapter.run_javascript(notes_fixture(container) <> source, opts)
      assert %{"result" => ^expected} = Jason.decode!(output)
    end
  end

  test "Notes absence uses folder membership even when a deleted global ID still exists" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))
    {source, opts} = capture(fn -> Native.observe(:notes_absent, manifest, %{id: "note"}, []) end)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(notes_fixture("recently-deleted") <> source, opts)
    assert %{"result" => true} = Jason.decode!(output)
  end

  test "accessibility PID targets keep their predicate when native references share a process name" do
    fixture = """
    function process(title){return {attributes:{byName:function(name){return {
      exists:function(){return true;},value:function(){return title;}
    };}}};}
    var intended=process('intended'),other=process('other');
    function matches(){return [other];}
    Object.defineProperty(matches,'length',{value:1});
    matches[0]=intended;
    var fixture={processes:{whose:function(predicate){
      if(predicate.unixId!==42)throw new Error('Wrong PID');return matches;
    }}};
    """

    {source, opts} = capture(fn -> Accessibility.get_attribute(42, [], "AXTitle") end)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
    assert %{"result" => "intended"} = Jason.decode!(output)
  end

  test "accessibility selectors and trees keep child references scoped to the intended process" do
    fixture = """
    function collection(intended,other){
      function values(){return other;}
      Object.defineProperty(values,'length',{value:intended.length});
      intended.forEach(function(o,i){values[i]=o;});return values;
    }
    function node(role,title,children){return {
      attributes:{name:function(){return ['AXRole','AXTitle'];},byName:function(name){return {
        exists:function(){return name==='AXRole'||name==='AXTitle';},
        value:function(){return name==='AXRole'?role:title;}
      };}},actions:{name:function(){return [];}},uiElements:children
    };}
    var leaf=collection([],[]),intendedWindow=node('AXWindow','intended',leaf),otherWindow=node('AXWindow','other',leaf);
    var intended=node('AXApplication','intended process',collection([intendedWindow],[otherWindow]));
    var fixture={processes:{whose:function(){return collection([intended],[intended]);}}};
    """

    {source, opts} = capture(fn -> Accessibility.get_attribute(42, [%{role: "AXWindow"}], "AXTitle") end)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
    assert %{"result" => "intended"} = Jason.decode!(output)

    {source, opts} = capture(fn -> Accessibility.tree(42, depth: 1) end)
    assert {:ok, output} = OSAScriptAdapter.run_javascript(fixture <> source, opts)
    assert %{"result" => %{"children" => [%{"title" => "intended"}]}} = Jason.decode!(output)
  end

  test "accessibility key delivery checks the actual foreground PID when System Events reports false" do
    for mode <- [:active, :activate] do
      {source, opts} = capture(fn -> Accessibility.press_key_code(42, 5, using: [:command, :shift]) end)
      assert {:ok, output} = OSAScriptAdapter.run_javascript(focus_fixture(source, mode), opts)
      assert %{"result" => true} = Jason.decode!(output)
    end
  end

  test "accessibility withholds keys when another process retains focus" do
    {source, opts} = capture(fn -> Accessibility.press_key_code(42, 5, using: [:command, :shift]) end)
    assert {:error, error} = OSAScriptAdapter.run_javascript(focus_fixture(source, :refused), opts)
    assert error.message =~ "Target process did not become frontmost"
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

  defp focus_fixture(source, mode) do
    source = String.replace(source, "function run(argv)", "function fixtureRun(ObjC,$,argv)")

    """
    var front=#{if mode == :active, do: 42, else: 17};
    var target={unixId:function(){return 42;},frontmost:function(){return false;}};
    var fixture={processes:{whose:function(){return [target];}},keyCode:function(code,options){
      if(front!==42)throw new Error('Keys delivered to another process');
      if(code!==5||JSON.stringify(options.using)!=='["command down","shift down"]')throw new Error('Wrong keys');
    }};
    var bridge={NSRunningApplication:{runningApplicationWithProcessIdentifier:function(pid){
      if(pid!==42)throw new Error('Wrong activation target');return {
        isNil:function(){return false;},activateWithOptions:function(){if(#{mode != :refused})front=42;}
      };
    }},NSWorkspace:{sharedWorkspace:{}},NSThread:{sleepForTimeInterval:function(){}},NSApplicationActivateIgnoringOtherApps:2};
    Object.defineProperty(bridge.NSWorkspace.sharedWorkspace,'frontmostApplication',{get:function(){return {
      isNil:function(){return false;},processIdentifier:front
    };}});
    #{source}
    function run(argv){return fixtureRun({import:function(){}},bridge,argv);}
    """
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

  defp mutable_calendar_fixture(retain_event \\ false) do
    """
    var removed=false;
    var event={uid:function(){return 'event';},exists:function(){return true;},summary:function(){return 'Synthetic';},
      startDate:function(){return new Date('2030-01-01T10:00:00Z');},endDate:function(){return new Date('2030-01-01T11:00:00Z');},
      alldayEvent:function(){return false;},description:function(){return '';},location:function(){return '';},
      recurrence:function(){return '';},url:function(){return '';},attendees:function(){return [];}};
    function events(){return removed?[]:[event];}
    events.byId=function(id){if(id!=='event')throw new Error('Wrong event');return event;};
    events.whose=function(){throw new Error('UID filters unsupported');};
    events[0]={indexed:true,kind:'event'};
    var calendar={exists:function(){return true;},events:events,writable:function(){return true;}};
    var indexedCalendar={indexed:true,kind:'calendar',events:events,writable:function(){return true;}};
    function calendars(){return [calendar];}
    calendars.byId=function(id){if(id!=='calendar')throw new Error('Wrong calendar');return calendar;};
    calendars[0]=indexedCalendar;
    var fixtureDisplayString=function(){return '.calendars.byId("calendar")';};
    var fixture={calendars:calendars,delete:function(o){
      if(!o.indexed)throw new Error('Mutation requires indexed reference');
      if(o.kind==='event'&&!#{retain_event})removed=true;
    }};
    """
  end

  defp notes_fixture(container) do
    """
    var note={exists:function(){return true;},name:function(){return 'EXMC-QA-run';},
      container:function(){return {id:function(){return #{Jason.encode!(container)};}};}};
    function notes(){return [];}
    notes.byId=function(){return note;};
    var folder={exists:function(){return true;},notes:notes};
    var fixture={folders:{byId:function(){return folder;}}};
    """
  end
end
