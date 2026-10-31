defmodule ExMacOSControl.EventKit.Installer do
  @moduledoc false
  alias ExMacOSControl.{Automation, Command, Composition, Error, Platform}

  def install(destination, opts \\ []) do
    with :ok <- Automation.required_string(destination, "Helper destination"),
         :ok <- Automation.options(opts, [:timeout, :max_output_bytes]),
         true <- String.ends_with?(destination, ".app"),
         true <- Platform.macos?() do
      Composition.run(fn -> install_owned(Path.expand(destination)) end, Keyword.put_new(opts, :timeout, 120_000))
    else
      {:error, _} = error ->
        error

      _ ->
        {:error,
         Error.execution_error("An EventKit helper requires macOS and a new .app destination", outcome: :not_started)}
    end
  end

  defp install_owned(path) do
    Composition.effect(:install_eventkit_helper, fn -> build(path) end,
      resource: :eventkit_helper,
      identity: %{path: path}
    )
  end

  defp build(path) do
    with :ok <- File.mkdir_p(Path.dirname(path)), :ok <- File.mkdir(path) do
      result = compile(path)
      if match?({:error, _}, result), do: File.rm_rf(path)
      result
    else
      {:error, reason} ->
        {:error, Error.execution_error("Helper destination must be new", reason: reason, outcome: :not_started)}
    end
  end

  defp compile(path) do
    priv = :ex_macos_control |> :code.priv_dir() |> to_string() |> Path.join("eventkit")
    directory = Path.join(path, "Contents/MacOS")
    cache = Path.join(System.tmp_dir!(), "eventkit-build-" <> Base.encode16(:crypto.strong_rand_bytes(8)))
    File.mkdir_p!(directory)
    File.mkdir_p!(cache)
    File.chmod!(path, 0o700)
    info = Path.join(path, "Contents/Info.plist")
    File.cp!(Path.join(priv, "Info.plist"), info)
    binary = Path.join(directory, "EventKitBridge")

    try do
      with {:ok, %{stdout: arch}} <- command("/usr/bin/uname", ["-m"]),
           args = [
             "swiftc",
             "-warnings-as-errors",
             "-module-cache-path",
             cache,
             "-target",
             String.trim(arch) <> "-apple-macosx14.0",
             Path.join(priv, "main.swift"),
             "-o",
             binary,
             "-framework",
             "EventKit",
             "-framework",
             "Foundation",
             "-Xlinker",
             "-sectcreate",
             "-Xlinker",
             "__TEXT",
             "-Xlinker",
             "__info_plist",
             "-Xlinker",
             info
           ],
           {:ok, _} <- command("/usr/bin/xcrun", args),
           {:ok, _} <-
             command("/usr/bin/codesign", [
               "--force",
               "--sign",
               "-",
               "--identifier",
               "org.exmacoscontrol.eventkit",
               path
             ]) do
        {:ok, path}
      end
    after
      File.rm_rf(cache)
    end
  end

  defp command(executable, args) do
    case Command.run(executable, args, ExMacOSControl.execution_options()) do
      {:ok, %{exit_status: 0}} = result ->
        result

      {:ok, result} ->
        {:error,
         Error.execution_error("EventKit helper build failed", exit_status: result.exit_status, stderr: result.stderr)}

      error ->
        error
    end
  end
end
