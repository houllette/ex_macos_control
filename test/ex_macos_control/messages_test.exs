defmodule ExMacOSControl.MessagesTest do
  use ExUnit.Case, async: true
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
        assert script =~ "participant"
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

    test "uses iMessage service by default" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "iMessage"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello")
    end
  end

  describe "send_message/3" do
    test "sends message with service: :imessage" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "iMessage"
        assert script =~ "+1234567890"
        assert script =~ "Hello!"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello!", service: :imessage)
    end

    test "sends message with service: :sms" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "SMS"
        assert script =~ "+1234567890"
        assert script =~ "Hello!"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello!", service: :sms)
    end

    test "sends message with service: :auto (default)" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "iMessage"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello!", service: :auto)
    end

    test "defaults to iMessage when service not specified" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "iMessage"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("+1234567890", "Hello!", [])
    end

    test "handles errors with service options" do
      error = Error.execution_error("Service not available")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} =
               Messages.send_message("+1234567890", "Hello!", service: :sms)
    end

    test "escapes quotes with service option" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        assert script =~ "SMS"
        {:ok, ""}
      end)

      assert :ok = Messages.send_message("John \"Johnny\" Doe", "Quote: \"Hi\"", service: :sms)
    end
  end

  describe "get_recent_messages/1" do
    test "retrieves messages from chat" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Messages"
        assert script =~ "+1234567890"
        assert script =~ "chat"
        assert script =~ "participants"
        assert script =~ "messages"

        {:ok,
         "+1234567890|Hello!|Monday, January 15, 2024 at 2:30:00 PM\n+1234567890|How are you?|Monday, January 15, 2024 at 2:31:00 PM\n"}
      end)

      assert {:ok, messages} = Messages.get_recent_messages("+1234567890")
      assert length(messages) == 2

      assert Enum.at(messages, 0) == %{
               from: "+1234567890",
               text: "Hello!",
               timestamp: "Monday, January 15, 2024 at 2:30:00 PM"
             }

      assert Enum.at(messages, 1) == %{
               from: "+1234567890",
               text: "How are you?",
               timestamp: "Monday, January 15, 2024 at 2:31:00 PM"
             }
    end

    test "handles empty message list" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
      end)

      assert {:ok, []} = Messages.get_recent_messages("+1234567890")
    end

    test "escapes quotes in recipient" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert {:ok, []} = Messages.get_recent_messages("John \"Johnny\" Doe")
    end

    test "handles chat not found error" do
      error = Error.not_found("Chat not found")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.get_recent_messages("+1234567890")
    end

    test "handles Messages app error" do
      error = Error.execution_error("Messages app error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.get_recent_messages("+1234567890")
    end

    test "handles permission denied error" do
      error = Error.permission_denied("Full Disk Access required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.get_recent_messages("+1234567890")
    end

    test "parses single message correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "sender@example.com|Test message|Monday, January 15, 2024 at 3:00:00 PM\n"}
      end)

      assert {:ok, [message]} = Messages.get_recent_messages("sender@example.com")

      assert message == %{
               from: "sender@example.com",
               text: "Test message",
               timestamp: "Monday, January 15, 2024 at 3:00:00 PM"
             }
    end

    test "trims whitespace from parsed fields" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "  sender@example.com  |  Test message  |  Monday, January 15, 2024  \n"}
      end)

      assert {:ok, [message]} = Messages.get_recent_messages("sender@example.com")

      assert message.from == "sender@example.com"
      assert message.text == "Test message"
      assert message.timestamp == "Monday, January 15, 2024"
    end
  end

  describe "list_chats/0" do
    test "lists all chats" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Messages"
        assert script =~ "chats"
        assert script =~ "id"
        assert script =~ "name"
        assert script =~ "unread count"

        {:ok, "iMessage;+E:+1234567890|+1234567890|2,iMessage;-;+E:john@icloud.com|John Doe|0"}
      end)

      assert {:ok, chats} = Messages.list_chats()
      assert length(chats) == 2

      assert Enum.at(chats, 0) == %{
               id: "iMessage;+E:+1234567890",
               name: "+1234567890",
               unread: 2
             }

      assert Enum.at(chats, 1) == %{
               id: "iMessage;-;+E:john@icloud.com",
               name: "John Doe",
               unread: 0
             }
    end

    test "handles empty chat list" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, ""}
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
        {:ok, "chat123|Contact Name|5"}
      end)

      assert {:ok, [chat]} = Messages.list_chats()

      assert chat == %{
               id: "chat123",
               name: "Contact Name",
               unread: 5
             }
    end

    test "trims whitespace from parsed fields" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "  chat123  |  Contact Name  |  5  "}
      end)

      assert {:ok, [chat]} = Messages.list_chats()

      assert chat.id == "chat123"
      assert chat.name == "Contact Name"
      assert chat.unread == 5
    end

    test "parses zero unread count" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "chat123|Contact|0"}
      end)

      assert {:ok, [chat]} = Messages.list_chats()
      assert chat.unread == 0
    end
  end

  describe "get_unread_count/0" do
    test "returns total unread count" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Messages"
        assert script =~ "chats"
        assert script =~ "unread count"
        assert script =~ "totalUnread"
        {:ok, "5"}
      end)

      assert {:ok, 5} = Messages.get_unread_count()
    end

    test "handles zero unread messages" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "0"}
      end)

      assert {:ok, 0} = Messages.get_unread_count()
    end

    test "handles large unread count" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "999"}
      end)

      assert {:ok, 999} = Messages.get_unread_count()
    end

    test "handles Messages app error" do
      error = Error.execution_error("Messages app error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.get_unread_count()
    end

    test "handles permission denied error" do
      error = Error.permission_denied("Automation permission required")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Messages.get_unread_count()
    end

    test "trims whitespace from count" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "  42  "}
      end)

      assert {:ok, 42} = Messages.get_unread_count()
    end

    test "handles count with newlines" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "42\n"}
      end)

      assert {:ok, 42} = Messages.get_unread_count()
    end
  end
end
