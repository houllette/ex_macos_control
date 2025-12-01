defmodule ExMacOSControl.Error do
  @moduledoc """
  Structured error handling for macOS automation operations.

  This module provides a comprehensive error handling system with:
  - Structured error types for common failure scenarios
  - Parsing of osascript error output
  - Helpful error messages with remediation steps
  - Exception behavior for seamless integration with Elixir error handling

  ## Error Types

  The following error types are supported:

  - `:syntax_error` - Invalid AppleScript/JXA syntax
  - `:execution_error` - Runtime error during script execution
  - `:timeout` - Script execution exceeded the timeout limit
  - `:not_found` - Script file or application not found
  - `:permission_denied` - Accessibility or automation permissions required
  - `:unsupported_platform` - Operation attempted on non-macOS platform

  ## Examples

      # Create a syntax error
      iex> error = ExMacOSControl.Error.syntax_error("Expected end of line", line: 5)
      iex> error.type
      :syntax_error

      # Parse osascript error output
      iex> stderr = "syntax error: Expected end of line but found identifier. (-2741)"
      iex> error = ExMacOSControl.Error.parse_osascript_error(stderr, 1)
      iex> error.type
      :syntax_error

      # Get remediation steps
      iex> error = ExMacOSControl.Error.permission_denied("Accessibility required")
      iex> steps = ExMacOSControl.Error.remediation_steps(error)
      iex> Enum.count(steps) > 0
      true

      # Raise as exception
      iex> error = ExMacOSControl.Error.timeout("Script timed out", timeout: 5000)
      iex> raise error
      ** (ExMacOSControl.Error) Script execution timed out after 5000ms

  """

  defexception [:type, :message, :details]

  @typedoc """
  Error type indicating the category of failure.
  """
  @type error_type ::
          :syntax_error
          | :execution_error
          | :timeout
          | :not_found
          | :permission_denied
          | :unsupported_platform

  @typedoc """
  Structured error with type, message, and additional details.
  """
  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map()
        }

  ## Exception Behavior

  @doc """
  Formats the error as a string for exception messages.

  Includes the error message and relevant details, along with
  remediation steps when applicable.
  """
  @spec exception(keyword()) :: t()
  def exception(opts) do
    type = Keyword.get(opts, :type, :execution_error)
    message = Keyword.get(opts, :message, "An error occurred")
    details = Keyword.get(opts, :details, %{})

    %__MODULE__{
      type: type,
      message: message,
      details: details
    }
  end

  @impl true
  def message(%__MODULE__{type: type, message: msg, details: details}) do
    base_message = format_error_message(type, msg, details)
    steps = remediation_steps(%__MODULE__{type: type, message: msg, details: details})

    if Enum.empty?(steps) do
      base_message
    else
      """
      #{base_message}

      Remediation steps:
      #{Enum.map_join(steps, "\n", &"  - #{&1}")}
      """
    end
  end

  ## Error Constructors

  @doc """
  Creates a syntax error.

  ## Parameters

  - `message` - Description of the syntax error
  - `opts` - Optional keyword list with additional details (e.g., `:line`, `:column`)

  ## Examples

      iex> error = ExMacOSControl.Error.syntax_error("Expected end of line", line: 5)
      iex> error.type
      :syntax_error
      iex> error.details.line
      5

  """
  @spec syntax_error(String.t(), keyword()) :: t()
  def syntax_error(message, opts \\ []) do
    %__MODULE__{
      type: :syntax_error,
      message: message,
      details: Enum.into(opts, %{})
    }
  end

  @doc """
  Creates an execution error.

  ## Parameters

  - `message` - Description of the execution error
  - `opts` - Optional keyword list with additional details

  ## Examples

      iex> error = ExMacOSControl.Error.execution_error("Invalid index")
      iex> error.type
      :execution_error

  """
  @spec execution_error(String.t(), keyword()) :: t()
  def execution_error(message, opts \\ []) do
    %__MODULE__{
      type: :execution_error,
      message: message,
      details: Enum.into(opts, %{})
    }
  end

  @doc """
  Creates a timeout error.

  ## Parameters

  - `message` - Description of the timeout
  - `opts` - Optional keyword list with additional details (e.g., `:timeout` in milliseconds)

  ## Examples

      iex> error = ExMacOSControl.Error.timeout("Script exceeded timeout", timeout: 5000)
      iex> error.type
      :timeout
      iex> error.details.timeout
      5000

  """
  @spec timeout(String.t(), keyword()) :: t()
  def timeout(message, opts \\ []) do
    %__MODULE__{
      type: :timeout,
      message: message,
      details: Enum.into(opts, %{})
    }
  end

  @doc """
  Creates a not found error.

  ## Parameters

  - `message` - Description of what was not found
  - `opts` - Optional keyword list with additional details (e.g., `:app`, `:file`)

  ## Examples

      iex> error = ExMacOSControl.Error.not_found("Application not found", app: "Foo")
      iex> error.type
      :not_found
      iex> error.details.app
      "Foo"

  """
  @spec not_found(String.t(), keyword()) :: t()
  def not_found(message, opts \\ []) do
    %__MODULE__{
      type: :not_found,
      message: message,
      details: Enum.into(opts, %{})
    }
  end

  @doc """
  Creates a permission denied error.

  ## Parameters

  - `message` - Description of the permission issue
  - `opts` - Optional keyword list with additional details

  ## Examples

      iex> error = ExMacOSControl.Error.permission_denied("Accessibility permissions required")
      iex> error.type
      :permission_denied

  """
  @spec permission_denied(String.t(), keyword()) :: t()
  def permission_denied(message, opts \\ []) do
    %__MODULE__{
      type: :permission_denied,
      message: message,
      details: Enum.into(opts, %{})
    }
  end

  @doc """
  Creates an unsupported platform error.

  ## Parameters

  - `message` - Description of the platform issue
  - `opts` - Optional keyword list with additional details (e.g., `:platform`)

  ## Examples

      iex> error = ExMacOSControl.Error.unsupported_platform("Not running on macOS", platform: :linux)
      iex> error.type
      :unsupported_platform
      iex> error.details.platform
      :linux

  """
  @spec unsupported_platform(String.t(), keyword()) :: t()
  def unsupported_platform(message, opts \\ []) do
    %__MODULE__{
      type: :unsupported_platform,
      message: message,
      details: Enum.into(opts, %{})
    }
  end

  ## Error Parsing

  @doc """
  Parses osascript error output into a structured error.

  Analyzes stderr output and exit codes from osascript to determine
  the error type and extract relevant information.

  ## Parameters

  - `stderr` - The stderr output from osascript
  - `exit_code` - The exit code from osascript

  ## Examples

      iex> stderr = "syntax error: Expected end of line but found identifier. (-2741)"
      iex> error = ExMacOSControl.Error.parse_osascript_error(stderr, 1)
      iex> error.type
      :syntax_error

      iex> stderr = "execution error: Finder got an error: Can't get window 1. (-1719)"
      iex> error = ExMacOSControl.Error.parse_osascript_error(stderr, 1)
      iex> error.type
      :execution_error

  """
  @spec parse_osascript_error(String.t(), integer()) :: t()
  def parse_osascript_error(stderr, exit_code) do
    stderr = String.trim(stderr)

    cond do
      timeout_error?(exit_code, stderr) ->
        timeout("Script execution timed out", exit_code: exit_code, stderr: stderr)

      syntax_error?(stderr) ->
        parse_syntax_error(stderr, exit_code)

      permission_error?(stderr) ->
        parse_permission_error(stderr, exit_code)

      not_found_error?(stderr) ->
        parse_not_found_error(stderr, exit_code)

      execution_error?(stderr) ->
        parse_execution_error(stderr, exit_code)

      true ->
        execution_error("An unknown error occurred: #{stderr}",
          exit_code: exit_code,
          stderr: stderr
        )
    end
  end

  ## Remediation Steps

  @doc """
  Provides remediation steps for an error.

  Returns a list of actionable steps the user can take to resolve the error.

  ## Parameters

  - `error` - The error to provide remediation for

  ## Examples

      iex> error = ExMacOSControl.Error.permission_denied("Accessibility required")
      iex> steps = ExMacOSControl.Error.remediation_steps(error)
      iex> is_list(steps)
      true

  """
  @spec remediation_steps(t()) :: [String.t()]
  def remediation_steps(%__MODULE__{type: :syntax_error}) do
    [
      "Check your AppleScript/JXA syntax for errors",
      "Verify all quotes, parentheses, and braces are properly closed",
      "Consult the AppleScript Language Guide for correct syntax",
      "Try running the script in Script Editor to get more detailed error information"
    ]
  end

  def remediation_steps(%__MODULE__{type: :permission_denied}) do
    [
      "Open System Settings (or System Preferences on older macOS)",
      "Go to Privacy & Security → Accessibility",
      "Add or enable your application/terminal",
      "You may need to restart your application after granting permissions"
    ]
  end

  def remediation_steps(%__MODULE__{type: :not_found, details: details}) do
    base_steps = [
      "Verify the application is installed on your system",
      "Check the application name spelling (case-sensitive)"
    ]

    app_specific =
      if app = details[:app] do
        ["Try opening #{app} manually to confirm it's available"]
      else
        []
      end

    base_steps ++ app_specific
  end

  def remediation_steps(%__MODULE__{type: :timeout, details: details}) do
    base_steps = [
      "Increase the timeout value if the script legitimately needs more time",
      "Check if the script is stuck in an infinite loop",
      "Verify the target application is responsive"
    ]

    timeout_specific =
      if timeout = details[:timeout] do
        ["Current timeout: #{timeout}ms - consider increasing to #{timeout * 2}ms or more"]
      else
        []
      end

    base_steps ++ timeout_specific
  end

  def remediation_steps(%__MODULE__{type: :unsupported_platform}) do
    [
      "This library requires macOS to function",
      "If you need cross-platform automation, consider platform-specific alternatives",
      "Use platform detection to conditionally run macOS-specific code"
    ]
  end

  def remediation_steps(%__MODULE__{type: :execution_error}) do
    [
      "Review the error message for specific details",
      "Verify the target application supports the requested operation",
      "Check that all required parameters are provided correctly",
      "Try running a simpler version of the script to isolate the issue"
    ]
  end

  ## Private Helpers

  # Error type detection helpers
  defp timeout_error?(exit_code, stderr) do
    exit_code == 124 or String.contains?(stderr, "timeout")
  end

  defp syntax_error?(stderr) do
    String.starts_with?(stderr, "syntax error:")
  end

  defp permission_error?(stderr) do
    String.contains?(stderr, "not allowed") or String.contains?(stderr, "not authorized")
  end

  defp not_found_error?(stderr) do
    String.contains?(stderr, "could not be found") or String.contains?(stderr, "application \"")
  end

  defp execution_error?(stderr) do
    String.starts_with?(stderr, "execution error:")
  end

  # Error message formatting
  defp format_error_message(:syntax_error, msg, details) do
    line_info = if line = details[:line], do: " at line #{line}", else: ""
    "AppleScript syntax error#{line_info}: #{msg}"
  end

  defp format_error_message(:execution_error, msg, _details) do
    "Script execution error: #{msg}"
  end

  defp format_error_message(:timeout, msg, details) do
    timeout_info = if timeout = details[:timeout], do: " after #{timeout}ms", else: ""
    "Script execution timed out#{timeout_info}: #{msg}"
  end

  defp format_error_message(:not_found, msg, _details) do
    "Resource not found: #{msg}"
  end

  defp format_error_message(:permission_denied, msg, _details) do
    "Permission denied: #{msg}"
  end

  defp format_error_message(:unsupported_platform, msg, details) do
    platform_info = if platform = details[:platform], do: " (current: #{platform})", else: ""
    "Unsupported platform#{platform_info}: #{msg}"
  end

  defp parse_syntax_error(stderr, exit_code) do
    error_code = extract_error_code(stderr)
    message = extract_message(stderr, "syntax error:")

    syntax_error(message,
      exit_code: exit_code,
      error_code: error_code,
      stderr: stderr
    )
  end

  defp parse_execution_error(stderr, exit_code) do
    error_code = extract_error_code(stderr)
    message = extract_message(stderr, "execution error:")

    execution_error(message,
      exit_code: exit_code,
      error_code: error_code,
      stderr: stderr
    )
  end

  defp parse_permission_error(stderr, exit_code) do
    error_code = extract_error_code(stderr)
    message = extract_message(stderr, "execution error:") || stderr

    permission_denied(message,
      exit_code: exit_code,
      error_code: error_code,
      stderr: stderr
    )
  end

  defp parse_not_found_error(stderr, exit_code) do
    error_code = extract_error_code(stderr)
    app_name = extract_application_name(stderr)
    message = extract_message(stderr, "execution error:") || stderr

    not_found(message,
      exit_code: exit_code,
      error_code: error_code,
      app: app_name,
      stderr: stderr
    )
  end

  defp extract_error_code(stderr) do
    case Regex.run(~r/\((-?\d+)\)/, stderr) do
      [_, code] -> String.to_integer(code)
      _ -> nil
    end
  end

  defp extract_message(stderr, prefix) do
    stderr
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, prefix))
    |> case do
      nil ->
        nil

      line ->
        line
        |> String.replace_prefix(prefix, "")
        |> String.trim()
        |> String.replace(~r/\s*\(-?\d+\)\s*$/, "")
    end
  end

  defp extract_application_name(stderr) do
    case Regex.run(~r/[Tt]he application "([^"]+)"/, stderr) do
      [_, app] -> app
      _ -> nil
    end
  end
end
