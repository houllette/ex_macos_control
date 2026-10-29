defmodule ExMacOSControl.MessagesIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.Messages
  alias ExMacOSControl.SystemEvents
  alias ExMacOSControl.TestHelpers

  # Skip ALL integration tests by default for safety
  @moduletag :skip
  @moduletag :integration

  # IMPORTANT: To run these tests manually:
  # 1. Set up a test contact or use your own number
  # 2. Set environment variable: export TEST_MESSAGES_RECIPIENT="+1234567890"
  # 3. Run: mix test --include skip test/integration/messages_integration_test.exs
  # 4. Be prepared to receive actual messages!
  #
  # NOTE: send_message tests are intentionally omitted to prevent
  # accidental message sending during test runs. Test those manually
  # in the REPL if needed.

  setup do
    TestHelpers.skip_unless_integration()

    # Use real adapter for integration tests
    original_adapter = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)

    on_exit(fn ->
      Application.put_env(:ex_macos_control, :adapter, original_adapter)
    end)

    # Launch Messages if not running
    SystemEvents.launch_application("Messages")
    Process.sleep(1000)

    :ok
  end

  describe "get_recent_messages/1" do
    @tag :skip
    test "retrieves messages from existing chat" do
      # Replace with actual test phone number/contact
      recipient = System.get_env("TEST_MESSAGES_RECIPIENT") || "+1234567890"

      assert {:ok, messages} = Messages.get_recent_messages(recipient)
      assert is_list(messages)

      # If there are messages, verify structure
      if messages != [] do
        message = hd(messages)
        assert Map.has_key?(message, :from)
        assert Map.has_key?(message, :text)
        assert Map.has_key?(message, :timestamp)
        assert is_binary(message.from)
        assert is_binary(message.text)
        assert is_binary(message.timestamp)
      end
    end

    @tag :skip
    test "handles non-existent chat gracefully" do
      # Try to get messages from a chat that likely doesn't exist
      recipient = "nonexistent-recipient-#{System.unique_integer()}"

      result = Messages.get_recent_messages(recipient)

      # Should either return empty list or error
      case result do
        {:ok, messages} -> assert messages == []
        {:error, error} -> assert error.type in [:not_found, :execution_error]
      end
    end
  end

  describe "list_chats/0" do
    @tag :skip
    test "lists all active chats" do
      assert {:ok, chats} = Messages.list_chats()
      assert is_list(chats)

      # If there are chats, verify structure
      if chats != [] do
        chat = hd(chats)
        assert Map.has_key?(chat, :id)
        assert Map.has_key?(chat, :name)
        assert Map.has_key?(chat, :unread)
        assert is_binary(chat.id)
        assert is_binary(chat.name)
        assert is_nil(chat.unread)
      end
    end

    @tag :skip
    test "returns consistent data structure" do
      assert {:ok, chats} = Messages.list_chats()

      # All chats should have the same structure
      Enum.each(chats, fn chat ->
        assert Map.keys(chat) |> Enum.sort() == [:id, :name, :unread]
        assert is_binary(chat.id)
        assert is_binary(chat.name)
        assert is_nil(chat.unread)
      end)
    end
  end

  describe "get_unread_count/0" do
    @tag :skip
    test "reports unsupported unread counts instead of inventing zero" do
      assert {:error, %ExMacOSControl.Error{type: :execution_error}} = Messages.get_unread_count()
    end
  end
end
