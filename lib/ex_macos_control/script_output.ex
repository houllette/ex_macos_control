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
    on exmc_join(parts, separator)
      set previousDelimiters to AppleScript's text item delimiters
      try
        set AppleScript's text item delimiters to separator
        set joinedText to parts as text
        set AppleScript's text item delimiters to previousDelimiters
        return joinedText
      on error errMsg number errNum
        set AppleScript's text item delimiters to previousDelimiters
        error errMsg number errNum
      end try
    end exmc_join

    on exmc_encode_field(fieldValue)
      set fieldText to fieldValue as text
      set encodedParts to {}
      repeat with fieldCharacter in characters of fieldText
        set c to contents of fieldCharacter
        set characterID to id of c
        if characterID is 92 then
          set end of encodedParts to "\\\\"
        else if characterID is 9 then
          set end of encodedParts to "\\t"
        else if characterID is 10 then
          set end of encodedParts to "\\n"
        else if characterID is 13 then
          set end of encodedParts to "\\r"
        else
          set end of encodedParts to c
        end if
      end repeat
      return my exmc_join(encodedParts, "")
    end exmc_encode_field

    on exmc_encode_rows(outputRows)
      script rowBuffer
        property encodedRows : {}
      end script
      set rowBuffer's encodedRows to {"EXMC1"}
      repeat with outputRow in (get outputRows)
        set encodedFields to {}
        repeat with outputField in (get contents of outputRow)
          set encodedField to my exmc_encode_field(contents of outputField)
          set end of encodedFields to encodedField
        end repeat
        set end of rowBuffer's encodedRows to my exmc_join(encodedFields, tab)
      end repeat
      set end of rowBuffer's encodedRows to "END"
      return my exmc_join(rowBuffer's encodedRows, linefeed)
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
