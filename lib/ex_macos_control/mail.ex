defmodule ExMacOSControl.Mail do
  @moduledoc """
  Automation helpers for macOS Mail app.

  Provides functions to send emails, check unread counts, and search mailboxes
  programmatically using AppleScript.

  ## Requirements

  - macOS Mail.app must be installed (pre-installed on macOS)
  - Mail.app must be configured with at least one email account for sending
  - Automation permission for Mail.app (macOS may prompt on first use)

  ## Permissions

  When using Mail automation, macOS may prompt for permission to control Mail.app.
  This is a one-time prompt that should be accepted.

  ## Examples

      # Send an email
      :ok = ExMacOSControl.Mail.send_email(
        to: "recipient@example.com",
        subject: "Hello",
        body: "This is an automated email."
      )

      # Check unread count
      {:ok, count} = ExMacOSControl.Mail.get_unread_count()

      # Check unread count for specific mailbox
      {:ok, count} = ExMacOSControl.Mail.get_unread_count("Work")

      # Search mailbox
      {:ok, messages} = ExMacOSControl.Mail.search_mailbox("INBOX", "important")

  ## Notes

  - `send_email/1` sends emails immediately - there is no "draft" mode
  - Email addresses are validated with basic checks only
  - Search is case-insensitive and searches subject lines
  - All functions require Mail.app to be accessible

  ## Safety

  Be cautious when using `send_email/1` in automated scripts. Consider:
  - Adding confirmation prompts for production use
  - Testing with safe recipient addresses first
  - Implementing rate limiting if sending multiple emails
  """

  alias ExMacOSControl.{Automation, Composition, Error, ScriptOutput}

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    ExMacOSControl
  end

  @doc """
  Sends an email using the macOS Mail app.

  Creates and sends an email immediately with the specified recipients and content.
  Mail.app must be configured with an email account.

  ## Options

    * `:to` - (required) Recipient email address or list of addresses
    * `:subject` - (required) Email subject (string)
    * `:body` - (required) Email body text (string)
    * `:cc` - (optional) CC recipients (list of strings)
    * `:bcc` - (optional) BCC recipients (list of strings)
    * `:sender` - (optional) Configured sender address
    * `:attachments` - (optional) Existing file paths
    * `:timeout`, `:max_output_bytes` - Execution deadline and output bound

  ## Returns

    * `:ok` - Mail accepted the send command; this does not prove delivery
    * `{:error, error}` - Failed to send (see error types below)

  ## Error Types

    * `:execution_error` - Mail not configured, invalid email, or send failed
    * `:execution_error` - Missing required fields

  ## Examples

      iex> ExMacOSControl.Mail.send_email(
      ...>   to: "friend@example.com",
      ...>   subject: "Hello",
      ...>   body: "How are you?"
      ...> )
      :ok

      iex> ExMacOSControl.Mail.send_email(
      ...>   to: "team@example.com",
      ...>   subject: "Meeting Notes",
      ...>   body: "Here are today's notes.",
      ...>   cc: ["manager@example.com"]
      ...> )
      :ok

  ## Safety Notes

    * Email is sent immediately - there is no undo
    * Verify recipient addresses before sending
    * Consider adding confirmation for production use

  ## Requirements

    * Mail.app must be configured with an email account
    * Network connection required
    * Automation permission for Mail.app
  """
  @spec send_email(keyword()) :: :ok | {:error, Error.t()}
  def send_email(opts) do
    with :ok <- validate_email_opts(opts),
         :ok <- validate_email_list(List.wrap(opts[:to])),
         :ok <- validate_email_list(Keyword.get(opts, :cc, [])),
         :ok <- validate_email_list(Keyword.get(opts, :bcc, [])),
         :ok <- validate_attachments(opts) do
      script = build_message_script(opts)

      send_result(
        ExMacOSControl.with_options(Keyword.take(opts, [:timeout, :max_output_bytes]), fn ->
          adapter().run_applescript(script)
        end)
      )
    end
  end

  defp send_result({:ok, "true"}), do: :ok
  defp send_result({:ok, _}), do: {:error, Error.execution_error("Mail did not accept the message for sending")}
  defp send_result({:error, _} = error), do: error

  @doc """
  Gets the count of unread messages in the inbox.

  Returns the number of unread messages in the default inbox mailbox.

  ## Returns

    * `{:ok, count}` - Number of unread messages (integer >= 0)
    * `{:error, error}` - If Mail is not running or accessible

  ## Examples

      ExMacOSControl.Mail.get_unread_count()
      # => {:ok, 42}

      # When inbox is empty
      ExMacOSControl.Mail.get_unread_count()
      # => {:ok, 0}

  """
  @spec get_unread_count() :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_unread_count do
    script = """
    tell application "Mail"
      return unread count of inbox
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        parse_count(output)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the count of unread messages in a specific mailbox.

  Returns the number of unread messages in the specified mailbox.

  ## Parameters

    * `mailbox_name` - Name of the mailbox to check

  ## Returns

    * `{:ok, count}` - Number of unread messages (integer >= 0)
    * `{:error, error}` - If mailbox doesn't exist or Mail is not accessible

  ## Examples

      ExMacOSControl.Mail.get_unread_count("Work")
      # => {:ok, 5}

      ExMacOSControl.Mail.get_unread_count("Archive")
      # => {:ok, 0}

  """
  @spec get_unread_count(String.t() | keyword()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_unread_count(opts) when is_list(opts), do: ExMacOSControl.with_options(opts, &get_unread_count/0)

  def get_unread_count(mailbox_name) when is_binary(mailbox_name) do
    script = """
    tell application "Mail"
      return unread count of mailbox "#{escape_quotes(mailbox_name)}"
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        parse_count(output)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches for messages in a mailbox.

  Searches message subjects in the specified mailbox for the given search term.
  The search is case-insensitive.

  ## Parameters

    * `mailbox_name` - Name of the mailbox to search
    * `search_term` - Term to search for in message subjects

  ## Returns

    * `{:ok, messages}` - List of matching messages
    * `{:ok, []}` - If no matches found
    * `{:error, error}` - If mailbox doesn't exist or Mail is not accessible

  Each message is a map with the following keys:
    * `:subject` - Message subject (string)
    * `:from` - Sender email/name (string)
    * `:date` - Date received (string)

  ## Examples

      ExMacOSControl.Mail.search_mailbox("INBOX", "invoice")
      # => {:ok, [
      #      %{subject: "Invoice #123", from: "billing@example.com", date: "2025-01-15"},
      #      %{subject: "Re: Invoice", from: "support@example.com", date: "2025-01-14"}
      #    ]}

      # No matches
      ExMacOSControl.Mail.search_mailbox("INBOX", "nonexistent")
      # => {:ok, []}

  ## Notes

    * Search is case-insensitive
    * Only searches subject lines
    * This legacy helper preserves Mail's enumeration order; use search_messages/3 for explicit date ordering
  """
  @spec search_mailbox(String.t(), String.t()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def search_mailbox(mailbox_name, search_term) do
    script = """
    tell application "Mail"
      set matchingMessages to (messages of mailbox "#{escape_quotes(mailbox_name)}" whose subject contains "#{escape_quotes(search_term)}")
      set results to {}
      repeat with aMessage in matchingMessages
        set msgSubject to subject of aMessage
        set msgFrom to sender of aMessage
        set msgDate to date received of aMessage as text
        set end of results to {msgSubject, msgFrom, msgDate}
      end repeat
      return my exmc_encode_rows(results)
    end tell
    #{ScriptOutput.handlers()}
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        with {:ok, rows} <- ScriptOutput.decode(output, 3) do
          {:ok, Enum.map(rows, fn [subject, from, date] -> %{subject: subject, from: from, date: date} end)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Helpers

  # Validates that required email options are present
  @spec validate_email_opts(keyword()) :: :ok | {:error, Error.t()}
  defp validate_email_opts(opts) do
    allowed = [:to, :subject, :body, :cc, :bcc, :sender, :from, :attachments, :timeout, :max_output_bytes]

    if not is_list(opts) or not Keyword.keyword?(opts) or Keyword.keys(opts) -- allowed != [] do
      {:error, Error.execution_error("Unknown or invalid Mail options")}
    else
      validate_required_fields(opts)
    end
  end

  defp validate_required_fields(opts) do
    required_fields = [:to, :subject, :body]

    missing_field =
      Enum.find(required_fields, fn field ->
        is_nil(opts[field]) or opts[field] in ["", []]
      end)

    case missing_field do
      nil ->
        validate_message_text(opts)

      field ->
        {:error, Error.execution_error("Missing required field", field: field)}
    end
  end

  defp validate_message_text(opts) do
    if is_binary(opts[:subject]) and is_binary(opts[:body]) do
      :ok
    else
      {:error, Error.execution_error("Subject and body must be strings")}
    end
  end

  # Validates a list of email addresses
  @spec validate_email_list(list(String.t())) :: :ok | {:error, Error.t()}
  defp validate_email_list(emails) when is_list(emails) do
    case Enum.find_index(emails, &(not valid_email?(&1))) do
      nil ->
        :ok

      index ->
        {:error, Error.execution_error("Invalid email address", address: Enum.at(emails, index))}
    end
  end

  defp validate_email_list(emails) do
    {:error, Error.execution_error("Recipients must be a list of email addresses", recipients: emails)}
  end

  # Basic email validation
  @spec valid_email?(String.t()) :: boolean()
  defp valid_email?(email) when is_binary(email) do
    String.contains?(email, "@") and
      String.match?(email, ~r/^[^@]+@[^@]+\.[^@]+$/)
  end

  defp valid_email?(_), do: false

  # Builds AppleScript for creating and sending a message
  @spec build_message_script(keyword()) :: String.t()
  defp build_message_script(opts, operation \\ "send") do
    to_recipients = format_recipients(List.wrap(opts[:to]), "to recipient")
    sender = opts[:sender] || opts[:from]
    sender_property = if sender, do: ~s(, sender:"#{escape_quotes(sender)}"), else: ""

    attachments =
      Enum.map_join(Keyword.get(opts, :attachments, []), "\n", fn path ->
        ~s(make new attachment with properties {file name:POSIX file "#{escape_quotes(Path.expand(path))}"} at after the last paragraph)
      end)

    subject = escape_quotes(opts[:subject])
    body = escape_quotes(opts[:body])
    cc = opts[:cc] || []
    bcc = opts[:bcc] || []

    cc_recipients = format_recipients(cc, "cc recipient")
    bcc_recipients = format_recipients(bcc, "bcc recipient")

    """
    tell application "Mail"
      set newMessage to make new outgoing message with properties {subject:"#{subject}", content:"#{body}"#{sender_property}}
      tell newMessage
        #{to_recipients}
        #{cc_recipients}
        #{bcc_recipients}
        #{attachments}
        #{operation}
      end tell
    end tell
    """
  end

  # Formats recipients for AppleScript
  @spec format_recipients([String.t()], String.t()) :: String.t()
  defp format_recipients([], _type), do: ""

  defp format_recipients(emails, type) do
    Enum.map_join(emails, "\n        ", fn email ->
      "make new #{type} with properties {address:\"#{escape_quotes(email)}\"}"
    end)
  end

  # Parses unread count from AppleScript output
  @spec parse_count(String.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  defp parse_count(output) do
    output = String.trim(output)

    case Integer.parse(output) do
      {count, ""} when count >= 0 ->
        {:ok, count}

      _ ->
        {:error, Error.execution_error("Invalid unread count", output: output)}
    end
  end

  # Escapes double quotes in strings for AppleScript
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(string) do
    ExMacOSControl.Script.escape_string(string)
  end

  defp validate_attachments(opts) do
    files = Keyword.get(opts, :attachments, [])
    sender = opts[:sender] || opts[:from]

    cond do
      opts[:sender] && opts[:from] ->
        {:error, Error.execution_error("Choose sender or from")}

      not is_nil(sender) and not valid_email?(sender) ->
        {:error, Error.execution_error("Invalid sender address")}

      not valid_attachment_files?(files) ->
        {:error, Error.execution_error("Attachments must be existing files")}

      true ->
        :ok
    end
  end

  @doc "Creates and saves a draft without sending it; returns its outgoing-message ID."
  def create_draft(opts) do
    with :ok <- validate_email_opts(opts),
         :ok <- validate_email_list(List.wrap(opts[:to])),
         :ok <- validate_email_list(Keyword.get(opts, :cc, [])),
         :ok <- validate_email_list(Keyword.get(opts, :bcc, [])),
         :ok <- validate_attachments(opts) do
      execution = opts |> ExMacOSControl.Automation.execution_options() |> Keyword.put_new(:timeout, 30_000)

      ExMacOSControl.with_options(execution, fn ->
        adapter().run_applescript(build_message_script(opts, "save\n        return id as text"))
      end)
    end
  end

  defdelegate capture_message(account, mailbox, id, opts \\ []), to: ExMacOSControl.Capture, as: :message

  @doc "Creates a draft from captured content. File captures attach their paths; other captures supply text."
  def create_draft_from(capture, opts) do
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
           ]) do
      opts =
        opts
        |> Keyword.put_new(:subject, ExMacOSControl.Capture.title(capture))
        |> Keyword.put_new(:body, ExMacOSControl.Capture.render(capture, :reference))
        |> Keyword.put_new(:attachments, ExMacOSControl.Capture.files(capture))

      create_draft(opts)
    end
  end

  def list_accounts(opts \\ []),
    do: ExMacOSControl.Resources.list("com.apple.mail", "app.accounts", [id: "o.id()", name: "o.name()"], %{}, opts)

  def list_mailboxes(account_id, opts \\ []),
    do:
      ExMacOSControl.Resources.list(
        "com.apple.mail",
        "byId(app.accounts,input.account_id).mailboxes",
        [name: "o.name()", unread: "o.unreadCount()"],
        %{account_id: account_id},
        opts
      )

  @doc "Searches an account mailbox with paging and explicit newest-first ordering. Mailbox can be a name or a path of names."
  def search_messages(account_id, mailbox, opts \\ []) do
    alias ExMacOSControl.Automation

    with :ok <-
           Automation.options(opts, [:query, :sender, :read, :from, :to, :limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts),
         {:ok, from} <- Automation.date(opts[:from]),
         {:ok, to} <- Automation.date(opts[:to]) do
      code =
        mailbox_code() <>
          """
          var filter={}; if(input.query)filter.subject={_contains:input.query}; if(input.sender)filter.sender={_contains:input.sender}; if(input.read!==null)filter.readStatus=input.read;
          var values=box.messages.whose(filter)().map(function(o){return {o:o,date:o.dateReceived()};});
          values=values.filter(function(x){return (!input.from||x.date>=new Date(input.from))&&(!input.to||x.date<=new Date(input.to));});
          values.sort(function(a,b){return b.date-a.date;});
          return page(values).map(function(x){var o=x.o;return {id:o.id(),message_id:o.messageId(),subject:o.subject(),sender:o.sender(),received_at:iso(x.date),read:o.readStatus(),flagged:o.flaggedStatus()};});
          """

      params =
        Map.merge(paging, %{
          account_id: account_id,
          mailbox: mailbox,
          query: opts[:query],
          sender: opts[:sender],
          read: opts[:read],
          from: from,
          to: to
        })

      Automation.query("com.apple.mail", code, params, Automation.execution_options(opts))
    end
  end

  def get_message(account_id, mailbox, id, opts \\ []) do
    ExMacOSControl.Automation.query(
      "com.apple.mail",
      mailbox_code() <>
        "var o=byId(box.messages,input.id);return {id:o.id(),message_id:o.messageId(),subject:o.subject(),sender:o.sender(),received_at:iso(o.dateReceived()),content:o.content(),source:o.source(),read:o.readStatus(),attachments:o.mailAttachments().map(function(a,i){return {index:i+1,name:a.name(),size:a.fileSize()};})};",
      %{account_id: account_id, mailbox: mailbox, id: id},
      opts
    )
  end

  def update_message(account_id, mailbox, id, attrs, opts \\ []) do
    with {:ok, properties, _} <-
           ExMacOSControl.Resources.properties(attrs,
             read: {"readStatus", :boolean},
             flagged: {"flaggedStatus", :boolean},
             junk: {"junkMailStatus", :boolean}
           ) do
      ExMacOSControl.Automation.action(
        "com.apple.mail",
        mailbox_code() <>
          "var o=byId(box.messages,input.id);Object.keys(input.properties).forEach(function(key){o[key]=input.properties[key];});",
        %{account_id: account_id, mailbox: mailbox, id: id, properties: properties},
        opts
      )
    end
  end

  def save_attachment(account_id, mailbox, id, index, destination, opts \\ []) when is_integer(index) and index > 0 do
    with :ok <- ExMacOSControl.Automation.required_string(destination, "Output path"),
         false <- File.exists?(destination) do
      ExMacOSControl.Automation.action(
        "com.apple.mail",
        mailbox_code() <>
          "var a=byId(box.messages,input.id).mailAttachments[input.index-1];if(!a.exists())throw new Error('Attachment not found');app.save(a,{in:Path(input.path)});",
        %{account_id: account_id, mailbox: mailbox, id: id, index: index, path: Path.expand(destination)},
        opts
      )
    else
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("Attachment destination already exists")}
    end
  end

  def get_unread_count(mailbox, opts), do: ExMacOSControl.with_options(opts, fn -> get_unread_count(mailbox) end)

  def search_mailbox(mailbox, query, opts),
    do: ExMacOSControl.with_options(opts, fn -> search_mailbox(mailbox, query) end)

  @doc """
  Saves all attachments from one message into an existing directory, returning
  paths. Names are prefixed with their attachment index to avoid duplicates.
  Every output is checked for collisions before the first save. Completed paths
  survive in error details; saves are not retried.
  """
  def save_attachments(account_id, mailbox, id, destination, opts \\ []) do
    if is_binary(destination) and File.dir?(destination) do
      Composition.run(
        fn -> do_save_attachments(account_id, mailbox, id, destination) end,
        opts
      )
    else
      Automation.invalid("Attachment destination must be an existing directory")
    end
  end

  @doc """
  Creates a saved reply draft with quoted message text; does not send it.
  This is a new outgoing message, not a promise of Mail conversation threading.
  Options include body, sender, cc, bcc and execution limits.
  """
  def draft_reply(account_id, mailbox, id, opts \\ []) do
    with :ok <- Automation.options(opts, [:body, :sender, :cc, :bcc, :timeout, :max_output_bytes]),
         true <- is_binary(Keyword.get(opts, :body, "")) do
      Composition.run(
        fn -> do_draft_reply(account_id, mailbox, id, opts) end,
        Keyword.take(opts, [:timeout, :max_output_bytes])
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Reply body must be text")
    end
  end

  defp attachment_outputs(attachments, destination) do
    outputs =
      Enum.map(attachments, fn a ->
        {a.index, Path.join(Path.expand(destination), "#{a.index}-#{Path.basename(a.name)}")}
      end)

    if Enum.all?(outputs, fn {_index, path} -> File.lstat(path) == {:error, :enoent} end),
      do: {:ok, outputs},
      else: Automation.invalid("An attachment output already exists")
  end

  defp reply_address(sender) do
    case Regex.run(~r/<([^<>]+)>\s*$/, sender) do
      [_, address] -> address
      _ -> String.trim(sender)
    end
  end

  defp mailbox_code do
    """
    var parts=Array.isArray(input.mailbox)?input.mailbox:[input.mailbox];
    if(parts.length===0)throw new Error('Mailbox path is empty');
    var owner=byId(app.accounts,input.account_id),box;
    parts.forEach(function(name){box=owner.mailboxes.byName(name);if(!box.exists())throw new Error('Mailbox not found');owner=box;});
    """
  end

  defp valid_attachment_files?(files), do: is_list(files) and Enum.all?(files, &(is_binary(&1) and File.regular?(&1)))

  defp do_save_attachments(account_id, mailbox, id, destination) do
    with {:ok, message} <- Composition.step(:read_message, fn -> get_message(account_id, mailbox, id) end),
         {:ok, outputs} <- attachment_outputs(message.attachments, destination) do
      Composition.map(outputs, :save_attachment, &save_one_attachment(account_id, mailbox, id, &1))
    end
  end

  defp save_one_attachment(account_id, mailbox, id, {index, path}) do
    with :ok <- save_attachment(account_id, mailbox, id, index, path), do: {:ok, path}
  end

  defp do_draft_reply(account_id, mailbox, id, opts) do
    with {:ok, message} <- Composition.step(:read_message, fn -> get_message(account_id, mailbox, id) end) do
      recipient = reply_address(message.sender)
      subject = if Regex.match?(~r/^re:/i, message.subject), do: message.subject, else: "Re: " <> message.subject
      quoted = message.content |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))
      body = Keyword.get(opts, :body, "") <> "\n\n" <> quoted

      Composition.effect(:create_draft, fn ->
        create_draft(
          Keyword.merge(Keyword.take(opts, [:sender, :cc, :bcc]), to: recipient, subject: subject, body: body)
        )
      end)
    end
  end
end
