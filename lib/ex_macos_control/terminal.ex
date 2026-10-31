defmodule ExMacOSControl.Terminal do
  @moduledoc """
  Commands without a target run through /bin/sh to completion in an owned
  Terminal window and close it by default. keep_open: true explicitly uses an
  interactive session and keeps it open. Existing target windows are borrowed
  and always remain open. run/2 returns output and exit status; do_script/2
  returns :ok for a successful managed command. Terminal's
  scripting dictionary cannot create tabs; `new_tab: true` is rejected.
  """
  alias ExMacOSControl.{Automation, Composition, Error, GUI, Wait}
  @app "com.apple.Terminal"

  def list_sessions(opts \\ []) do
    Automation.query(
      @app,
      "var result=[]; app.windows().forEach(function(w){(w.tabs()||[]).forEach(function(t,i){result.push({window_id:w.id(),tab_index:i+1,title:t.customTitle(),busy:t.busy()});});}); return result;",
      %{},
      opts
    )
  end

  def do_script(command, opts \\ []) do
    with :ok <- Automation.required_string(command, "Shell command"),
         :ok <- Automation.options(opts, [:window_id, :tab_index, :new_tab, :keep_open, :timeout, :max_output_bytes]),
         :ok <- target_options(opts) do
      if opts[:window_id] || opts[:keep_open] == true, do: dispatch(command, opts), else: managed(command, opts)
    end
  end

  @doc "Runs a bounded shell command in Aqua, closes its owned window and returns output, exit status and cleanup evidence."
  def run(command, opts \\ []) do
    with :ok <- Automation.required_string(command, "Shell command"),
         :ok <- Automation.options(opts, [:timeout, :max_output_bytes, :keep_open]),
         true <- is_boolean(Keyword.get(opts, :keep_open, false)) do
      options = opts |> Keyword.delete(:keep_open) |> Keyword.put(:keep_window, opts[:keep_open] || false)
      GUI.run("/bin/sh", ["-c", command], options)
    else
      false -> Automation.invalid("keep_open must be a boolean")
      error -> error
    end
  end

  defp managed(command, opts) do
    case run(command, Keyword.take(opts, [:timeout, :max_output_bytes])) do
      {:ok, %{exit_status: 0}} ->
        :ok

      {:ok, result} ->
        {:error, Error.execution_error("Terminal command failed", outcome: :unknown, command_result: result)}

      error ->
        error
    end
  end

  defp dispatch(command, opts) do
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

  @doc """
  Polls a targeted tab until Terminal reports it idle and returns a session
  snapshot. This does not prove command success, provide an exit code, or detect
  background jobs. Use after a command has visibly started; an idle shell can
  otherwise be observed before queued work begins. Never re-executes a command.
  """
  def wait_until_idle(window_id, tab_index, opts \\ []) do
    with :ok <- target_options(window_id: window_id, tab_index: tab_index),
         :ok <- Automation.options(opts, [:timeout, :interval, :max_output_bytes]),
         true <- is_integer(Keyword.get(opts, :interval, 50)) and Keyword.get(opts, :interval, 50) > 0 do
      Composition.run(&wait_for_idle/3, [window_id, tab_index, opts], Keyword.take(opts, [:timeout, :max_output_bytes]))
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Interval must be a positive integer")
    end
  end

  defp wait_for_idle(window_id, tab_index, opts) do
    predicate = &idle?(window_id, tab_index, &1)

    with :ok <- Composition.step(:wait_for_terminal, &Wait.until/2, [predicate, Keyword.take(opts, [:interval])]) do
      Composition.step(:read_terminal, &read_session/2, [window_id, tab_index])
    end
  end

  defp idle?(window_id, tab_index, remaining) do
    with {:ok, session} <- read_session(window_id, tab_index, timeout: remaining), do: {:ok, session.busy == false}
  end

  defp target_options(opts) do
    cond do
      not is_boolean(Keyword.get(opts, :keep_open, false)) ->
        Automation.invalid("keep_open must be a boolean")

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
