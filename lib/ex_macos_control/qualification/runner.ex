defmodule ExMacOSControl.Qualification.Runner do
  @moduledoc false
  alias ExMacOSControl.Automation
  alias ExMacOSControl.Qualification.{Host, Journal, Manifest, Session, Suite}

  def check(manifest, profile, backend) do
    with {:ok, _} <- Manifest.validate(manifest, profile),
         :ok <- journal_ready(manifest),
         {:ok, snapshot} <-
           backend.guard(manifest, profile, timeout: 5000, max_output_bytes: manifest["limits"]["max_bytes"]) do
      {:ok, %{status: :ready, profile: profile, host: snapshot}}
    end
  rescue
    _ -> Automation.invalid("Qualification preflight raised; refusing effects")
  catch
    _, _ -> Automation.invalid("Qualification preflight exited; refusing effects")
  end

  defp journal_ready(manifest) do
    case Journal.ready(manifest["workspace"]) do
      :ok -> :ok
      _ -> Automation.invalid("An unresolved journal or unsafe storage blocks qualification")
    end
  end

  def run(manifest, profile, backend, run_id) do
    with {:ok, _} <- Manifest.validate(manifest, profile),
         {:ok, lock} <- Host.lock() do
      try do
        guarded_run(manifest, profile, backend, run_id)
      after
        Host.unlock(lock)
      end
    else
      _ -> Automation.invalid("Qualification manifest is invalid or another live runner holds the host lock")
    end
  rescue
    _ -> Automation.invalid("Qualification interrupted; inspect unresolved journals before another run")
  catch
    _, _ -> Automation.invalid("Qualification interrupted; inspect unresolved journals before another run")
  end

  defp guarded_run(manifest, profile, backend, run_id) do
    with {:ok, check} <- check(manifest, profile, backend),
         {:ok, journal} <- Journal.open(manifest["workspace"], run_id) do
      try do
        execute(manifest, profile, backend, journal, check.host)
      after
        Journal.close(journal)
      end
    end
  end

  defp execute(manifest, profile, backend, journal, snapshot) do
    event = %{
      event: "started",
      profile: profile,
      manifest_sha256: hash(manifest),
      host: snapshot,
      fixtures: manifest["fixtures"],
      apps: manifest["apps"],
      limits: manifest["limits"],
      backend: inspect(backend),
      code_fingerprint: code_fingerprint(backend)
    }

    case Journal.append(journal, event) do
      :ok -> manifest |> Session.new(profile, backend, journal) |> Suite.run() |> finish(journal)
      _ -> Automation.invalid("Unable to persist run intent; no operations were dispatched")
    end
  end

  defp finish({:ok, state}, journal) do
    event = %{event: "finished", status: "passed", effects: state.effects, sends: state.sends}

    case Journal.append(journal, event) do
      :ok -> {:ok, Map.put(event, :journal, journal.path)}
      _ -> Automation.invalid("Unable to persist completion; reconcile before another run")
    end
  end

  defp finish({:error, error, state}, journal) do
    Journal.append(journal, %{
      event: "finished",
      status: "needs_reconciliation",
      effects: state.effects,
      sends: state.sends
    })

    {:error, error}
  end

  defp hash(value), do: Base.encode16(:crypto.hash(:sha256, Jason.encode!(value)), case: :lower)

  defp code_fingerprint(backend) do
    modules = [
      __MODULE__,
      Session,
      Suite,
      Journal,
      Manifest,
      Host,
      backend,
      ExMacOSControl.Qualification.Capture,
      ExMacOSControl.Notes,
      ExMacOSControl.Mail,
      ExMacOSControl.OSAScriptAdapter,
      ExMacOSControl.Automation,
      ExMacOSControl.Command,
      ExMacOSControl.Capabilities,
      ExMacOSControl.Permissions
    ]

    identity =
      Enum.map(modules, fn module ->
        Code.ensure_loaded!(module)
        {module, module.module_info(:md5)}
      end)

    Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(identity)), case: :lower)
  end
end
