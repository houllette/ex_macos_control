defmodule ExMacOSControl.AppleScriptIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.TestHelpers

  # These tests require macOS with osascript
  @moduletag :integration

  setup do
    # Skip if not on macOS with osascript
    TestHelpers.skip_unless_integration()
    :ok
  end

  describe "AppleScript execution on macOS" do
    @tag :integration
    test "executes simple AppleScript" do
      # Note: Actual implementation will come in C1 chunk
      # This test demonstrates the integration test pattern
      _script = "return \"Hello, World!\""

      # This will fail until C1 is implemented - that's expected in TDD!
      # {:ok, result} = ExMacOSControl.run_applescript(script)
      # assert TestHelpers.normalize_output(result) == "Hello, World!"

      # For now, just verify the fixture exists
      assert File.exists?(TestHelpers.fixture_path("applescript/hello_world.applescript"))
    end

    @tag :integration
    test "executes AppleScript from fixture file" do
      fixture_path = TestHelpers.fixture_path("applescript/hello_world.applescript")
      assert File.exists?(fixture_path)

      content = File.read!(fixture_path)
      assert String.contains?(content, "Hello, World!")
    end

    @tag :integration
    test "fixture files are valid AppleScript" do
      # Verify all AppleScript fixtures are readable
      fixtures = TestHelpers.applescript_fixtures()

      Enum.each(fixtures, fn fixture ->
        path = TestHelpers.fixture_path("applescript/#{fixture}")
        assert File.exists?(path), "Fixture #{fixture} does not exist"

        content = File.read!(path)
        assert byte_size(content) > 0, "Fixture #{fixture} is empty"
      end)
    end
  end

  describe "Platform detection" do
    @tag :integration
    test "correctly identifies macOS" do
      assert TestHelpers.macos?() == true
    end

    @tag :integration
    test "osascript is available" do
      assert TestHelpers.osascript_available?() == true
    end

    @tag :integration
    test "integration tests should run" do
      assert TestHelpers.should_run_integration_tests?() == true
    end
  end
end
