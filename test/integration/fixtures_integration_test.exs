defmodule ExMacOSControl.FixturesIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.TestHelpers

  # These tests validate that our fixtures are actually valid on macOS
  @moduletag :integration

  setup do
    TestHelpers.skip_unless_integration()
    :ok
  end

  describe "AppleScript fixtures validation" do
    @tag :integration
    test "hello_world.applescript is valid AppleScript" do
      script_path = TestHelpers.fixture_path("applescript/hello_world.applescript")
      content = File.read!(script_path)

      # Use osascript to validate syntax
      case System.cmd("osascript", ["-e", content]) do
        {output, 0} ->
          assert TestHelpers.normalize_output(output) == "Hello, World!"

        {error, code} ->
          flunk("AppleScript failed: #{error} (exit code: #{code})")
      end
    end

    @tag :integration
    test "with_arguments.applescript works with arguments" do
      script_path = TestHelpers.fixture_path("applescript/with_arguments.applescript")

      case System.cmd("osascript", [script_path, "test_arg"]) do
        {output, 0} ->
          assert TestHelpers.normalize_output(output) == "test_arg"

        {error, code} ->
          flunk("AppleScript failed: #{error} (exit code: #{code})")
      end
    end

    @tag :integration
    test "syntax_error.applescript fails with syntax error" do
      script_path = TestHelpers.fixture_path("applescript/syntax_error.applescript")

      case System.cmd("osascript", [script_path], stderr_to_stdout: true) do
        {_output, 0} ->
          flunk("Expected syntax error but script succeeded")

        {error, code} ->
          assert code != 0
          assert String.contains?(error, "syntax error") or String.contains?(error, "error")
      end
    end
  end

  describe "JavaScript fixtures validation" do
    @tag :integration
    test "hello_world.js is valid JXA" do
      script_path = TestHelpers.fixture_path("javascript/hello_world.js")
      content = File.read!(script_path)

      case System.cmd("osascript", ["-l", "JavaScript", "-e", content]) do
        {output, 0} ->
          assert TestHelpers.normalize_output(output) == "Hello from JXA!"

        {error, code} ->
          flunk("JXA script failed: #{error} (exit code: #{code})")
      end
    end

    @tag :integration
    test "with_arguments.js works with arguments" do
      script_path = TestHelpers.fixture_path("javascript/with_arguments.js")

      case System.cmd("osascript", ["-l", "JavaScript", script_path, "test_arg"]) do
        {output, 0} ->
          assert TestHelpers.normalize_output(output) == "test_arg"

        {error, code} ->
          flunk("JXA script failed: #{error} (exit code: #{code})")
      end
    end

    @tag :integration
    test "syntax_error.js fails with error" do
      script_path = TestHelpers.fixture_path("javascript/syntax_error.js")

      case System.cmd("osascript", ["-l", "JavaScript", script_path], stderr_to_stdout: true) do
        {_output, 0} ->
          flunk("Expected syntax error but script succeeded")

        {error, code} ->
          assert code != 0
          assert String.contains?(error, "Error") or String.contains?(error, "error")
      end
    end
  end

  describe "Error fixtures accuracy" do
    @tag :integration
    test "error fixtures contain realistic error messages" do
      error_fixtures = TestHelpers.error_fixtures()

      Enum.each(error_fixtures, fn fixture ->
        {:ok, content} = TestHelpers.read_fixture("errors/#{fixture}")

        # Each error fixture should contain some error-related text
        assert String.contains?(content, "error") or String.contains?(content, "Error"),
               "Error fixture #{fixture} doesn't contain 'error'"
      end)
    end

    @tag :integration
    test "syntax_error.txt contains realistic error format" do
      # Generate a real error
      {error_output, code} =
        System.cmd("osascript", ["-e", "this is not valid"], stderr_to_stdout: true)

      assert code != 0

      # Read our fixture
      {:ok, fixture_content} = TestHelpers.read_fixture("errors/syntax_error.txt")

      # Both should contain "error"
      assert String.contains?(error_output, "error")
      assert String.contains?(fixture_content, "error")

      # Both should contain error codes in parentheses
      assert error_output =~ ~r/\(-\d+\)/
      assert fixture_content =~ ~r/\(-\d+\)/
    end
  end
end
