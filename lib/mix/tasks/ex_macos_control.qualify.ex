defmodule Mix.Tasks.ExMacosControl.Qualify do
  use Mix.Task
  alias ExMacOSControl.Qualification.Host
  @shortdoc "Checks or runs a guarded qualification profile in a disposable macOS session"
  @moduledoc """
  Prints provisioning identity without accessing target apps:

      mix ex_macos_control.qualify --host-info

  Checks readiness without effects:

      mix ex_macos_control.qualify --manifest tmp/qualification.json --profile notes-crud

  Executes a fixed case only with both opt-ins:

      EXMC_LIVE_TESTS=1 mix ex_macos_control.qualify --manifest tmp/qualification.json --profile notes-crud --execute

  `--run-id` accepts a fresh 32-character lowercase hexadecimal identifier. Private
  manifests and journals belong under `tmp/`. No external-send or recording profile
  is enabled. Missing fixtures/permissions fail the run; they never become a pass.
  """

  @impl true
  def run(["--host-info"]) do
    Mix.Task.run("app.start")

    case Host.snapshot() do
      {:ok, snapshot} -> Mix.shell().info(Jason.encode!(snapshot))
      {:error, error} -> Mix.raise(error.message)
    end
  end

  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [manifest: :string, profile: :string, execute: :boolean, run_id: :string])

    unless rest == [] and invalid == [] and unique_options?(opts) and is_binary(opts[:manifest]) and
             is_binary(opts[:profile]),
           do: Mix.raise("Specify --manifest and --profile; unknown arguments are refused")

    Mix.Task.run("app.start")

    case ExMacOSControl.Qualification.run(opts[:manifest], opts[:profile], Keyword.take(opts, [:execute, :run_id])) do
      {:ok, result} -> Mix.shell().info(Jason.encode!(result))
      {:error, error} -> Mix.raise(error.message)
    end
  end

  defp unique_options?(opts), do: length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0)))
end
