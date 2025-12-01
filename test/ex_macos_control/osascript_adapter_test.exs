defmodule ExMacOSControl.OSAScriptAdapterTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.OSAScriptAdapter

  describe "run_applescript/1" do
    test "executes basic AppleScript" do
      script = ~s(return "Hello, World!")
      assert {:ok, output} = OSAScriptAdapter.run_applescript(script)
      assert String.trim(output) == "Hello, World!"
    end

    test "returns error tuple on failure" do
      script = "invalid applescript syntax"
      assert {:error, %ExMacOSControl.Error{} = error} = OSAScriptAdapter.run_applescript(script)
      assert error.details.exit_code != 0
    end
  end

  describe "run_javascript/1" do
    test "executes basic JXA script" do
      script = "(function() { return \"Hello from JXA!\"; })()"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script)
      assert String.trim(output) == "Hello from JXA!"
    end

    test "executes JXA with Application automation" do
      # This will check if Finder is running (should always be true on macOS)
      script = "Application('Finder').running()"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script)
      assert String.trim(output) == "true"
    end

    test "returns trimmed output" do
      script = "(function() { return \"test\"; })()"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script)
      assert output == "test"
    end

    test "returns error tuple on syntax error" do
      script = "invalid javascript syntax {"
      assert {:error, %ExMacOSControl.Error{} = error} = OSAScriptAdapter.run_javascript(script)
      assert error.details.exit_code != 0
    end

    test "returns error tuple on execution error" do
      script = "(function() { throw new Error(\"test error\"); })()"
      assert {:error, %ExMacOSControl.Error{} = error} = OSAScriptAdapter.run_javascript(script)
      assert error.details.exit_code != 0
    end

    test "handles JavaScript undefined return" do
      script = "(function() { })()"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script)
      # undefined in JXA returns empty or "undefined"
      assert output == "" or output == "undefined"
    end

    test "executes complex JXA with System Events" do
      script = """
        var app = Application('System Events');
        var processes = app.processes.whose({ name: 'Finder' });
        processes.length > 0 ? "yes" : "no";
      """

      assert {:ok, output} = OSAScriptAdapter.run_javascript(script)
      assert String.trim(output) == "yes"
    end
  end

  describe "run_javascript/2 with options" do
    test "executes JXA with arguments option" do
      # JXA uses function run(argv) to receive arguments
      script = "function run(argv) { return argv[0]; }"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script, args: ["hello"])
      assert output == "hello"
    end

    test "executes JXA with multiple arguments" do
      script = "function run(argv) { return argv.join(' '); }"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script, args: ["hello", "world"])
      assert output == "hello world"
    end

    test "handles empty args option" do
      script = "function run(argv) { return argv.length.toString(); }"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script, args: [])
      assert output == "0"
    end

    test "executes JXA with special characters in arguments" do
      script = "function run(argv) { return argv[0]; }"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script, args: ["hello world!"])
      assert output == "hello world!"
    end

    test "accepts empty options" do
      script = "(function() { return \"test\"; })()"
      assert {:ok, output} = OSAScriptAdapter.run_javascript(script, [])
      assert output == "test"
    end
  end

  describe "run_shortcut/1" do
    test "delegates to run_applescript/1" do
      # This will fail if the shortcut doesn't exist, but that's expected
      assert {:error, _} = OSAScriptAdapter.run_shortcut("NonexistentShortcut")
    end
  end
end
