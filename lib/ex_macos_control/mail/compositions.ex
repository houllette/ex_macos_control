defmodule ExMacOSControl.Mail.Compositions do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Error, Mail}
  alias ExMacOSControl.Mail.Draft

  def create(opts) do
    with :ok <- validate(opts) do
      Composition.run(&create_workflow/1, [opts], Keyword.take(opts, [:timeout, :max_output_bytes]))
    end
  end

  defp create_workflow(opts) do
    Composition.effect(:create_verified_draft, fn -> create_and_verify(opts) end, resource: :draft)
  end

  defp create_and_verify(opts) do
    with {:ok, before} <- Composition.step(:existing_drafts, fn -> matching_ids(opts[:subject]) end),
         {:ok, outgoing} <- Composition.effect(:create_draft, &Mail.create_draft/1, [opts]) do
      await_saved(before, outgoing, opts)
    end
  end

  defp await_saved(before, outgoing, opts) do
    key = make_ref()

    try do
      predicate = &observe_saved(before, opts, key, &1)

      case Composition.verify(:saved_draft, predicate) do
        :ok ->
          record = Process.get(key)

          {:ok,
           %Draft{
             id: record.id,
             outgoing_id: outgoing,
             subject: opts[:subject],
             message_id: Map.get(record, :message_id),
             created_at: DateTime.utc_now()
           }}

        {:error, %Error{} = error} ->
          {:error, %{error | details: Map.merge(error.details || %{}, %{outcome: :unknown, outgoing_id: outgoing})}}
      end
    after
      Process.delete(key)
    end
  end

  defp observe_saved(before, opts, key, remaining) do
    params = %{
      before: before,
      subject: opts[:subject],
      body: opts[:body],
      recipients: List.wrap(opts[:to]) |> Enum.map(&String.downcase(String.trim(&1))),
      attachments: Enum.map(Keyword.get(opts, :attachments, []), &Path.basename/1)
    }

    case Automation.query(
           "com.apple.mail",
           """
           return app.draftsMailbox().messages.whose({subject:input.subject})().filter(function(o){
             if(input.before.indexOf(o.id())>=0||o.content().indexOf(input.body)<0)return false;
             var recipients=o.toRecipients.address().map(function(s){return s.trim().toLowerCase();}).sort();
             var attachments=o.mailAttachments.name().sort();
             return JSON.stringify(recipients)===JSON.stringify(input.recipients.sort()) &&
               JSON.stringify(attachments)===JSON.stringify(input.attachments.sort());
           }).map(function(o){return {id:o.id(),message_id:o.messageId()};});
           """,
           params,
           timeout: remaining
         ) do
      {:ok, [record]} ->
        Process.put(key, record)
        true

      {:ok, []} ->
        false

      {:ok, _} ->
        Automation.invalid("More than one new saved draft matches; refusing to guess its identity")

      error ->
        error
    end
  end

  defp matching_ids(subject),
    do:
      Automation.query(
        "com.apple.mail",
        "return app.draftsMailbox().messages.whose({subject:input.subject})().map(function(o){return o.id();});",
        %{subject: subject}
      )

  def get(%Draft{} = draft, opts) do
    Automation.query(
      "com.apple.mail",
      resolve() <>
        "return {id:o.id(),subject:o.subject(),content:o.content(),attachments:o.mailAttachments().map(function(a){return {name:a.name(),size:a.fileSize()};})};",
      params(draft),
      opts
    )
  end

  def delete(%Draft{} = draft, opts) do
    Automation.action("com.apple.mail", resolve() <> "app.delete(o);", params(draft), opts)
  end

  defp resolve do
    """
    var o=byId(app.draftsMailbox().messages,input.id);
    if(o.subject()!==input.subject || (input.message_id && o.messageId()!==input.message_id))throw new Error('Saved draft identity changed');
    """
  end

  defp params(draft), do: %{id: draft.id, subject: draft.subject, message_id: draft.message_id}

  defp validate(opts) do
    with :ok <-
           Automation.options(opts, [
             :to,
             :subject,
             :body,
             :cc,
             :bcc,
             :sender,
             :from,
             :attachments,
             :timeout,
             :max_output_bytes
           ]),
         :ok <- Automation.required_string(opts[:subject], "Draft subject"),
         :ok <- Automation.required_string(opts[:body], "Draft body"),
         recipients = List.wrap(opts[:to]),
         true <- recipients != [] and Enum.all?(recipients, &is_binary/1) do
      :ok
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Draft recipients must be a non-empty list of email addresses")
    end
  end
end
