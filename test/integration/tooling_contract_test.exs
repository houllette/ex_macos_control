defmodule ExMacOSControl.ToolingContractTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  alias ExMacOSControl.{Capabilities, Error, Finder, OSAScriptAdapter, Script}

  setup do
    previous = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)
    on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, previous) end)
  end

  test "metadata discovery finds installed identities without target app events" do
    assert {:ok, apps} = Capabilities.list_apps(paths: ["/System/Library/CoreServices"])
    assert Enum.any?(apps, &(&1.bundle_id == "com.apple.finder"))

    assert {:ok, %{status: :declared, qualification: :unverified, suites: suites}} =
             Capabilities.dictionary("com.apple.finder", paths: ["/System/Library/CoreServices"])

    assert Enum.any?(suites, &Enum.any?(&1.commands, fn c -> c["name"] == "open" end))
  end

  test "source validation, compilation and decompilation do not execute the source" do
    path = Path.expand("tmp/tooling-#{System.unique_integer([:positive])}.scpt")
    marker = path <> ".marker"

    on_exit(fn ->
      File.rm(path)
      File.rm(marker)
    end)

    source = ~s(do shell script "touch '#{marker}'")
    assert :ok = Script.validate(source)
    assert :ok = Script.compile(source, path)
    assert {:ok, result} = Script.decompile(path)
    assert result =~ "touch"
    refute File.exists?(marker)
    assert {:error, %Error{}} = Script.validate("invalid applescript syntax")
    assert :ok = Script.validate("function run(argv) { return argv[0]; }", language: :javascript)
  end

  test "file metadata retains numeric sizes and ISO dates through Foundation" do
    path = Path.expand("tmp/metadata-#{System.unique_integer([:positive])}")
    File.write!(path, "data")
    on_exit(fn -> File.rm(path) end)
    assert {:ok, %{path: ^path, size: 4, created_at: created, modified_at: modified}} = Finder.metadata(path)
    assert {:ok, _, _} = DateTime.from_iso8601(created)
    assert {:ok, _, _} = DateTime.from_iso8601(modified)
  end

  test "stdin accepts scripts larger than the inline command argument limit" do
    script = "-- " <> String.duplicate("padding", 20_000) <> "\nreturn \"large\""
    assert {:ok, "large"} = OSAScriptAdapter.run_applescript(script)

    assert {:ok, "--flag"} =
             OSAScriptAdapter.run_applescript("on run argv\nreturn item 1 of argv\nend run",
               stdin: true,
               args: ["--flag"]
             )
  end

  test "property list writes validate and preserve existing permissions" do
    path = Path.expand("tmp/plist-#{System.unique_integer([:positive])}.plist")
    on_exit(fn -> File.rm(path) end)
    value = %{"text" => "literal 雪\n", "enabled" => false, "values" => [1, 2]}
    assert :ok = ExMacOSControl.PropertyList.write(path, value, format: :binary)
    assert {:ok, ^value} = ExMacOSControl.PropertyList.read(path)
    assert :ok = File.chmod(path, 0o600)
    assert :ok = ExMacOSControl.PropertyList.write(path, value)
    assert {:ok, %{mode: mode}} = File.stat(path)
    assert Bitwise.band(mode, 0o777) == 0o600
  end
end
