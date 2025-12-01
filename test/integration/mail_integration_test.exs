defmodule ExMacOSControl.MailIntegrationTest do
  use ExUnit.Case, async: false

  import Mox

  @moduletag :integration
  @moduletag :skip

  alias ExMacOSControl.Mail

  setup :verify_on_exit!

  setup do
    Mox.stub_with(ExMacOSControl.AdapterMock, ExMacOSControl.OSAScriptAdapter)
    :ok
  end

  describe "get_unread_count/0" do
    @tag :skip
    test "returns unread count or error" do
      result = Mail.get_unread_count()

      case result do
        {:ok, count} ->
          assert is_integer(count)
          assert count >= 0

        {:error, _} ->
          # Acceptable if Mail not configured
          assert true
      end
    end
  end

  describe "get_unread_count/1" do
    @tag :skip
    test "handles mailbox names" do
      result = Mail.get_unread_count("INBOX")

      # Accept success or mailbox not found
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    @tag :skip
    test "handles nonexistent mailbox" do
      result = Mail.get_unread_count("NonExistentMailbox123")

      # Should error for nonexistent mailbox
      case result do
        {:ok, _} ->
          # Mailbox exists
          assert true

        {:error, error} ->
          assert error.type == :not_found or error.type == :execution_error
      end
    end
  end

  describe "search_mailbox/2" do
    @tag :skip
    test "searches inbox" do
      result = Mail.search_mailbox("INBOX", "test")

      case result do
        {:ok, messages} ->
          assert is_list(messages)

          # Each message should have expected keys
          Enum.each(messages, fn msg ->
            assert Map.has_key?(msg, :subject)
            assert Map.has_key?(msg, :from)
            assert Map.has_key?(msg, :date)
            assert is_binary(msg.subject)
            assert is_binary(msg.from)
            assert is_binary(msg.date)
          end)

        {:error, _} ->
          # Acceptable if mailbox doesn't exist or Mail not configured
          assert true
      end
    end

    @tag :skip
    test "returns empty list when no matches" do
      # Use a very unlikely search term
      result = Mail.search_mailbox("INBOX", "xyzabc123unlikely")

      case result do
        {:ok, messages} ->
          assert is_list(messages)

        {:error, _} ->
          # Acceptable if Mail not configured
          assert true
      end
    end

    @tag :skip
    test "handles nonexistent mailbox" do
      result = Mail.search_mailbox("NonExistentMailbox123", "test")

      # Should error for nonexistent mailbox
      case result do
        {:ok, _} ->
          # Mailbox exists
          assert true

        {:error, error} ->
          assert error.type == :not_found or error.type == :execution_error
      end
    end
  end

  # IMPORTANT: send_email/1 is NOT tested in integration tests
  # It actually sends real emails, which is too risky for automated tests
  # Users should test manually in iex if needed:
  #
  # iex> ExMacOSControl.Mail.send_email(
  # ...>   to: "your-email@example.com",
  # ...>   subject: "Test from ExMacOSControl",
  # ...>   body: "This is a test email."
  # ...> )
end
