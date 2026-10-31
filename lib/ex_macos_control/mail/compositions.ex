defmodule ExMacOSControl.Mail.Compositions do
  @moduledoc false
  alias ExMacOSControl.{Automation, Composition, Desktop, Error, Mail}
  alias ExMacOSControl.Mail.Draft

  def create(opts) do
    with :ok <- validate(opts),
         {:ok, files} <- attachment_snapshot(Keyword.get(opts, :attachments, [])) do
      Desktop.with_lock(fn -> create_workflow(opts, files) end, Keyword.take(opts, [:timeout, :max_output_bytes]))
    end
  end

  defp create_workflow(opts, files) do
    Composition.effect(:create_verified_draft, fn -> create_and_verify(opts, files) end, resource: :draft)
  end

  defp create_and_verify(opts, files) do
    with {:ok, before} <- Composition.step(:existing_drafts, fn -> draft_snapshot(opts[:subject]) end),
         {:ok, outgoing} <-
           Composition.effect(:create_draft, fn -> Mail.create_draft(opts) end,
             resource: :outgoing_draft,
             identity: process_identity(before.pid)
           ) do
      await_saved(before.ids, outgoing, opts, files, before.pid)
    end
  end

  defp await_saved(before, outgoing, opts, files, pid) do
    key = make_ref()

    try do
      predicate = &observe_saved(before, opts, files, key, &1)

      case Composition.verify(:saved_draft, predicate) do
        :ok ->
          record = Process.get(key)

          {:ok,
           %Draft{
             id: record.id,
             outgoing_id: outgoing,
             subject: opts[:subject],
             message_id: Map.get(record, :message_id),
             mail_pid: pid,
             created_at: DateTime.utc_now()
           }}

        {:error, %Error{} = error} ->
          {:error, %{error | details: Map.merge(error.details || %{}, %{outcome: :unknown, outgoing_id: outgoing})}}
      end
    after
      Process.delete(key)
    end
  end

  defp observe_saved(before, opts, files, key, remaining) do
    params = %{
      before: before,
      subject: opts[:subject],
      body: opts[:body],
      recipients: List.wrap(opts[:to]) |> Enum.map(&String.downcase(String.trim(&1))),
      cc: Enum.map(Keyword.get(opts, :cc, []), &String.downcase(String.trim(&1))),
      bcc: Enum.map(Keyword.get(opts, :bcc, []), &String.downcase(String.trim(&1))),
      sender: opts[:sender] || opts[:from],
      attachments: files
    }

    case Automation.query(
           "com.apple.mail",
           """
           function address(s){var m=String(s).match(/<([^<>]+)>\\s*$/);return (m?m[1]:String(s)).trim().toLowerCase();}
           function addresses(values){return values.map(address).sort();}
           function text(s){return String(s).replace(/\\r\\n?/g,'\\n').replace(/\\uFFFC/g,'').split('\\n').map(function(s){return s.replace(/[ \\t]+$/,'');}).join('\\n').trim();}
           function attachments(values){return values.sort(function(a,b){return a.name.localeCompare(b.name)||a.size-b.size;});}
           return app.draftsMailbox().messages.whose({subject:input.subject})().filter(function(o){
             if(input.before.indexOf(o.id())>=0 || text(o.content())!==text(input.body))return false;
             if(input.sender && address(o.sender())!==address(input.sender))return false;
             var files=o.mailAttachments().map(function(a){return {name:a.name(),size:a.fileSize()};});
             return JSON.stringify(addresses(o.toRecipients.address()))===JSON.stringify(input.recipients.sort()) &&
               JSON.stringify(addresses(o.ccRecipients.address()))===JSON.stringify(input.cc.sort()) &&
               JSON.stringify(addresses(o.bccRecipients.address()))===JSON.stringify(input.bcc.sort()) &&
               JSON.stringify(attachments(files))===JSON.stringify(attachments(input.attachments));
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

  defp draft_snapshot(subject) do
    result =
      Automation.query(
        "com.apple.mail",
        mail_process() <>
          "var ids=app.draftsMailbox().messages.whose({subject:input.subject})().map(function(o){return o.id();});var pid=mailPID();if(!pid)throw new Error('Mail stopped before draft creation');return {ids:ids,pid:pid};",
        %{subject: subject}
      )

    case result do
      {:ok, %{ids: ids, pid: pid} = snapshot} when is_list(ids) and is_integer(pid) and pid > 0 ->
        if Enum.all?(ids, &(is_integer(&1) or is_binary(&1))),
          do: {:ok, snapshot},
          else: invalid_snapshot()

      {:error, %Error{} = error} ->
        {:error, %{error | details: Map.put(error.details || %{}, :outcome, :not_started)}}

      _ ->
        invalid_snapshot()
    end
  end

  defp invalid_snapshot, do: {:error, Error.execution_error("Invalid Mail process snapshot", outcome: :not_started)}

  defp attachment_snapshot(paths) when is_list(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, files} ->
      case attachment_info(path) do
        {:ok, file} -> {:cont, {:ok, files ++ [file]}}
        error -> {:halt, error}
      end
    end)
  end

  defp attachment_snapshot(_), do: Automation.invalid("Attachments must be a list of existing files")

  defp attachment_info(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} -> {:ok, %{name: Path.basename(path), size: size}}
      _ -> Automation.invalid("An attachment file is unavailable")
    end
  end

  defp attachment_info(_), do: Automation.invalid("Attachment paths must be strings")

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
    Desktop.with_lock(fn -> delete_workflow(draft) end, opts)
  end

  defp delete_workflow(draft) do
    identity = Map.merge(%{id: draft.id, outgoing_id: draft.outgoing_id}, process_identity(draft.mail_pid))

    with :ok <- Composition.effect(:delete_draft, fn -> delete_native(draft) end, resource: :draft, identity: identity),
         do: Composition.verify(:draft_absent, &draft_absent?(draft, &1))
  end

  defp delete_native(draft) do
    Automation.action(
      "com.apple.mail",
      mail_process() <>
        """
        var box=app.draftsMailbox(),ids=box.messages.id();
        if(ids.map(String).indexOf(String(input.id))>=0){#{resolve()}}
        if(input.mail_pid && mailPID()===input.mail_pid){
          var outgoing=app.outgoingMessages(),matches=outgoing.filter(function(o){return String(o.id())===String(input.outgoing_id);});
          if(matches.length>1)throw new Error('Ambiguous outgoing draft');
          if(matches.length===1){
            if(matches[0].subject()!==input.subject)throw new Error('Outgoing draft identity changed');
            app.close(matches[0],{saving:'no'});
          }
        }
        if(box.messages.id().map(String).indexOf(String(input.id))>=0){#{resolve()}app.delete(o);}
        """,
      params(draft)
    )
  end

  defp draft_absent?(draft, remaining) do
    Automation.query(
      "com.apple.mail",
      mail_process() <>
        """
        if(app.draftsMailbox().messages.id().map(String).indexOf(String(input.id))>=0)return false;
        if(input.mail_pid && mailPID()===input.mail_pid)
          return app.outgoingMessages.id().map(String).indexOf(String(input.outgoing_id))<0;
        return true;
        """,
      params(draft),
      timeout: remaining
    )
  end

  defp mail_process do
    """
    function mailPID(){ObjC.import('AppKit');var values=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($('com.apple.mail'));
      if(values.count>1)throw new Error('Ambiguous Mail process');var process=values.firstObject;return process.isNil()?null:Number(process.processIdentifier);}
    """
  end

  defp process_identity(pid) when is_integer(pid) and pid > 0, do: %{application_pid: pid}
  defp process_identity(_), do: %{}

  defp resolve do
    """
    var o=byId(app.draftsMailbox().messages,input.id);
    if(o.subject()!==input.subject || (input.message_id && o.messageId()!==input.message_id))throw new Error('Saved draft identity changed');
    """
  end

  defp params(draft),
    do: %{
      id: draft.id,
      subject: draft.subject,
      message_id: draft.message_id,
      outgoing_id: draft.outgoing_id,
      mail_pid: draft.mail_pid
    }

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
