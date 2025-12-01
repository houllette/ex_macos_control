defmodule ExMacOSControl.OSAScriptAdapterScriptFileTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.Error
  alias ExMacOSControl.OSAScriptAdapter
  alias ExMacOSControl.TestHelpers

  describe "run_script_file/2 - file validation" do
    test "returns error when file does not exist" do
      nonexistent_file = "/tmp/nonexistent_script_#{:rand.uniform(999_999)}.applescript"

      assert {:error, %Error{type: :not_found}} =
               OSAScriptAdapter.run_script_file(nonexistent_file, [])
    end

    test "returns error when path is not a regular file (directory)" do
      # Use System.tmp_dir! which should exist
      dir_path = System.tmp_dir!()

      assert {:error, %Error{type: :not_found}} =
               OSAScriptAdapter.run_script_file(dir_path, [])
    end
  end

  describe "run_script_file/2 - language detection" do
    test "detects AppleScript from .applescript extension" do
      TestHelpers.with_temp_script("return \"test\"", ".applescript", fn path ->
        # This will fail until we implement the function, but that's expected in TDD
        assert {:ok, "test"} = OSAScriptAdapter.run_script_file(path, [])
      end)
    end

    test "detects AppleScript from .scpt extension" do
      TestHelpers.with_temp_script("return \"test\"", ".scpt", fn path ->
        assert {:ok, "test"} = OSAScriptAdapter.run_script_file(path, [])
      end)
    end

    test "detects JavaScript from .js extension" do
      TestHelpers.with_temp_script("(function() { return 'test'; })()", ".js", fn path ->
        assert {:ok, "test"} = OSAScriptAdapter.run_script_file(path, [])
      end)
    end

    test "detects JavaScript from .jxa extension" do
      TestHelpers.with_temp_script("(function() { return 'test'; })()", ".jxa", fn path ->
        assert {:ok, "test"} = OSAScriptAdapter.run_script_file(path, [])
      end)
    end

    test "is case insensitive for extensions" do
      TestHelpers.with_temp_script("return \"test\"", ".APPLESCRIPT", fn path ->
        assert {:ok, "test"} = OSAScriptAdapter.run_script_file(path, [])
      end)
    end

    test "returns error for unknown extension without language option" do
      TestHelpers.with_temp_script("return \"test\"", ".txt", fn path ->
        assert {:error, %Error{type: :execution_error}} =
                 OSAScriptAdapter.run_script_file(path, [])
      end)
    end
  end

  describe "run_script_file/2 - explicit language override" do
    test "allows explicit :applescript language for .txt file" do
      TestHelpers.with_temp_script("return \"from txt\"", ".txt", fn path ->
        assert {:ok, "from txt"} = OSAScriptAdapter.run_script_file(path, language: :applescript)
      end)
    end

    test "allows explicit :javascript language for .txt file" do
      TestHelpers.with_temp_script("(function() { return 'from txt'; })()", ".txt", fn path ->
        assert {:ok, "from txt"} = OSAScriptAdapter.run_script_file(path, language: :javascript)
      end)
    end

    test "explicit language overrides extension-based detection" do
      # JS code in .applescript file - should work with language override
      TestHelpers.with_temp_script("(function() { return 'js code'; })()", ".applescript", fn path ->
        assert {:ok, "js code"} = OSAScriptAdapter.run_script_file(path, language: :javascript)
      end)
    end

    test "returns error for invalid language option" do
      TestHelpers.with_temp_script("return \"test\"", ".applescript", fn path ->
        assert {:error, %Error{type: :execution_error}} =
                 OSAScriptAdapter.run_script_file(path, language: :invalid)
      end)
    end
  end

  describe "run_script_file/2 - AppleScript file execution" do
    test "executes AppleScript file successfully" do
      path = TestHelpers.fixture_path("applescript/hello_world.applescript")
      assert {:ok, "Hello, World!"} = OSAScriptAdapter.run_script_file(path, [])
    end

    test "executes AppleScript file with arguments" do
      path = TestHelpers.fixture_path("applescript/with_arguments.applescript")
      assert {:ok, "test_arg"} = OSAScriptAdapter.run_script_file(path, args: ["test_arg"])
    end

    test "executes AppleScript file with timeout" do
      TestHelpers.with_temp_script("delay 0.1\nreturn \"done\"", ".applescript", fn path ->
        assert {:ok, "done"} = OSAScriptAdapter.run_script_file(path, timeout: 5000)
      end)
    end

    test "times out AppleScript file execution" do
      path = TestHelpers.fixture_path("applescript/delay_script.applescript")

      assert {:error, %Error{type: :timeout}} =
               OSAScriptAdapter.run_script_file(path, timeout: 100)
    end

    test "returns error for AppleScript syntax errors" do
      path = TestHelpers.fixture_path("applescript/syntax_error.applescript")

      # When osascript runs files, syntax errors come through as execution_error
      assert {:error, %Error{} = error} = OSAScriptAdapter.run_script_file(path, [])
      assert error.type in [:syntax_error, :execution_error]
    end
  end

  describe "run_script_file/2 - JavaScript file execution" do
    test "executes JavaScript file successfully" do
      path = TestHelpers.fixture_path("javascript/hello_world.js")
      assert {:ok, "Hello from JXA!"} = OSAScriptAdapter.run_script_file(path, [])
    end

    test "executes JavaScript file with arguments" do
      path = TestHelpers.fixture_path("javascript/with_arguments.js")
      assert {:ok, "test_arg"} = OSAScriptAdapter.run_script_file(path, args: ["test_arg"])
    end

    test "executes JavaScript file with timeout" do
      TestHelpers.with_temp_script(
        "function run() { var d = new Date(); while((new Date()) - d < 100); return 'done'; }",
        ".js",
        fn path ->
          assert {:ok, "done"} = OSAScriptAdapter.run_script_file(path, timeout: 5000)
        end
      )
    end

    test "returns error for JavaScript syntax errors" do
      path = TestHelpers.fixture_path("javascript/syntax_error.js")

      # When osascript runs files, syntax errors come through as execution_error
      assert {:error, %Error{} = error} = OSAScriptAdapter.run_script_file(path, [])
      assert error.type in [:syntax_error, :execution_error]
    end
  end

  describe "run_script_file/2 - combined options" do
    test "works with both args and timeout" do
      path = TestHelpers.fixture_path("applescript/with_arguments.applescript")

      assert {:ok, "combined"} =
               OSAScriptAdapter.run_script_file(path, args: ["combined"], timeout: 5000)
    end

    test "works with all options: language, args, and timeout" do
      TestHelpers.with_temp_script("return \"test\"", ".txt", fn path ->
        assert {:ok, "test"} =
                 OSAScriptAdapter.run_script_file(path,
                   language: :applescript,
                   args: [],
                   timeout: 5000
                 )
      end)
    end
  end
end
