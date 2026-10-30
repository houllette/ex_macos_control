defmodule ExMacOSControl.MessagesTest do
  use ExUnit.Case, async: true
  import ExMacOSControl.TestHelpers, only: [script_output: 1]
  import Mox

  alias ExMacOSControl.Error
  alias ExMacOSControl.Messages

  setup :verify_on_exit!

  describe "send_message/2" do
    test "sends message to phone number" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Messages"
        assert script =~ "+1234567890"
        assert script =~ "Hello from Elixir!"
        assert script =~ "send"
        assert script =~ "buddy"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello from Elixir!")
    end

    test "sends message to contact name" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "John Doe"
        assert script =~ "Meeting at 3pm?"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("John Doe", "Meeting at 3pm?")
    end

    test "escapes quotes in recipient" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("John \"Johnny\" Doe", "Hello")
    end

    test "escapes quotes in text" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "He said \"Hello\"")
    end

    test "escapes quotes in both recipient and text" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        # Should have escaped quotes for both
        assert String.match?(script, ~r/\\\".*\\\"/)
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("John \"Johnny\" Doe", "Quote: \"Hello\"")
    end

    test "handles Messages app errors" do
      error = Error.execution_error("Messages app error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.send_message("+1234567890", "Hello")
    end

    test "handles invalid recipient errors" do
      error = Error.execution_error("Invalid recipient")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.send_message("invalid", "Hello")
    end

    test "handles permission denied errors" do
      error = Error.permission_denied("Automation permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.send_message("+1234567890", "Hello")
    end
  end

  describe "send_message/3" do
    test "rejects explicit service selection without sending anything" do
      for service <- [:imessage, :sms, :invalid, nil] do
        assert {:error, %Error{type: :execution_error, message: message}} =
                 Messages.send_message("+1234567890", "Hello!", service: service)

        assert message =~ "service selection is not supported"
      end
    end

    test "sends message with service: :auto (default)" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "buddy"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello!", service: :auto)
    end

    test "rejects invalid recipients, message text and options without sending" do
      for {recipient, text, opts} <- [
            {nil, "Hello", []},
            {" ", "Hello", []},
            {"Alice", nil, []},
            {"Alice", "", []},
            {"Alice", "Hello", nil},
            {"Alice", "Hello", [:invalid]},
            {"Alice", "Hello", [group_chat: :yes]}
          ] do
        assert {:error, %Error{type: :execution_error}} = Messages.send_message(recipient, text, opts)
      end
    end

    test "refuses to send when multiple chats match the participant names" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([["one", "Alice & Bob"], ["two", "Alice & Bob"]])}
      end)

      assert {:error, %Error{message: message}} = Messages.send_message("Alice & Bob", "Hello", group_chat: true)
      assert message =~ "Multiple chats"
    end

    test "refuses to send when chat output is malformed" do
      for output <- ["one|Alice & Bob|0", "EXMC1\none\nEND", script_output([["", "Alice & Bob"]])] do
        expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script -> {:ok, output} end)

        assert {:error, %Error{type: :execution_error}} =
                 Messages.send_message("Alice & Bob", "Hello", group_chat: true)
      end
    end

    test "sends message to group chat" do
      # First call: list_chats to find the group
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "chats"
        assert script =~ "repeat with chatParticipant in participants_list"
        refute script =~ "first_participant"
        {:ok, script_output([["any;+;chat123", "John Doe & Jane Smith"], ["any;-;+1234567890", "John Doe"]])}
      end)

      # Second call: send to the chat
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "chat id"
        assert script =~ "any;+;chat123"
        assert script =~ "Hello everyone!"
        assert script =~ ~s|if (count of targetParticipants) < 2 then error "Destination is not a group chat"|
        assert script =~ ~s(if targetNames is not "John Doe & Jane Smith" then error)
        assert script =~ "Group participants changed; refusing to send"
        assert script =~ "send \"Hello everyone!\" to targetChat"
        {:ok, ""}
      end)

      assert :ok =
               Messages.send_message("John Doe & Jane Smith", "Hello everyone!", group_chat: true)
    end

    test "handles group chat not found" do
      # list_chats call returns chats without the target group
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "chats"
        {:ok, script_output([["any;-;+1234567890", "John Doe"]])}
      end)

      assert {:error, %Error{type: :not_found}} =
               Messages.send_message("Alice & Bob", "Hello!", group_chat: true)
    end

    test "handles list_chats error when sending to group" do
      error = Error.execution_error("Messages app error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} =
               Messages.send_message("John & Jane", "Hello!", group_chat: true)
    end

    test "sends to group chat with exact participant match" do
      # Should match exact participant names
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([["any;+;chat456", "Alice Smith & Bob Jones"], ["any;+;chat789", "Alice Smith"]])}
      end)

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "chat id"
        assert script =~ "any;+;chat456"
        {:ok, ""}
      end)

      assert :ok =
               Messages.send_message("Alice Smith & Bob Jones", "Test", group_chat: true)
    end

    test "escapes quotes in group chat message" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([["any;+;chat123", "John & Jane"]])}
      end)

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("John & Jane", "Quote: \"Hi\"", group_chat: true)
    end
  end

  describe "get_recent_messages/1" do
    test "reports unsupported history without contacting the adapter" do
      assert {:error, %Error{type: :execution_error, message: message, details: %{}}} =
               Messages.get_recent_messages("+1234567890")

      assert message =~ "history is not supported"
    end

    test "does not interpolate recipient content into a script" do
      for recipient <- ["Alice", "John \"Johnny\" Doe", "line\nbreak\\path"] do
        assert {:error, %Error{type: :execution_error, message: message}} = Messages.get_recent_messages(recipient)
        refute message =~ recipient
      end
    end
  end

  describe "list_chats/0" do
    test "lists all chats" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Messages"
        assert script =~ "chats"
        assert script =~ "id"
        assert script =~ "participants"

        {:ok,
         script_output([
           ["iMessage;+E:+1234567890", "+1234567890"],
           ["iMessage;-;+E:john@icloud.com", "John Doe"]
         ])}
      end)

      assert {:ok, chats} = Messages.list_chats()
      assert length(chats) == 2

      assert Enum.at(chats, 0) == %{
               id: "iMessage;+E:+1234567890",
               name: "+1234567890",
               unread: nil
             }

      assert Enum.at(chats, 1) == %{
               id: "iMessage;-;+E:john@icloud.com",
               name: "John Doe",
               unread: nil
             }
    end

    test "handles empty chat list" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([])}
      end)

      assert {:ok, []} = Messages.list_chats()
    end

    test "handles Messages app error" do
      error = Error.execution_error("Messages app error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.list_chats()
    end

    test "handles permission denied error" do
      error = Error.permission_denied("Automation permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.list_chats()
    end

    test "parses single chat correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([["chat123", "Contact Name"]])}
      end)

      assert {:ok, [chat]} = Messages.list_chats()

      assert chat == %{
               id: "chat123",
               name: "Contact Name",
               unread: nil
             }
    end

    test "preserves whitespace in parsed fields" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([["  chat123  ", "  Contact Name  "]])}
      end)

      assert {:ok, [chat]} = Messages.list_chats()

      assert chat.id == "  chat123  "
      assert chat.name == "  Contact Name  "
      assert is_nil(chat.unread)
    end

    test "marks unavailable unread counts as unknown" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, script_output([["chat123", "Contact"]])}
      end)

      assert {:ok, [chat]} = Messages.list_chats()
      assert is_nil(chat.unread)
    end
  end

  describe "get_unread_count/0" do
    test "reports unsupported functionality instead of fabricating zero" do
      assert {:error, %Error{type: :execution_error, message: message}} = Messages.get_unread_count()
      assert message =~ "not supported"
    end
  end
end
