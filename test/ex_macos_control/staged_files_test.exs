defmodule ExMacOSControl.StagedFilesTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.{Capture, Mail}
  alias ExMacOSControl.Capture.{Files, StagedFiles}
  alias ExMacOSControl.Composition.Journal

  setup do
    root = Path.expand("tmp/staged-capture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    source = Path.join(root, "雪.bin")
    File.write!(source, "original\0bytes")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, source: source, destination: Path.join(root, "copies"), capture: capture([source])}
  end

  test "copied bytes survive source removal and verify independently", context do
    assert {:ok, %StagedFiles{} = staged} = Capture.stage_files(context.capture, context.destination)
    File.rm!(context.source)
    assert [path] = Capture.files(staged)
    assert File.read!(path) == "original\0bytes"
    assert staged.source == context.capture.source and staged.captured_at == context.capture.captured_at
    assert hd(staged.entries).sha256 == Base.encode16(:crypto.hash(:sha256, "original\0bytes"), case: :lower)
    assert :ok = Capture.verify_files(staged)
    assert Capture.render(staged) == path
    assert :ok = Capture.cleanup_files(staged)
    refute File.exists?(context.destination)
  end

  test "existing destinations and deterministic filename collisions write nothing", context do
    File.mkdir!(context.destination)
    sentinel = Path.join(context.destination, "sentinel")
    File.write!(sentinel, "keep")
    assert {:error, %{details: %{outcome: :not_started}}} = Capture.stage_files(context.capture, context.destination)
    assert File.read!(sentinel) == "keep"
    other = Path.join(context.root, "other")
    File.mkdir!(other)
    a = Path.join(other, "File.txt")
    b = Path.join(context.root, "file.TXT")
    File.write!(a, "one")
    File.write!(b, "two")
    destination = Path.join(context.root, "collision")
    assert {:error, _} = Capture.stage_files(capture([a, b]), destination)
    refute File.exists?(destination)
  end

  test "symlinks, directories and oversized inputs reject before creating the stage", context do
    link = Path.join(context.root, "link")
    File.ln_s!(context.source, link)
    assert {:error, _} = Capture.stage_files(capture([link]), context.destination)
    assert {:error, _} = Capture.stage_files(capture([context.root]), context.destination)
    assert {:error, _} = Capture.stage_files(context.capture, context.destination, max_bytes: 1)
    refute File.exists?(context.destination)
  end

  test "changed copies block Mail handoffs and cleanup before any app dispatch", context do
    assert {:ok, staged} = Capture.stage_files(context.capture, context.destination)
    [path] = staged.paths
    File.write!(path, "changed")
    assert {:error, _} = Capture.verify_files(staged)
    assert {:error, _} = Mail.create_verified_draft_from(staged, to: "self@example.invalid")
    assert {:error, _} = Mail.create_draft_from(staged, to: "self@example.invalid")
    assert {:error, _} = Capture.cleanup_files(staged)
    assert File.read!(path) == "changed"
  end

  test "foreign entries prevent cleanup without deleting any owned file", context do
    assert {:ok, staged} = Capture.stage_files(context.capture, context.destination)
    foreign = Path.join(staged.root, "user-added")
    File.write!(foreign, "keep")
    assert {:error, _} = Capture.cleanup_files(staged)
    assert Enum.all?(staged.paths, &File.exists?/1) and File.read!(foreign) == "keep"
  end

  test "directory replacement and copied-file symlinks cannot redirect cleanup", context do
    assert {:ok, staged} = Capture.stage_files(context.capture, context.destination)
    moved = staged.root <> "-moved"
    File.rename!(staged.root, moved)
    File.mkdir!(staged.root)
    File.cp!(context.source, hd(staged.paths))
    assert {:error, _} = Capture.cleanup_files(staged)
    assert File.exists?(hd(staged.paths))
    File.rm_rf!(staged.root)
    File.rename!(moved, staged.root)
    File.rm!(hd(staged.paths))
    File.ln_s!(context.source, hd(staged.paths))
    assert {:error, _} = Capture.verify_files(staged)
    assert {:error, _} = Capture.cleanup_files(staged)
    assert File.read!(context.source) == "original\0bytes"
  end

  test "in-place same-size source changes are detected and partial paths stay inspectable", context do
    File.write!(context.source, :binary.copy("a", 2_097_152))
    attach(fn -> File.write!(context.source, :binary.copy("b", 2_097_152)) end)

    assert {:error, error} =
             Capture.stage_files(context.capture, context.destination, journal: Path.join(context.root, "journal"))

    assert error.details.staging_root == context.destination
    assert error.details.recovery_status == :needs_reconciliation
    assert {:ok, %{pending: [_ | _]}} = Journal.inspect_run(error.details.journal_path)
    assert File.read!(context.source) == :binary.copy("b", 2_097_152)
  end

  test "source replacement with identical bytes still invalidates the copy", context do
    contents = :binary.copy("a", 2_097_152)
    File.write!(context.source, contents)

    attach(fn ->
      File.rename!(context.source, context.source <> ".old")
      File.write!(context.source, contents)
    end)

    assert {:error, _} = Capture.stage_files(context.capture, context.destination)
    assert File.read!(context.source) == contents
  end

  test "an output created between preflight and copying is never overwritten", context do
    File.write!(context.source, :binary.copy("a", 2_097_152))
    second = Path.join(context.root, "second.bin")
    File.write!(second, "second")
    collision = Path.join(context.destination, "second.bin")
    attach(fn -> File.write!(collision, "user content") end)

    assert {:error, %{details: %{outcome: :unknown}}} =
             Capture.stage_files(capture([context.source, second]), context.destination)

    assert File.read!(collision) == "user content"
  end

  test "one, ten and one hundred copies preserve every checksum", context do
    for count <- [1, 10, 100] do
      paths =
        for index <- 1..count do
          path = Path.join(context.root, "#{count}-#{index}.txt")
          File.write!(path, "#{count}-#{index}")
          path
        end

      assert {:ok, staged} = Capture.stage_files(capture(paths), Path.join(context.root, "batch-#{count}"))
      assert Enum.map(staged.paths, &File.read!/1) == Enum.map(paths, &File.read!/1)
      assert :ok = Capture.verify_files(staged)
      assert :ok = Capture.cleanup_files(staged)
    end
  end

  defp capture(paths), do: %Files{paths: paths, source: %{app: :finder}, captured_at: DateTime.utc_now()}

  defp attach(fun) do
    id = {__MODULE__, make_ref()}

    :telemetry.attach(id, [:ex_macos_control, :capture, :copy, :chunk], &__MODULE__.change_once/4, %{
      pid: self(),
      key: id,
      fun: fun
    })

    on_exit(fn -> :telemetry.detach(id) end)
  end

  def change_once(_event, _measurement, _metadata, %{pid: pid, key: key, fun: fun}) do
    if self() == pid and not Process.get(key, false) do
      Process.put(key, true)
      fun.()
    end
  end
end
