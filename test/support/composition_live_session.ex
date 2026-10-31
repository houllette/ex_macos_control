defmodule ExMacOSControl.CompositionLiveSession do
  @moduledoc false
  import ExUnit.Assertions

  alias ExMacOSControl.{
    Applications,
    Automation,
    Capabilities,
    Composition,
    Desktop,
    DesktopSession,
    LiveEvidence,
    OSAScriptAdapter,
    Permissions
  }

  alias ExMacOSControl.Qualification.Host

  def start(context) do
    assert System.get_env("EXMC_LIVE_TESTS") == "1"
    assert System.get_env("EXMC_PERSONAL_TESTS") == "1"
    assert {:ok, host} = Host.snapshot()
    assert host["session"] == "Aqua", "Personal qualification must run from the logged-in GUI session"
    previous = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, OSAScriptAdapter)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:ex_macos_control, :adapter, previous) end)
    marker = "EXMC-QA-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    root = Path.expand("tmp/composition-qualification/" <> marker)
    apps = context[:apps] || []
    {revision, 0} = System.cmd("git", ["rev-parse", "HEAD"])

    session =
      LiveEvidence.open(root, %{
        marker: marker,
        case: to_string(context.test),
        host: host,
        revision: String.trim(revision),
        source_sha256: source_fingerprint(),
        apps: Map.new(apps, &{&1, app_version(&1)}),
        permissions: permission_states(apps)
      })

    ExUnit.Callbacks.on_exit(fn ->
      summary = LiveEvidence.finish(session)
      assert summary.status == :passed, "Live evidence #{summary.status}; inspect #{session.root}"
    end)

    desktop = DesktopSession.start(apps: apps, finder: context[:finder] || false)
    Enum.each(apps, &prepare_app/1)
    session = Map.put(session, :desktop, desktop.desktop_directory)
    event(session, "started", %{test: to_string(context.test), macos: host["macos"]})
    session
  end

  def effect(session, name, fun, opts \\ []) do
    run_id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    event(session, "intent", %{operation: name, run_id: run_id})

    result =
      Desktop.with_lock(fn -> Composition.effect(name, fun) end,
        journal: Path.join(session.root, "execution"),
        run_id: run_id,
        timeout: Keyword.get(opts, :timeout, 30_000)
      )

    event(session, effect_status(result, opts), %{
      operation: name,
      run_id: run_id
    })

    result
  end

  defp effect_status({:error, _}, opts), do: if(opts[:expect_error], do: "expected_failure", else: "effect_failed")
  defp effect_status(_result, _opts), do: "acknowledged"

  def create(session, kind, fun, cleanup, absent, identity \\ %{}) do
    intent = LiveEvidence.intent(session, kind, identity)

    case effect(session, kind, fun) do
      {:ok, id} = result ->
        own(session, kind, id, fn -> cleanup.(id) end, verify: fn -> absent.(id) end, intent_id: intent)
        result

      {:error, %{details: %{outcome: :not_started}}} = error ->
        event(session, "resource_not_started", %{intent_id: intent})
        error

      error ->
        error
    end
  end

  def own(session, kind, id, cleanup, opts \\ []) do
    intent = opts[:intent_id] || LiveEvidence.intent(session, kind)
    event(session, "owned", %{kind: kind, id: id, intent_id: intent})

    ExUnit.Callbacks.on_exit(fn ->
      result =
        Desktop.with_lock(fn -> LiveEvidence.cleanup(session, intent, cleanup, opts[:verify]) end, timeout: 20_000)

      assert :ok = result, "Owned #{kind} cleanup failed; inspect #{session.root}"
    end)

    id
  end

  def query(bundle, body, params \\ %{}), do: Automation.query(bundle, body, params, timeout: 15_000)

  defdelegate event(session, event, data \\ %{}), to: LiveEvidence

  def absent(bundle, collection, id) do
    with {:ok, _} <- Applications.ensure_running(bundle, timeout: 5000),
         do: query(bundle, "var ids=app.#{collection}.id();return !ids || ids.indexOf(input.id)<0;", %{id: id})
  end

  defp app_version(identity) do
    case Capabilities.app(identity) do
      {:ok, app} -> Map.take(app, [:bundle_id, :version, :build])
      _ -> %{status: :unavailable}
    end
  end

  defp source_fingerprint do
    ["lib/**/*.{ex,exs}", "test/**/*.{ex,exs}"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.sort()
    |> Enum.map(fn path -> [path, <<0>>, File.read!(path), <<0>>] end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp permission_states(apps) do
    diagnosis = Permissions.diagnose(apps)

    %{
      accessibility: permission_state(diagnosis.accessibility),
      automation: Map.new(diagnosis.automation, fn {app, result} -> {app, permission_state(result)} end)
    }
  end

  defp permission_state({:ok, state}), do: state
  defp permission_state({:error, _}), do: :error
  defp permission_state(state) when is_atom(state), do: state

  defp prepare_app(identity) when identity in ["com.apple.reminders", "com.apple.iCal"],
    do: assert({:ok, _} = Applications.open(identity, background: true, timeout: 15_000))

  defp prepare_app(identity), do: assert({:ok, _} = Applications.ensure_running(identity, timeout: 15_000))
end
