defmodule ExMacOSControl.Desktop.Session.Native do
  @moduledoc false
  @behaviour ExMacOSControl.Desktop.Session
  alias ExMacOSControl.{Applications, Automation, Composition, Error, Wait}

  @managed ~w(com.apple.Notes com.apple.reminders com.apple.iCal com.apple.AddressBook com.apple.mail com.apple.Photos com.apple.Music com.apple.TV com.apple.systempreferences com.apple.MobileSMS)
  @readiness ~w(com.apple.reminders com.apple.iCal)
  @process """
  ObjC.import('AppKit');
  function process(id){var values=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($(id));
    if(Number(values.count)>1)throw new Error('Ambiguous application instance');
    var p=values.firstObject;if(p.isNil())return null;
    return {pid:Number(p.processIdentifier),started:Number(p.launchDate.timeIntervalSince1970)};}
  function bundleId(id){var ws=$.NSWorkspace.sharedWorkspace,url=ws.URLForApplicationWithBundleIdentifier($(id));
    if(!url.isNil())return ObjC.unwrap($.NSBundle.bundleWithURL(url).bundleIdentifier);
    var path=ObjC.unwrap(ws.fullPathForApplication($(id)));if(!path && id.charAt(0)==='/')path=id;
    if(!path)return id;var bundle=$.NSBundle.bundleWithPath($(path));return bundle.isNil()?id:ObjC.unwrap(bundle.bundleIdentifier);}
  function windows(id){var app=Application(id),result=[];
    app.windows().forEach(function(w){try{if(w.exists()){var id=w.id();if(!result.some(function(row){return row.id===id;}))result.push({id:id});}}
      catch(error){if(error.errorNumber!==-1728 && !/Can't get object|not found/i.test(String(error.message)))throw error;}});return result;}
  """

  @impl true
  def snapshot(identities) do
    Automation.query(
      nil,
      @process <>
        """
        var front=$.NSWorkspace.sharedWorkspace.frontmostApplication;
        var result={focus:front.isNil()?null:ObjC.unwrap(front.bundleIdentifier),focus_process:front.isNil()?null:{pid:Number(front.processIdentifier),started:Number(front.launchDate.timeIntervalSince1970)},apps:{}};
        input.identities.forEach(function(id){var resolved=bundleId(id),p=process(resolved);result.apps[id]={bundle_id:resolved,process:p,windows:p && input.managed.indexOf(resolved)>=0?windows(resolved):[]};});
        return result;
        """,
      %{identities: identities, managed: @managed}
    )
  end

  @impl true
  def prepare(identity, before) do
    app = before["apps"][identity]
    identity = app[:bundle_id] || identity

    cond do
      identity not in @managed -> {:ok, []}
      app["process"] == nil or (identity in @readiness and app["windows"] == []) -> open_and_capture(identity, app)
      true -> {:ok, []}
    end
  end

  defp open_and_capture(identity, before) do
    with {:ok, _} <- Applications.open(identity, background: true),
         {:ok, current} <- ready_windows(identity) do
      prior = Enum.map(before["windows"], & &1.id)

      refs =
        current["windows"]
        |> Enum.reject(&(&1.id in prior))
        |> Enum.map(&%{bundle_id: identity, window_id: &1.id, process: current["process"]})

      {:ok, refs}
    end
  end

  defp ready_windows(identity) do
    key = make_ref()

    try do
      with :ok <- Wait.until(fn -> window_ready(identity, key) end, timeout: 5000), do: {:ok, Process.get(key)}
    after
      Process.delete(key)
    end
  end

  defp window_ready(identity, key) do
    with {:ok, snapshot} <- snapshot([identity]) do
      current = snapshot["apps"][identity]
      Process.put(key, current)
      current["process"] != nil and current["windows"] != []
    end
  end

  @impl true
  def close(ref) do
    with :ok <-
           Composition.effect(:close_support_window, fn -> close_native(ref) end,
             resource: :window,
             identity: %{window_id: ref.window_id, application_pid: ref.process.pid}
           ),
         do: Composition.verify(:support_window_closed, &closed?(ref, &1))
  end

  defp close_native(ref) do
    case Automation.query(
           nil,
           @process <>
             """
             var p=process(input.bundle_id);if(p===null)return true;
             if(p.pid!==input.process.pid || p.started!==input.process.started)throw new Error('Application instance changed; preserving window');
             var app=Application(input.bundle_id),matches=app.windows().filter(function(w){return w.id()===input.window_id;});
             if(matches.length===0)return true;
             if(matches.length!==1)throw new Error('Ambiguous support window');
             var w=app.windows.byId(input.window_id);
             if(input.bundle_id==='com.apple.mail'){
               var subjects=app.outgoingMessages.subject();
               if(subjects.indexOf(w.name())>=0)throw new Error('Mail compose window is not a support window');
             }
             try{if(w.modified())return false;}catch(error){if(error.errorNumber===-1743 || /permission|not authorized/i.test(String(error.message)))throw error;}
             app.close(w,{saving:'yes'});
             return true;
             """,
           ref
         ) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error, Error.execution_error("Support window is modified or remains open", window_id: ref.window_id)}

      error ->
        error
    end
  end

  defp closed?(ref, remaining) do
    Automation.query(
      nil,
      @process <>
        """
        var p=process(input.bundle_id);
        if(p===null || p.pid!==input.process.pid || p.started!==input.process.started)return true;
        var app=Application(input.bundle_id);
        if(app.windows.id().indexOf(input.window_id)<0)return true;
        var w=app.windows.byId(input.window_id);return !w.exists() || !w.visible();
        """,
      ref,
      timeout: remaining
    )
  end

  @impl true
  def restore(before) do
    Automation.action(
      nil,
      @process <>
        """
        var front=$.NSWorkspace.sharedWorkspace.frontmostApplication;
        if(front.isNil() || !input.focus)return true;
        var id=ObjC.unwrap(front.bundleIdentifier);
        if(Object.keys(input.apps).every(function(key){return (input.apps[key].bundle_id||key)!==id;}))return true;
        var values=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($(input.focus));
        if(Number(values.count)===1 && input.focus_process){var previous=values.firstObject;
        if(Number(previous.processIdentifier)===input.focus_process.pid && Number(previous.launchDate.timeIntervalSince1970)===input.focus_process.started)previous.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);}
        """,
      %{focus: before["focus"], focus_process: before["focus_process"], apps: before["apps"]}
    )
  end
end
