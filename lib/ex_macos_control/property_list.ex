defmodule ExMacOSControl.PropertyList do
  @moduledoc "Reads JSON-compatible property lists and writes XML or binary plists through the native validator."
  alias ExMacOSControl.{Automation, Command, Error}

  def read(path, opts \\ []) do
    with :ok <- Automation.options(opts, [:timeout, :max_output_bytes]),
         true <- is_binary(path) and File.regular?(path),
         {:ok, %{exit_status: 0, stdout: json}} <-
           Command.run(
             "plutil",
             ["-convert", "json", "-o", "-", "--", Path.expand(path)],
             Keyword.put_new(Automation.execution_options(opts), :timeout, 30_000)
           ),
         {:ok, value} <- Jason.decode(json) do
      {:ok, value}
    else
      {:error, %Error{}} = error -> error
      _ -> Automation.invalid("Unable to read a JSON-compatible property list")
    end
  end

  def write(path, value, opts \\ []) do
    with :ok <- Automation.options(opts, [:format, :timeout, :max_output_bytes]),
         :ok <- Automation.required_string(path, "Property list path"),
         format = Keyword.get(opts, :format, :xml),
         true <- format in [:xml, :binary],
         {:ok, json} <- Jason.encode(value),
         {:ok, %{exit_status: 0, stdout: data}} <-
           Command.run(
             "plutil",
             ["-convert", if(format == :xml, do: "xml1", else: "binary1"), "-o", "-", "--", "-"],
             Keyword.put(Keyword.put_new(Automation.execution_options(opts), :timeout, 30_000), :input, json)
           ) do
      atomic_write(Path.expand(path), data)
    else
      {:error, %Error{}} = error -> error
      _ -> Automation.invalid("Unable to encode property list")
    end
  end

  defp atomic_write(path, data) do
    scratch = path <> ".exmc-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    try do
      mode =
        case File.stat(path) do
          {:ok, stat} -> Bitwise.band(stat.mode, 0o777)
          _ -> 0o600
        end

      with {:ok, io} <- File.open(scratch, [:write, :exclusive, :binary]) do
        result =
          try do
            with :ok <- File.chmod(scratch, mode), do: IO.binwrite(io, data)
          after
            File.close(io)
          end

        with :ok <- result, do: File.rename(scratch, path)
      end
      |> case do
        :ok -> :ok
        {:error, reason} -> {:error, Error.execution_error("Unable to write property list", reason: reason)}
      end
    after
      File.rm(scratch)
    end
  end
end
