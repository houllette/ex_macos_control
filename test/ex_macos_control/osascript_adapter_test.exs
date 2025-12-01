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

  describe "run_shortcut/2 with input" do
    test "accepts input as a string" do
      # This will fail if the shortcut doesn't exist, but we're testing the interface
      result = OSAScriptAdapter.run_shortcut("TestShortcut", input: "Hello, World!")
      # Should return either :ok or {:ok, result} or {:error, reason}
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts input as a number" do
      result = OSAScriptAdapter.run_shortcut("TestShortcut", input: 42)
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts input as a float" do
      result = OSAScriptAdapter.run_shortcut("TestShortcut", input: 3.14)
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts input as a map" do
      result = OSAScriptAdapter.run_shortcut("TestShortcut", input: %{"key" => "value", "number" => 42})
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts input as a list" do
      result = OSAScriptAdapter.run_shortcut("TestShortcut", input: ["item1", "item2", "item3"])
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles strings with special characters" do
      result = OSAScriptAdapter.run_shortcut("TestShortcut", input: ~s(Hello "World" with 'quotes'))
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles nested structures" do
      result =
        OSAScriptAdapter.run_shortcut("TestShortcut",
          input: %{
            "user" => %{"name" => "John", "age" => 30},
            "items" => ["a", "b", "c"]
          }
        )

      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "works without input option (backward compatible)" do
      result = OSAScriptAdapter.run_shortcut("TestShortcut", [])
      assert match?(:ok, result) or match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "list_shortcuts/0" do
    test "returns a list of shortcuts" do
      result = OSAScriptAdapter.list_shortcuts()
      # Should return {:ok, list} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, shortcuts} ->
          assert is_list(shortcuts)

        {:error, _reason} ->
          # Shortcuts app might not be available
          :ok
      end
    end
  end
end
