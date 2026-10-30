defmodule ExMacOSControl.Shortcuts do
  @moduledoc """
  Shortcuts discovery, identifiers, folders and typed file input/output.

  `run/2` uses the native CLI and accepts names or identifiers. Map/list input is
  JSON text, not a native shortcut dictionary. `workflow/4` uses a versioned JSON
  envelope with a user-installed workflow. `sign/3` is an explicit distribution
  operation: Apple receives the shortcut for validation during signing.
  """
  alias ExMacOSControl.{Automation, Command, Error, Resources}
  @app "com.apple.shortcuts.events"

  def list(opts \\ []) do
    with :ok <- Automation.options(opts, [:folder_id, :limit, :offset, :timeout, :max_output_bytes]) do
      collection = if opts[:folder_id], do: "byId(app.folders,input.folder_id).shortcuts", else: "app.shortcuts"

      Resources.list(
        @app,
        collection,
        [
          id: "o.id()",
          name: "o.name()",
          subtitle: "o.subtitle()",
          accepts_input: "o.acceptsInput()",
          action_count: "o.actionCount()"
        ],
        %{folder_id: opts[:folder_id]},
        Keyword.delete(opts, :folder_id)
      )
    end
  end

  def list_folders(opts \\ []), do: Resources.list(@app, "app.folders", [id: "o.id()", name: "o.name()"], %{}, opts)

  def run(identifier, opts \\ []) do
    with :ok <- Automation.required_string(identifier, "Shortcut identity"),
         :ok <-
           Automation.options(opts, [
             :input,
             :input_paths,
             :output_path,
             :output_type,
             :output,
             :trim,
             :timeout,
             :max_output_bytes
           ]),
         :ok <- validate_run(opts),
         {:ok, input} <- serialize_input(opts[:input]) do
      args = ["run"] ++ cli_options(opts) ++ ["--", identifier]

      command_opts =
        opts |> Automation.execution_options() |> Keyword.put_new(:timeout, 30_000) |> Keyword.put(:input, input)

      case Command.run("shortcuts", args, command_opts) do
        {:ok, %{exit_status: 0} = execution} ->
          output(execution, opts)

        {:ok, execution} ->
          {:error,
           Error.execution_error("Shortcut failed", exit_status: execution.exit_status, stderr: execution.stderr)}

        error ->
          error
      end
    end
  end

  def view(identifier, opts \\ []) do
    with :ok <- Automation.required_string(identifier, "Shortcut identity"),
         :ok <- Automation.options(opts, [:timeout, :max_output_bytes]) do
      cli_action(["view", "--", identifier], opts)
    end
  end

  def sign(input, output, opts \\ []) do
    with :ok <- Automation.options(opts, [:mode, :timeout, :max_output_bytes]),
         true <- is_binary(input) and File.regular?(input),
         :ok <- Automation.required_string(output, "Signed output path"),
         false <- File.exists?(output),
         mode = Keyword.get(opts, :mode, :anyone),
         true <- mode in [:anyone, :people_who_know_me] do
      mode = if mode == :anyone, do: "anyone", else: "people-who-know-me"
      cli_action(["sign", "--mode", mode, "--input", Path.expand(input), "--output", Path.expand(output)], opts)
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Signing needs an existing shortcut, a new output path and a supported mode")
    end
  end

  def workflow(identifier, operation, payload, opts \\ []) do
    with :ok <- Automation.required_string(operation, "Workflow operation"),
         :ok <- Automation.options(opts, [:timeout, :max_output_bytes]),
         {:ok, %{"exmc" => 1, "result" => result}} <-
           run(
             identifier,
             Keyword.merge(opts, input: %{exmc: 1, operation: operation, input: payload}, output: :json)
           ) do
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Workflow must return a version 1 JSON envelope with a result")
    end
  end

  defp validate_run(opts) do
    paths = Keyword.get(opts, :input_paths, [])

    cond do
      not valid_paths?(paths) ->
        Automation.invalid("input_paths must name existing files")

      paths != [] and Keyword.has_key?(opts, :input) ->
        Automation.invalid("Choose input or input_paths")

      output_mode(opts) not in [:text, :json, :execution, :binary] ->
        Automation.invalid("Invalid shortcut output mode")

      not is_boolean(Keyword.get(opts, :trim, true)) ->
        Automation.invalid("trim must be a boolean")

      not optional_string?(opts[:output_path]) ->
        Automation.invalid("output_path must be a path")

      not optional_string?(opts[:output_type]) ->
        Automation.invalid("output_type must be a UTI string")

      true ->
        :ok
    end
  end

  defp valid_paths?(paths), do: is_list(paths) and Enum.all?(paths, &(is_binary(&1) and File.exists?(&1)))
  defp optional_string?(nil), do: true
  defp optional_string?(value), do: is_binary(value) and String.trim(value) != "" and not String.contains?(value, <<0>>)

  defp output_mode(opts),
    do: Keyword.get(opts, :output, if(opts[:output_type] && is_nil(opts[:output_path]), do: :binary, else: :text))

  defp cli_options(opts) do
    input =
      if opts[:input_paths] in [nil, []], do: [], else: ["--input-path" | Enum.map(opts[:input_paths], &Path.expand/1)]

    output = if opts[:output_path], do: ["--output-path", Path.expand(opts[:output_path])], else: []
    type = if opts[:output_type], do: ["--output-type", opts[:output_type]], else: []
    input ++ output ++ type
  end

  defp serialize_input(nil), do: {:ok, ""}
  defp serialize_input(input) when is_binary(input), do: {:ok, input}
  defp serialize_input(input) when is_number(input), do: {:ok, to_string(input)}

  defp serialize_input(input) when is_map(input) or is_list(input) do
    case Jason.encode(input) do
      {:ok, json} -> {:ok, json}
      _ -> Automation.invalid("Shortcut input is not JSON serializable")
    end
  end

  defp serialize_input(_), do: Automation.invalid("Unsupported shortcut input type")

  defp output(execution, opts) do
    case output_mode(opts) do
      :binary -> {:ok, execution.stdout}
      :execution -> {:ok, execution}
      mode -> text_output(execution.stdout, mode, opts)
    end
  end

  defp text_output(stdout, mode, opts) do
    text = if Keyword.get(opts, :trim, true), do: String.trim(stdout), else: stdout

    case mode do
      :json ->
        case Jason.decode(text) do
          {:ok, result} -> {:ok, result}
          _ -> Automation.invalid("Shortcut did not return valid JSON")
        end

      :text ->
        if text == "", do: :ok, else: {:ok, text}
    end
  end

  defp cli_action(args, opts) do
    case Command.run("shortcuts", args, Keyword.put_new(Automation.execution_options(opts), :timeout, 30_000)) do
      {:ok, %{exit_status: 0}} ->
        :ok

      {:ok, result} ->
        {:error,
         Error.execution_error("Shortcuts command failed", exit_status: result.exit_status, stderr: result.stderr)}

      error ->
        error
    end
  end
end
