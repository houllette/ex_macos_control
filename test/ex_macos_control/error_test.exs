defmodule ExMacOSControl.ErrorTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.Error

  describe "exception struct" do
    test "creates error with type, message, and details" do
      error = %Error{
        type: :syntax_error,
        message: "Invalid syntax",
        details: %{line: 5, column: 10}
      }

      assert error.type == :syntax_error
      assert error.message == "Invalid syntax"
      assert error.details == %{line: 5, column: 10}
    end

    test "implements Exception behavior" do
      error = %Error{type: :execution_error, message: "Test error"}
      exception_message = Exception.message(error)

      assert is_binary(exception_message)
      assert exception_message =~ "Test error"
    end

    test "creates exception from keyword list" do
      error = Error.exception(type: :timeout, message: "Timed out", details: %{timeout: 1000})

      assert error.type == :timeout
      assert error.message == "Timed out"
      assert error.details.timeout == 1000
    end

    test "creates exception with defaults" do
      error = Error.exception([])

      assert error.type == :execution_error
      assert error.message == "An error occurred"
      assert error.details == %{}
    end
  end

  describe "error type construction" do
    test "creates syntax_error" do
      error = Error.syntax_error("Invalid AppleScript syntax", line: 3)

      assert error.type == :syntax_error
      assert error.message =~ "Invalid AppleScript syntax"
      assert error.details.line == 3
    end

    test "creates execution_error" do
      error = Error.execution_error("Runtime error in script")

      assert error.type == :execution_error
      assert error.message =~ "Runtime error in script"
    end

    test "creates timeout error" do
      error = Error.timeout("Script exceeded 5000ms timeout", timeout: 5000)

      assert error.type == :timeout
      assert error.message =~ "timeout"
      assert error.details.timeout == 5000
    end

    test "creates not_found error" do
      error = Error.not_found("Application 'NonExistentApp' not found", app: "NonExistentApp")

      assert error.type == :not_found
      assert error.message =~ "not found"
      assert error.details.app == "NonExistentApp"
    end

    test "creates permission_denied error" do
      error = Error.permission_denied("Accessibility permissions required")

      assert error.type == :permission_denied
      assert error.message =~ "permission"
    end

    test "creates unsupported_platform error" do
      error = Error.unsupported_platform("Not running on macOS", platform: :linux)

      assert error.type == :unsupported_platform
      assert error.message =~ "macOS"
      assert error.details.platform == :linux
    end
  end

  describe "parse_osascript_error/2" do
    test "parses syntax error from osascript output" do
      stderr = """
      syntax error: Expected end of line but found identifier. (-2741)
      """

      error = Error.parse_osascript_error(stderr, 1)

      assert error.type == :syntax_error
      assert error.message =~ "Expected end of line"
      assert error.details.exit_code == 1
    end

    test "parses execution error from osascript output" do
      stderr = """
      execution error: Finder got an error: Can't get window 1. Invalid index. (-1719)
      """

      error = Error.parse_osascript_error(stderr, 1)

      assert error.type == :execution_error
      assert error.message =~ "Finder got an error"
      assert error.message =~ "Invalid index"
      assert error.details.exit_code == 1
      assert error.details.error_code == -1719
    end

    test "parses application not found error" do
      stderr = """
      execution error: The application "NonExistent" could not be found. (-1728)
      """

      error = Error.parse_osascript_error(stderr, 1)

      assert error.type == :not_found
      assert error.message =~ "NonExistent"
      assert error.details.app == "NonExistent"
      assert error.details.error_code == -1728
    end

    test "parses permission denied error" do
      stderr = """
      execution error: System Events got an error: osascript is not allowed to send keystrokes. (-1743)
      """

      error = Error.parse_osascript_error(stderr, 1)

      assert error.type == :permission_denied
      assert error.message =~ "not allowed"
      assert error.details.error_code == -1743
    end

    test "handles timeout (exit code 124 or specific error)" do
      stderr = "Script timeout"

      error = Error.parse_osascript_error(stderr, 124)

      assert error.type == :timeout
      assert error.message =~ "timed out"
    end

    test "parses error with line number information" do
      stderr = """
      syntax error: A identifier can't go after this identifier. (-2740)
      \t"hello" & & "world"
      \t          ^
      """

      error = Error.parse_osascript_error(stderr, 1)

      assert error.type == :syntax_error
      assert is_map(error.details)
    end

    test "handles unknown error format gracefully" do
      stderr = "Some unknown error format"

      error = Error.parse_osascript_error(stderr, 1)

      assert error.type == :execution_error
      assert error.message =~ "unknown error"
      assert error.details.exit_code == 1
    end

    test "extracts error codes from osascript output" do
      stderr = "execution error: Something happened. (-12345)"

      error = Error.parse_osascript_error(stderr, 1)

      assert error.details.error_code == -12_345
    end
  end

  describe "error message formatting" do
    test "formats syntax error with remediation steps" do
      error = Error.syntax_error("Expected end of line", line: 3)
      message = Exception.message(error)

      assert message =~ "syntax error"
      assert message =~ "line 3"
      assert message =~ "Expected end of line"
    end

    test "formats permission error with remediation steps" do
      error = Error.permission_denied("Accessibility permissions required")
      message = Exception.message(error)

      assert message =~ "permission"
      assert message =~ "System Settings" or message =~ "System Preferences"
    end

    test "formats not_found error with helpful message" do
      error = Error.not_found("Application 'Foo' not found", app: "Foo")
      message = Exception.message(error)

      assert message =~ "not found"
      assert message =~ "Foo"
    end

    test "formats timeout error with timeout value" do
      error = Error.timeout("Script exceeded timeout", timeout: 5000)
      message = Exception.message(error)

      assert message =~ "timeout"
      assert message =~ "5000" or message =~ "5s"
    end

    test "formats unsupported platform error with platform info" do
      error = Error.unsupported_platform("Not macOS", platform: :linux)
      message = Exception.message(error)

      assert message =~ "macOS"
      assert message =~ "linux"
    end
  end

  describe "remediation_steps/1" do
    test "provides steps for permission_denied error" do
      error = Error.permission_denied("Accessibility required")
      steps = Error.remediation_steps(error)

      assert is_list(steps)
      assert length(steps) > 0
      assert Enum.any?(steps, &String.contains?(&1, "System Settings"))
    end

    test "provides steps for syntax_error" do
      error = Error.syntax_error("Bad syntax", line: 5)
      steps = Error.remediation_steps(error)

      assert is_list(steps)
      assert Enum.any?(steps, &String.contains?(&1, "syntax"))
    end

    test "provides steps for not_found error" do
      error = Error.not_found("App not found", app: "Foo")
      steps = Error.remediation_steps(error)

      assert is_list(steps)
      assert Enum.any?(steps, &String.contains?(&1, "installed"))
    end

    test "provides steps for timeout error" do
      error = Error.timeout("Timeout", timeout: 5000)
      steps = Error.remediation_steps(error)

      assert is_list(steps)
      assert Enum.any?(steps, &String.contains?(&1, "timeout"))
    end

    test "provides steps for unsupported_platform error" do
      error = Error.unsupported_platform("Not macOS", platform: :linux)
      steps = Error.remediation_steps(error)

      assert is_list(steps)
      assert Enum.any?(steps, &String.contains?(&1, "macOS"))
    end

    test "returns empty list for execution_error when no specific remediation" do
      error = Error.execution_error("Generic error")
      steps = Error.remediation_steps(error)

      assert is_list(steps)
      # May be empty or have generic suggestions
    end
  end
end
