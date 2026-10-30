defmodule ExMacOSControl.Terminal do
  @moduledoc "Terminal sessions and explicit shell-command execution. Command completion is separate from Terminal accepting a command."
  alias ExMacOSControl.Automation
  @app "com.apple.Terminal"

  def list_sessions(opts \\ []) do
    Automation.query(
      @app,
      "var result=[]; app.windows().forEach(function(w){w.tabs().forEach(function(t,i){result.push({window_id:w.id(),tab_index:i+1,title:t.customTitle(),busy:t.busy()});});}); return result;",
      %{},
      opts
    )
  end

  def do_script(command, opts \\ []) do
    with :ok <- Automation.required_string(command, "Shell command"),
         :ok <- Automation.options(opts, [:window_id, :tab_index, :new_tab, :timeout, :max_output_bytes]),
         true <- is_boolean(Keyword.get(opts, :new_tab, false)) do
      Automation.action(
        @app,
        "var target=null; if(input.window_id){var w=byId(app.windows,input.window_id); target=w.tabs[input.tab_index-1]; if(!target.exists()) throw new Error('Object not found');} if(input.new_tab){var options={}; if(target) options.nextTo=target; app.doScriptInNewTab(input.command,options);} else {var options={}; if(target) options.in=target; app.doScript(input.command,options);}",
        %{
          command: command,
          window_id: opts[:window_id],
          tab_index: Keyword.get(opts, :tab_index, 1),
          new_tab: Keyword.get(opts, :new_tab, false)
        },
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("new_tab must be a boolean")
    end
  end

  def read_session(window_id, tab_index, opts \\ []) when is_integer(tab_index) and tab_index > 0 do
    Automation.query(
      @app,
      "var t=byId(app.windows,input.window_id).tabs[input.tab_index-1]; if(!t.exists()) throw new Error('Object not found'); return {title:t.customTitle(),busy:t.busy(),text:t.contents()};",
      %{window_id: window_id, tab_index: tab_index},
      opts
    )
  end
end
