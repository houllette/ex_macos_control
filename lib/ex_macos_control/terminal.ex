defmodule ExMacOSControl.Terminal do
  @moduledoc """
  Terminal sessions and explicit shell-command execution. Command completion is
  separate from Terminal accepting a command. Commands open a new window unless
  an existing window ID and optional 1-based tab index are supplied. Terminal's
  scripting dictionary cannot create tabs; `new_tab: true` is rejected.
  """
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
         :ok <- target_options(opts) do
      Automation.action(
        @app,
        "var options={}; if(input.window_id!==null){var w=byId(app.windows,input.window_id); var target=w.tabs[input.tab_index-1]; if(!target.exists()) throw new Error('Object not found'); options.in=target;} app.doScript(input.command,options);",
        %{
          command: command,
          window_id: opts[:window_id],
          tab_index: Keyword.get(opts, :tab_index, 1)
        },
        Automation.execution_options(opts)
      )
    end
  end

  def read_session(window_id, tab_index, opts \\ []) do
    with :ok <- target_options(window_id: window_id, tab_index: tab_index) do
      Automation.query(
        @app,
        "var t=byId(app.windows,input.window_id).tabs[input.tab_index-1]; if(!t.exists()) throw new Error('Object not found'); return {title:t.customTitle(),busy:t.busy(),text:t.contents()};",
        %{window_id: window_id, tab_index: tab_index},
        opts
      )
    end
  end

  defp target_options(opts) do
    cond do
      Keyword.get(opts, :new_tab, false) != false ->
        Automation.invalid("Terminal scripting cannot create tabs; use an existing window ID and tab index")

      Keyword.has_key?(opts, :window_id) and not positive_integer?(opts[:window_id]) ->
        Automation.invalid("Window ID must be a positive integer")

      not positive_integer?(Keyword.get(opts, :tab_index, 1)) ->
        Automation.invalid("Tab index must be a positive integer")

      Keyword.has_key?(opts, :tab_index) and not Keyword.has_key?(opts, :window_id) ->
        Automation.invalid("A tab index requires a window ID")

      true ->
        :ok
    end
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0
end
