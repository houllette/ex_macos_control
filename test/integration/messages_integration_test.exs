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
    test "reports unsupported history instead of compiling an invalid script" do
      assert {:error, %ExMacOSControl.Error{type: :execution_error, message: message}} =
               Messages.get_recent_messages("nobody@example.invalid")

      assert message =~ "history is not supported"
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
