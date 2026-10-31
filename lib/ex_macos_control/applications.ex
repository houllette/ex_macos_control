defmodule ExMacOSControl.Applications do
  @moduledoc """
  Application lifecycle compositions addressed by bundle ID, app name or path.

  Readiness means a running process exists, not that documents or account data
  have loaded. `ensure_running/2` does not activate an already running app.
  `with_frontmost/3` serializes foreground work and restores the previous app
  when it still exists; it never quits an application.
  """
  alias ExMacOSControl.{Automation, Command, Composition, Desktop, Error, Wait}

  @doc "Resolves an installed application and reports its running process without launching it."
  def status(identity, opts \\ []) do
    with :ok <- Automation.required_string(identity, "Application identity") do
      Automation.query(
        nil,
        """
        ObjC.import('AppKit');
        var ws=$.NSWorkspace.sharedWorkspace;
        var url=ws.URLForApplicationWithBundleIdentifier($(input.identity));
        var path=url.isNil() ? ObjC.unwrap(ws.fullPathForApplication($(input.identity))) : ObjC.unwrap(url.path);
        if(!path && /^\\//.test(input.identity) && /\\.app$/.test(input.identity))path=input.identity;
        if(!path)throw new Error('Application not found');
        var bundle=$.NSBundle.bundleWithPath($(path));
        if(bundle.isNil())throw new Error('Application not found');
        var id=ObjC.unwrap(bundle.bundleIdentifier);
        if(!id)throw new Error('Application not found');
        var apps=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($(id));
        if(apps.count>1)throw new Error('Ambiguous application process');
        var process=apps.firstObject;
        return {bundle_id:id,path:path,running:!process.isNil(),pid:process.isNil()?null:Number(process.processIdentifier)};
        """,
        %{identity: identity},
        opts
      )
    end
  end

  @doc "Launches only if needed and waits for a running process; returns its identity and PID."
  def ensure_running(identity, opts \\ []) do
    Composition.run(
      fn -> do_ensure_running(identity) end,
      opts
    )
  end

  @doc """
  Opens or reopens the application's normal UI through LaunchServices and waits
  for its process. background: true preserves foreground ownership. This supports
  apps that automatically terminate after a launch-only start without windows.
  Returns the running identity and PID.
  """
  def open(identity, opts \\ []) do
    with :ok <- Automation.options(opts, [:background, :timeout, :max_output_bytes, :trace_to, :journal, :run_id]),
         true <- is_boolean(Keyword.get(opts, :background, false)) do
      Desktop.with_lock(fn -> do_open(identity, opts) end, Keyword.delete(opts, :background))
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("background must be a boolean")
    end
  end

  defp do_open(identity, opts) do
    with {:ok, app} <- Composition.step(:application_status, fn -> status(identity) end),
         :ok <- Composition.effect(:open_application, fn -> launch_ui(app.path, opts) end) do
      ensure_running(app.bundle_id)
    end
  end

  defp launch_ui(path, opts) do
    args = if opts[:background], do: ["-g", "-a", path], else: ["-a", path]

    case Command.run("open", args, ExMacOSControl.execution_options()) do
      {:ok, %{exit_status: 0}} -> :ok
      {:ok, result} -> {:error, Error.execution_error("Application open failed", exit_status: result.exit_status)}
      error -> error
    end
  end

  @doc "Ensures an app is running, activates it, and verifies foreground ownership by PID."
  def activate(identity, opts \\ []) do
    Desktop.with_lock(
      fn -> do_activate(identity) end,
      opts
    )
  end

  @doc "Runs a tagged-result callback with the app frontmost, then restores previous focus."
  def with_frontmost(identity, fun, opts \\ []) when is_function(fun, 1) do
    Desktop.with_lock(
      fn -> do_with_frontmost(identity, fun) end,
      opts
    )
  end

  @doc "Quits only a running app and waits for process exit. Unsaved-document dialogs may time out."
  def quit_if_running(identity, opts \\ []) do
    Composition.run(
      fn -> do_quit_if_running(identity) end,
      opts
    )
  end

  @doc "Quits, waits for exit, launches once, and waits for a new process."
  def restart(identity, opts \\ []) do
    Composition.run(
      fn ->
        with :ok <- quit_if_running(identity), do: ensure_running(identity)
      end,
      opts
    )
  end

  defp ensure(%{running: true} = app), do: {:ok, app}

  defp ensure(app) do
    with :ok <-
           Composition.effect(:launch_application, fn ->
             Automation.action(nil, "Application(input.id).launch();", %{id: app.bundle_id})
           end),
         :ok <- wait_status(app.bundle_id, true) do
      Composition.step(:running_application, fn -> status(app.bundle_id) end)
    end
  end

  defp quit(%{running: false}), do: :ok

  defp quit(app) do
    with :ok <-
           Composition.effect(:quit_application, fn ->
             Automation.action(nil, "Application(input.id).quit();", %{id: app.bundle_id})
           end),
         do: wait_status(app.bundle_id, false)
  end

  defp wait_status(identity, running) do
    Composition.step(:wait_for_application, fn ->
      Wait.until(&matches_status(identity, running, &1))
    end)
  end

  defp matches_status(identity, running, remaining) do
    with {:ok, app} <- status(identity, timeout: remaining), do: {:ok, app.running == running}
  end

  defp focus(pid) do
    with :ok <-
           Automation.action(
             nil,
             """
             ObjC.import('AppKit');
             var a=$.NSRunningApplication.runningApplicationWithProcessIdentifier(input.pid);
             if(a.isNil())throw new Error('Target process exited');
             a.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
             """,
             %{pid: pid}
           ) do
      Wait.until(&frontmost?(pid, &1))
    end
  end

  defp frontmost?(pid, remaining) do
    with {:ok, current} <- frontmost(timeout: remaining), do: {:ok, current == pid}
  end

  defp frontmost(opts \\ []) do
    Automation.query(
      nil,
      """
      ObjC.import('AppKit');
      var a=$.NSWorkspace.sharedWorkspace.frontmostApplication;
      return a.isNil()?null:Number(a.processIdentifier);
      """,
      %{},
      opts
    )
  end

  defp restore_focus(nil), do: :ok

  defp restore_focus(pid) do
    with {:ok, exists} <-
           Automation.query(
             nil,
             """
             ObjC.import('AppKit');
             var a=$.NSRunningApplication.runningApplicationWithProcessIdentifier(input.pid);
             if(a.isNil())return false;
             a.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
             return true;
             """,
             %{pid: pid}
           ) do
      if exists, do: Wait.until(&frontmost?(pid, &1)), else: :ok
    end
  end

  defp do_ensure_running(identity) do
    with {:ok, app} <- Composition.step(:application_status, fn -> status(identity) end) do
      ensure(app)
    end
  end

  defp do_activate(identity) do
    with {:ok, app} <- ensure_running(identity),
         :ok <- Composition.effect(:activate_application, fn -> focus(app.pid) end) do
      {:ok, app}
    end
  end

  defp do_with_frontmost(identity, fun) do
    with {:ok, previous} <- Composition.step(:previous_focus, &frontmost/0) do
      Composition.resource(
        previous,
        fn _ -> use_frontmost(identity, fun) end,
        &restore_focus/1
      )
    end
  end

  defp use_frontmost(identity, fun) do
    with {:ok, app} <- activate(identity), do: fun.(app)
  end

  defp do_quit_if_running(identity) do
    with {:ok, app} <- Composition.step(:application_status, fn -> status(identity) end) do
      quit(app)
    end
  end
end
