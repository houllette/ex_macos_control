defmodule ExMacOSControl.Qualification do
  @moduledoc """
  Runs fixed live qualification cases in an explicitly identified disposable macOS session.

  `run/3` checks readiness by default. Effects require both `execute: true` and
  `EXMC_LIVE_TESTS=1`. Supported profiles are `notes-crud` and `mail-capture`.
  External delivery and recording are disabled. The runner accepts no arbitrary
  scripts or recipient overrides and never changes accounts or grants permissions.

  A version 1 JSON manifest must be private (0600), expire within 24 hours, and
  specify absolute workspace, standard-user/home/machine identity, exact app path/version/build,
  fixture IDs, and finite effect/send/time/byte limits. Capture addresses must end
  in `.invalid`, and Mail must have exactly one account and one SMTP server using
  `127.0.0.1`. Capture is a plaintext test transport without authentication or relay.
  Its initial case checks one plain-text message without attachments or a signature;
  multipart messages are refused rather than partially validated.

  Journals live in `tmp/qualification/` within the workspace. Every effect has a
  synced intent before dispatch; run IDs cannot be reused. Failed or interrupted
  journals block further effects until independently reconciled. The host mutex
  serializes runners across workspaces. This is a qualification harness, not a
  sandbox for untrusted scripts or a rollback mechanism for cloud effects.
  Read-only `mix ex_macos_control.qualify --host-info` prints provisioning identity
  without launching or querying target apps. Run it inside the dedicated QA login.
  """
  alias ExMacOSControl.Automation
  alias ExMacOSControl.Qualification.{Manifest, Native, Runner}

  def run(path, profile, opts \\ []) do
    with :ok <- Automation.options(opts, [:execute, :run_id]),
         true <- is_boolean(Keyword.get(opts, :execute, false)),
         :ok <- enabled(opts),
         {:ok, manifest} <- Manifest.load(path),
         {:ok, manifest} <- Manifest.validate(manifest, profile) do
      if opts[:execute] do
        run_id = Keyword.get_lazy(opts, :run_id, &new_run_id/0)
        Runner.run(manifest, profile, Native, run_id)
      else
        Runner.check(manifest, profile, Native)
      end
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("execute must be a boolean")
    end
  end

  defp new_run_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  defp enabled(opts) do
    if opts[:execute] && System.get_env("EXMC_LIVE_TESTS") != "1",
      do: Automation.invalid("Live effects require EXMC_LIVE_TESTS=1 as well as execute: true"),
      else: :ok
  end
end
