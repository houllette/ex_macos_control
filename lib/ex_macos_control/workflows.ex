defmodule ExMacOSControl.Workflows do
  @moduledoc """
  Cross-application compositions built from the native app APIs.

  Sources (selection, page, message or clipboard) are captured once. Writes are
  attempted once and share a total deadline, defaulting to 30 seconds. Errors
  include acknowledged completed steps; account changes are not rolled back.
  Mail handoffs create drafts and never send them. Every destination is explicit.

  Page captures require Safari's JavaScript from Apple Events setting. Note
  bodies are escaped HTML. Reminder and mail bodies are plain text. App-specific
  options are accepted only where documented; timeout/max_output_bytes are shared.
  """
  @doc "Runs a Shortcut with the captured Finder selection as native file input."
  defdelegate selection_to_shortcut(identifier, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Mail draft attaching selected Finder files. Mail options are passed separately."
  defdelegate selection_to_draft(mail_options, opts \\ []), to: ExMacOSControl.Workflows.Recipes
  @doc "Captures selected files and creates a verified saved Mail draft, returning a durable Draft reference."
  defdelegate selection_to_verified_draft(mail_options, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Sends selected Finder files to an explicit Messages chat ID. Real sends, attempted once each."
  defdelegate selection_to_chat(chat_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Sends the current Safari page URL and selected text to an explicit Messages chat ID, once."
  defdelegate current_page_to_chat(chat_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Sends captured clipboard text to an explicit Messages chat ID, once."
  defdelegate clipboard_to_chat(chat_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Imports selected Finder files into a new Photos album. Supports folder_id and skip_duplicates."
  defdelegate selection_to_album(name, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Applies Image Events steps to selected Finder files. Supports format and execution limits."
  defdelegate selection_to_images(destination, steps, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Saves the current Safari page to Notes. Uses selected text when present, otherwise page text; supports title/folder_id."
  defdelegate current_page_to_note(opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Reminder from the current Safari page, including its URL and selected text."
  defdelegate current_page_to_reminder(list_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Mail draft containing the current Safari page URL and selected text."
  defdelegate current_page_to_draft(mail_options, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a plain-text Note from a captured text clipboard. Supports folder_id."
  defdelegate clipboard_to_note(title, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Reminder with captured text clipboard content as its body."
  defdelegate clipboard_to_reminder(list_id, title, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Runs a Shortcut on captured clipboard text. Does not change the clipboard."
  defdelegate clipboard_to_shortcut(identifier, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Runs a Shortcut and replaces the text clipboard with its text output. Empty output writes an empty string."
  defdelegate shortcut_to_clipboard(identifier, input, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Copies a Mail message's subject, sender and text to Notes; supports title/folder_id."
  defdelegate message_to_note(account_id, mailbox, message_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Reminder from a Mail message without changing message flags."
  defdelegate message_to_reminder(account_id, mailbox, message_id, list_id, opts \\ []),
    to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Note with an event's title, dates, location and description. Supports title/folder_id."
  defdelegate event_to_note(calendar_id, event_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Reminder for an event, defaulting its due date to the event start."
  defdelegate event_to_reminder(calendar_id, event_id, list_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Reminder using a Note's title and plain text; leaves the source Note intact."
  defdelegate note_to_reminder(note_id, list_id, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Creates a Calendar event from a Reminder. Requires start_at and end_at; title/description default to the Reminder. complete_reminder marks it complete after creation is acknowledged. Set verify_event: true to read back all requested event fields before completing the reminder. Returns event_id and reminder_id. No effect is retried."
  defdelegate reminder_to_event(reminder_id, calendar_id, attributes, opts \\ []), to: ExMacOSControl.Workflows.Recipes

  @doc "Opens a persistent workspace: Finder folder, optional applications and Safari\nURLs. Returns application identities and owned Page references. Options are\napplications (identities), urls, timeout and max_output_bytes. Created windows\nstay open; partial results identify resources if a later step fails.\n"
  defdelegate open_workspace(directory, opts \\ []), to: ExMacOSControl.Workflows.Recipes
end
