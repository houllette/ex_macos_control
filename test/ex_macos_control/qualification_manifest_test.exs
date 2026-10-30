defmodule ExMacOSControl.Qualification.ManifestTest do
  use ExUnit.Case, async: true
  alias ExMacOSControl.{Error, QualificationFixture}
  alias ExMacOSControl.Qualification.{Host, Manifest}

  test "accepts only a finite, explicitly scoped manifest" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))
    assert {:ok, ^manifest} = Manifest.validate(manifest, "notes-crud")

    for changed <- [
          Map.put(manifest, "expires_at", 1),
          Map.put(manifest, "extra", "ignored?"),
          Map.put(manifest, "expires_at", "2000-01-01T00:00:00Z"),
          put_in(manifest, ["host", "uid"], 0),
          put_in(manifest, ["host", "disposable"], false),
          put_in(manifest, ["limits", "deadline_ms"], nil),
          put_in(manifest, ["limits", "max_effects"], 2),
          put_in(manifest, ["limits", "max_sends"], 1),
          put_in(manifest, ["fixtures", "notes", "folder_id"], ""),
          put_in(manifest, ["fixtures", "notes", "folder_name"], "Personal")
        ] do
      assert {:error, %Error{}} = Manifest.validate(changed, "notes-crud")
    end

    for profile <- ["external-send", "recording", "shell", nil] do
      assert {:error, %Error{}} = Manifest.validate(manifest, profile)
    end

    for value <- [nil, [], "json?", 1], do: assert({:error, %Error{}} = Manifest.validate(value, "notes-crud"))
  end

  test "capture refuses real-domain addresses, extra recipients and excess sends" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"), "mail-capture")
    assert {:ok, _} = Manifest.validate(manifest, "mail-capture")

    for changed <- [
          put_in(manifest, ["fixtures", "mail", "recipient"], "real@example.com"),
          put_in(manifest, ["fixtures", "mail", "recipient"], ["one@qa.invalid", "two@qa.invalid"]),
          put_in(manifest, ["fixtures", "mail", "sender"], "Display Name <sender@qa.invalid>"),
          put_in(manifest, ["fixtures", "mail", "smtp_port"], 25),
          put_in(manifest, ["limits", "max_sends"], 2)
        ] do
      assert {:error, %Error{}} = Manifest.validate(changed, "mail-capture")
    end
  end

  test "identity includes the active console session and exact workspace" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))
    QualificationFixture.setup(manifest)
    snapshot = Process.get({QualificationFixture, :snapshot})
    assert :ok = Host.verify(manifest, snapshot)

    for {key, value} <- [
          {"uid", 0},
          {"groups", ["staff", "admin"]},
          {"console_uid", 503},
          {"workspace", "/tmp"},
          {"username", "personal"},
          {"machine_sha256", "other"}
        ] do
      assert {:error, %Error{}} = Host.verify(manifest, Map.put(snapshot, key, value))
    end
  end

  test "manifest loading refuses public permissions and symlinks" do
    directory = Path.expand("tmp/manifest-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    path = Path.join(directory, "manifest.json")
    manifest = QualificationFixture.manifest(directory)
    File.write!(path, Jason.encode!(manifest))
    File.chmod!(path, 0o644)
    assert {:error, %Error{}} = Manifest.load(path)
    File.chmod!(path, 0o600)
    assert {:ok, ^manifest} = Manifest.load(path)
    File.write!(path, ~s({"version":1,"version":1}))
    assert {:error, %Error{}} = Manifest.load(path)
    File.ln_s!(path, path <> ".link")
    assert {:error, %Error{}} = Manifest.load(path <> ".link")
  end
end
