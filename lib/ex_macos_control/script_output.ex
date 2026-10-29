defmodule ExMacOSControl.ScriptOutput do
  @moduledoc false

  alias ExMacOSControl.Error

  @header "EXMC1\n"
  @footer "END"

  # A framed, escaped TSV format keeps commas, pipes, newlines, Unicode and
  # leading/trailing whitespace intact, even when osascript output is trimmed.
  # Call with `my exmc_encode_rows(rows)` inside application tell blocks.
  @spec handlers() :: String.t()
  def handlers do
    ~S"""
    on exmc_encode_field(fieldValue)
      set fieldText to fieldValue as text
      set encodedText to ""
      repeat with fieldCharacter in characters of fieldText
        set c to contents of fieldCharacter
        if c is "\\" then
          set encodedText to encodedText & "\\\\"
        else if c is tab then
          set encodedText to encodedText & "\\t"
        else if c is linefeed then
          set encodedText to encodedText & "\\n"
        else if c is return then
          set encodedText to encodedText & "\\r"
        else
          set encodedText to encodedText & c
        end if
      end repeat
      return encodedText
    end exmc_encode_field

    on exmc_encode_rows(outputRows)
      set encodedOutput to "EXMC1" & linefeed
      repeat with outputRow in outputRows
        set firstField to true
        repeat with outputField in outputRow
          if not firstField then set encodedOutput to encodedOutput & tab
          set encodedField to my exmc_encode_field(contents of outputField)
          set encodedOutput to encodedOutput & encodedField
          set firstField to false
        end repeat
        set encodedOutput to encodedOutput & linefeed
      end repeat
      return encodedOutput & "END"
    end exmc_encode_rows
    """
  end

  @spec decode(String.t(), pos_integer()) :: {:ok, [[String.t()]]} | {:error, Error.t()}
  def decode(output, field_count) when is_binary(output) and is_integer(field_count) and field_count > 0 do
    case output do
      @header <> body -> decode_body(body, field_count)
      _ -> invalid_output()
    end
  end

  defp decode_body(@footer, _field_count), do: {:ok, []}

  defp decode_body(body, field_count) do
    with true <- String.valid?(body) and not String.contains?(body, "\r"),
         true <- String.ends_with?(body, "\n" <> @footer),
         rows <- body |> String.replace_suffix("\n" <> @footer, "") |> String.split("\n"),
         {:ok, decoded} <- decode_rows(rows, field_count) do
      {:ok, decoded}
    else
      _ -> invalid_output()
    end
  end

  defp decode_rows(rows, field_count) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      fields = String.split(row, "\t")

      with true <- length(fields) == field_count,
           {:ok, decoded} <- decode_fields(fields) do
        {:cont, {:ok, [decoded | acc]}}
      else
        _ -> {:halt, invalid_output()}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_fields(fields) do
    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, acc} ->
      case decode_field(field, []) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_field("", acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  defp decode_field("\\\\" <> rest, acc), do: decode_field(rest, ["\\" | acc])
  defp decode_field("\\t" <> rest, acc), do: decode_field(rest, ["\t" | acc])
  defp decode_field("\\n" <> rest, acc), do: decode_field(rest, ["\n" | acc])
  defp decode_field("\\r" <> rest, acc), do: decode_field(rest, ["\r" | acc])
  defp decode_field("\\" <> _rest, _acc), do: invalid_output()
  defp decode_field(<<byte, rest::binary>>, acc), do: decode_field(rest, [<<byte>> | acc])

  defp invalid_output do
    # Do not include raw output: it may contain private messages or email content.
    {:error, Error.execution_error("Invalid structured AppleScript output")}
  end
end
