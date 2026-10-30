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
  test "native encoder preserves width distinctions and Unicode character sequences" do
    fields = ["fullwidth＼name.txt", ~S(fullwidth\name.txt), "﹨", "e\u0301", "👩🏽‍💻", "🏳️‍🌈", "x\uFEFFy", "line\r\nbreak"]
    script = "on run argv\nreturn my exmc_encode_rows({argv})\nend run\n" <> ScriptOutput.handlers()

    assert {:ok, output} = OSAScriptAdapter.run_applescript(script, args: fields, timeout: 5000)
    assert {:ok, [^fields]} = ScriptOutput.decode(output, length(fields))
  end

  @tag :integration
  test "native encoder restores text item delimiters and preserves references" do
    script =
      ~S"""
      set AppleScript's text item delimiters to {"original", "delimiters"}
      set sampleField to "one" & tab & "two" & linefeed & "three" & return & "four\\"
      set sampleRows to {{sampleField, "", "＼"}}
      tell current application
        set encodedRows to my exmc_encode_rows(sampleRows)
      end tell
      if AppleScript's text item delimiters is not {"original", "delimiters"} then error "Delimiters changed"
      return encodedRows
      """ <> ScriptOutput.handlers()

    assert {:ok, output} = OSAScriptAdapter.run_applescript(script, timeout: 5000)
    assert {:ok, [["one\ttwo\nthree\rfour\\", "", "＼"]]} = ScriptOutput.decode(output, 3)
  end

  @tag :integration
  test "native encoder keeps repeated calls independent" do
    script =
      """
      set firstOutput to my exmc_encode_rows({{"first"}})
      set secondOutput to my exmc_encode_rows({{"second"}})
      set emptyOutput to my exmc_encode_rows({})
      return my exmc_encode_rows({{firstOutput, secondOutput, emptyOutput}})
      """ <> ScriptOutput.handlers()

    assert {:ok, output} = OSAScriptAdapter.run_applescript(script, timeout: 5000)

    assert {:ok, [["EXMC1\nfirst\nEND", "EXMC1\nsecond\nEND", "EXMC1\nEND"]]} = ScriptOutput.decode(output, 3)
  end

  @tag :integration
  test "native encoder round-trips large collections" do
    script =
      ~S"""
      set outputRows to {}
      repeat 1000 times
        set end of outputRows to {"synthetic,|雪＼", "one" & linefeed & "two", "  tail  "}
      end repeat
      return my exmc_encode_rows(outputRows)
      """ <> ScriptOutput.handlers()

    assert {:ok, output} = OSAScriptAdapter.run_applescript(script, timeout: 10_000)
    assert {:ok, rows} = ScriptOutput.decode(output, 3)
    assert rows == List.duplicate(["synthetic,|雪＼", "one\ntwo", "  tail  "], 1000)
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
