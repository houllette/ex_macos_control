defmodule ExMacOSControl.Notes do
  @moduledoc """
  Notes accounts, folders and notes addressed by stable IDs. Bodies are HTML;
  reads also expose plain text. Locked/shared content remains subject to Notes.
  List calls are paged; execution options include timeout and max_output_bytes.
  """
  alias ExMacOSControl.{Automation, Composition, Resources}
  @app "com.apple.Notes"
  @summary [
    id: "o.id()",
    title: "o.name()",
    folder_id: "o.container().id()",
    created_at: "iso(o.creationDate())",
    modified_at: "iso(o.modificationDate())"
  ]
  @schema [title: {"name", :string}, body: {"body", :string}]

  def list_accounts(opts \\ []), do: Resources.list(@app, "app.accounts", [id: "o.id()", name: "o.name()"], %{}, opts)
  def list_folders(opts \\ []), do: Resources.list(@app, "app.folders", [id: "o.id()", name: "o.name()"], %{}, opts)

  def list_notes(opts \\ []) do
    with :ok <- Automation.options(opts, [:folder_id, :limit, :offset, :timeout, :max_output_bytes]) do
      collection = if opts[:folder_id], do: "byId(app.folders, input.folder_id).notes", else: "app.notes"
      Resources.list(@app, collection, @summary, %{folder_id: opts[:folder_id]}, Keyword.delete(opts, :folder_id))
    end
  end

  def get_note(id, opts \\ []),
    do: Resources.get(@app, "app.notes", @summary ++ [body: "o.body()", plaintext: "o.plaintext()"], id, %{}, opts)

  def create_note(attrs, opts \\ []) do
    with :ok <- Automation.options(opts, [:folder_id, :timeout, :max_output_bytes]),
         :ok <- Automation.options(attrs, Keyword.keys(@schema)),
         :ok <- Automation.required_string(attrs[:title], "Note title") do
      collection =
        if opts[:folder_id],
          do: "byId(app.folders, input.folder_id).notes",
          else: "app.defaultAccount().defaultFolder().notes"

      Resources.create(
        @app,
        collection,
        "Note",
        @schema,
        attrs,
        %{folder_id: opts[:folder_id]},
        Automation.execution_options(opts)
      )
    end
  end

  def update_note(id, attrs, opts \\ []), do: Resources.update(@app, "app.notes", @schema, id, attrs, %{}, opts)
  def delete_note(id, opts \\ []), do: Resources.delete(@app, "app.notes", id, %{}, opts)

  def rename_folder(id, name, opts \\ []) do
    with :ok <- Automation.required_string(name, "Folder name") do
      Resources.update(@app, "app.folders", [name: {"name", :string}], id, [name: name], %{}, opts)
    end
  end

  def delete_folder(id, opts \\ []), do: Resources.delete(@app, "app.folders", id, %{}, opts)

  def selection(opts \\ []),
    do:
      Automation.query(@app, "return app.selection().map(function(o){return {id:o.id(),title:o.name()};});", %{}, opts)

  def show_note(id, opts \\ []) do
    with :ok <- Automation.required_string(id, "Note ID"),
         :ok <- Automation.options(opts, [:separately, :timeout, :max_output_bytes]),
         true <- is_boolean(Keyword.get(opts, :separately, false)) do
      Automation.action(
        @app,
        "app.show(byId(app.notes,input.id),{separately:input.separately});",
        %{id: id, separately: Keyword.get(opts, :separately, false)},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("separately must be a boolean")
    end
  end

  def append_text(id, text, opts \\ []) do
    with :ok <- Automation.required_string(id, "Note ID"), :ok <- Automation.required_string(text, "Text") do
      Automation.action(
        @app,
        "var o = byId(app.notes, input.id); o.body = o.body() + input.html;",
        %{id: id, html: escape_text(text)},
        opts
      )
    end
  end

  def create_folder(name, opts \\ []) do
    with :ok <- Automation.options(opts, [:account_id, :timeout, :max_output_bytes]),
         :ok <- Automation.required_string(name, "Folder name") do
      collection =
        if opts[:account_id], do: "byId(app.accounts, input.account_id).folders", else: "app.defaultAccount().folders"

      Resources.create(
        @app,
        collection,
        "Folder",
        [name: {"name", :string}],
        [name: name],
        %{account_id: opts[:account_id]},
        Automation.execution_options(opts)
      )
    end
  end

  def list_attachments(id, opts \\ []),
    do:
      Resources.list(
        @app,
        "byId(app.notes, input.id).attachments",
        [id: "o.id()", name: "o.name()", url: "o.url()"],
        %{id: id},
        opts
      )

  @doc "Creates a note from plain text, escaping HTML rather than interpreting user text as markup."
  def create_text_note(title, text, opts \\ []) do
    if is_binary(text),
      do: create_note([title: title, body: "<p>" <> Composition.html(text) <> "</p>"], opts),
      else: Automation.invalid("Note text must be a string")
  end

  @doc "Creates an escaped HTML note from an immutable capture. Options include title and folder_id."
  def create_from(capture, opts \\ []) do
    with :ok <- Automation.options(opts, [:title, :folder_id, :timeout, :max_output_bytes]) do
      create_note(
        [
          title: Keyword.get(opts, :title, ExMacOSControl.Capture.title(capture)),
          body: ExMacOSControl.Capture.render(capture, :html)
        ],
        Keyword.delete(opts, :title)
      )
    end
  end

  defdelegate capture_note(id, opts \\ []), to: ExMacOSControl.Capture, as: :note

  @doc "Creates a note and shows it. A failed show retains the created note ID in error details."
  def create_and_show(attrs, opts \\ []) do
    with :ok <- Automation.options(opts, [:folder_id, :separately, :timeout, :max_output_bytes]),
         true <- is_boolean(Keyword.get(opts, :separately, false)) do
      Composition.run(
        fn -> do_create_and_show(attrs, opts) end,
        Keyword.take(opts, [:timeout, :max_output_bytes])
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("separately must be a boolean")
    end
  end

  @doc "Copies a note into an optional folder, preserving its HTML body."
  def duplicate_note(id, opts \\ []) do
    with :ok <- Automation.options(opts, [:folder_id, :title, :timeout, :max_output_bytes]),
         :ok <- Automation.required_string(Keyword.get(opts, :title, "Copy"), "Note title") do
      Composition.run(
        fn -> do_duplicate_note(id, opts) end,
        Keyword.take(opts, [:timeout, :max_output_bytes])
      )
    end
  end

  defp escape_text(text),
    do:
      "<p>" <>
        (text
         |> String.replace("&", "&amp;")
         |> String.replace("<", "&lt;")
         |> String.replace(">", "&gt;")
         |> String.replace("\n", "<br>")) <> "</p>"

  defp do_create_and_show(attrs, opts) do
    with {:ok, id} <-
           Composition.step(:create_note, fn -> create_note(attrs, Keyword.take(opts, [:folder_id])) end),
         :ok <- Composition.step(:show_note, fn -> show_note(id, Keyword.take(opts, [:separately])) end) do
      {:ok, id}
    end
  end

  defp do_duplicate_note(id, opts) do
    with {:ok, note} <- Composition.step(:read_note, fn -> get_note(id) end) do
      Composition.step(:create_note, fn ->
        create_note(
          [title: Keyword.get(opts, :title, note.title), body: note.body],
          Keyword.take(opts, [:folder_id])
        )
      end)
    end
  end
end
