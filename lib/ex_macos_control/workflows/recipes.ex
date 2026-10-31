defmodule ExMacOSControl.Workflows.Recipes do
  @moduledoc false
  alias ExMacOSControl.{
    Applications,
    Automation,
    Calendar,
    Capture,
    Composition,
    Finder,
    ImageEvents,
    Mail,
    Messages,
    Notes,
    Photos,
    Reminders,
    Safari,
    Shortcuts,
    StandardAdditions,
    Validation
  }

  @execution [:timeout, :max_output_bytes]
  @note [:folder_id, :title]
  @reminder [:title, :due_at, :reminder_at, :priority, :flagged]
  @shortcut [:output, :trim, :output_path, :output_type]

  @doc "Runs a Shortcut with the captured Finder selection as native file input."
  def selection_to_shortcut(identifier, opts \\ []) do
    with :ok <- Automation.required_string(identifier, "Shortcut identity"),
         :ok <- Automation.options(opts, @execution ++ @shortcut) do
      Finder.with_selection(
        fn paths ->
          Composition.effect(:run_shortcut, &Shortcuts.run/2, [
            identifier,
            Keyword.put(Keyword.take(opts, @shortcut), :input_paths, paths)
          ])
        end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Mail draft attaching selected Finder files. Mail options are passed separately."
  def selection_to_draft(mail_options, opts \\ []) do
    with :ok <- mail_options(mail_options) do
      Finder.with_selection(
        fn paths ->
          Composition.effect(:create_draft, &Mail.create_draft/1, [Keyword.put(mail_options, :attachments, paths)])
        end,
        opts
      )
    end
  end

  def selection_to_verified_draft(mail_options, opts \\ []) do
    with :ok <- mail_options(mail_options) do
      Finder.with_selection(
        fn paths ->
          Mail.create_verified_draft(Keyword.put(mail_options, :attachments, paths))
        end,
        opts
      )
    end
  end

  @doc "Sends selected Finder files to an explicit Messages chat ID. Real sends, attempted once each."
  def selection_to_chat(chat_id, opts \\ []) do
    with :ok <- Automation.required_string(chat_id, "Chat ID") do
      Finder.with_selection(&Messages.send_files_to_chat(chat_id, &1), opts)
    end
  end

  @doc "Sends the current Safari page URL and selected text to an explicit Messages chat ID, once."
  def current_page_to_chat(chat_id, opts \\ []) do
    with :ok <- Automation.required_string(chat_id, "Chat ID") do
      Composition.run(&send_page/1, [chat_id], opts)
    end
  end

  @doc "Sends captured clipboard text to an explicit Messages chat ID, once."
  def clipboard_to_chat(chat_id, opts \\ []) do
    with :ok <- Automation.required_string(chat_id, "Chat ID") do
      Composition.run(&send_clipboard/1, [chat_id], opts)
    end
  end

  @doc "Imports selected Finder files into a new Photos album. Supports folder_id and skip_duplicates."
  def selection_to_album(name, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ [:folder_id, :skip_duplicates]) do
      Finder.with_selection(
        fn paths -> Photos.import_into_new_album(paths, name, Keyword.drop(opts, @execution)) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Applies Image Events steps to selected Finder files. Supports format and execution limits."
  def selection_to_images(destination, steps, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ [:format]) do
      Finder.with_selection(
        fn paths -> ImageEvents.process_many(paths, destination, steps, Keyword.take(opts, [:format])) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Saves the current Safari page to Notes. Uses selected text when present, otherwise page text; supports title/folder_id."
  def current_page_to_note(opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ @note) do
      Composition.run(
        fn -> do_current_page_to_note(opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Reminder from the current Safari page, including its URL and selected text."
  def current_page_to_reminder(list_id, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "Reminder list ID"),
         :ok <- Automation.options(opts, @execution ++ @reminder) do
      Composition.run(
        fn -> do_current_page_to_reminder(list_id, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Mail draft containing the current Safari page URL and selected text."
  def current_page_to_draft(mail_options, opts \\ []) do
    with :ok <- mail_options(mail_options) do
      Composition.run(
        fn -> do_current_page_to_draft(mail_options) end,
        opts
      )
    end
  end

  @doc "Creates a plain-text Note from a captured text clipboard. Supports folder_id."
  def clipboard_to_note(title, opts \\ []) do
    with :ok <- Automation.required_string(title, "Note title"),
         :ok <- Automation.options(opts, @execution ++ [:folder_id]) do
      Composition.run(
        fn -> do_clipboard_to_note(title, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Reminder with captured text clipboard content as its body."
  def clipboard_to_reminder(list_id, title, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "Reminder list ID"),
         :ok <- Automation.required_string(title, "Reminder title"),
         :ok <- Automation.options(opts, @execution ++ @reminder) do
      Composition.run(
        fn -> do_clipboard_to_reminder(list_id, title, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Runs a Shortcut on captured clipboard text. Does not change the clipboard."
  def clipboard_to_shortcut(identifier, opts \\ []) do
    with :ok <- Automation.required_string(identifier, "Shortcut identity"),
         :ok <- Automation.options(opts, @execution ++ @shortcut) do
      Composition.run(
        fn -> do_clipboard_to_shortcut(identifier, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Runs a Shortcut and replaces the text clipboard with its text output. Empty output writes an empty string."
  def shortcut_to_clipboard(identifier, input, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ [:trim]) do
      Composition.run(
        fn -> do_shortcut_to_clipboard(identifier, input, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Copies a Mail message's subject, sender and text to Notes; supports title/folder_id."
  def message_to_note(account_id, mailbox, message_id, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ @note) do
      Composition.run(
        fn -> do_message_to_note(account_id, mailbox, message_id, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Reminder from a Mail message without changing message flags."
  def message_to_reminder(account_id, mailbox, message_id, list_id, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "Reminder list ID"),
         :ok <- Automation.options(opts, @execution ++ @reminder) do
      Composition.run(
        fn -> do_message_to_reminder(account_id, mailbox, message_id, list_id, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Note with an event's title, dates, location and description. Supports title/folder_id."
  def event_to_note(calendar_id, event_id, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ @note) do
      Composition.run(
        fn -> do_event_to_note(calendar_id, event_id, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Reminder for an event, defaulting its due date to the event start."
  def event_to_reminder(calendar_id, event_id, list_id, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "Reminder list ID"),
         :ok <- Automation.options(opts, @execution ++ @reminder) do
      Composition.run(
        fn -> do_event_to_reminder(calendar_id, event_id, list_id, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc "Creates a Reminder using a Note's title and plain text; leaves the source Note intact."
  def note_to_reminder(note_id, list_id, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "Reminder list ID"),
         :ok <- Automation.options(opts, @execution ++ @reminder) do
      Composition.run(
        fn -> do_note_to_reminder(note_id, list_id, opts) end,
        Keyword.take(opts, @execution)
      )
    end
  end

  @doc """
  Creates a Calendar event from a Reminder. Event attributes must include explicit
  start_at and end_at; title/description default to the Reminder. The optional
  complete_reminder boolean marks it complete only after event creation succeeds.
  Returns event_id and reminder_id. No effect is retried.
  """
  def reminder_to_event(reminder_id, calendar_id, attributes, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ [:complete_reminder, :verify_event, :list_id]),
         :ok <-
           Automation.options(attributes, [
             :title,
             :start_at,
             :end_at,
             :all_day,
             :description,
             :location,
             :recurrence,
             :url
           ]),
         true <-
           is_boolean(Keyword.get(opts, :complete_reminder, false)) and
             is_boolean(Keyword.get(opts, :verify_event, false)) do
      Composition.run(
        fn -> do_reminder_to_event(reminder_id, calendar_id, attributes, opts) end,
        Keyword.take(opts, @execution)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("complete_reminder and verify_event must be booleans")
    end
  end

  @doc """
  Opens a persistent workspace: Finder folder, optional applications and Safari
  URLs. Returns application identities and owned Page references. Options are
  applications (identities), urls, timeout and max_output_bytes. Created windows
  stay open; partial results identify resources if a later step fails.
  """
  def open_workspace(directory, opts \\ []) do
    with :ok <- Automation.options(opts, @execution ++ [:applications, :urls]),
         true <- is_binary(directory) and File.dir?(directory),
         :ok <- identity_list(Keyword.get(opts, :applications, [])),
         :ok <- identity_list(Keyword.get(opts, :urls, [])) do
      Composition.run(
        fn -> do_open_workspace(directory, opts) end,
        Keyword.take(opts, @execution)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Workspace folder must exist")
    end
  end

  defp capture_page do
    Safari.capture_current()
  end

  defp send_page(chat_id) do
    with {:ok, page} <- capture_page() do
      Composition.effect(:send_message, &Messages.send_to_chat/2, [chat_id, page.url <> "\n\n" <> page.selection])
    end
  end

  defp send_clipboard(chat_id) do
    with {:ok, text} <- Composition.step(:read_clipboard, &StandardAdditions.clipboard/0) do
      Composition.effect(:send_message, &Messages.send_to_chat/2, [chat_id, text])
    end
  end

  defp create_reminder(list_id, title, body, opts) do
    attrs = opts |> Keyword.take(@reminder) |> Keyword.put_new(:title, title) |> Keyword.put(:body, body)
    Composition.effect(:create_reminder, fn -> Reminders.create_reminder(list_id, attrs) end)
  end

  defp read_message(account, mailbox, id),
    do: Composition.step(:read_message, fn -> Mail.capture_message(account, mailbox, id) end)

  defp read_event(calendar, id), do: Composition.step(:read_event, fn -> Calendar.capture_event(calendar, id) end)
  defp message_body(message), do: Capture.render(message)

  defp event_body(event), do: Capture.render(event)

  defp maybe_complete(id, opts) do
    if opts[:complete_reminder],
      do: Composition.effect(:complete_reminder, fn -> Reminders.complete_reminder(id, list_id: opts[:list_id]) end),
      else: :ok
  end

  defp mail_options(opts), do: Automation.options(opts, [:to, :subject, :body, :cc, :bcc, :sender, :from])

  defp identity_list(values) do
    if is_list(values) and length(values) <= 1000,
      do: Validation.all(values, &Automation.required_string(&1, "Application identity or URL")),
      else: Automation.invalid("Applications and URLs must be lists of at most 1000 strings")
  end

  defp do_current_page_to_note(opts) do
    with {:ok, page} <- capture_page() do
      Composition.effect(:create_note, fn ->
        Notes.create_from(page, Keyword.take(opts, [:folder_id, :title]))
      end)
    end
  end

  defp do_current_page_to_reminder(list_id, opts) do
    with {:ok, page} <- capture_page() do
      Composition.effect(:create_reminder, fn -> Reminders.create_from(list_id, page, Keyword.take(opts, @reminder)) end)
    end
  end

  defp do_current_page_to_draft(mail_options) do
    with {:ok, page} <- capture_page() do
      Composition.effect(:create_draft, fn -> Mail.create_draft_from(page, mail_options) end)
    end
  end

  defp do_clipboard_to_note(title, opts) do
    with {:ok, text} <- Composition.step(:read_clipboard, &StandardAdditions.clipboard/0) do
      Composition.effect(:create_note, fn ->
        Notes.create_text_note(title, text, Keyword.take(opts, [:folder_id]))
      end)
    end
  end

  defp do_clipboard_to_reminder(list_id, title, opts) do
    with {:ok, text} <- Composition.step(:read_clipboard, &StandardAdditions.clipboard/0),
         do: create_reminder(list_id, title, text, opts)
  end

  defp do_clipboard_to_shortcut(identifier, opts) do
    with {:ok, text} <- Composition.step(:read_clipboard, &StandardAdditions.clipboard/0) do
      Composition.effect(:run_shortcut, fn ->
        Shortcuts.run(identifier, Keyword.put(Keyword.take(opts, @shortcut), :input, text))
      end)
    end
  end

  defp do_shortcut_to_clipboard(identifier, input, opts) do
    with {:ok, text} <- shortcut_text(identifier, input, opts),
         :ok <- Composition.effect(:write_clipboard, &StandardAdditions.set_clipboard/1, [text]) do
      {:ok, text}
    end
  end

  defp shortcut_text(identifier, input, opts) do
    options = Keyword.merge(Keyword.take(opts, [:trim]), input: input, output: :text)

    case Composition.effect(:run_shortcut, &Shortcuts.run/2, [identifier, options]) do
      :ok -> {:ok, ""}
      result -> result
    end
  end

  defp do_message_to_note(account_id, mailbox, message_id, opts) do
    with {:ok, message} <- read_message(account_id, mailbox, message_id) do
      Composition.effect(:create_note, fn ->
        Notes.create_text_note(
          Keyword.get(opts, :title, Capture.title(message)),
          message_body(message),
          Keyword.take(opts, [:folder_id])
        )
      end)
    end
  end

  defp do_message_to_reminder(account_id, mailbox, message_id, list_id, opts) do
    with {:ok, message} <- read_message(account_id, mailbox, message_id),
         do: create_reminder(list_id, Capture.title(message), message_body(message), opts)
  end

  defp do_event_to_note(calendar_id, event_id, opts) do
    with {:ok, event} <- read_event(calendar_id, event_id) do
      Composition.effect(:create_note, fn ->
        Notes.create_text_note(
          Keyword.get(opts, :title, Capture.title(event)),
          event_body(event),
          Keyword.take(opts, [:folder_id])
        )
      end)
    end
  end

  defp do_event_to_reminder(calendar_id, event_id, list_id, opts) do
    with {:ok, event} <- read_event(calendar_id, event_id) do
      create_reminder(list_id, Capture.title(event), event_body(event), Keyword.put_new(opts, :due_at, event.start_at))
    end
  end

  defp do_note_to_reminder(note_id, list_id, opts) do
    with {:ok, note} <- Composition.step(:read_note, fn -> Notes.get_note(note_id) end),
         do: create_reminder(list_id, note.title, note.plaintext, opts)
  end

  defp do_reminder_to_event(reminder_id, calendar_id, attributes, opts) do
    with {:ok, reminder} <-
           Composition.step(:read_reminder, fn -> Reminders.get_reminder(reminder_id, list_id: opts[:list_id]) end),
         attrs =
           attributes
           |> Keyword.put_new(:title, reminder.title)
           |> Keyword.put_new(:description, reminder.body || ""),
         {:ok, id} <- Composition.effect(:create_event, fn -> Calendar.create_event(calendar_id, attrs) end),
         :ok <- maybe_verify_event(calendar_id, id, attrs, opts),
         :ok <- maybe_complete(reminder_id, opts) do
      {:ok, %{event_id: id, reminder_id: reminder_id}}
    end
  end

  defp maybe_verify_event(calendar_id, id, attrs, opts) do
    if opts[:verify_event], do: verify_event(calendar_id, id, attrs), else: :ok
  end

  defp verify_event(calendar_id, id, attrs) do
    key = make_ref()

    try do
      case Composition.verify(:created_event, &event_matches?(calendar_id, id, attrs, key, &1)) do
        {:error, error} ->
          {:error,
           %{
             error
             | details:
                 Map.put(error.details || %{}, :event_verification, %{
                   calendar_id: calendar_id,
                   event_id: id,
                   expected: Map.new(attrs),
                   observed: Process.get(key)
                 })
           }}

        result ->
          result
      end
    after
      Process.delete(key)
    end
  end

  defp event_matches?(calendar, id, attrs, key, remaining) do
    with {:ok, event} <- Calendar.get_event(calendar, id, timeout: remaining) do
      Process.put(key, Map.take(event, Keyword.keys(attrs)))
      Enum.all?(attrs, &event_field_matches?(&1, event))
    end
  end

  defp event_field_matches?({key, expected}, event) when key in [:start_at, :end_at] do
    with {:ok, expected} <- Automation.date(expected),
         {:ok, actual} <- Automation.date(Map.get(event, key)),
         {:ok, expected, _} <- DateTime.from_iso8601(expected),
         {:ok, actual, _} <- DateTime.from_iso8601(actual) do
      DateTime.compare(expected, actual) == :eq
    else
      _ -> false
    end
  end

  defp event_field_matches?({key, expected}, event) when key in [:description, :location, :url, :recurrence],
    do: (Map.get(event, key) || "") == (expected || "")

  defp event_field_matches?({key, expected}, event), do: Map.get(event, key) == expected

  defp do_open_workspace(directory, opts) do
    with {:ok, apps} <-
           Composition.map(
             Keyword.get(opts, :applications, []),
             :ensure_application,
             &Applications.ensure_running/1
           ),
         :ok <- Composition.effect(:open_folder, fn -> Finder.new_window(directory) end),
         {:ok, pages} <- Composition.map(Keyword.get(opts, :urls, []), :open_page, &Safari.open_page/1) do
      {:ok, %{folder: Path.expand(directory), applications: apps, pages: pages}}
    end
  end
end
