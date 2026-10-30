defmodule ExMacOSControl.Qualification.JournalTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.Error
  alias ExMacOSControl.Qualification.Journal

  setup do
    workspace = Path.expand("tmp/journal-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)
    %{workspace: workspace, first: String.duplicate("d", 32), second: String.duplicate("e", 32)}
  end

  test "crash residue and failure block another run; a verified completion permits a fresh ID", context do
    assert {:ok, journal} = Journal.open(context.workspace, context.first)
    assert :ok = Journal.append(journal, %{event: "intent", operation: "create"})
    assert {:error, %Error{}} = Journal.open(context.workspace, context.second)
    assert :ok = Journal.append(journal, %{event: "finished", status: "needs_reconciliation"})
    assert {:error, %Error{}} = Journal.open(context.workspace, context.second)
    assert :ok = Journal.append(journal, %{event: "finished", status: "passed"})
    Journal.close(journal)
    assert {:ok, second} = Journal.open(context.workspace, context.second)
    Journal.close(second)
  end

  test "truncated journals and symlinked storage are refused", context do
    {:ok, journal} = Journal.open(context.workspace, context.first)
    Journal.close(journal)
    File.write!(Path.join(journal.path, "events.jsonl"), ~s({"event":"finished","status":"passed"}))
    assert {:error, %Error{}} = Journal.open(context.workspace, context.second)
    other = Path.join(context.workspace, "other")
    File.mkdir_p!(Path.join(other, "tmp"))
    File.ln_s!(Path.dirname(journal.path), Path.join(other, "tmp/qualification"))
    assert {:error, %Error{}} = Journal.open(other, context.second)
  end

  test "a malformed earlier record cannot be hidden by a passing final record", context do
    {:ok, journal} = Journal.open(context.workspace, context.first)
    Journal.close(journal)

    File.write!(
      Path.join(journal.path, "events.jsonl"),
      "corrupt\n" <> ~s({"event":"finished","status":"passed"}) <> "\n"
    )

    assert {:error, _} = Journal.ready(context.workspace)
    assert {:error, %Error{}} = Journal.open(context.workspace, context.second)
  end
end
