defmodule ExMacOSControl.Capabilities do
  @moduledoc """
  Discovers installed app identities, OSA languages and declared scripting terminology.

  Dictionary declarations are returned with `qualification: :unverified`; they do
  not prove runtime support or permission. Discovery reads metadata without launching
  target applications. XML includes are local and bounded, and external entities
  are disabled. Dictionary caches are invalidated by the content of every source.
  """

  alias ExMacOSControl.{Automation, Command, Error, ScriptingDictionary}

  @roots [
    "/Applications",
    "/System/Applications",
    "/System/Applications/Utilities",
    "/System/Library/CoreServices",
    "/System/Library/CoreServices/Applications",
    "/System/Library/ScriptingAdditions"
  ]

  def list_apps(opts \\ []) do
    with :ok <- Automation.options(opts, [:paths, :timeout, :max_output_bytes]),
         paths when is_list(paths) <-
           Keyword.get(opts, :paths, @roots ++ [Path.join(System.user_home!(), "Applications")]),
         true <- Enum.all?(paths, &is_binary/1) do
      Automation.query(
        nil,
        """
        ObjC.import('Foundation');
        var fm = $.NSFileManager.defaultManager, results = [];
        input.paths.forEach(function(root) {
          var entries = ObjC.deepUnwrap(fm.contentsOfDirectoryAtPathError($(root), null)) || [];
          entries.forEach(function(name) {
            if (!/\\.(app|osax)$/.test(name)) return;
            var path = root + '/' + name;
            var plist = ObjC.deepUnwrap($.NSDictionary.dictionaryWithContentsOfFile($(path + '/Contents/Info.plist')));
            if (!plist || typeof plist !== 'object') return;
            function get(key) { var v=plist[key]; return ['string','number','boolean'].indexOf(typeof v)>=0 ? v : null; }
            results.push({name: name.replace(/\\.(app|osax)$/, ''), path: path,
              bundle_id: get('CFBundleIdentifier'), version: get('CFBundleShortVersionString'),
              build: get('CFBundleVersion'), dictionary: get('OSAScriptingDefinition'),
              scriptable: get('NSAppleScriptEnabled')===null ? null : /^(true|yes|1)$/i.test(String(get('NSAppleScriptEnabled')))});
          });
        });
        return results;
        """,
        %{paths: paths},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("paths must be a list of directories")
    end
  end

  def app(identifier, opts \\ []) do
    with :ok <- Automation.required_string(identifier, "Application identity"),
         {:ok, apps} <- list_apps(opts) do
      matches =
        Enum.filter(apps, &(&1.bundle_id == identifier or &1.name == identifier or &1.path == Path.expand(identifier)))

      case matches do
        [app] -> {:ok, app}
        [] -> {:error, Error.not_found("Application not found")}
        _ -> Automation.invalid("Ambiguous application name; use a bundle ID or path")
      end
    end
  end

  def dictionary(identifier, opts \\ []) do
    with {:ok, app} <- app(identifier, opts) do
      dictionary_for_app(app)
    end
  end

  defp dictionary_for_app(app) do
    resources = Path.join(app.path, "Contents/Resources")

    declared =
      if is_binary(app.dictionary),
        do: [Path.join(resources, app.dictionary), Path.join(resources, app.dictionary <> ".sdef")],
        else: []

    candidates = Enum.uniq(declared ++ Path.wildcard(Path.join(resources, "*.sdef")))

    case Enum.find(candidates, &File.regular?/1) do
      nil -> {:ok, %{status: :unknown, qualification: :unverified, app: app, reason: :no_bundled_sdef}}
      path -> with {:ok, dictionary} <- dictionary_file(path), do: {:ok, Map.put(dictionary, :app, app)}
    end
  end

  def dictionary_file(path) do
    key = {__MODULE__, Path.expand(path)}

    case :persistent_term.get(key, nil) do
      %{sources: sources} = cached ->
        if ScriptingDictionary.fresh?(sources), do: {:ok, cached}, else: load_dictionary(path, key)

      _ ->
        load_dictionary(path, key)
    end
  end

  @doc "Reports whether extracted terminology declares a command. declared is nil when no dictionary was found."
  def declares?(identifier, command, opts \\ []) do
    with {:ok, dictionary} <- dictionary(identifier, opts) do
      {:ok, %{declared: declared_command?(dictionary, command), status: dictionary.status, qualification: :unverified}}
    end
  end

  defp declared_command?(%{status: :declared, suites: suites}, command) do
    Enum.any?(suites, fn suite -> Enum.any?(suite.commands, &(&1["name"] == command)) end)
  end

  defp declared_command?(_dictionary, _command), do: nil

  def languages do
    case Command.run("osalang", [], timeout: 5000) do
      {:ok, %{exit_status: 0, stdout: output}} -> {:ok, String.split(output, "\n", trim: true)}
      {:error, _} = error -> error
      _ -> Automation.invalid("Unable to inspect OSA languages")
    end
  end

  defp load_dictionary(path, key) do
    with {:ok, dictionary} <- ScriptingDictionary.read(path) do
      :persistent_term.put(key, dictionary)
      {:ok, dictionary}
    end
  end
end
