defmodule ExMacOSControl.Qualification.NativeTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExMacOSControl.{Error, QualificationFixture}
  alias ExMacOSControl.Qualification.Native
  setup :verify_on_exit!

  test "cleanup refuses a note whose exact container and marker cannot be proved" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))

    context = %{
      id: "unowned",
      marker: "EXMC-QA-run",
      deadline: System.monotonic_time(:millisecond) + 1000,
      expires_at: manifest["expires_at"]
    }

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn source, opts ->
      assert source =~ "byId(app.folders,input.folder).notes"
      assert source =~ "o.name()===input.marker"
      assert source =~ "o.container().id()===input.folder"
      input = opts[:args] |> hd() |> Jason.decode!()
      assert input["folder"] == "qa-folder"
      assert input["id"] == "unowned"
      assert input["marker"] == context.marker
      {:ok, ~s({"exmc":1,"result":false})}
    end)

    assert {:error, %Error{}} = Native.perform(:notes_delete, manifest, context, timeout: 1000, max_output_bytes: 1024)
  end

  test "updates keep the marker on the first line so Notes retains its title" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))
    context = context(manifest)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
      input = opts[:args] |> hd() |> Jason.decode!()
      assert input["properties"]["body"] == "<p>#{context.marker}</p><p>changed</p>"
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    assert :ok = Native.perform(:notes_update, manifest, context, timeout: 1000, max_output_bytes: 4096)
  end

  defp context(manifest) do
    %{
      id: "note",
      marker: "EXMC-QA-run",
      deadline: System.monotonic_time(:millisecond) + 1000,
      expires_at: manifest["expires_at"]
    }
  end

  test "an effect lease expires again after ownership inspection" do
    manifest = QualificationFixture.manifest(Path.expand("tmp/qa"))

    context = %{
      id: "note",
      marker: "EXMC-QA-run",
      deadline: System.monotonic_time(:millisecond) + 250,
      expires_at: manifest["expires_at"]
    }

    expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
      Process.sleep(300)
      {:ok, ~s({"exmc":1,"result":true})}
    end)

    assert {:error, %Error{message: "Effect lease expired before dispatch"}} =
             Native.perform(:notes_delete, manifest, context, timeout: 1000, max_output_bytes: 1024)
  end
end
