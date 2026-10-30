defmodule ExMacOSControl.QuickTime do
  @moduledoc "QuickTime playback, trimming, export and recording. Targets are 1-based document indices or unambiguous names."
  alias ExMacOSControl.Automation
  @app "com.apple.QuickTimePlayerX"

  def list_movies(opts \\ []) do
    with :ok <- Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts) do
      Automation.query(
        @app,
        "return page(app.documents()).map(function(o,i){return {index:input.offset+i+1,name:o.name(),duration:o.duration(),position:o.currentTime(),playing:o.playing(),muted:o.muted()};});",
        paging,
        Automation.execution_options(opts)
      )
    end
  end

  def open(path, opts \\ []) do
    if is_binary(path) and File.regular?(path),
      do: Automation.action(@app, "app.open(Path(input.path));", %{path: Path.expand(path)}, opts),
      else: Automation.invalid("Movie file does not exist")
  end

  for {name, command} <- [
        play: "play",
        pause: "pause",
        stop: "stop",
        resume: "resume",
        start_recording: "start",
        present: "present"
      ] do
    def unquote(name)(target, opts \\ []), do: document(target, "app.#{unquote(command)}(o);", %{}, opts)
  end

  def seek(target, seconds, opts \\ []) when is_number(seconds) and seconds >= 0,
    do:
      document(
        target,
        "if(input.seconds>o.duration()) throw new Error('Position exceeds movie duration'); o.currentTime=input.seconds;",
        %{seconds: seconds},
        opts
      )

  def trim(target, from, to, opts \\ []) when is_number(from) and is_number(to) and from >= 0 and to > from do
    document(
      target,
      "if(input.to>o.duration()) throw new Error('Trim exceeds movie duration'); app.trim(o,{from:input.from,to:input.to});",
      %{from: from, to: to},
      opts
    )
  end

  def export(target, path, preset, opts \\ []) do
    with :ok <- Automation.required_string(path, "Output path"),
         :ok <- Automation.required_string(preset, "Export preset"),
         false <- File.exists?(path) do
      document(
        target,
        "app.export(o,{in:Path(input.path),usingSettingsPreset:input.preset});",
        %{path: Path.expand(path), preset: preset},
        opts
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Export destination already exists")
    end
  end

  @doc "Creates a recording document. Screen recording opens the macOS capture UI and returns `{:ok, nil}` when no document is created."
  def new_recording(kind, opts \\ []) when kind in [:audio, :movie, :screen] do
    command = %{audio: "newAudioRecording", movie: "newMovieRecording", screen: "newScreenRecording"}[kind]
    result = if kind == :screen, do: "return o == null ? null : o.name();", else: "return o.name();"
    Automation.query(@app, "var o=app.#{command}(); #{result}", %{}, opts)
  end

  defp document(target, body, params, opts) do
    if (is_integer(target) and target > 0) or (is_binary(target) and target != "") do
      Automation.action(
        @app,
        "var matches=typeof input.target==='number' ? [app.documents[input.target-1]] : app.documents.whose({name:input.target})(); if(matches.length!==1 || !matches[0].exists()) throw new Error('Missing or ambiguous movie'); var o=matches[0]; #{body}",
        Map.put(params, :target, target),
        opts
      )
    else
      Automation.invalid("Movie target must be an index or name")
    end
  end
end
