defmodule ExMacOSControl.TestHelpersTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.TestHelpers

  describe "fixtures_path/0" do
    test "returns absolute path to fixtures directory" do
      path = TestHelpers.fixtures_path()
      assert String.contains?(path, "test/support/fixtures")
      assert File.dir?(path)
    end
  end

  describe "fixture_path/1" do
    test "returns absolute path to specific fixture" do
      path = TestHelpers.fixture_path("applescript/hello_world.applescript")
      assert String.ends_with?(path, "test/support/fixtures/applescript/hello_world.applescript")
    end

    test "creates valid paths for nested fixtures" do
      path = TestHelpers.fixture_path("errors/syntax_error.txt")
      assert String.contains?(path, "fixtures/errors/syntax_error.txt")
    end
  end

  describe "read_fixture/1" do
    test "reads existing fixture file" do
      {:ok, content} = TestHelpers.read_fixture("applescript/hello_world.applescript")
      assert is_binary(content)
      assert String.contains?(content, "Hello, World!")
    end

    test "returns error for nonexistent fixture" do
      assert {:error, :enoent} = TestHelpers.read_fixture("nonexistent.txt")
    end

    test "reads error fixture files" do
      {:ok, content} = TestHelpers.read_fixture("errors/syntax_error.txt")
      assert String.contains?(content, "syntax error")
    end
  end

  describe "read_fixture!/1" do
    test "reads existing fixture file" do
      content = TestHelpers.read_fixture!("applescript/hello_world.applescript")
      assert is_binary(content)
      assert String.contains?(content, "Hello, World!")
    end

    test "raises for nonexistent fixture" do
      assert_raise File.Error, fn ->
        TestHelpers.read_fixture!("nonexistent.txt")
      end
    end
  end

  describe "macos?/0" do
    test "returns boolean" do
      result = TestHelpers.macos?()
      assert is_boolean(result)
    end

    test "returns true on macOS" do
      # This will only pass on macOS, which is fine for this test
      os_type = :os.type()

      case os_type do
        {:unix, :darwin} -> assert TestHelpers.macos?()
        _ -> refute TestHelpers.macos?()
      end
    end
  end

  describe "osascript_available?/0" do
    test "returns boolean" do
      result = TestHelpers.osascript_available?()
      assert is_boolean(result)
    end

    test "matches System.find_executable result" do
      expected = not is_nil(System.find_executable("osascript"))
      assert TestHelpers.osascript_available?() == expected
    end
  end

  describe "should_run_integration_tests?/0" do
    test "returns boolean" do
      result = TestHelpers.should_run_integration_tests?()
      assert is_boolean(result)
    end

    test "requires both macOS and osascript" do
      result = TestHelpers.should_run_integration_tests?()
      expected = TestHelpers.macos?() and TestHelpers.osascript_available?()
      assert result == expected
    end
  end

  describe "applescript_fixtures/0" do
    test "returns list of AppleScript fixture files" do
      fixtures = TestHelpers.applescript_fixtures()
      assert is_list(fixtures)
      assert length(fixtures) > 0
    end

    test "includes expected fixtures" do
      fixtures = TestHelpers.applescript_fixtures()
      assert "hello_world.applescript" in fixtures
      assert "with_arguments.applescript" in fixtures
      assert "delay_script.applescript" in fixtures
      assert "syntax_error.applescript" in fixtures
    end

    test "returns sorted list" do
      fixtures = TestHelpers.applescript_fixtures()
      assert fixtures == Enum.sort(fixtures)
    end
  end

  describe "javascript_fixtures/0" do
    test "returns list of JavaScript fixture files" do
      fixtures = TestHelpers.javascript_fixtures()
      assert is_list(fixtures)
      assert length(fixtures) > 0
    end

    test "includes expected fixtures" do
      fixtures = TestHelpers.javascript_fixtures()
      assert "hello_world.js" in fixtures
      assert "with_arguments.js" in fixtures
      assert "system_events.js" in fixtures
      assert "syntax_error.js" in fixtures
    end

    test "returns sorted list" do
      fixtures = TestHelpers.javascript_fixtures()
      assert fixtures == Enum.sort(fixtures)
    end
  end

  describe "error_fixtures/0" do
    test "returns list of error fixture files" do
      fixtures = TestHelpers.error_fixtures()
      assert is_list(fixtures)
      assert length(fixtures) > 0
    end

    test "includes expected error fixtures" do
      fixtures = TestHelpers.error_fixtures()
      assert "syntax_error.txt" in fixtures
      assert "execution_error.txt" in fixtures
      assert "permission_denied.txt" in fixtures
      assert "app_not_found.txt" in fixtures
    end

    test "returns sorted list" do
      fixtures = TestHelpers.error_fixtures()
      assert fixtures == Enum.sort(fixtures)
    end
  end

  describe "with_temp_script/3" do
    test "creates temporary file with content" do
      content = "return 'test'"

      TestHelpers.with_temp_script(content, ".applescript", fn path ->
        assert File.exists?(path)
        assert String.ends_with?(path, ".applescript")
        assert File.read!(path) == content
      end)
    end

    test "cleans up temporary file after use" do
      {:ok, captured_path} = Agent.start_link(fn -> nil end)

      TestHelpers.with_temp_script("test", ".txt", fn path ->
        Agent.update(captured_path, fn _ -> path end)
        assert File.exists?(path)
      end)

      # File should be cleaned up
      path = Agent.get(captured_path, & &1)

      if path do
        refute File.exists?(path)
      end

      Agent.stop(captured_path)
    end

    test "returns function result" do
      result =
        TestHelpers.with_temp_script("test", ".txt", fn _path ->
          :return_value
        end)

      assert result == :return_value
    end

    test "cleans up even if function raises" do
      {:ok, captured_path} = Agent.start_link(fn -> nil end)

      assert_raise RuntimeError, fn ->
        TestHelpers.with_temp_script("test", ".txt", fn path ->
          Agent.update(captured_path, fn _ -> path end)
          raise "test error"
        end)
      end

      # File should still be cleaned up
      path = Agent.get(captured_path, & &1)

      if path do
        refute File.exists?(path)
      end

      Agent.stop(captured_path)
    end
  end

  describe "normalize_output/1" do
    test "trims leading whitespace" do
      assert TestHelpers.normalize_output("  hello") == "hello"
    end

    test "trims trailing whitespace" do
      assert TestHelpers.normalize_output("hello  ") == "hello"
    end

    test "trims newlines" do
      assert TestHelpers.normalize_output("hello\n") == "hello"
      assert TestHelpers.normalize_output("\nhello") == "hello"
      assert TestHelpers.normalize_output("\nhello\n") == "hello"
    end

    test "trims mixed whitespace" do
      assert TestHelpers.normalize_output("  \n  hello  \n  ") == "hello"
    end

    test "preserves internal whitespace" do
      assert TestHelpers.normalize_output("  hello world  ") == "hello world"
    end
  end
end
