defmodule ExMacOSControl.Photos do
  @moduledoc "Photos albums, folders, media metadata, import/export and slideshow controls. Media is addressed by Photos IDs."
  alias ExMacOSControl.{Automation, Composition, Resources, Validation}
  @app "com.apple.Photos"
  @fields [
    id: "o.id()",
    name: "o.name()",
    filename: "o.filename()",
    width: "o.width()",
    height: "o.height()",
    date: "iso(o.date())",
    favorite: "o.favorite()",
    keywords: "o.keywords()",
    description: "o.description()"
  ]
  def list_albums(opts \\ []), do: Resources.list(@app, "app.albums", [id: "o.id()", name: "o.name()"], %{}, opts)
  def list_folders(opts \\ []), do: Resources.list(@app, "app.folders", [id: "o.id()", name: "o.name()"], %{}, opts)

  def list_media(opts \\ []) do
    with :ok <- Automation.options(opts, [:album_id, :limit, :offset, :timeout, :max_output_bytes]) do
      collection = if opts[:album_id], do: "byId(app.albums,input.album_id).mediaItems", else: "app.mediaItems"
      Resources.list(@app, collection, @fields, %{album_id: opts[:album_id]}, Keyword.delete(opts, :album_id))
    end
  end

  def get_media(id, opts \\ []),
    do: Resources.get(@app, "app.mediaItems", @fields ++ [location: "o.location()"], id, %{}, opts)

  def search(query, opts \\ []) do
    with :ok <- Automation.required_string(query, "Search text"),
         :ok <- Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts) do
      Automation.query(
        @app,
        "return page(app.search({for:input.query})).map(function(o){return {id:o.id(),name:o.name(),filename:o.filename()};});",
        Map.put(paging, :query, query),
        Automation.execution_options(opts)
      )
    end
  end

  def create_album(name, opts \\ []), do: create_container(name, "album", opts)
  def create_folder(name, opts \\ []), do: create_container(name, "folder", opts)

  def rename_album(id, name, opts \\ []), do: rename_container(id, name, "app.albums", opts)
  def rename_folder(id, name, opts \\ []), do: rename_container(id, name, "app.folders", opts)

  def delete_album(id, opts \\ []), do: Resources.delete(@app, "app.albums", id, %{}, opts)
  def delete_folder(id, opts \\ []), do: Resources.delete(@app, "app.folders", id, %{}, opts)

  def set_favorite(id, favorite, opts \\ []),
    do:
      Resources.update(@app, "app.mediaItems", [favorite: {"favorite", :boolean}], id, [favorite: favorite], %{}, opts)

  def update_metadata(id, attrs, opts \\ []),
    do:
      Resources.update(
        @app,
        "app.mediaItems",
        [name: {"name", :string}, description: {"description", :string}, date: {"date", :date}],
        id,
        attrs,
        %{},
        opts
      )

  def set_keywords(id, keywords, opts \\ []) do
    if is_list(keywords) and Enum.all?(keywords, &is_binary/1) do
      Automation.action(
        @app,
        "byId(app.mediaItems,input.id).keywords=input.keywords;",
        %{id: id, keywords: keywords},
        opts
      )
    else
      Automation.invalid("Keywords must be a list of strings")
    end
  end

  def add_to_album(ids, album_id, opts \\ []) do
    with :ok <- ids(ids) do
      Automation.action(
        @app,
        "app.add(input.ids.map(function(id){return byId(app.mediaItems,id);}),{to:byId(app.albums,input.album_id)});",
        %{ids: ids, album_id: album_id},
        opts
      )
    end
  end

  def import_files(paths, opts \\ []) do
    with :ok <- Automation.options(opts, [:album_id, :skip_duplicates, :timeout, :max_output_bytes]),
         true <- is_list(paths) and paths != [] and Enum.all?(paths, &(is_binary(&1) and File.regular?(&1))),
         true <- is_boolean(Keyword.get(opts, :skip_duplicates, true)) do
      Automation.query(
        @app,
        "var options={skipCheckDuplicates: !input.skip_duplicates}; if(input.album_id) options.into=byId(app.albums,input.album_id); return app.import(input.paths.map(function(p){return Path(p);}),options).map(function(o){return o.id();});",
        %{
          paths: Enum.map(paths, &Path.expand/1),
          album_id: opts[:album_id],
          skip_duplicates: Keyword.get(opts, :skip_duplicates, true)
        },
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Import needs existing files and a boolean skip_duplicates option")
    end
  end

  def export(ids, destination, opts \\ []) do
    with :ok <- ids(ids),
         :ok <- Automation.options(opts, [:originals, :timeout, :max_output_bytes]),
         true <- is_binary(destination) and File.dir?(destination),
         true <- is_boolean(Keyword.get(opts, :originals, false)) do
      Automation.action(
        @app,
        "app.export(input.ids.map(function(id){return byId(app.mediaItems,id);}),{to:Path(input.path),usingOriginals:input.originals});",
        %{ids: ids, path: Path.expand(destination), originals: Keyword.get(opts, :originals, false)},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Export needs an existing directory and a boolean originals option")
    end
  end

  def start_slideshow(ids, opts \\ []) do
    with :ok <- ids(ids) do
      Automation.action(
        @app,
        "app.startSlideshow({using:input.ids.map(function(id){return byId(app.mediaItems,id);})});",
        %{ids: ids},
        opts
      )
    end
  end

  def slideshow_running?(opts \\ []), do: Automation.query(@app, "return app.slideshowRunning();", %{}, opts)

  @doc """
  Creates a new album and imports files into it. Returns album_id and media_ids.
  Validates input files and options before creating the album. The album remains
  available for recovery if importing fails; an uncertain import is not retried.
  """
  def import_into_new_album(paths, name, opts \\ []) do
    with :ok <- Automation.required_string(name, "Album name"),
         :ok <- Validation.items(paths),
         true <- Enum.all?(paths, &(is_binary(&1) and File.regular?(&1))),
         :ok <- Automation.options(opts, [:folder_id, :skip_duplicates, :timeout, :max_output_bytes]),
         true <- is_boolean(Keyword.get(opts, :skip_duplicates, true)) do
      Composition.run(
        fn -> do_import_into_new_album(paths, name, opts) end,
        Keyword.take(opts, [:timeout, :max_output_bytes])
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Import needs existing files and boolean skip_duplicates")
    end
  end

  for {name, command} <- [
        stop_slideshow: "stopSlideshow",
        pause_slideshow: "pauseSlideshow",
        resume_slideshow: "resumeSlideshow",
        next_slide: "nextSlide",
        previous_slide: "previousSlide"
      ] do
    def unquote(name)(opts \\ []), do: Automation.action(@app, unquote("app.#{command}();"), %{}, opts)
  end

  defp create_container(name, type, opts) do
    with :ok <- Automation.required_string(name, "Container name"),
         :ok <- Automation.options(opts, [:folder_id, :timeout, :max_output_bytes]) do
      Automation.query(
        @app,
        "var options={new:input.type,named:input.name};if(input.folder_id)options.at=byId(app.folders,input.folder_id);return app.make(options).id();",
        %{type: type, name: name, folder_id: opts[:folder_id]},
        Automation.execution_options(opts)
      )
    end
  end

  defp rename_container(id, name, collection, opts) do
    with :ok <- Automation.required_string(name, "Container name") do
      Resources.update(@app, collection, [name: {"name", :string}], id, [name: name], %{}, opts)
    end
  end

  defp ids(values) do
    if is_list(values) and values != [] and Enum.all?(values, &(is_binary(&1) and &1 != "")),
      do: :ok,
      else: Automation.invalid("Media IDs must be a non-empty list of strings")
  end

  defp do_import_into_new_album(paths, name, opts) do
    with {:ok, album} <-
           Composition.effect(:create_album, fn -> create_album(name, Keyword.take(opts, [:folder_id])) end),
         {:ok, media} <-
           Composition.step(:import_files, fn ->
             import_files(paths, Keyword.merge(Keyword.take(opts, [:skip_duplicates]), album_id: album))
           end) do
      {:ok, %{album_id: album, media_ids: media}}
    end
  end
end
