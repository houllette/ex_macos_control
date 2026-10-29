defmodule ExMacOSControl.ScriptOutputTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.{Error, OSAScriptAdapter, ScriptOutput, TestHelpers}

  test "decodes empty output and preserves empty rows and fields" do
    assert {:ok, []} = ScriptOutput.decode("EXMC1\nEND", 1)
    assert {:ok, [[""]]} = ScriptOutput.decode("EXMC1\n\nEND", 1)
    assert {:ok, [["", ""], ["one", ""]]} = ScriptOutput.decode("EXMC1\n\t\none\t\nEND", 2)
  end

  test "preserves punctuation, Unicode, whitespace and escaped control characters" do
    rows = [
      ["  résumé,雪|END  ", "line one\nline two\r\t\\n\\t\\r\\", ""],
      ["EXMC1", "END", " last field \n"]
    ]

    assert {:ok, ^rows} = ScriptOutput.decode(TestHelpers.script_output(rows), 3)
  end

  test "rejects truncated, malformed and legacy output without exposing private data" do
    invalid = [
      "",
      "private,message|content",
      "EXMC1\n",
      "EXMC1\nprivate\n",
      "EXMC1\nprivate\nENDextra",
      "EXMC1\nprivate\tdata\nEND",
      "EXMC1\nprivate\\q\nEND",
      "EXMC1\nprivate\\\nEND",
      "EXMC1\nprivate\rdata\nEND",
      "EXMC1\n" <> <<255>> <> "\nEND"
    ]

    for output <- invalid do
      assert {:error, %Error{type: :execution_error} = error} = ScriptOutput.decode(output, 1)
      refute Exception.message(error) =~ "private"
      assert error.details == %{}
    end
  end

  @tag :integration
  test "native AppleScript encoder round-trips fields without application automation" do
    script =
      ~S"""
      set sampleField to "  résumé,雪|quote\"slash\\" & tab & "tab" & linefeed & "line" & return & "return  "
      tell current application
        return my exmc_encode_rows({{sampleField, ""}, {"EXMC1", "END"}})
      end tell
      """ <> ScriptOutput.handlers()

    expected = [["  résumé,雪|quote\"slash\\\ttab\nline\rreturn  ", ""], ["EXMC1", "END"]]
    assert {:ok, output} = OSAScriptAdapter.run_applescript(script)
    assert {:ok, ^expected} = ScriptOutput.decode(output, 2)
  end

  @tag :integration
  test "native AppleScript encoder handles empty collections and empty single fields" do
    for rows <- [[], [[""]], [["", ""]]] do
      literal = if rows == [], do: "{}", else: "{{#{Enum.map_join(hd(rows), ", ", fn _ -> ~s("") end)}}}"
      script = "return my exmc_encode_rows(#{literal})\n" <> ScriptOutput.handlers()
      assert {:ok, output} = OSAScriptAdapter.run_applescript(script)
      field_count = if rows == [], do: 1, else: length(hd(rows))
      assert {:ok, ^rows} = ScriptOutput.decode(output, field_count)
    end
  end
end
