defmodule ExMacOSControl.VerifiedDraftContractTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Mail, OSAScriptAdapter}
  alias ExMacOSControl.Mail.Draft
  @moduletag :integration
  setup :verify_on_exit!

  test "saved draft matching rejects wrong sender, cc, bcc, body and attachment size in the native engine" do
    valid = %{
      body: "Body\r\n",
      sender: "Self <self@example.invalid>",
      cc: ["cc@example.invalid"],
      bcc: ["bcc@example.invalid"],
      attachments: []
    }

    for {key, value} <- [
          sender: "wrong@example.invalid",
          cc: [],
          bcc: [],
          body: "prefix Body suffix",
          attachments: [%{name: "extra.txt", size: 1}]
        ] do
      fixture = draft_fixture(Map.put(valid, key, value))
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{ids: [], pid: 42}) end)
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, "outgoing"} end)

      expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
        assert {:ok, output} = native(fixture, source, opts)
        assert Jason.decode!(output)["result"] == []
        {:error, ExMacOSControl.Error.execution_error("fixture mismatch observed")}
      end)

      assert {:error, _} =
               Mail.create_verified_draft(
                 to: "self@example.invalid",
                 subject: "Title",
                 body: "Body",
                 sender: "self@example.invalid",
                 cc: ["cc@example.invalid"],
                 bcc: ["bcc@example.invalid"]
               )
    end

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> response(%{ids: [], pid: 42}) end)
    expect(ExMacOSControl.AdapterMock, :run_applescript, fn _, _ -> {:ok, "outgoing"} end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      native(draft_fixture(valid), source, opts)
    end)

    assert {:ok, %Draft{id: 7}} =
             Mail.create_verified_draft(
               to: "self@example.invalid",
               subject: "Title",
               body: "Body",
               sender: "self@example.invalid",
               cc: ["cc@example.invalid"],
               bcc: ["bcc@example.invalid"]
             )
  end

  test "a changed native identity prevents draft deletion" do
    fixture = """
    var draft={exists:function(){return true;},subject:function(){return 'changed';},messageId:function(){return 'native';}};
    var fixture={draftsMailbox:function(){return {messages:{id:function(){return [42];},byId:function(){return draft;}}};},
      delete:function(){throw new Error('Must not delete a changed draft');}};
    """

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      source =
        String.replace(
          source,
          "var app = input.__bundle_id ? Application(input.__bundle_id) : Application.currentApplication();",
          "var app=fixture;"
        )

      OSAScriptAdapter.run_javascript(fixture <> source, opts)
    end)

    reference = %Draft{
      id: 42,
      outgoing_id: "999",
      subject: "original",
      message_id: "native",
      created_at: DateTime.utc_now()
    }

    assert {:error, error} = Mail.delete_draft(reference)
    assert error.message =~ "Saved draft identity changed"
    refute error.message =~ "Must not delete"
  end

  test "native draft deletion closes its compose object and accepts Mail already removing the saved message" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "app.close"
      native_process(compose_fixture(true, true, "original", true), source, opts)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      refute source =~ "app.close"
      native_process(compose_fixture(false, false, "original", false), source, opts)
    end)

    assert :ok = Mail.delete_draft(reference(100))
  end

  test "a changed Mail process preserves a reused outgoing ID while deleting the captured saved message" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      native_process(compose_fixture(true, true, "new user's compose", false), source, opts)
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      native_process(compose_fixture(false, true, "new user's compose", false), source, opts)
    end)

    assert :ok = Mail.delete_draft(reference(99))
  end

  test "a changed outgoing identity refuses both close and saved message deletion" do
    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      native_process(compose_fixture(true, true, "changed", false), source, opts)
    end)

    assert {:error, error} = Mail.delete_draft(reference(100))
    assert error.message =~ "Outgoing draft identity changed"
    refute error.message =~ "Must not close"
  end

  defp reference(pid),
    do: %Draft{
      id: 42,
      outgoing_id: "999",
      mail_pid: pid,
      subject: "original",
      message_id: "native",
      created_at: DateTime.utc_now()
    }

  defp native_process(fixture, source, opts) do
    source = String.replace(source, ~r/function mailPID\(\)\{.*?\}\n/s, "function mailPID(){return 100;}\n")
    native(fixture, source, opts)
  end

  defp compose_fixture(saved, outgoing, subject, close_allowed) do
    """
    var saved=#{saved},outgoing=#{outgoing},closeAllowed=#{close_allowed};
    var draft={exists:function(){return saved;},subject:function(){return 'original';},messageId:function(){return 'native';}};
    var compose={id:function(){return 999;},subject:function(){return #{Jason.encode!(subject)};}};
    var messages={id:function(){return saved?[42]:[];},byId:function(){return draft;}};
    var outgoingMessages=function(){return outgoing?[compose]:[];};outgoingMessages.id=function(){return outgoing?[999]:[];};
    var fixture={draftsMailbox:function(){return {messages:messages};},outgoingMessages:outgoingMessages,
      close:function(o,options){if(!closeAllowed)throw new Error('Must not close a different compose object');
        if(o!==compose||options.saving!=='no')throw new Error('Wrong close target or save policy');outgoing=false;saved=false;},
      delete:function(o){if(o!==draft)throw new Error('Wrong saved target');saved=false;}};
    """
  end

  defp draft_fixture(data) do
    """
    var data=#{Jason.encode!(data)};
    var candidate={id:function(){return 7;},messageId:function(){return 'saved';},
      content:function(){return data.body;},sender:function(){return data.sender;},
      toRecipients:{address:function(){return ['self@example.invalid'];}},
      ccRecipients:{address:function(){return data.cc;}},bccRecipients:{address:function(){return data.bcc;}},
      mailAttachments:function(){return data.attachments.map(function(a){return {name:function(){return a.name;},fileSize:function(){return a.size;}};});}};
    var fixture={draftsMailbox:function(){return {messages:{whose:function(){return function(){return [candidate];};}}};}};
    """
  end

  defp native(fixture, source, opts) do
    source =
      String.replace(
        source,
        "var app = input.__bundle_id ? Application(input.__bundle_id) : Application.currentApplication();",
        "var app=fixture;"
      )

    OSAScriptAdapter.run_javascript(fixture <> source, opts)
  end

  defp response(value), do: {:ok, Jason.encode!(%{exmc: 1, result: value})}
end
