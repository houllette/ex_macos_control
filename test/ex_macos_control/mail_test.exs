defmodule ExMacOSControl.MailTest do
  use ExUnit.Case, async: true
  import Mox

  alias ExMacOSControl.Error
  alias ExMacOSControl.Mail

  setup :verify_on_exit!

  describe "send_email/1" do
    test "sends email with required fields" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Mail"
        assert script =~ "make new outgoing message"
        assert script =~ "recipient@example.com"
        assert script =~ "Test Subject"
        assert script =~ "Test Body"
        assert script =~ "send"
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test Subject",
                 body: "Test Body"
               )
    end

    test "sends email with CC recipients" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "recipient@example.com"
        assert script =~ "cc@example.com"
        assert script =~ "make new cc recipient"
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test",
                 body: "Test",
                 cc: ["cc@example.com"]
               )
    end

    test "sends email with BCC recipients" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "recipient@example.com"
        assert script =~ "bcc@example.com"
        assert script =~ "make new bcc recipient"
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test",
                 body: "Test",
                 bcc: ["bcc@example.com"]
               )
    end

    test "sends email with both CC and BCC" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "cc@example.com"
        assert script =~ "bcc@example.com"
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test",
                 body: "Test",
                 cc: ["cc@example.com"],
                 bcc: ["bcc@example.com"]
               )
    end

    test "sends email with multiple CC recipients" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "cc1@example.com"
        assert script =~ "cc2@example.com"
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test",
                 body: "Test",
                 cc: ["cc1@example.com", "cc2@example.com"]
               )
    end

    test "validates email addresses" do
      assert {:error, error} =
               Mail.send_email(
                 to: "invalid-email",
                 subject: "Test",
                 body: "Test"
               )

      assert error.type == :execution_error
      assert error.message =~ "Invalid email address"
    end

    test "validates CC email addresses" do
      assert {:error, error} =
               Mail.send_email(
                 to: "valid@example.com",
                 subject: "Test",
                 body: "Test",
                 cc: ["invalid-email"]
               )

      assert error.type == :execution_error
      assert error.message =~ "Invalid email address"
    end

    test "validates BCC email addresses" do
      assert {:error, error} =
               Mail.send_email(
                 to: "valid@example.com",
                 subject: "Test",
                 body: "Test",
                 bcc: ["invalid-email"]
               )

      assert error.type == :execution_error
      assert error.message =~ "Invalid email address"
    end

    test "requires to field" do
      assert {:error, error} =
               Mail.send_email(
                 subject: "Test",
                 body: "Test"
               )

      assert error.type == :execution_error
      assert error.message =~ "Missing required field"
      assert error.details[:field] == :to
    end

    test "requires subject field" do
      assert {:error, error} =
               Mail.send_email(
                 to: "recipient@example.com",
                 body: "Test"
               )

      assert error.type == :execution_error
      assert error.message =~ "Missing required field"
      assert error.details[:field] == :subject
    end

    test "requires body field" do
      assert {:error, error} =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test"
               )

      assert error.type == :execution_error
      assert error.message =~ "Missing required field"
      assert error.details[:field] == :body
    end

    test "handles Mail app errors" do
      error = Error.execution_error("Mail app error")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test",
                 body: "Test"
               )
    end

    test "escapes quotes in subject" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test \"quoted\" subject",
                 body: "Test"
               )
    end

    test "escapes quotes in body" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert :ok =
               Mail.send_email(
                 to: "recipient@example.com",
                 subject: "Test",
                 body: "Test \"quoted\" body"
               )
    end
  end

  describe "get_unread_count/0" do
    test "returns unread count for inbox" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Mail"
        assert script =~ "unread count"
        assert script =~ "inbox"
        {:ok, "42"}
      end)

      assert {:ok, 42} = Mail.get_unread_count()
    end

    test "handles zero unread messages" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "unread count"
        {:ok, "0"}
      end)

      assert {:ok, 0} = Mail.get_unread_count()
    end

    test "handles Mail app errors" do
      error = Error.execution_error("Mail not running")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Mail.get_unread_count()
    end

    test "parses count correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "123"}
      end)

      assert {:ok, 123} = Mail.get_unread_count()
    end

    test "handles non-integer output" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "not a number"}
      end)

      assert {:error, error} = Mail.get_unread_count()
      assert error.type == :execution_error
      assert error.message =~ "Invalid unread count"
    end
  end

  describe "get_unread_count/1" do
    test "returns unread count for specific mailbox" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Mail"
        assert script =~ "unread count"
        assert script =~ "mailbox"
        assert script =~ "Work"
        {:ok, "5"}
      end)

      assert {:ok, 5} = Mail.get_unread_count("Work")
    end

    test "handles mailbox not found" do
      error = Error.not_found("Mailbox not found", mailbox: "NonExistent")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Mail.get_unread_count("NonExistent")
    end

    test "handles Mail app errors" do
      error = Error.execution_error("Mail not running")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Mail.get_unread_count("Work")
    end

    test "parses count correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "99"}
      end)

      assert {:ok, 99} = Mail.get_unread_count("Archive")
    end

    test "escapes quotes in mailbox name" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, "1"}
      end)

      assert {:ok, 1} = Mail.get_unread_count("My \"Special\" Mailbox")
    end
  end

  describe "search_mailbox/2" do
    test "searches mailbox and returns results" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Mail"
        assert script =~ "messages of mailbox"
        assert script =~ "INBOX"
        assert script =~ "invoice"
        {:ok, "Invoice #123|billing@example.com|2025-01-15,Re: Invoice|support@example.com|2025-01-14"}
      end)

      assert {:ok, messages} = Mail.search_mailbox("INBOX", "invoice")
      assert length(messages) == 2

      assert Enum.at(messages, 0) == %{
               subject: "Invoice #123",
               from: "billing@example.com",
               date: "2025-01-15"
             }

      assert Enum.at(messages, 1) == %{
               subject: "Re: Invoice",
               from: "support@example.com",
               date: "2025-01-14"
             }
    end

    test "returns empty list when no matches" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "INBOX"
        assert script =~ "nonexistent"
        {:ok, ""}
      end)

      assert {:ok, []} = Mail.search_mailbox("INBOX", "nonexistent")
    end

    test "handles mailbox not found" do
      error = Error.not_found("Mailbox not found", mailbox: "NonExistent")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Mail.search_mailbox("NonExistent", "test")
    end

    test "handles Mail app errors" do
      error = Error.execution_error("Mail not running")

      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, error}
      end)

      assert {:error, ^error} = Mail.search_mailbox("INBOX", "test")
    end

    test "escapes quotes in mailbox name" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert {:ok, []} = Mail.search_mailbox("My \"Special\" Mailbox", "test")
    end

    test "escapes quotes in search term" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "\\\""
        {:ok, ""}
      end)

      assert {:ok, []} = Mail.search_mailbox("INBOX", "\"quoted\" search")
    end

    test "parses single result correctly" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "Test Subject|sender@example.com|2025-01-15"}
      end)

      assert {:ok, [message]} = Mail.search_mailbox("INBOX", "test")

      assert message == %{
               subject: "Test Subject",
               from: "sender@example.com",
               date: "2025-01-15"
             }
    end
  end
end
