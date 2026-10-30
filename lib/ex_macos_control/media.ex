defmodule ExMacOSControl.Media do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Resources}

  defmacro __using__(opts) do
    bundle = Keyword.fetch!(opts, :bundle_id)

    controls =
      for {name, command} <- [
            play: "play",
            pause: "pause",
            stop: "stop",
            next_track: "nextTrack",
            previous_track: "previousTrack",
            play_pause: "playpause",
            resume: "resume"
          ] do
        quote do
          def unquote(name)(opts \\ []), do: ExMacOSControl.Media.control(@media_bundle, unquote(command), opts)
        end
      end

    quote do
      @media_bundle unquote(bundle)
      unquote_splicing(controls)
      def state(opts \\ []), do: ExMacOSControl.Media.state(@media_bundle, opts)
      def play_track(id, opts \\ []), do: ExMacOSControl.Media.play_track(@media_bundle, id, opts)
      def seek(seconds, opts \\ []), do: ExMacOSControl.Media.seek(@media_bundle, seconds, opts)
      def set_volume(volume, opts \\ []), do: ExMacOSControl.Media.set_volume(@media_bundle, volume, opts)
      def set_muted(muted, opts \\ []), do: ExMacOSControl.Media.set_muted(@media_bundle, muted, opts)
      def list_playlists(opts \\ []), do: ExMacOSControl.Media.list_playlists(@media_bundle, opts)
      def list_tracks(opts \\ []), do: ExMacOSControl.Media.list_tracks(@media_bundle, opts)
      def search(query, opts \\ []), do: ExMacOSControl.Media.search(@media_bundle, query, opts)
      def create_playlist(name, opts \\ []), do: ExMacOSControl.Media.create_playlist(@media_bundle, name, opts)

      @doc "Creates a playlist and adds explicit persistent track IDs in order. Partial failures retain the playlist ID."
      def create_playlist_with_tracks(name, ids, opts \\ []),
        do: ExMacOSControl.Media.create_playlist_with_tracks(@media_bundle, name, ids, opts)

      def add_to_playlist(track_id, playlist_id, opts \\ []),
        do: ExMacOSControl.Media.add_to_playlist(@media_bundle, track_id, playlist_id, opts)

      def update_track(id, attrs, opts \\ []), do: ExMacOSControl.Media.update_track(@media_bundle, id, attrs, opts)
    end
  end

  def control(bundle, command, opts), do: Automation.action(bundle, "app.#{command}();", %{}, opts)

  def state(bundle, opts),
    do:
      Automation.query(
        bundle,
        "var state=app.playerState(); var track=null; if(state!=='stopped') { var t=app.currentTrack(); track={id:t.persistentID(),name:t.name(),duration:t.duration()}; } return {playing:state==='playing',state:state,position:app.playerPosition(),volume:app.soundVolume(),muted:app.mute(),current_track:track};",
        %{},
        opts
      )

  def play_track(bundle, id, opts) do
    with :ok <- Automation.required_string(id, "Persistent track ID") do
      Automation.action(
        bundle,
        "var t=app.tracks.whose({persistentID:input.id})()[0]; if(!t) throw new Error('Object not found'); app.play(t);",
        %{id: id},
        opts
      )
    end
  end

  def seek(bundle, seconds, opts) when is_number(seconds) and seconds >= 0,
    do: Automation.action(bundle, "app.playerPosition=input.seconds;", %{seconds: seconds}, opts)

  def seek(_, _, _), do: Automation.invalid("Position must be a non-negative number")

  def set_volume(bundle, volume, opts) when is_integer(volume) and volume in 0..100,
    do: Automation.action(bundle, "app.soundVolume=input.volume;", %{volume: volume}, opts)

  def set_volume(_, _, _), do: Automation.invalid("Volume must be an integer from 0 to 100")

  def set_muted(bundle, muted, opts) when is_boolean(muted),
    do: Automation.action(bundle, "app.mute=input.muted;", %{muted: muted}, opts)

  def set_muted(_, _, _), do: Automation.invalid("Muted must be a boolean")

  def list_playlists(bundle, opts),
    do:
      Resources.list(
        bundle,
        "app.playlists",
        [id: "o.persistentID()", name: "o.name()", duration: "o.duration()"],
        %{},
        opts
      )

  def list_tracks(bundle, opts) do
    with :ok <- Automation.options(opts, [:playlist_id, :limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts) do
      Automation.query(
        bundle,
        "var p=input.playlist_id ? app.playlists.whose({persistentID:input.playlist_id})()[0] : null; if(input.playlist_id && !p) throw new Error('Object not found'); var tracks=p?p.tracks():app.tracks(); return page(tracks).map(function(o){return {id:o.persistentID(),name:o.name(),album:o.album(),duration:o.duration(),rating:o.rating()};});",
        Map.put(paging, :playlist_id, opts[:playlist_id]),
        Automation.execution_options(opts)
      )
    end
  end

  def search(bundle, query, opts) do
    with :ok <- Automation.required_string(query, "Search text"),
         :ok <- Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts) do
      Automation.query(
        bundle,
        "return page(app.search(app.libraryPlaylists[0],{for:input.query})).map(function(o){return {id:o.persistentID(),name:o.name(),album:o.album(),duration:o.duration()};});",
        Map.put(paging, :query, query),
        Automation.execution_options(opts)
      )
    end
  end

  def create_playlist(bundle, name, opts) do
    with :ok <- Automation.required_string(name, "Playlist name") do
      Automation.query(
        bundle,
        "var p=app.make({new:'userPlaylist',withProperties:{name:input.name}}); return p.persistentID();",
        %{name: name},
        opts
      )
    end
  end

  def create_playlist_with_tracks(bundle, name, ids, opts) do
    with :ok <- Automation.required_string(name, "Playlist name"),
         :ok <- Composition.validate_items(ids),
         :ok <- Composition.validate_all(ids, &Automation.required_string(&1, "Track ID")) do
      Composition.run(
        fn -> do_create_playlist_with_tracks(bundle, name, ids) end,
        opts
      )
    end
  end

  def add_to_playlist(bundle, track_id, playlist_id, opts),
    do:
      Automation.action(
        bundle,
        "var t=app.tracks.whose({persistentID:input.track_id})()[0], p=app.playlists.whose({persistentID:input.playlist_id})()[0]; if(!t||!p) throw new Error('Object not found'); app.duplicate(t,{to:p});",
        %{track_id: track_id, playlist_id: playlist_id},
        opts
      )

  def update_track(bundle, id, attrs, opts) do
    with true <- Keyword.get(attrs, :rating, 0) in 0..100,
         {:ok, properties, _} <-
           Resources.properties(attrs,
             name: {"name", :string},
             album: {"album", :string},
             rating: {"rating", :integer},
             comment: {"comment", :string}
           ) do
      Automation.action(
        bundle,
        "var o=app.tracks.whose({persistentID:input.id})()[0]; if(!o) throw new Error('Object not found'); Object.keys(input.properties).forEach(function(k){o[k]=input.properties[k];});",
        %{id: id, properties: properties},
        opts
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Rating must be an integer from 0 to 100")
    end
  end

  defp do_create_playlist_with_tracks(bundle, name, ids) do
    with {:ok, playlist} <- Composition.effect(:create_playlist, fn -> create_playlist(bundle, name, []) end),
         {:ok, _} <- Composition.map(ids, :add_track, fn id -> add_to_playlist(bundle, id, playlist, []) end) do
      {:ok, playlist}
    end
  end
end
