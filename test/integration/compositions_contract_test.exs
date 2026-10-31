defmodule ExMacOSControl.CompositionsContractTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Applications, ImageEvents, OSAScriptAdapter, Reminders, Safari, Script}
  alias ExMacOSControl.Safari.Page
  @moduletag :integration
  setup :verify_on_exit!

  test "Safari extraction and field editing execute in the native JXA engine against an isolated DOM fixture" do
    text = "quotes\" 雪\n<script>\u2028\u2029"

    fixture = """
    function Event(name,options){this.type=name;this.bubbles=options.bubbles;}
    var values={field:'old',events:[]};
    var proto={};Object.defineProperty(proto,'value',{
      get:function(){return values.field;},set:function(value){values.field=value;}
    });
    var field=Object.create(proto);field.dispatchEvent=function(event){values.events.push(event.type);};
    var location={href:'https://example.invalid/'};
    var window={getSelection:function(){return 'Selected';}};
    var document={readyState:'complete',title:'Title',body:{innerText:'Body'},querySelector:function(selector){
      if(selector==='#field')return field;
      if(selector==='#text')return {textContent:#{Jason.encode!(text)},getAttribute:function(){return 'attribute';}};
      return null;
    }};
    document.querySelectorAll=function(selector){var e=document.querySelector(selector);return e?[e]:[];};
    var tab={exists:function(){return true;}};
    var fixture={windows:function(){return [{id:function(){return 42;},tabs:function(){return [tab];}}];},doJavaScript:function(code,options){
      if(options.in!==tab)throw new Error('Wrong tab');
      // Each native execution starts with a fresh fixture. The verification
      // query sees the committed field value from the preceding action.
      if(code.indexOf('e.value===input.value')>=0)values.field=#{Jason.encode!(text)};
      var result=eval(code);
      if(code.indexOf('descriptor.set.call')>=0){
        if(values.field!==#{Jason.encode!(text)}||values.events.join(',')!=='input,change')throw new Error('Field events missing');
      }
      return result;
    }};
    """

    stub_native(fixture)
    page = %Page{window_id: 42, tab_index: 1, owned: true}
    assert {:ok, ^text} = Safari.text(page, "#text")
    assert {:ok, "attribute"} = Safari.attribute(page, "#text", "title")
    assert {:ok, %{"chosen" => ^text}} = Safari.extract(page, %{"chosen" => "#text"})

    assert {:ok, %{"title" => ^text, "__proto__" => ^text}} =
             Safari.extract(page, %{"title" => "#text", "__proto__" => "#text"})

    assert {:ok, %{selection: "Selected", title: "Title"}} = Safari.snapshot(page)
    assert :ok = Safari.fill(page, "#field", text)
  end

  test "owned window cleanup refuses to close unrelated added tabs" do
    stub_native("""
    var fixture={windows:function(){return [{id:function(){return 42;},tabs:function(){return [{},{}];}}];},
      close:function(){throw new Error('Must not close unrelated tabs');}};
    """)

    assert {:error, error} = Safari.close_page(%Page{window_id: 42, tab_index: 1, owned: true})
    assert error.message =~ "additional tabs"
    refute error.message =~ "Must not close"
  end

  test "closing an already closed owned window is a no-op despite stale native specifiers" do
    stub_native("""
    var fixture={windows:function(){return [];},close:function(){throw new Error('Must not close another window');}};
    """)

    assert :ok = Safari.close_page(%Page{window_id: 42, tab_index: 1, owned: true})
  end

  test "stale DOM targets cannot fall through to another window" do
    stub_native("""
    var fixture={windows:function(){return [{id:function(){return 99;},tabs:function(){return [{}];}}];},
      doJavaScript:function(){throw new Error('Must not inspect another window');}};
    """)

    assert {:error, error} = Safari.text(%Page{window_id: 42, tab_index: 1}, "#field")
    assert error.message =~ "Safari window not found"
    refute error.message =~ "Must not inspect"
  end

  test "native closed-window placeholders with null tabs are never operated on" do
    stub_native("""
    var fixture={windows:function(){return [{id:function(){return 42;},tabs:function(){return null;}}];},
      close:function(){throw new Error('Must not close a placeholder');},
      doJavaScript:function(){throw new Error('Must not inspect a placeholder');}};
    """)

    assert :ok = Safari.close_page(%Page{window_id: 42, tab_index: 1, owned: true})
    assert {:error, error} = Safari.text(%Page{window_id: 42, tab_index: 1}, "#field")
    assert error.message =~ "no tabs"
  end

  test "reminder paging uses bulk columns and preserves dates and booleans" do
    stub_native("""
    var values={id:['first','second'],name:['First','Second'],body:[null,'Body'],completed:[false,true],
      dueDate:[null,new Date('2026-11-01T12:00:00Z')],remindMeDate:[null,null],priority:[0,2],flagged:[false,false]};
    var reminders={};Object.keys(values).forEach(function(k){reminders[k]=function(){return values[k];};});
    var fixture={lists:{byId:function(id){if(id!=='owned-list')throw new Error('Wrong list');return {
      exists:function(){return true;},reminders:reminders};}}};
    """)

    assert {:ok,
            [
              %{
                id: "second",
                title: "Second",
                completed: true,
                flagged: false,
                due_at: "2026-11-01T12:00:00.000Z",
                reminder_at: nil
              }
            ]} = Reminders.list_reminders("owned-list", limit: 1, offset: 1)
  end

  test "scoped reminder completion compiles explicit ID references and independently verifies native flags" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, opts ->
      assert opts[:args] == ["owned-list", "first", "second"]
      assert source =~ "set knownIDs to id of every reminder of targetList"
      assert source =~ "set completed of reminder id (wantedID as text) of targetList to true"
      assert source =~ "return \"EXMC_MISSING\""
      assert :ok = Script.validate(source)
      {:ok, "2"}
    end)

    stub_native("""
    var fixture={lists:{byId:function(){return {exists:function(){return true;},reminders:{
      id:function(){return ['first','second','untouched'];},completed:function(){return [true,true,false];}}};}}};
    """)

    assert {:ok, ["first", "second"]} = Reminders.complete_many(["first", "second"], list_id: "owned-list")
  end

  test "image operations preserve order and save once in the native engine" do
    directory = Path.expand("tmp/image-contract-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "input.png")
    File.write!(path, "synthetic")
    on_exit(fn -> File.rm_rf(directory) end)

    stub_native("""
    var operations=[],image={};
    var fixture={open:function(){return image;},
      scale:function(o,opts){if(o!==image||opts.toSize!==800)throw new Error('scale');operations.push('scale');},
      rotate:function(o,opts){if(opts.toAngle!==90)throw new Error('rotate');operations.push('rotate');},
      crop:function(o,opts){if(opts.toDimensions.join(',')!=='100,200')throw new Error('crop');operations.push('crop');},
      flip:function(o,opts){if(opts.horizontal!==true)throw new Error('flip');operations.push('flip');},
      save:function(o,opts){if(operations.join(',')!=='scale,rotate,crop,flip'||opts.as!=='JPEG')throw new Error('save');operations.push('save');},
      close:function(o){if(o!==image||operations.join(',')!=='scale,rotate,crop,flip,save')throw new Error('close');}};
    """)

    assert :ok =
             ImageEvents.process(
               path,
               Path.join(directory, "output.jpg"),
               [scale: 800, rotate: 90, crop: [100, 200], flip: :horizontal],
               format: "JPEG"
             )
  end

  test "application identity and running PID are resolved through native AppKit without launching an app" do
    stub(ExMacOSControl.AdapterMock, :run_javascript, &OSAScriptAdapter.run_javascript/2)

    assert {:ok, %{bundle_id: "com.apple.finder", path: path, running: running, pid: pid}} =
             Applications.status("com.apple.finder")

    assert String.ends_with?(path, "/Finder.app")
    assert is_boolean(running)
    if running, do: assert(is_integer(pid) and pid > 0), else: assert(is_nil(pid))
  end

  test "owned-window creation AppleScript compiles without opening any window" do
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn source, _ ->
      assert :ok = Script.validate(source)
      {:ok, "42"}
    end)

    assert {:ok, %Page{owned: true, window_id: 42}} = Safari.open_page("https://example.invalid")
  end

  defp stub_native(fixture) do
    stub(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      source =
        String.replace(
          source,
          "var app = input.__bundle_id ? Application(input.__bundle_id) : Application.currentApplication();",
          "var app=fixture;"
        )

      OSAScriptAdapter.run_javascript(fixture <> source, opts)
    end)
  end
end
