defmodule ExMacOSControl.GUI do
  @moduledoc """
  Runs a bounded command in the logged-in Aqua session through one owned Terminal
  window. The window closes after completion by default, including command
  failures. keep_window: true retains it for inspection. Output and ownership
  evidence stay in a new private directory under root (default tmp/gui-runs).

  Never targets an existing Terminal tab. Cleanup checks the app's PID/launch
  time, window ID, TTY, token and tab count. Changed or busy windows are preserved
  and cleanup failures are returned. An uncertain launch is never replayed.
  """
  alias ExMacOSControl.{Automation, Command, Composition, Error, Platform, Wait}

  @environment ~w(EXMC_LIVE_TESTS EXMC_PERSONAL_TESTS EXMC_EVENTKIT_HELPER EXMC_TEST_EMAIL EXMC_CAMPAIGN_REPEATS EXMC_CAMPAIGN_MODE MIX_ENV)
  @options [:root, :timeout, :max_output_bytes, :keep_window]

  def run(executable, arguments, opts \\ []) do
    with :ok <- Automation.required_string(executable, "Executable"),
         :ok <- Automation.options(opts, @options),
         true <- is_list(arguments) and Enum.all?(arguments, &(is_binary(&1) and not String.contains?(&1, <<0>>))),
         true <- is_boolean(Keyword.get(opts, :keep_window, false)),
         true <- Platform.macos?() do
      launch(executable, arguments, opts)
    else
      {:error, _} = error -> error
      _ -> invalid("GUI commands require macOS, string arguments and a boolean keep_window")
    end
  end

  defp launch(executable, arguments, opts) do
    with {:ok, request} <- prepare(executable, arguments, opts) do
      case Command.run("open", ["-a", "Terminal", request.wrapper], timeout: 5000) do
        {:ok, %{exit_status: 0}} -> await(request)
        error -> uncertain("GUI launch was not acknowledged", request, error)
      end
    end
  end

  defp prepare(executable, arguments, opts) do
    token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    root = Path.expand(Keyword.get(opts, :root, "tmp/gui-runs"))
    directory = Path.join(root, token)
    requested = Keyword.get(opts, :timeout, 300_000)

    timeout =
      if is_integer(requested) and is_integer(Composition.remaining()),
        do: min(requested, Composition.remaining()),
        else: requested

    with true <- is_integer(timeout) and timeout > 0, {:ok, focus} <- preflight() do
      write_request(directory, token, executable, arguments, timeout, Keyword.put(opts, :previous_focus, focus))
    else
      false -> invalid("GUI timeout must be a positive integer")
      error -> error
    end
  end

  defp preflight do
    path = :ex_macos_control |> :code.priv_dir() |> to_string() |> Path.join("gui/window.js")

    with elixir when is_binary(elixir) <- System.find_executable("elixir"),
         {:ok, source} <- File.read(path),
         code =
           "new Function(" <>
             Jason.encode!(source) <>
             ");ObjC.import('AppKit');var p=$.NSWorkspace.sharedWorkspace.frontmostApplication;JSON.stringify(p.isNil()?null:{pid:Number(p.processIdentifier),started:Number(p.launchDate.timeIntervalSince1970)});",
         {:ok, %{exit_status: 0, stdout: output}} <-
           Command.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", code], timeout: 5000),
         {:ok, focus} <- Jason.decode(String.trim(output)) do
      {:ok, focus}
    else
      _ -> invalid("GUI runner requires the Elixir CLI and valid native window helper")
    end
  end

  defp write_request(directory, token, executable, arguments, timeout, opts) do
    with :ok <- File.mkdir_p(Path.dirname(directory)),
         :ok <- File.mkdir(directory),
         :ok <- File.chmod(directory, 0o700) do
      request = %{
        token: token,
        directory: directory,
        cwd: File.cwd!(),
        executable: executable,
        arguments: arguments,
        timeout: timeout,
        max_output_bytes: Keyword.get(opts, :max_output_bytes, 10_485_760),
        keep_window: Keyword.get(opts, :keep_window, false),
        previous_focus: opts[:previous_focus],
        owner: Path.join(directory, "owner.json"),
        cleanup: Path.join(directory, "cleanup.json"),
        failed: Path.join(directory, "startup-failure.json"),
        result: Path.join(directory, "result.json"),
        wrapper: Path.join(directory, "run.command")
      }

      path = Path.join(directory, "request.json")

      with :ok <- File.write(path, Jason.encode!(request)),
           :ok <- File.write(request.wrapper, wrapper(request, path)),
           :ok <- File.chmod(request.wrapper, 0o700),
           do: {:ok, request}
    else
      error -> invalid("Cannot create private GUI job storage", cause: error)
    end
  end

  defp wrapper(request, path) do
    script = :ex_macos_control |> :code.priv_dir() |> to_string() |> Path.join("gui/window.js")
    elixir = System.find_executable("elixir")
    paths = :code.get_path() |> Enum.map(&to_string/1) |> Enum.flat_map(&["-pa", &1])

    environment =
      System.get_env()
      |> Map.take(@environment)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> "export " <> key <> "=" <> quote_shell(value) end)

    cleaner = ~s|ExMacOSControl.GUI.cleanup(System.fetch_env!("EXMC_GUI_REQUEST"))|
    helper = "ExMacOSControl.GUI.execute(System.fetch_env!(\"EXMC_GUI_REQUEST\"))"

    """
    #!/bin/zsh
    umask 077
    cd #{quote_shell(request.cwd)} || exit 1
    export TMPDIR=#{quote_shell(Path.expand("tmp"))}
    export PATH=#{quote_shell(System.get_env("PATH", "/usr/bin:/bin"))}
    #{environment}
    export EXMC_GUI_REQUEST=#{quote_shell(path)}
    /usr/bin/osascript -l JavaScript #{quote_shell(script)} claim #{quote_shell(path)} "/dev/$(/bin/ps -p $$ -o tty= | /usr/bin/tr -d ' ')" > #{quote_shell(Path.join(request.directory, "claim.log"))} 2>&1 || { printf '%s' #{quote_shell(Jason.encode!(%{token: request.token, ok: false, stage: "ownership"}))} > #{quote_shell(request.failed)}; exit 1; }
    function exmc_close_owned_window() {
      /usr/bin/nohup #{Enum.map_join([elixir | paths] ++ ["-e", cleaner], " ", &quote_shell/1)} > #{quote_shell(Path.join(request.directory, "cleanup.log"))} 2>&1 < /dev/null &!
    }
    trap exmc_close_owned_window EXIT
    #{Enum.map_join([elixir | paths] ++ ["-e", helper], " ", &quote_shell/1)} > #{quote_shell(Path.join(request.directory, "helper.log"))} 2>&1
    """
  end

  @doc false
  def execute(path) do
    Application.ensure_all_started(:ex_macos_control)
    request = Jason.decode!(File.read!(path))

    case File.open(Path.join(request["directory"], "started"), [:write, :exclusive]) do
      {:ok, lock} ->
        File.close(lock)
        execute_once(request)

      _ ->
        {:error, Error.execution_error("GUI job was already started; refusing replay", outcome: :unknown)}
    end
  end

  defp execute_once(request) do
    result =
      Command.run(request["executable"], request["arguments"],
        timeout: request["timeout"],
        max_output_bytes: request["max_output_bytes"]
      )

    value =
      case result do
        {:ok, output} -> %{ok: true, output: output}
        {:error, error} -> %{ok: false, error: %{type: error.type, message: error.message, details: error.details}}
      end

    write_ack(request["result"], Map.put(value, :token, request["token"]))
  end

  @doc false
  def cleanup(path) do
    Application.ensure_all_started(:ex_macos_control)
    request = Jason.decode!(File.read!(path))
    Process.sleep(150)
    script = :ex_macos_control |> :code.priv_dir() |> to_string() |> Path.join("gui/window.js")
    result = Command.run("/usr/bin/osascript", ["-l", "JavaScript", script, "close", path], timeout: 8000)

    if not File.exists?(request["cleanup"]) do
      write_ack(request["cleanup"], %{token: request["token"], ok: false, error: inspect(result)})
    end
  end

  defp write_ack(path, value) do
    temporary = path <> ".partial"
    File.write!(temporary, Jason.encode!(value), [:exclusive])
    File.rename!(temporary, path)
  end

  defp await(request) do
    # Child work has its own finite deadline even if the initiating process exits.
    with :ok <-
           Wait.until(
             fn -> File.exists?(request.failed) or (File.exists?(request.result) and File.exists?(request.cleanup)) end,
             timeout: request.timeout + 20_000,
             interval: 100
           ),
         :ok <- startup_ack(request),
         {:ok, result} <- read_ack(request.result, request.token),
         {:ok, cleanup} <- read_ack(request.cleanup, request.token) do
      finish(request, result, cleanup)
    else
      error -> uncertain("GUI job or cleanup was not acknowledged; inspect its evidence", request, error)
    end
  end

  defp startup_ack(request) do
    if File.exists?(request.failed),
      do: uncertain("GUI window ownership could not be established; preserving the window", request, :startup),
      else: :ok
  end

  defp read_ack(path, token) do
    with {:ok, bytes} <- File.read(path), {:ok, %{"token" => ^token} = value} <- Jason.decode(bytes) do
      {:ok, value}
    else
      _ -> {:error, Error.execution_error("Invalid GUI acknowledgement", outcome: :unknown)}
    end
  end

  defp finish(
         request,
         %{"ok" => true, "output" => %{"exit_status" => status, "stdout" => stdout, "stderr" => stderr}},
         %{"ok" => true}
       )
       when is_integer(status) and status >= 0 and is_binary(stdout) and is_binary(stderr) do
    {:ok,
     %{
       exit_status: status,
       stdout: stdout,
       stderr: stderr,
       evidence: request.directory,
       window_retained: request.keep_window
     }}
  end

  defp finish(request, result, cleanup),
    do: uncertain("GUI command or window cleanup failed", request, %{result: result, cleanup: cleanup})

  defp uncertain(message, request, cause),
    do: {:error, Error.execution_error(message, outcome: :unknown, evidence: request.directory, cause: cause)}

  defp invalid(message, details \\ []),
    do: {:error, Error.execution_error(message, Keyword.put(details, :outcome, :not_started))}

  defp quote_shell(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
