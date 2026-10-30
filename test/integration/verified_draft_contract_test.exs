defmodule ExMacOSControl.VerifiedDraftContractTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Mail, OSAScriptAdapter}
  alias ExMacOSControl.Mail.Draft
  @moduletag :integration
  setup :verify_on_exit!

  test "a changed native identity prevents draft deletion" do
    fixture = """
    var draft={exists:function(){return true;},subject:function(){return 'changed';},messageId:function(){return 'native';}};
    var fixture={draftsMailbox:function(){return {messages:{byId:function(){return draft;}}};},
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
end
