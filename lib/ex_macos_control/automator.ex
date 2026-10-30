defmodule ExMacOSControl.Automator do
  @moduledoc "Runs an existing Automator workflow with text input and named variables through the native CLI."
  alias ExMacOSControl.{Automation, Command, Error}

  def run(path, opts \\ []) do
    with :ok <- Automation.options(opts, [:input, :variables, :timeout, :max_output_bytes]),
         true <- workflow?(path),
         variables = Keyword.get(opts, :variables, %{}),
         true <- valid_variables?(variables) do
      args = Enum.flat_map(variables, fn {key, value} -> ["-D", key <> "=" <> value] end)
      args = args ++ if(Keyword.has_key?(opts, :input), do: ["-i", "-"], else: []) ++ [Path.expand(path)]

      case Command.run(
             "automator",
             args,
             opts
             |> Automation.execution_options()
             |> Keyword.put_new(:timeout, 30_000)
             |> Keyword.merge(Keyword.take(opts, [:input]))
           ) do
        {:ok, %{exit_status: 0, stdout: output}} ->
          {:ok, output}

        {:ok, result} ->
          {:error,
           Error.execution_error("Automator workflow failed", exit_status: result.exit_status, stderr: result.stderr)}

        error ->
          error
      end
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Workflow must exist and variables must be a string map")
    end
  end

  defp workflow?(path),
    do: is_binary(path) and (File.regular?(path) or File.regular?(Path.join(path, "Contents/document.wflow")))

  defp valid_variables?(variables),
    do:
      is_map(variables) and
        Enum.all?(variables, fn {key, value} ->
          is_binary(key) and not String.contains?(key, "=") and is_binary(value)
        end)
end
