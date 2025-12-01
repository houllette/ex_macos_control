defmodule ExMacOSControl.TestHelpers do
  @moduledoc """
  Common test utilities and helpers for ExMacOSControl testing.

  This module provides utilities for:
  - Loading test fixtures (AppleScript, JXA, error outputs)
  - Platform detection for conditional test execution
  - Common assertions for macOS automation testing
  - Mock adapter configuration
  """

  @doc """
  Returns the absolute path to the fixtures directory.

  ## Examples

      iex> ExMacOSControl.TestHelpers.fixtures_path()
      "/absolute/path/to/test/support/fixtures"
  """
  @spec fixtures_path() :: String.t()
  def fixtures_path do
    Path.join([__DIR__, "fixtures"]) |> Path.expand()
  end

  @doc """
  Returns the absolute path to a specific fixture file.

  ## Examples

      iex> ExMacOSControl.TestHelpers.fixture_path("applescript/hello_world.applescript")
      "/absolute/path/to/test/support/fixtures/applescript/hello_world.applescript"
  """
  @spec fixture_path(String.t()) :: String.t()
  def fixture_path(relative_path) do
    Path.join(fixtures_path(), relative_path)
  end

  @doc """
  Reads the contents of a fixture file.

  ## Examples

      iex> ExMacOSControl.TestHelpers.read_fixture("errors/syntax_error.txt")
      {:ok, "syntax error: Expected end of line but found identifier. (-2741)\\n"}

      iex> ExMacOSControl.TestHelpers.read_fixture("nonexistent.txt")
      {:error, :enoent}
  """
  @spec read_fixture(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def read_fixture(relative_path) do
    relative_path
    |> fixture_path()
    |> File.read()
  end

  @doc """
  Reads the contents of a fixture file, raising on error.

  ## Examples

      iex> ExMacOSControl.TestHelpers.read_fixture!("applescript/hello_world.applescript")
      "-- Simple hello world AppleScript\\nreturn \\"Hello, World!\\"\\n"
  """
  @spec read_fixture!(String.t()) :: String.t()
  def read_fixture!(relative_path) do
    relative_path
    |> fixture_path()
    |> File.read!()
  end

  @doc """
  Detects if the current platform is macOS.

  ## Examples

      iex> ExMacOSControl.TestHelpers.macos?()
      true  # or false depending on platform
  """
  @spec macos?() :: boolean()
  def macos? do
    case :os.type() do
      {:unix, :darwin} -> true
      _ -> false
    end
  end

  @doc """
  Detects if osascript is available on the current system.

  ## Examples

      iex> ExMacOSControl.TestHelpers.osascript_available?()
      true  # or false
  """
  @spec osascript_available?() :: boolean()
  def osascript_available? do
    case System.find_executable("osascript") do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Determines if integration tests should run on the current platform.

  Returns true if running on macOS with osascript available.

  ## Examples

      iex> ExMacOSControl.TestHelpers.should_run_integration_tests?()
      true  # or false
  """
  @spec should_run_integration_tests?() :: boolean()
  def should_run_integration_tests? do
    macos?() and osascript_available?()
  end

  @doc """
  Skips a test if not running on macOS with a helpful message.

  ## Examples

      test "some macOS-specific test" do
        skip_unless_macos()
        # test code here
      end
  """
  @spec skip_unless_macos() :: :ok | no_return()
  def skip_unless_macos do
    unless macos?() do
      raise ExUnit.AssertionError,
        message: "Test requires macOS but running on #{inspect(:os.type())}"
    end

    :ok
  end

  @doc """
  Skips a test if osascript is not available with a helpful message.

  ## Examples

      test "some osascript test" do
        skip_unless_osascript()
        # test code here
      end
  """
  @spec skip_unless_osascript() :: :ok | no_return()
  def skip_unless_osascript do
    unless osascript_available?() do
      raise ExUnit.AssertionError,
        message: "Test requires osascript but it is not available in PATH"
    end

    :ok
  end

  @doc """
  Skips a test if integration tests should not run.

  This combines platform and osascript checks.

  ## Examples

      @tag :integration
      test "integration test" do
        skip_unless_integration()
        # integration test code here
      end
  """
  @spec skip_unless_integration() :: :ok | no_return()
  def skip_unless_integration do
    unless should_run_integration_tests?() do
      raise ExUnit.AssertionError,
        message: """
        Integration tests require macOS with osascript.
        Current platform: #{inspect(:os.type())}
        osascript available: #{osascript_available?()}
        """
    end

    :ok
  end

  @doc """
  Returns a list of all available AppleScript fixture files.

  ## Examples

      iex> ExMacOSControl.TestHelpers.applescript_fixtures()
      ["hello_world.applescript", "with_arguments.applescript", ...]
  """
  @spec applescript_fixtures() :: [String.t()]
  def applescript_fixtures do
    fixtures_path()
    |> Path.join("applescript")
    |> File.ls!()
    |> Enum.sort()
  end

  @doc """
  Returns a list of all available JavaScript fixture files.

  ## Examples

      iex> ExMacOSControl.TestHelpers.javascript_fixtures()
      ["hello_world.js", "with_arguments.js", ...]
  """
  @spec javascript_fixtures() :: [String.t()]
  def javascript_fixtures do
    fixtures_path()
    |> Path.join("javascript")
    |> File.ls!()
    |> Enum.sort()
  end

  @doc """
  Returns a list of all available error fixture files.

  ## Examples

      iex> ExMacOSControl.TestHelpers.error_fixtures()
      ["app_not_found.txt", "execution_error.txt", ...]
  """
  @spec error_fixtures() :: [String.t()]
  def error_fixtures do
    fixtures_path()
    |> Path.join("errors")
    |> File.ls!()
    |> Enum.sort()
  end

  @doc """
  Asserts that a script execution returns an ok tuple.

  ## Examples

      assert_script_success({:ok, "result"})
  """
  defmacro assert_script_success({:ok, _result} = value) do
    quote do
      assert {:ok, _} = unquote(value)
    end
  end

  @doc """
  Asserts that a script execution returns an error tuple.

  ## Examples

      assert_script_error({:error, :timeout})
  """
  defmacro assert_script_error({:error, _reason} = value) do
    quote do
      assert {:error, _} = unquote(value)
    end
  end

  @doc """
  Creates a temporary script file for testing.

  The file is automatically cleaned up after the test.

  ## Examples

      with_temp_script "return 'test'", ".applescript", fn path ->
        # use the temporary file at path
        {:ok, result} = ExMacOSControl.run_script_file(path)
        assert result == "test"
      end
  """
  @spec with_temp_script(String.t(), String.t(), (String.t() -> any())) :: any()
  def with_temp_script(content, extension, fun) do
    temp_file = Path.join(System.tmp_dir!(), "ex_macos_control_test_#{:rand.uniform(999_999)}")
    temp_file_with_ext = temp_file <> extension

    try do
      File.write!(temp_file_with_ext, content)
      fun.(temp_file_with_ext)
    after
      File.rm(temp_file_with_ext)
    end
  end

  @doc """
  Normalizes script output by trimming whitespace.

  osascript sometimes adds trailing newlines or whitespace.

  ## Examples

      iex> ExMacOSControl.TestHelpers.normalize_output("  hello  \\n")
      "hello"
  """
  @spec normalize_output(String.t()) :: String.t()
  def normalize_output(output) do
    output
    |> String.trim()
  end
end
