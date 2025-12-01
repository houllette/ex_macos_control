defmodule ExMacOSControl.Integration.ScriptFileIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{Error, OSAScriptAdapter, TestHelpers}

  @moduletag :integration

  setup do
    TestHelpers.skip_unless_integration()
    :ok
  end

  # Helper to call the real adapter directly, bypassing the facade's mock configuration
  defp run_script_file(file_path, opts \\ []) do
    OSAScriptAdapter.run_script_file(file_path, opts)
  end

  describe "run_script_file/1 - AppleScript files" do
    test "executes AppleScript file successfully" do
      path = TestHelpers.fixture_path("applescript/hello_world.applescript")

      assert {:ok, result} = run_script_file(path)
      assert result == "Hello, World!"
    end

    test "handles file not found error" do
      path = "/tmp/nonexistent_#{:rand.uniform(999_999)}.applescript"

      assert {:error, %Error{type: :not_found}} = run_script_file(path)
    end

    test "handles directory instead of file" do
      dir_path = System.tmp_dir!()

      assert {:error, %Error{type: :not_found}} = run_script_file(dir_path)
    end
  end

  describe "run_script_file/1 - JavaScript files" do
    test "executes JavaScript file successfully" do
      path = TestHelpers.fixture_path("javascript/hello_world.js")

      assert {:ok, result} = run_script_file(path)
      assert result == "Hello from JXA!"
    end

    test "auto-detects .jxa extension" do
      TestHelpers.with_temp_script("(function() { return 'JXA test'; })()", ".jxa", fn path ->
        assert {:ok, "JXA test"} = run_script_file(path)
      end)
    end
  end

  describe "run_script_file/2 - with arguments" do
    test "passes arguments to AppleScript file" do
      path = TestHelpers.fixture_path("applescript/with_arguments.applescript")

      assert {:ok, "test_value"} = run_script_file(path, args: ["test_value"])
    end

    test "passes multiple arguments to AppleScript file" do
      script = """
      on run argv
        set arg1 to item 1 of argv
        set arg2 to item 2 of argv
        return arg1 & " " & arg2
      end run
      """

      TestHelpers.with_temp_script(script, ".applescript", fn path ->
        assert {:ok, "hello world"} = run_script_file(path, args: ["hello", "world"])
      end)
    end

    test "passes arguments to JavaScript file" do
      path = TestHelpers.fixture_path("javascript/with_arguments.js")

      assert {:ok, "js_arg"} = run_script_file(path, args: ["js_arg"])
    end
  end

  describe "run_script_file/2 - with timeout" do
    test "executes within timeout" do
      path = TestHelpers.fixture_path("applescript/hello_world.applescript")

      assert {:ok, "Hello, World!"} = run_script_file(path, timeout: 5000)
    end

    test "times out when script takes too long" do
      path = TestHelpers.fixture_path("applescript/delay_script.applescript")

      assert {:error, %Error{type: :timeout}} =
               run_script_file(path, timeout: 100)
    end
  end

  describe "run_script_file/2 - language override" do
    test "allows explicit AppleScript for .txt file" do
      script = "return \"from txt\""

      TestHelpers.with_temp_script(script, ".txt", fn path ->
        assert {:ok, "from txt"} = run_script_file(path, language: :applescript)
      end)
    end

    test "allows explicit JavaScript for .txt file" do
      script = "(function() { return 'js from txt'; })()"

      TestHelpers.with_temp_script(script, ".txt", fn path ->
        assert {:ok, "js from txt"} = run_script_file(path, language: :javascript)
      end)
    end

    test "language override works even when extension suggests different language" do
      # JavaScript code in .applescript file
      js_code = "(function() { return 'override works'; })()"

      TestHelpers.with_temp_script(js_code, ".applescript", fn path ->
        assert {:ok, "override works"} =
                 run_script_file(path, language: :javascript)
      end)
    end

    test "returns error for unknown extension without language option" do
      TestHelpers.with_temp_script("return \"test\"", ".unknown", fn path ->
        assert {:error, %Error{type: :execution_error}} = run_script_file(path)
      end)
    end
  end

  describe "run_script_file/2 - case insensitivity" do
    test "handles uppercase .APPLESCRIPT extension" do
      TestHelpers.with_temp_script("return \"uppercase\"", ".APPLESCRIPT", fn path ->
        assert {:ok, "uppercase"} = run_script_file(path)
      end)
    end

    test "handles mixed case .AppleScript extension" do
      TestHelpers.with_temp_script("return \"mixed\"", ".AppleScript", fn path ->
        assert {:ok, "mixed"} = run_script_file(path)
      end)
    end

    test "handles uppercase .JS extension" do
      TestHelpers.with_temp_script("(function() { return 'uppercase js'; })()", ".JS", fn path ->
        assert {:ok, "uppercase js"} = run_script_file(path)
      end)
    end
  end

  describe "run_script_file/2 - combined options" do
    test "works with all options: language, args, and timeout" do
      script = """
      on run argv
        return item 1 of argv
      end run
      """

      TestHelpers.with_temp_script(script, ".txt", fn path ->
        assert {:ok, "combined"} =
                 run_script_file(path,
                   language: :applescript,
                   args: ["combined"],
                   timeout: 5000
                 )
      end)
    end
  end

  describe "run_script_file/2 - error handling" do
    test "returns syntax error for invalid AppleScript" do
      path = TestHelpers.fixture_path("applescript/syntax_error.applescript")

      assert {:error, %Error{} = error} = run_script_file(path)
      assert error.type in [:syntax_error, :execution_error]
    end

    test "returns syntax error for invalid JavaScript" do
      path = TestHelpers.fixture_path("javascript/syntax_error.js")

      assert {:error, %Error{} = error} = run_script_file(path)
      assert error.type in [:syntax_error, :execution_error]
    end
  end
end
