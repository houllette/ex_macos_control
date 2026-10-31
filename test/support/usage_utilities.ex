defmodule ExMacOSControl.UsageUtilities do
  @moduledoc false
  alias ExMacOSControl.{Composition, Finder, ImageEvents, Mail, Notes, Reminders, Workflows}

  def research(capture, folder, list, mail) do
    Composition.run(fn -> do_research(capture, folder, list, mail) end)
  end

  defp do_research(capture, folder, list, mail) do
    with {:ok, note} <- Composition.effect(:create_note, fn -> Notes.create_from(capture, folder_id: folder) end),
         {:ok, reminder} <- Composition.effect(:create_reminder, fn -> Reminders.create_from(list, capture) end),
         {:ok, draft} <- Mail.create_verified_draft_from(capture, mail) do
      {:ok, %{note: note, reminder: reminder, draft: draft}}
    end
  end

  def prepare_files(paths, staging, output, mail) do
    Composition.run(fn ->
      with {:ok, copies} <- Finder.copy_files(paths, staging),
           {:ok, outputs} <- ImageEvents.process_many(copies, output, scale: 16),
           {:ok, draft} <- Mail.create_verified_draft(Keyword.put(mail, :attachments, outputs)) do
        {:ok, %{copies: copies, outputs: outputs, draft: draft}}
      end
    end)
  end

  def schedule(reminder, calendar, attrs, opts \\ []),
    do:
      Workflows.reminder_to_event(
        reminder,
        calendar,
        attrs,
        Keyword.merge(opts, verify_event: true, complete_reminder: true)
      )
end
