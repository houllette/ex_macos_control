defmodule ExMacOSControl.DesktopSession do
  @moduledoc false
  import ExUnit.Assertions
  alias ExMacOSControl.{OSAScriptAdapter, Script}

  def start(opts \\ []) do
    lock()
    directory = Path.expand("tmp/desktop-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}")
    File.mkdir_p!(directory)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(directory) end)

    apps = Keyword.get(opts, :apps, []) ++ if(opts[:safari], do: ["com.apple.Safari"], else: [])

    assert {:ok, %{"focus" => focus, "running" => running}} =
             OSAScriptAdapter.run_javascript(
               """
               ObjC.import('AppKit');
               var ids=#{Jason.encode!(apps)};
               JSON.stringify({focus:ObjC.unwrap($.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier)||'',
                 running:ids.filter(function(id){return $.NSRunningApplication.runningApplicationsWithBundleIdentifier($(id)).count>0;})});
               """,
               timeout: 5000,
               output: :json
             )

    # Register focus restoration before creating windows so setup failures restore it too.
    ExUnit.Callbacks.on_exit(fn ->
      assert {:ok, _} =
               OSAScriptAdapter.run_javascript(
                 """
                 ObjC.import('AppKit');
                 #{Jason.encode!(apps -- running)}.forEach(function(id){
                   var app=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($(id)).firstObject;
                   if(!app.isNil()) app.hide;
                 });
                 var a=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($(#{Jason.encode!(focus)})).firstObject;
                 if(!a.isNil()) a.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
                 """,
                 timeout: 5000
               )
    end)

    safari = if opts[:safari], do: safari_window()

    ExUnit.Callbacks.on_exit(fn -> cleanup(directory, safari) end)

    if opts[:finder] do
      assert {:ok, _} =
               OSAScriptAdapter.run_applescript(
                 """
                 tell application "Finder"
                   activate
                   make new Finder window to POSIX file "#{Script.escape_string(directory)}"
                 end tell
                 """,
                 timeout: 5000
               )
    end

    %{desktop_directory: directory}
  end

  defp safari_window do
    assert {:ok, id} =
             OSAScriptAdapter.run_applescript(
               """
               tell application "Safari"
                 make new document with properties {URL:"about:blank"}
                 return id of front window
               end tell
               """,
               timeout: 5000
             )

    String.to_integer(id)
  end

  defp cleanup(directory, safari) do
    assert {:ok, _} =
             OSAScriptAdapter.run_javascript(
               """
               ObjC.import('Foundation');
               var root=#{Jason.encode!(directory)}, finder=Application('com.apple.finder');
               finder.finderWindows().forEach(function(w){
                 var path=ObjC.unwrap($.NSURL.URLWithString($(w.target().url())).path);
                 if(path===root || path.indexOf(root+'/')===0) finder.close(w);
               });
               var id=#{Jason.encode!(safari)};
               if(id!==null){var app=Application('com.apple.Safari'),w=app.windows.byId(id);if(w.exists())app.close(w);}
               """,
               timeout: 5000
             )
  end

  # Hold the socket through on_exit, which runs after the test process has exited.
  # A second Mix invocation must not interleave desktop tests with this one.
  defp lock do
    caller = self()
    reference = make_ref()

    holder =
      spawn(fn ->
        result = :gen_tcp.listen(41_050, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: false])
        send(caller, {reference, result})

        case result do
          {:ok, socket} ->
            receive do
              {^reference, cleanup} ->
                :gen_tcp.close(socket)
                send(cleanup, reference)
            after
              120_000 -> :gen_tcp.close(socket)
            end

          _ ->
            :ok
        end
      end)

    receive do
      {^reference, {:ok, _}} ->
        ExUnit.Callbacks.on_exit(fn ->
          send(holder, {reference, self()})

          receive do
            ^reference -> :ok
          after
            1000 -> flunk("Desktop lock holder did not release its socket")
          end
        end)

      {^reference, {:error, reason}} ->
        flunk("Desktop session unavailable (#{inspect(reason)}); run one desktop test process at a time")
    end
  end
end
