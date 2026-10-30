defmodule ExMacOSControl.Messages do
  @moduledoc """
  Provides functions for automating the Messages application on macOS.

  This module enables you to send iMessages and SMS and list chats.
  Message history and unread counts are not exposed by the AppleScript API.

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

      # Send to a group chat
      ExMacOSControl.Messages.send_message(
        "John Doe & Jane Smith",
        "Hello everyone!",
        group_chat: true
      )
      # => :ok

      # Let Messages select the delivery service
      ExMacOSControl.Messages.send_message(
        "+1234567890",
        "Hello!",
        service: :auto
      )
      # => :ok

      # List all chats
      {:ok, chats} = ExMacOSControl.Messages.list_chats()
      # => {:ok, [
      #   %{id: "...", name: "...", unread: nil},
      #   ...
      # ]}

      # Unread counts are unavailable
      ExMacOSControl.Messages.get_unread_count()
      # => {:error, %ExMacOSControl.Error{type: :execution_error, ...}}

  ## Group Chat Support

  To send messages to group chats, use the `group_chat: true` option:

      ExMacOSControl.Messages.send_message(
        "Alice Smith & Bob Jones & Carol White",
        "Meeting at 3pm!",
        group_chat: true
      )

  The recipient string should be the participant full names joined by " & ".
  The function will automatically find the matching group chat by calling
  `list_chats()` and matching the participant names.

  ## Permissions

  Messages automation requires:
  - **Automation permission** for Terminal/your app to control Messages

  You can grant these in System Preferences > Privacy & Security.

  ## Limitations

  - Only `service: :auto` is supported; explicit `:sms`/`:imessage` requests return an error before sending
  - `get_unread_count/0` returns an error, and chat `:unread` values are `nil` (unknown), not zero
  - `get_recent_messages/1` returns an unsupported-functionality error without contacting Messages
  - Direct SQLite access is not implemented; Full Disk Access does not add AppleScript history support
  """

  alias ExMacOSControl.{Error, ScriptOutput}

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    Application.get_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)
  end

  @doc """
  Sends a message to a recipient via Messages app.

  The recipient can be either a phone number (with country code) or a contact name.
  Messages selects the delivery service; this library does not guarantee SMS fallback.

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

  - `recipient` - Phone number, contact name, or group chat participant names
  - `text` - The message content to send
  - `opts` - Keyword list of options:
    - `:service` - Only `:auto` is supported (default). Other values return an error before sending.
    - `:group_chat` - `true` if sending to a group chat (default: `false`)

  ## Returns

  - `:ok` on success
  - `{:error, Error.t()}` on failure

  ## Examples

      # Allow Messages to choose the service
      send_message("+1234567890", "Hello!", service: :auto)
      # => :ok

      # Explicit routing is unsupported and never silently ignored
      send_message("john@icloud.com", "Hello!", service: :imessage)
      # => {:error, %ExMacOSControl.Error{type: :execution_error, ...}}

      # Send to a group chat (participant names joined by " & ")
      send_message("John Doe & Jane Smith", "Hello everyone!", group_chat: true)
      # => :ok

  ## Group Chat Usage

  When `group_chat: true` is specified, the function will:
  1. Call `list_chats()` to get all available chats
  2. Find a chat where participant names match the recipient string
  3. Use the chat ID to send the message

  The recipient string for group chats should be participant full names
  joined by " & " (e.g., "Alice Smith & Bob Jones & Carol White").

  ## Errors

  - `:not_found` - Group chat not found when `group_chat: true`
  - `:execution_error` - Messages app error or invalid recipient
  """
  @spec send_message(String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def send_message(recipient, text, opts) do
    with :ok <- validate_send_options(recipient, text, opts) do
      if Keyword.get(opts, :group_chat, false) do
        send_to_group_chat(recipient, text)
      else
        send_script(build_send_message_script(recipient, text))
      end
    end
  end

  @doc """
  Reports that message history is unsupported by the Messages AppleScript API.

  Returns an execution error without contacting Messages. Full Disk Access does
  not add history support to the scripting dictionary; direct database access is
  not implemented.
  """
  @spec get_recent_messages(String.t()) :: {:error, Error.t()}
  def get_recent_messages(_recipient) do
    {:error, Error.execution_error("Messages history is not supported by the AppleScript API")}
  end

  @doc """
  Lists all active chats in the Messages app.

  Returns a list of chats with their IDs and names. The `:unread` field is `nil`
  because the AppleScript API does not expose unread counts.

  ## Returns

  - `{:ok, [chat]}` - List of chat maps with :id, :name, :unread
  - `{:error, Error.t()}` on failure

  ## Examples

      list_chats()
      # => {:ok, [
      #   %{id: "chat1", name: "+1234567890", unread: nil},
      #   %{id: "chat2", name: "John Doe", unread: nil},
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
      set chatRows to {}
      repeat with c in chats
        try
          set chatID to id of c
          set chatName to ""
          set participants_list to participants of c
          repeat with chatParticipant in participants_list
            set participantName to full name of chatParticipant
            if participantName is "" or participantName is missing value then
              set participantName to id of chatParticipant
            end if
            if chatName is not "" then set chatName to chatName & " & "
            set chatName to chatName & participantName
          end repeat
          set end of chatRows to {chatID, chatName}
        on error errMsg number errNum
          error errMsg number errNum
        end try
      end repeat
      return my exmc_encode_rows(chatRows)
    end tell
    #{ScriptOutput.handlers()}
    """

    case adapter().run_applescript(script) do
      {:ok, result} -> parse_chats(result)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reports that unread counts are unsupported by the Messages AppleScript API.

  Returns an execution error rather than fabricating a zero count. No application
  is contacted. Chat `:unread` fields returned by `list_chats/0` are likewise `nil`.
  """
  @spec get_unread_count() :: {:error, Error.t()}
  def get_unread_count do
    {:error, Error.execution_error("Messages unread counts are not supported by the AppleScript API")}
  end

  ## Private Helpers

  defp validate_send_options(recipient, text, opts) do
    cond do
      not is_binary(recipient) or String.trim(recipient) == "" ->
        {:error, Error.execution_error("Recipient must be a non-empty string")}

      not is_binary(text) or text == "" ->
        {:error, Error.execution_error("Message text must be a non-empty string")}

      not is_list(opts) or not Keyword.keyword?(opts) ->
        {:error, Error.execution_error("Message options must be a keyword list")}

      true ->
        validate_delivery_options(opts)
    end
  end

  defp validate_delivery_options(opts) do
    cond do
      Keyword.get(opts, :service, :auto) != :auto ->
        {:error, Error.execution_error("Explicit Messages service selection is not supported; use service: :auto")}

      not is_boolean(Keyword.get(opts, :group_chat, false)) ->
        {:error, Error.execution_error("The group_chat option must be a boolean")}

      true ->
        :ok
    end
  end

  defp send_script(script) do
    case adapter().run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Never send if the chat lookup is malformed, missing, or ambiguous.
  @spec send_to_group_chat(String.t(), String.t()) :: :ok | {:error, Error.t()}
  defp send_to_group_chat(participant_names, text) do
    with {:ok, chat_id} <- find_group_chat_by_participants(participant_names) do
      send_script(build_group_message_script(chat_id, participant_names, text))
    end
  end

  # Private helper to find a group chat ID by participant names
  @spec find_group_chat_by_participants(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  defp find_group_chat_by_participants(participant_names) do
    case list_chats() do
      {:ok, chats} ->
        matching_chats = Enum.filter(chats, fn chat -> chat.name == participant_names end)

        case matching_chats do
          [] ->
            {:error, Error.not_found("Group chat not found with participants: #{participant_names}")}

          [chat] ->
            {:ok, chat.id}

          _ ->
            {:error, Error.execution_error("Multiple chats match the recipient; refusing to send")}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper to escape quotes in strings
  @spec escape_quotes(String.t()) :: String.t()
  defp escape_quotes(str) do
    ExMacOSControl.Script.escape_string(str)
  end

  @spec build_send_message_script(String.t(), String.t()) :: String.t()
  defp build_send_message_script(recipient, text) do
    """
    tell application "Messages"
      send "#{escape_quotes(text)}" to buddy "#{escape_quotes(recipient)}"
    end tell
    """
  end

  # Recheck the complete destination immediately before sending, not just its first participant.
  defp build_group_message_script(chat_id, participant_names, text) do
    """
    tell application "Messages"
      set targetChat to chat id "#{escape_quotes(chat_id)}"
      set targetParticipants to participants of targetChat
      if (count of targetParticipants) < 2 then error "Destination is not a group chat"
      set targetNames to ""
      repeat with chatParticipant in targetParticipants
        set participantName to full name of chatParticipant
        if participantName is "" or participantName is missing value then
          set participantName to id of chatParticipant
        end if
        if targetNames is not "" then set targetNames to targetNames & " & "
        set targetNames to targetNames & participantName
      end repeat
      if targetNames is not "#{escape_quotes(participant_names)}" then error "Group participants changed; refusing to send"
      send "#{escape_quotes(text)}" to targetChat
    end tell
    """
  end

  defp chat_from_row([id, name]), do: %{id: id, name: name, unread: nil}
  defp invalid_chat_row?([id, _name]), do: String.trim(id) == ""

  # Keep malformed data from crashing the caller or triggering a group send.
  @spec parse_chats(String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  defp parse_chats(output) do
    with {:ok, rows} <- ScriptOutput.decode(output, 2) do
      if Enum.any?(rows, &invalid_chat_row?/1) do
        {:error, Error.execution_error("Invalid structured chat output")}
      else
        {:ok, Enum.map(rows, &chat_from_row/1)}
      end
    end
  end
end
