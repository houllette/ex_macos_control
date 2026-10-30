defmodule ExMacOSControl.CapabilitiesTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Capabilities, Error, ScriptingDictionary}
  setup :verify_on_exit!

  setup do
    directory = Path.expand("tmp/dictionary-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    %{directory: directory}
  end

  test "resolves local standard suites and invalidates a cache when an include changes", %{directory: directory} do
    included = Path.join(directory, "standard.sdef")
    root = Path.join(directory, "app.sdef")
    File.write!(included, ~s|<dictionary><suite name="Standard"><command name="one"/></suite></dictionary>|)

    File.write!(
      root,
      ~s|<dictionary xmlns:xi="http://www.w3.org/2003/XInclude"><xi:include href="standard.sdef" xpointer="xpointer(/dictionary/suite)"/><suite name="App"><class name="item"><property name="title"/></class></suite></dictionary>|
    )

    assert {:ok, %{status: :declared, qualification: :unverified, suites: [standard, app]} = first} =
             Capabilities.dictionary_file(root)

    assert hd(standard.commands)["name"] == "one"
    assert hd(app.classes)["children"] |> hd() |> Map.get("name") == "title"
    File.write!(included, ~s|<dictionary><suite name="Standard"><command name="two"/></suite></dictionary>|)
    assert {:ok, second} = Capabilities.dictionary_file(root)
    refute second.fingerprint == first.fingerprint
  end

  test "rejects remote includes, include cycles and entities", %{directory: directory} do
    root = Path.join(directory, "app.sdef")

    for href <- ["https://example.invalid/private", "app.sdef"] do
      File.write!(
        root,
        ~s|<dictionary xmlns:xi="http://www.w3.org/2003/XInclude"><xi:include href="#{href}"/></dictionary>|
      )

      assert {:error, %Error{}} = Capabilities.dictionary_file(root)
    end

    assert {:error, %Error{}} =
             ScriptingDictionary.parse(
               ~s|<!DOCTYPE dictionary [<!ENTITY secret SYSTEM "file:///etc/passwd">]><dictionary>&secret;</dictionary>|
             )

    assert {:error, %Error{}} = ScriptingDictionary.parse("<dictionary><broken></dictionary>")
  end

  test "missing terminology remains unknown rather than becoming an unsupported command", %{directory: directory} do
    app_path = Path.join(directory, "Synthetic.app")
    File.mkdir_p!(Path.join(app_path, "Contents/Resources"))

    app = %{
      name: "Synthetic",
      path: app_path,
      bundle_id: "invalid.synthetic",
      version: "1",
      build: "1",
      dictionary: nil,
      scriptable: nil
    }

    expect(ExMacOSControl.AdapterMock, :run_javascript, 3, fn _, _ ->
      {:ok, Jason.encode!(%{exmc: 1, result: [app]})}
    end)

    assert {:ok, %{declared: nil, status: :unknown}} = Capabilities.declares?("invalid.synthetic", "open")

    File.write!(
      Path.join(app_path, "Contents/Resources/App.sdef"),
      ~s|<dictionary><suite name="App"><command name="open"/></suite></dictionary>|
    )

    assert {:ok, %{declared: true, status: :declared}} = Capabilities.declares?("invalid.synthetic", "open")
    assert {:ok, %{declared: false, status: :declared}} = Capabilities.declares?("invalid.synthetic", "other")
  end
end
