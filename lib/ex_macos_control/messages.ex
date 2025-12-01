defmodule ExMacOSControl.Messages do
  @moduledoc """
  Provides functions for automating the Messages application on macOS.

  This module enables you to send iMessages and SMS, retrieve messages,
  list chats, and check unread counts.

  ## Safety Warning

  ⚠️  The `send_message` functions will actually send real messages.
  Be careful when using these functions, especially in automated tests
  or scripts. All integration tests are skipped by default to prevent
  accidental message sending.

  ## Examples

      # Send a message to a phone number
      ExMacOSControl.Messages.send_message("+1234567890", "Hello!")
      # => :ok

      # Send to a contact name
      ExMacOSControl.Messages.send_message("John Doe", "Hey!")
      # => :ok

      # Specify service (iMessage or SMS)
      ExMacOSControl.Messages.send_message(
        "+1234567890",
        "Hello!",
        service: :sms
      )
      # => :ok

      # Get recent messages from a chat
      {:ok, messages} = ExMacOSControl.Messages.get_recent_messages("+1234567890")
      # => {:ok, [
      #   %{from: "...", text: "...", timestamp: "..."},
      #   ...
      # ]}

      # List all chats
      {:ok, chats} = ExMacOSControl.Messages.list_chats()
      # => {:ok, [
      #   %{id: "...", name: "...", unread: 0},
      #   ...
      # ]}

      # Get unread count
      {:ok, count} = ExMacOSControl.Messages.get_unread_count()
      # => {:ok, 5}

  ## Permissions

  Messages automation requires:
  - **Automation permission** for Terminal/your app to control Messages
  - **Full Disk Access** may be needed for reading message history

  You can grant these in System Preferences > Privacy & Security.
  """

  alias ExMacOSControl.Error

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Sends a message to a recipient via Messages app.

  The recipient can be either a phone number (with country code) or a contact name.
  By default, Messages will use iMessage if available, falling back to SMS.

  ## Parameters

  - `recipient` - Phone number (e.g., "+1234567890") or contact name (e.g., "John Doe")
  - `text` - The message content to send

  ## Returns

  - `:ok` on success
  - `{:error, Error.t()}` on failure

  ## Safety Warning

  ⚠️  This function sends real messages! Use with caution.

  ## Examples

      # Send to phone number
      send_message("+1234567890", "Hello from ExMacOSControl!")
      # => :ok

      # Send to contact name
      send_message("John Doe", "Meeting at 3pm?")
      # => :ok

  ## Errors

  - `:execution_error` - Messages app error or invalid recipient
  - `:not_found` - Messages app not found
  - `:permission_denied` - Automation permission required
  """
  @spec send_message(String.t(), String.t()) :: :ok | {:error, Error.t()}
  def send_message(recipient, text) do
    send_message(recipient, text, [])
  end

  @doc """
  Sends a message with additional options.

  ## Parameters

  - `recipient` - Phone number or contact name
  - `text` - The message content to send
  - `opts` - Keyword list of options:
    - `:service` - `:imessage` or `:sms` (default: automatically determined)

  ## Returns

  - `:ok` on success
  - `{:error, Error.t()}` on failure

  ## Examples

      # Force SMS (not iMessage)
      send_message("+1234567890", "Hello!", service: :sms)
      # => :ok

      # Force iMessage
      send_message("john@icloud.com", "Hello!", service: :imessage)
      # => :ok
  """
  @spec send_message(String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def send_message(recipient, text, opts) do
    service = Keyword.get(opts, :service, :auto)
    script = build_send_message_script(recipient, text, service)

    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets recent messages from a chat with the specified recipient.

  Returns the most recent messages (typically last 10-20) from the conversation.

  ## Parameters

  - `recipient` - Phone number or contact name

  ## Returns

  - `{:ok, [message]}` - List of message maps with :from, :text, :timestamp
  - `{:error, Error.t()}` on failure

  ## Examples

      get_recent_messages("+1234567890")
      # => {:ok, [
      #   %{
      #     from: "+1234567890",
      #     text: "Hello!",
      #     timestamp: "2024-01-15 14:30:00"
      #   },
      #   ...
      # ]}

  ## Errors

  - `:not_found` - Chat not found or Messages app not found
  - `:execution_error` - Error retrieving messages
  - `:permission_denied` - Full Disk Access may be required
  """
  @spec get_recent_messages(String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def get_recent_messages(recipient) do
    script = """
    tell application "Messages"
      set targetChat to first chat whose participants contains "#{escape_quotes(recipient)}"
      set recentMessages to last 20 messages of targetChat
      set output to ""

      repeat with msg in recentMessages
        set output to output & (handle of msg) & "|" & (text of msg) & "|" & (date of msg) & "\\n"
      end repeat

      return output
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, result} -> {:ok, parse_messages(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all active chats in the Messages app.

  Returns a list of chats with their IDs, names, and unread counts.

  ## Returns

  - `{:ok, [chat]}` - List of chat maps with :id, :name, :unread
  - `{:error, Error.t()}` on failure

  ## Examples

      list_chats()
      # => {:ok, [
      #   %{id: "chat1", name: "+1234567890", unread: 2},
      #   %{id: "chat2", name: "John Doe", unread: 0},
      #   ...
      # ]}

  ## Errors

  - `:execution_error` - Error retrieving chats
  - `:not_found` - Messages app not found
  """
  @spec list_chats() :: {:ok, [map()]} | {:error, Error.t()}
  def list_chats do
    script = """
    tell application "Messages"
      set chatList to {}
      repeat with c in chats
        try
          set chatInfo to (id of c) & "|" & (name of c) & "|" & (unread count of c)
          copy chatInfo to end of chatList
        end try
      end repeat
      return chatList as text
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, result} -> {:ok, parse_chats(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the total number of unread messages across all chats.

  ## Returns

  - `{:ok, count}` - Number of unread messages
  - `{:error, Error.t()}` on failure

  ## Examples

      get_unread_count()
      # => {:ok, 5}

  ## Errors

  - `:execution_error` - Error retrieving unread count
  - `:not_found` - Messages app not found
  """
  @spec get_unread_count() :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_unread_count do
    script = """
    tell application "Messages"
      set totalUnread to 0
      repeat with c in chats
        try
          set totalUnread to totalUnread + (unread count of c)
        end try
      end repeat
      return totalUnread
    end tell
    """

    case adapter().run_applescript(script) do
      {:ok, result} ->
        count = result |> String.trim() |> String.to_integer()
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Helpers

  # Private helper to escape quotes in strings
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(str) do
    String.replace(str, "\"", "\\\"")
  end

  # Build the send_message AppleScript based on service
  @spec build_send_message_script(String.t(), String.t(), atom()) :: String.t()
  defp build_send_message_script(recipient, text, service) do
    service_type =
      case service do
        :imessage -> "iMessage"
        :sms -> "SMS"
        :auto -> "iMessage"
      end

    """
    tell application "Messages"
      set targetService to 1st account whose service type = #{service_type}
      set targetBuddy to participant "#{escape_quotes(recipient)}" of targetService
      send "#{escape_quotes(text)}" to targetBuddy
    end tell
    """
  end

  # Parses messages from AppleScript output
  @spec parse_messages(String.t()) :: [map()]
  defp parse_messages(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_message_line/1)
  end

  # Parses a single message line
  @spec parse_message_line(String.t()) :: map()
  defp parse_message_line(line) do
    [from, text, timestamp] = String.split(line, "|", parts: 3)

    %{
      from: String.trim(from),
      text: String.trim(text),
      timestamp: String.trim(timestamp)
    }
  end

  # Parses chats from AppleScript output
  @spec parse_chats(String.t()) :: [map()]
  defp parse_chats(""), do: []

  defp parse_chats(output) do
    output
    |> String.split(",", trim: true)
    |> Enum.map(&parse_chat_line/1)
  end

  # Parses a single chat line
  @spec parse_chat_line(String.t()) :: map()
  defp parse_chat_line(line) do
    [id, name, unread] = String.split(line, "|", parts: 3)

    %{
      id: String.trim(id),
      name: String.trim(name),
      unread: String.trim(unread) |> String.to_integer()
    }
  end
end
