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
  - History requires an explicitly configured Shortcuts workflow; AppleScript alone does not expose messages
  - Direct SQLite access is not implemented; Full Disk Access does not add AppleScript history support
  """

  alias ExMacOSControl.{Error, ScriptOutput, Validation}

  # Get the adapter at runtime to support integration test configuration
  defp adapter do
    ExMacOSControl
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
      ExMacOSControl.with_options(Keyword.take(opts, [:timeout, :max_output_bytes]), fn ->
        deliver_message(recipient, text, opts)
      end)
    end
  end

  defp deliver_message(recipient, text, opts) do
    if Keyword.get(opts, :group_chat, false),
      do: send_to_group_chat(recipient, text),
      else: send_script(build_send_message_script(recipient, text))
  end

  @doc """
  Reads recent messages through the configured Shortcuts workflow.

  Set `:message_search_shortcut` in the `:ex_macos_control` application configuration
  to a user-installed workflow identifier. Without it, returns an execution error
  without contacting Messages. Full Disk Access does not add history support to
  the scripting dictionary; direct database access is not used.
  """
  @spec get_recent_messages(String.t()) :: {:ok, [term()]} | {:error, Error.t()}
  def get_recent_messages(recipient) do
    case Application.get_env(:ex_macos_control, :message_search_shortcut) do
      nil -> {:error, Error.execution_error("Messages history is not supported by the AppleScript API")}
      id -> search_messages("", shortcut_id: id, sender: recipient)
    end
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
      Keyword.keys(opts) -- [:service, :group_chat, :timeout, :max_output_bytes] != [] ->
        {:error, Error.execution_error("Unknown Messages option")}

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

  @doc "Sends a file through Messages using automatic service selection."
  def send_file(recipient, path, opts \\ []) do
    with :ok <- validate_send_options(recipient, "file", opts),
         true <- is_binary(path) and File.regular?(path),
         false <- Keyword.get(opts, :group_chat, false) do
      script =
        ~s(tell application "Messages" to send POSIX file "#{escape_quotes(Path.expand(path))}" to buddy "#{escape_quotes(recipient)}")

      execution = opts |> ExMacOSControl.Automation.execution_options() |> Keyword.put_new(:timeout, 30_000)
      ExMacOSControl.with_options(execution, fn -> send_script(script) end)
    else
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("File must exist; use send_file_to_chat for a group destination")}
    end
  end

  @doc "Sends text to an explicitly selected chat ID."
  def send_to_chat(id, text, opts \\ []) do
    with :ok <- ExMacOSControl.Automation.required_string(id, "Chat ID"),
         :ok <- ExMacOSControl.Automation.required_string(text, "Message text") do
      ExMacOSControl.Automation.action(
        "com.apple.MobileSMS",
        "app.send(input.text,{to:byId(app.chats,input.id)});",
        %{id: id, text: text},
        opts
      )
    end
  end

  def send_file_to_chat(id, path, opts \\ []) do
    if is_binary(path) and File.regular?(path) do
      ExMacOSControl.Automation.action(
        "com.apple.MobileSMS",
        "app.send(Path(input.path),{to:byId(app.chats,input.id)});",
        %{id: id, path: Path.expand(path)},
        opts
      )
    else
      {:error, Error.execution_error("Message file does not exist")}
    end
  end

  @doc """
  Sends the same text to explicit chat IDs in order. Sends real messages, once
  per supplied ID. Stops at the first error, including unknown outcomes; error
  details retain acknowledged chat IDs. Acceptance does not prove delivery.
  """
  def send_to_chats(ids, text, opts \\ []) do
    alias ExMacOSControl.{Automation, Composition}

    with :ok <- Validation.items(ids),
         :ok <- Validation.all(ids, &Automation.required_string(&1, "Chat ID")),
         :ok <- Automation.required_string(text, "Message text") do
      Composition.run(fn -> Composition.map(ids, :send_message, &send_one_chat(&1, text)) end, opts)
    end
  end

  @doc """
  Sends existing files to one explicit chat ID. Validates the entire batch first,
  sends each once, and retains acknowledged paths on partial failure. These are
  real sends; a timeout can mean that the last file was already dispatched.
  """
  def send_files_to_chat(id, paths, opts \\ []) do
    alias ExMacOSControl.{Automation, Composition}

    with :ok <- Automation.required_string(id, "Chat ID"),
         :ok <- Validation.items(paths),
         true <- Enum.all?(paths, &(is_binary(&1) and File.regular?(&1))) do
      Composition.run(fn -> Composition.map(paths, :send_file, &send_one_file(id, &1)) end, opts)
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Message files must exist")
    end
  end

  defp send_one_chat(id, text) do
    with :ok <- send_to_chat(id, text), do: {:ok, id}
  end

  defp send_one_file(id, path) do
    with :ok <- send_file_to_chat(id, path), do: {:ok, Path.expand(path)}
  end

  @doc "Lists accounts. service_type is nil when an account does not implement that property."
  def list_accounts(opts \\ []) do
    with :ok <- ExMacOSControl.Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- ExMacOSControl.Automation.page(opts) do
      ExMacOSControl.Automation.query(
        "com.apple.MobileSMS",
        """
        function serviceType(o) {
          try { return o.serviceType(); }
          catch (error) { if(error.errorNumber === -10000) return null; throw error; }
        }
        return page(app.accounts()).map(function(o){return {id:o.id(),name:o.description(),enabled:o.enabled(),service_type:serviceType(o)};});
        """,
        paging,
        ExMacOSControl.Automation.execution_options(opts)
      )
    end
  end

  def list_participants(opts \\ []),
    do:
      ExMacOSControl.Resources.list(
        "com.apple.MobileSMS",
        "app.participants",
        [id: "o.id()", name: "o.fullName()", handle: "o.handle()"],
        %{},
        opts
      )

  def list_chats(opts), do: ExMacOSControl.with_options(opts, &list_chats/0)

  @doc """
  Searches using a user-installed Shortcuts workflow, without accessing the Messages database.

  The workflow receives JSON text with `exmc: 1`, `operation: "messages.search"`,
  and an `input` object containing query, sender, date bounds, limit and offset.
  It must return JSON text shaped as `{"exmc":1,"result":[...]}`. Result fields
  belong to the installed workflow. Use `:shortcut_id` or the application setting
  `:message_search_shortcut` to select it.
  """
  def search_messages(query, opts \\ []) do
    allowed = [:shortcut_id, :sender, :from, :to, :limit, :offset, :timeout, :max_output_bytes]

    with :ok <- ExMacOSControl.Automation.options(opts, allowed),
         {:ok, paging} <- ExMacOSControl.Automation.page(opts),
         {:ok, from} <- ExMacOSControl.Automation.date(opts[:from]),
         {:ok, to} <- ExMacOSControl.Automation.date(opts[:to]),
         id = Keyword.get(opts, :shortcut_id, Application.get_env(:ex_macos_control, :message_search_shortcut)),
         :ok <- ExMacOSControl.Automation.required_string(id, "Message search shortcut ID"),
         {:ok, messages} when is_list(messages) <-
           ExMacOSControl.Shortcuts.workflow(
             id,
             "messages.search",
             Map.merge(paging, %{query: query, sender: opts[:sender], from: from, to: to}),
             ExMacOSControl.Automation.execution_options(opts)
           ) do
      {:ok, messages}
    else
      {:error, _} = error -> error
      _ -> {:error, Error.execution_error("Message search workflow must return a list")}
    end
  end
end
