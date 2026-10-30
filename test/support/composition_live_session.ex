defmodule ExMacOSControl.CompositionLiveSession do
  @moduledoc false
  import ExUnit.Assertions
  alias ExMacOSControl.{Automation, Composition, DesktopSession, OSAScriptAdapter}
  alias ExMacOSControl.Qualification.Host

  def start(context) do
    assert System.get_env("EXMC_LIVE_TESTS") == "1"
    assert System.get_env("EXMC_PERSONAL_TESTS") == "1"
    assert {:ok, host} = Host.snapshot()
    assert host["session"] == "Aqua", "Personal qualification must run from the logged-in GUI session"
    previous = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, previous) end)
    desktop = DesktopSession.start(apps: context[:apps] || [], finder: context[:finder] || false)
    marker = "EXMC-QA-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    root = Path.expand("tmp/composition-qualification/" <> marker)
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    session = %{root: root, marker: marker, desktop: desktop.desktop_directory}
    event(session, "started", %{test: to_string(context.test), macos: host["macos"]})
    session
  end

  def effect(session, name, fun) do
    event(session, "intent", %{operation: name})
    result = Composition.run(fn -> Composition.effect(name, fun) end, journal: Path.join(session.root, "execution"))
    event(session, "acknowledged", %{operation: name, result: inspect(result, limit: 5, printable_limit: 200)})
    result
  end

  def own(session, kind, id, cleanup) do
    event(session, "owned", %{kind: kind, id: id})

    ExUnit.Callbacks.on_exit(fn ->
      event(session, "cleanup_intent", %{kind: kind, id: id})
      assert :ok = cleanup.(), "Owned #{kind} cleanup failed; inspect #{session.root}"
      event(session, "cleaned", %{kind: kind, id: id})
    end)

    id
  end

  def query(bundle, body, params \\ %{}), do: Automation.query(bundle, body, params, timeout: 15_000)

  def event(session, event, data \\ %{}) do
    path = Path.join(session.root, "events.jsonl")
    record = Map.merge(data, %{event: event, at: DateTime.to_iso8601(DateTime.utc_now()), marker: session.marker})
    File.write!(path, Jason.encode!(record) <> "\n", [:append, :sync])
    File.chmod!(path, 0o600)
  end
end
