defmodule ExMacOSControl.Capture do
  @moduledoc """
  Captures native sources once and converts immutable snapshots without app access.

  Snapshot provenance retains native IDs and captured_at; it does not promise
  that a source still exists. Files retain paths, not copies of their contents.
  `render/2` supports :plain, :html and :reference. Reference content uses the
  URL and selection for pages; full content falls back to page text.
  """
  alias ExMacOSControl.{Calendar, Composition, Finder, Mail, Notes, Safari, StandardAdditions}
  alias ExMacOSControl.Capture.{Event, Files, Message, Page, Text}

  def page(target, opts \\ []) do
    with {:ok, data} <- Safari.snapshot(target, opts) do
      {:ok,
       struct!(
         Page,
         Map.merge(data, %{
           source: %{app: :safari, window_id: target.window_id, tab_index: target.tab_index},
           captured_at: DateTime.utc_now()
         })
       )}
    end
  end

  def current_page(opts \\ []) do
    Composition.run(
      fn ->
        with {:ok, target} <- Composition.step(:current_page, &Safari.current_page/0) do
          Composition.step(:capture_page, &page/1, [target])
        end
      end,
      opts
    )
  end

  def selection(opts \\ []) do
    Finder.with_selection(
      fn paths ->
        {:ok, %Files{paths: paths, source: %{app: :finder}, captured_at: DateTime.utc_now()}}
      end,
      opts
    )
  end

  def clipboard(opts \\ []) do
    with {:ok, value} <- StandardAdditions.clipboard(opts) do
      {:ok, %Text{title: "Clipboard", text: value, source: %{app: :clipboard}, captured_at: DateTime.utc_now()}}
    end
  end

  def message(account, mailbox, id, opts \\ []) do
    with {:ok, data} <- Mail.get_message(account, mailbox, id, opts) do
      {:ok,
       %Message{
         subject: data.subject,
         sender: data.sender,
         content: data.content,
         source: %{app: :mail, account_id: account, mailbox: mailbox, id: id},
         captured_at: DateTime.utc_now()
       }}
    end
  end

  def event(calendar, id, opts \\ []) do
    with {:ok, data} <- Calendar.get_event(calendar, id, opts) do
      fields = Map.take(data, [:title, :start_at, :end_at, :location, :description, :url])

      {:ok,
       struct!(
         Event,
         Map.merge(fields, %{source: %{app: :calendar, calendar_id: calendar, id: id}, captured_at: DateTime.utc_now()})
       )}
    end
  end

  def note(id, opts \\ []) do
    with {:ok, data} <- Notes.get_note(id, opts) do
      {:ok,
       %Text{title: data.title, text: data.plaintext, source: %{app: :notes, id: id}, captured_at: DateTime.utc_now()}}
    end
  end

  def title(%Page{} = page), do: nonempty(page.title, page.url)
  def title(%Text{title: title}), do: nonempty(title, "Untitled")
  def title(%Message{subject: subject}), do: nonempty(subject, "Message")
  def title(%Event{title: title}), do: nonempty(title, "Event")
  def title(%Files{paths: paths}), do: "#{length(paths)} selected files"

  def render(capture, format \\ :plain)
  def render(capture, :html), do: "<p>" <> Composition.html(render(capture, :plain)) <> "</p>"
  def render(%Page{} = page, :plain), do: page.url <> "\n\n" <> nonempty(page.selection, page.text)
  def render(%Page{} = page, :reference), do: page.url <> "\n\n" <> page.selection
  def render(%Text{text: text}, :plain), do: text
  def render(%Files{paths: paths}, :plain), do: Enum.join(paths, "\n")

  def render(%Message{} = message, :plain),
    do: "From: #{message.sender}\nSubject: #{message.subject}\n\n#{message.content}"

  def render(%Event{} = event, :plain),
    do: "#{event.start_at} – #{event.end_at}\n#{event.location}\n#{event.description}\n#{event.url}"

  def render(capture, :reference), do: render(capture, :plain)

  def files(%Files{paths: paths}), do: paths
  def files(_), do: []
  def source(%{source: source}), do: source

  defp nonempty(value, fallback) when is_binary(value), do: if(String.trim(value) == "", do: fallback, else: value)
  defp nonempty(_, fallback), do: fallback
end
