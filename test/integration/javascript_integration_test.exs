defmodule ExMacOSControl.JavaScriptIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{OSAScriptAdapter, TestHelpers}

  # These tests require macOS with osascript
  @moduletag :integration

  setup do
    # Skip if not on macOS with osascript
    TestHelpers.skip_unless_integration()
    :ok
  end

  # Helper to call the real adapter directly, bypassing the facade's mock configuration
  defp run_javascript(script, opts \\ []) do
    OSAScriptAdapter.run_javascript(script, opts)
  end

  defp run_applescript(script, opts \\ []) do
    OSAScriptAdapter.run_applescript(script, opts)
  end

  describe "JXA execution on macOS" do
    @tag :integration
    test "executes simple JXA from fixture" do
      script = TestHelpers.read_fixture!("javascript/hello_world.js")
      assert {:ok, result} = run_javascript(script)
      assert TestHelpers.normalize_output(result) == "Hello from JXA!"
    end

    @tag :integration
    test "executes JXA with arguments from fixture" do
      script = TestHelpers.read_fixture!("javascript/with_arguments.js")
      assert {:ok, result} = run_javascript(script, args: ["test value"])
      assert TestHelpers.normalize_output(result) == "test value"
    end

    @tag :integration
    test "executes JXA with multiple arguments" do
      script = TestHelpers.read_fixture!("javascript/with_arguments.js")
      assert {:ok, result} = run_javascript(script, args: ["first arg"])
      assert TestHelpers.normalize_output(result) == "first arg"
    end

    @tag :integration
    test "executes JXA with System Events from fixture" do
      script = TestHelpers.read_fixture!("javascript/system_events.js")
      assert {:ok, result} = run_javascript(script)
      # Finder should be running on macOS
      assert TestHelpers.normalize_output(result) == "Finder is running"
    end

    @tag :integration
    test "returns error for JXA syntax error from fixture" do
      script = TestHelpers.read_fixture!("javascript/syntax_error.js")
      assert {:error, %ExMacOSControl.Error{} = error} = run_javascript(script)
      assert error.details.exit_code != 0
    end

    @tag :integration
    test "executes inline JXA Application automation" do
      script = "Application('Finder').name()"
      assert {:ok, result} = run_javascript(script)
      assert TestHelpers.normalize_output(result) == "Finder"
    end

    @tag :integration
    test "executes inline JXA with ObjC bridge" do
      # Test basic ObjC bridge functionality
      script = """
      ObjC.import('Foundation');
      var str = $.NSString.alloc.initWithUTF8String('test');
      str.js;
      """

      assert {:ok, result} = run_javascript(script)
      assert TestHelpers.normalize_output(result) == "test"
    end
  end

  describe "JXA vs AppleScript comparison" do
    @tag :integration
    test "both languages can get Finder name" do
      jxa_script = "Application('Finder').name()"
      applescript = ~s(tell application "Finder" to return name)

      assert {:ok, jxa_result} = run_javascript(jxa_script)
      assert {:ok, as_result} = run_applescript(applescript)

      assert TestHelpers.normalize_output(jxa_result) ==
               TestHelpers.normalize_output(as_result)
    end

    @tag :integration
    test "both languages can count Finder windows" do
      jxa_script = "Application('Finder').windows().length"
      applescript = ~s(tell application "Finder" to return count of windows)

      assert {:ok, jxa_result} = run_javascript(jxa_script)
      assert {:ok, as_result} = run_applescript(applescript)

      # Both should return the same number (as strings)
      assert TestHelpers.normalize_output(jxa_result) ==
               TestHelpers.normalize_output(as_result)
    end
  end

  describe "JXA fixture files" do
    @tag :integration
    test "all JavaScript fixtures are valid and readable" do
      fixtures = TestHelpers.javascript_fixtures()
      assert length(fixtures) > 0

      Enum.each(fixtures, fn fixture ->
        path = TestHelpers.fixture_path("javascript/#{fixture}")
        assert File.exists?(path), "Fixture #{fixture} does not exist"

        content = File.read!(path)
        assert byte_size(content) > 0, "Fixture #{fixture} is empty"
      end)
    end
  end
end
