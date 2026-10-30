defmodule ExMacOSControl.QualificationContractTest do
  use ExUnit.Case, async: false
  import Mox
  @moduletag :integration
  alias ExMacOSControl.Qualification.{Host, Native}
  alias ExMacOSControl.{QualificationFixture, Script}
  setup :verify_on_exit!

  test "host provisioning inspection uses only native metadata" do
    assert {:ok, snapshot} = Host.snapshot()
    assert is_integer(snapshot["uid"])
    assert is_integer(snapshot["console_uid"])
    assert is_list(snapshot["groups"])
    assert byte_size(snapshot["machine_sha256"]) == 64
    assert snapshot["workspace"] == File.cwd!()
  end

  test "qualification scripts compile without performing any app operation" do
    notes = QualificationFixture.manifest(Path.expand("tmp/qa"))
    mail = QualificationFixture.manifest(Path.expand("tmp/qa"), "mail-capture")

    context = %{
      id: "note",
      marker: "EXMC-QA-run",
      deadline: System.monotonic_time(:millisecond) + 30_000,
      expires_at: notes["expires_at"]
    }

    opts = [timeout: 5000, max_output_bytes: 65_536]

    stub(ExMacOSControl.AdapterMock, :run_javascript, fn source, _ ->
      send(self(), {:source, :javascript, source})
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    stub(ExMacOSControl.AdapterMock, :run_applescript, fn source, _ ->
      send(self(), {:source, :applescript, source})
      {:ok, "true"}
    end)

    Native.fixture(notes, "notes-crud", opts)
    Native.fixture(mail, "mail-capture", opts)
    for operation <- [:notes_create, :notes_update, :notes_delete], do: Native.perform(operation, notes, context, opts)
    for operation <- [:notes_get, :notes_absent], do: Native.observe(operation, notes, context, opts)
    Native.observe(:mail_idle, mail, context, opts)
    Native.perform(:mail_send, mail, context, opts)

    for _ <- 1..12 do
      assert_receive {:source, language, source}
      assert :ok = Script.validate(source, language: language)
    end

    refute_receive {:source, _, _}
  end
end
