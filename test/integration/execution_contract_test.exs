defmodule ExMacOSControl.ExecutionContractTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias ExMacOSControl.{OSAScriptAdapter, ScriptOutput}

  test "dash arguments cannot become AppleScript or JXA source" do
    args = ["-e", "return 99", "--flag", "雪"]
    assert {:ok, "4"} = OSAScriptAdapter.run_applescript("on run argv\nreturn count argv\nend run", args: args)

    assert {:ok, ^args} =
             OSAScriptAdapter.run_javascript("function run(argv) { return JSON.stringify(argv); }",
               args: args,
               output: :json
             )
  end

  test "diagnostics do not corrupt structured output and raw whitespace can be preserved" do
    script =
      ~s|log "diagnostic"\nreturn my exmc_encode_rows({{1, 2, 800, 600, "  title,雪  "}})\n| <> ScriptOutput.handlers()

    assert {:ok, output} = OSAScriptAdapter.run_applescript(script)
    assert {:ok, [["1", "2", "800", "600", "  title,雪  "]]} = ScriptOutput.decode(output, 5)
    assert {:ok, "  x  \n"} = OSAScriptAdapter.run_applescript(~s(return "  x  "), trim: false)

    assert {:ok, %{stdout: "value\n", stderr: "diagnostic\n", exit_status: 0}} =
             OSAScriptAdapter.run_applescript(~s|log "diagnostic"\nreturn "value"|, output: :execution)
  end

  test "compiled script bundles execute" do
    path = Path.expand("tmp/bundle-#{System.unique_integer([:positive])}.scptd")
    on_exit(fn -> File.rm_rf(path) end)
    assert {_, 0} = System.cmd("osacompile", ["-o", path, "-e", ~s(return "bundle")])
    assert {:ok, "bundle"} = OSAScriptAdapter.run_script_file(path, [])
  end

  test "source output preserves nested structure" do
    assert {:ok, "{{1, 2}, {3, 4}}"} = OSAScriptAdapter.run_applescript("return {{1, 2}, {3, 4}}", output: :source)
  end
end
