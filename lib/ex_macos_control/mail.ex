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

  alias ExMacOSControl.Error

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Sends an email using the macOS Mail app.

  Creates and sends an email immediately with the specified recipients and content.
  Mail.app must be configured with an email account.

  ## Options

    * `:to` - (required) Recipient email address (string)
    * `:subject` - (required) Email subject (string)
    * `:body` - (required) Email body text (string)
    * `:cc` - (optional) CC recipients (list of strings)
    * `:bcc` - (optional) BCC recipients (list of strings)

  ## Returns

    * `:ok` - Email sent successfully
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
         :ok <- validate_email_address(opts[:to]),
         :ok <- validate_email_list(opts[:cc] || []),
         :ok <- validate_email_list(opts[:bcc] || []) do
      script = build_message_script(opts)

      case adapter().run_applescript(script) do
        {:ok, _output} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

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
  @spec get_unread_count(String.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_unread_count(mailbox_name) do
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
    * Results are ordered by date (newest first)
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
        set end of results to msgSubject & "|" & msgFrom & "|" & msgDate
      end repeat
      return results as text
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, output} ->
        messages = parse_search_results(output)
        {:ok, messages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Helpers

  # Validates that required email options are present
  @spec validate_email_opts(keyword()) :: :ok | {:error, Error.t()}
  defp validate_email_opts(opts) do
    required_fields = [:to, :subject, :body]

    missing_field =
      Enum.find(required_fields, fn field ->
        is_nil(opts[field]) or opts[field] == ""
      end)

    case missing_field do
      nil ->
        :ok

      field ->
        {:error, Error.execution_error("Missing required field", field: field)}
    end
  end

  # Validates a single email address
  @spec validate_email_address(String.t()) :: :ok | {:error, Error.t()}
  defp validate_email_address(email) do
    if valid_email?(email) do
      :ok
    else
      {:error, Error.execution_error("Invalid email address", address: email)}
    end
  end

  # Validates a list of email addresses
  @spec validate_email_list(list(String.t())) :: :ok | {:error, Error.t()}
  defp validate_email_list(emails) when is_list(emails) do
    invalid_email = Enum.find(emails, &(not valid_email?(&1)))

    case invalid_email do
      nil ->
        :ok

      email ->
        {:error, Error.execution_error("Invalid email address", address: email)}
    end
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
  defp build_message_script(opts) do
    to = opts[:to]
    subject = escape_quotes(opts[:subject])
    body = escape_quotes(opts[:body])
    cc = opts[:cc] || []
    bcc = opts[:bcc] || []

    cc_recipients = format_recipients(cc, "cc recipient")
    bcc_recipients = format_recipients(bcc, "bcc recipient")

    """
    tell application "Mail"
      set newMessage to make new outgoing message with properties {subject:"#{subject}", content:"#{body}"}
      tell newMessage
        make new to recipient with properties {address:"#{escape_quotes(to)}"}
        #{cc_recipients}
        #{bcc_recipients}
        send
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
      {count, _} when count >= 0 ->
        {:ok, count}

      _ ->
        {:error, Error.execution_error("Invalid unread count", output: output)}
    end
  end

  # Parses search results from AppleScript output
  @spec parse_search_results(String.t()) :: [map()]
  defp parse_search_results(""), do: []

  defp parse_search_results(output) do
    output
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_message/1)
    |> Enum.reject(&is_nil/1)
  end

  # Parses a single message result
  @spec parse_message(String.t()) :: map() | nil
  defp parse_message(message_string) do
    case String.split(message_string, "|") do
      [subject, from, date] ->
        %{
          subject: String.trim(subject),
          from: String.trim(from),
          date: String.trim(date)
        }

      _ ->
        nil
    end
  end

  # Escapes double quotes in strings for AppleScript
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(string) do
    String.replace(string, "\"", "\\\"")
  end
end
