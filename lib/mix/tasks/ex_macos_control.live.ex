defmodule Mix.Tasks.ExMacosControl.Live do
  use Mix.Task
  @shortdoc "Runs live test arguments in Aqua and closes its owned Terminal window"
  @moduledoc "Pass mix test arguments after --. EXMC_LIVE_TESTS/EXMC_PERSONAL_TESTS and entity permissions remain explicit. --keep-window retains only this runner's window."
  @impl true
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse_head(args, strict: [keep_window: :boolean, timeout: :integer])
    if invalid != [], do: Mix.raise("Unknown GUI runner options")
    Mix.Task.run("app.start")
    mix = System.find_executable("mix")

    case ExMacOSControl.GUI.run(mix, ["test" | rest], opts) do
      {:ok, result} ->
        Mix.shell().info(result.stdout)
        if result.stderr != "", do: Mix.shell().error(result.stderr)
        if result.exit_status != 0, do: Mix.raise("Live tests failed; evidence: #{result.evidence}")

      {:error, error} ->
        Mix.raise("#{error.message}; #{inspect(error.details)}")
    end
  end
end
