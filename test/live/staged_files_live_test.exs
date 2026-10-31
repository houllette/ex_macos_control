defmodule ExMacOSControl.StagedFilesLiveTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Capture, CompositionLiveSession, LiveEvidence, Mail}
  alias ExMacOSControl.Capture.Files
  @moduletag :personal
  @moduletag staged_files: true
  @moduletag timeout: 120_000
  @moduletag apps: ["com.apple.mail"]
  unless System.get_env("EXMC_LIVE_TESTS") == "1" and System.get_env("EXMC_PERSONAL_TESTS") == "1",
    do: @moduletag(skip: "Requires personal opt-in")

  test "copied captures attach their original bytes after source deletion", context do
    live = CompositionLiveSession.start(context)
    source = Path.join(live.root, "source.txt")
    bytes = live.marker <> " original bytes 雪\n"
    File.write!(source, bytes)
    capture = %Files{paths: [source], source: %{app: :finder}, captured_at: DateTime.utc_now()}
    root = Path.join(live.root, "staging")
    intent = LiveEvidence.intent(live, :file_capture, %{path: root})
    assert {:ok, staged} = Capture.stage_files(capture, root)

    CompositionLiveSession.own(live, :file_capture, root, fn -> Capture.cleanup_files(staged) end,
      intent_id: intent,
      verify: fn -> not File.exists?(root) end
    )

    File.rm!(source)
    intent = LiveEvidence.intent(live, :draft)

    assert {:ok, draft} =
             CompositionLiveSession.effect(live, :draft_staged_capture, fn ->
               Mail.create_verified_draft_from(staged,
                 to: System.get_env("EXMC_TEST_EMAIL", "holdenoullette@gmail.com"),
                 subject: live.marker
               )
             end)

    CompositionLiveSession.own(live, :draft, draft.id, fn -> Mail.delete_draft(draft) end,
      intent_id: intent,
      verify: fn -> CompositionLiveSession.draft_absent(draft) end
    )

    assert {:ok, %{attachments: [attachment]}} = Mail.get_draft(draft)
    assert attachment.size == byte_size(bytes)
    saved = Path.join(live.root, "readback.txt")

    assert {:ok, true} =
             CompositionLiveSession.effect(live, :read_back_attachment, fn ->
               CompositionLiveSession.query(
                 "com.apple.mail",
                 """
                 var o=app.draftsMailbox().messages.byId(input.id);
                 if(o.subject()!==input.subject || o.messageId()!==input.message_id)throw new Error('Draft identity changed');
                 var attachments=o.mailAttachments();if(attachments.length!==1)throw new Error('Attachment count changed');
                 app.save(attachments[0],{in:Path(input.path)});return true;
                 """,
                 %{id: draft.id, subject: draft.subject, message_id: draft.message_id, path: saved}
               )
             end)

    assert File.read!(saved) == bytes
    assert :ok = Capture.verify_files(staged)

    CompositionLiveSession.event(live, "verified", %{
      source_removed: true,
      copied_bytes: true,
      saved_attachment_bytes: true,
      sent: false
    })
  end
end
