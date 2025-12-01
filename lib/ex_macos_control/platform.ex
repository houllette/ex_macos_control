defmodule ExMacOSControl.Platform do
  @moduledoc """
  Platform detection and validation utilities for ExMacOSControl.

  This module provides functions to detect the current operating system,
  validate that the code is running on macOS, check for osascript availability,
  and query macOS version information.

  ## Platform Detection

  ExMacOSControl is designed to work exclusively on macOS. This module provides
  utilities to ensure clean failures with helpful error messages when used on
  unsupported platforms.

  ## Examples

  ### Basic Platform Checking

      # Check if running on macOS
      if ExMacOSControl.Platform.macos?() do
        # Safe to use macOS-specific features
        ExMacOSControl.run_applescript("return 'Hello'")
      end

  ### Validation with Error Handling

      # Validate before running scripts (returns {:ok, ...} or {:error, ...})
      case ExMacOSControl.Platform.validate_macos() do
        :ok ->
          # Proceed with macOS operations
          :ok

        {:error, error} ->
          # Handle error gracefully
          Logger.error("Platform error: \#{error.message}")
      end

  ### Early Validation (Raises on Error)

      # Use in functions that require macOS
      def my_macos_function do
        ExMacOSControl.Platform.validate_macos!()
        # Rest of implementation...
      end

  ### Version Checking

      # Check if running on macOS 13.0 or later
      if ExMacOSControl.Platform.version_at_least?({13, 0, 0}) do
        # Use features available in macOS 13+
      end

  ### osascript Availability

      # Check if osascript is available
      if ExMacOSControl.Platform.osascript_available?() do
        # Safe to execute AppleScript
      end

  ## Error Messages

  When validation fails on non-macOS platforms, helpful error messages are
  provided that include:

    * The detected operating system
    * Suggestions for alternative approaches
    * Links to documentation

  """

  alias ExMacOSControl.PlatformError

  @type os_type :: {atom(), atom()}
  @type version :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type version_comparison :: :lt | :eq | :gt

  ## Platform Detection

  @doc """
  Returns `true` if running on macOS, `false` otherwise.

  This function checks the OS type using `:os.type/0` and returns `true`
  only when the result is `{:unix, :darwin}`.

  ## Examples

      iex> ExMacOSControl.Platform.macos?()
      true  # On macOS

      iex> ExMacOSControl.Platform.macos?()
      false  # On Linux or other platforms

  """
  @spec macos? :: boolean()
  def macos? do
    os_type() == {:unix, :darwin}
  end

  @doc """
  Returns the current operating system type.

  This is a wrapper around `:os.type/0` that can be used for more detailed
  platform detection if needed.

  ## Examples

      iex> ExMacOSControl.Platform.os_type()
      {:unix, :darwin}  # On macOS

      iex> ExMacOSControl.Platform.os_type()
      {:unix, :linux}   # On Linux

  """
  @spec os_type :: os_type()
  def os_type do
    :os.type()
  end

  ## Platform Validation

  @doc """
  Validates that the current platform is macOS.

  Returns `:ok` if running on macOS, otherwise returns `{:error, PlatformError.t()}`.

  Use this function when you want to handle platform errors gracefully rather
  than raising an exception.

  ## Examples

      case ExMacOSControl.Platform.validate_macos() do
        :ok ->
          # Safe to proceed
          :ok

        {:error, error} ->
          Logger.error("Cannot run on this platform: \#{error.message}")
          {:error, :unsupported_platform}
      end

  """
  @spec validate_macos :: :ok | {:error, PlatformError.t()}
  def validate_macos do
    if macos?() do
      :ok
    else
      {:error, build_platform_error()}
    end
  end

  @doc """
  Validates that the current platform is macOS, raising an exception if not.

  Returns `:ok` if running on macOS, otherwise raises `ExMacOSControl.PlatformError`.

  Use this function when you want to fail fast on unsupported platforms,
  typically at the beginning of functions that absolutely require macOS.

  ## Examples

      def run_automation do
        ExMacOSControl.Platform.validate_macos!()
        # Rest of implementation - only executes on macOS
      end

  ## Errors

  Raises `ExMacOSControl.PlatformError` if not running on macOS.

  """
  @spec validate_macos! :: :ok
  def validate_macos! do
    if macos?() do
      :ok
    else
      raise build_platform_error()
    end
  end

  ## osascript Availability

  @doc """
  Checks if the `osascript` command is available on the system.

  Returns `true` if `osascript` can be found in the system PATH and is executable,
  `false` otherwise.

  On macOS, `osascript` should always be available as it's part of the base system.
  On other platforms, this will return `false`.

  ## Examples

      iex> ExMacOSControl.Platform.osascript_available?()
      true  # On macOS

      iex> ExMacOSControl.Platform.osascript_available?()
      false  # On Linux or if osascript is not installed

  """
  @spec osascript_available? :: boolean()
  def osascript_available? do
    case System.find_executable("osascript") do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Validates that the `osascript` command is available.

  Returns `:ok` if `osascript` is available, otherwise returns `{:error, PlatformError.t()}`.

  ## Examples

      case ExMacOSControl.Platform.validate_osascript() do
        :ok ->
          # Safe to execute AppleScript
          :ok

        {:error, error} ->
          Logger.error("osascript not available: \#{error.message}")
          {:error, :missing_osascript}
      end

  """
  @spec validate_osascript :: :ok | {:error, PlatformError.t()}
  def validate_osascript do
    if osascript_available?() do
      :ok
    else
      {:error, build_osascript_error()}
    end
  end

  @doc """
  Validates that the `osascript` command is available, raising an exception if not.

  Returns `:ok` if `osascript` is available, otherwise raises `ExMacOSControl.PlatformError`.

  ## Examples

      def execute_applescript(code) do
        ExMacOSControl.Platform.validate_osascript!()
        # Proceed with execution
      end

  ## Errors

  Raises `ExMacOSControl.PlatformError` if `osascript` is not available.

  """
  @spec validate_osascript! :: :ok
  def validate_osascript! do
    if osascript_available?() do
      :ok
    else
      raise build_osascript_error()
    end
  end

  ## macOS Version Detection

  @doc """
  Returns the current macOS version as a string.

  Returns `{:ok, version}` where version is a string like `"14.0"` or `"13.5.1"`,
  or `{:error, PlatformError.t()}` if not running on macOS or if the version
  cannot be determined.

  The version is obtained by executing the `sw_vers -productVersion` command.

  ## Examples

      iex> ExMacOSControl.Platform.macos_version()
      {:ok, "14.0"}

      # On non-macOS
      iex> ExMacOSControl.Platform.macos_version()
      {:error, %ExMacOSControl.PlatformError{}}

  """
  @spec macos_version :: {:ok, String.t()} | {:error, PlatformError.t()}
  def macos_version do
    if macos?() do
      case System.cmd("sw_vers", ["-productVersion"]) do
        {version, 0} ->
          {:ok, String.trim(version)}

        {_output, _status} ->
          {:error,
           %PlatformError{
             message: "Failed to determine macOS version",
             details: "sw_vers command failed"
           }}
      end
    else
      {:error,
       %PlatformError{
         message: "Cannot get macOS version: not running on macOS",
         os_type: os_type()
       }}
    end
  end

  @doc """
  Returns the current macOS version as a string, raising an exception if unavailable.

  Returns a version string like `"14.0"` or `"13.5.1"`, or raises
  `ExMacOSControl.PlatformError` if not running on macOS.

  ## Examples

      iex> ExMacOSControl.Platform.macos_version!()
      "14.0"

  ## Errors

  Raises `ExMacOSControl.PlatformError` if not running on macOS or if the
  version cannot be determined.

  """
  @spec macos_version! :: String.t()
  def macos_version! do
    case macos_version() do
      {:ok, version} -> version
      {:error, error} -> raise error
    end
  end

  @doc """
  Parses a macOS version string into a version tuple.

  Accepts version strings in formats like:
    * `"14.0"` -> `{14, 0, 0}`
    * `"13.5.1"` -> `{13, 5, 1}`
    * `"ProductVersion: 14.0"` -> `{14, 0, 0}` (from sw_vers output)

  Returns `{:ok, {major, minor, patch}}` on success, or `{:error, reason}` if
  the version string cannot be parsed.

  ## Examples

      iex> ExMacOSControl.Platform.parse_macos_version("14.0")
      {:ok, {14, 0, 0}}

      iex> ExMacOSControl.Platform.parse_macos_version("13.5.1")
      {:ok, {13, 5, 1}}

      iex> ExMacOSControl.Platform.parse_macos_version("ProductVersion: 14.0")
      {:ok, {14, 0, 0}}

      iex> ExMacOSControl.Platform.parse_macos_version("invalid")
      {:error, "Invalid version format"}

  """
  @spec parse_macos_version(String.t()) :: {:ok, version()} | {:error, String.t()}
  def parse_macos_version(version_string) when is_binary(version_string) do
    # Handle "ProductVersion: X.Y.Z" format from sw_vers
    version_string =
      version_string
      |> String.trim()
      |> String.replace(~r/^ProductVersion:\s*/, "")

    case String.split(version_string, ".") do
      [major] ->
        parse_version_parts([major, "0", "0"])

      [major, minor] ->
        parse_version_parts([major, minor, "0"])

      [major, minor, patch] ->
        parse_version_parts([major, minor, patch])

      _ ->
        {:error, "Invalid version format"}
    end
  end

  defp parse_version_parts([major, minor, patch]) do
    with {major_int, ""} <- Integer.parse(major),
         {minor_int, ""} <- Integer.parse(minor),
         {patch_int, ""} <- Integer.parse(patch) do
      {:ok, {major_int, minor_int, patch_int}}
    else
      _ -> {:error, "Invalid version format"}
    end
  end

  @doc """
  Compares two macOS version tuples.

  Returns:
    * `:gt` if the first version is greater than the second
    * `:lt` if the first version is less than the second
    * `:eq` if the versions are equal

  Versions can be provided as 1, 2, or 3-element tuples:
    * `{major}` is treated as `{major, 0, 0}`
    * `{major, minor}` is treated as `{major, minor, 0}`
    * `{major, minor, patch}` is used as-is

  ## Examples

      iex> ExMacOSControl.Platform.compare_version({14, 0, 0}, {13, 5, 1})
      :gt

      iex> ExMacOSControl.Platform.compare_version({13, 5, 1}, {14, 0, 0})
      :lt

      iex> ExMacOSControl.Platform.compare_version({14, 0, 0}, {14, 0, 0})
      :eq

      iex> ExMacOSControl.Platform.compare_version({14, 0}, {14, 0, 0})
      :eq

  """
  @spec compare_version(version() | tuple(), version() | tuple()) :: version_comparison()
  def compare_version(version1, version2) do
    v1 = normalize_version(version1)
    v2 = normalize_version(version2)

    cond do
      v1 > v2 -> :gt
      v1 < v2 -> :lt
      true -> :eq
    end
  end

  @doc """
  Checks if the current macOS version is at least the specified version.

  Returns `true` if running on macOS and the current version is greater than
  or equal to the specified version, `false` otherwise.

  The version can be specified as a 1, 2, or 3-element tuple:
    * `{major}` is treated as `{major, 0, 0}`
    * `{major, minor}` is treated as `{major, minor, 0}`
    * `{major, minor, patch}` is used as-is

  ## Examples

      iex> ExMacOSControl.Platform.version_at_least?({13, 0, 0})
      true  # If running macOS 13.0 or later

      iex> ExMacOSControl.Platform.version_at_least?({99, 0, 0})
      false  # Future version

      # On non-macOS
      iex> ExMacOSControl.Platform.version_at_least?({13, 0, 0})
      false

  """
  @spec version_at_least?(version() | tuple()) :: boolean()
  def version_at_least?(required_version) do
    case macos_version() do
      {:ok, version_string} ->
        case parse_macos_version(version_string) do
          {:ok, current_version} ->
            compare_version(current_version, required_version) in [:eq, :gt]

          {:error, _} ->
            false
        end

      {:error, _} ->
        false
    end
  end

  ## Private Helpers

  defp normalize_version({major}), do: {major, 0, 0}
  defp normalize_version({major, minor}), do: {major, minor, 0}
  defp normalize_version({major, minor, patch}), do: {major, minor, patch}

  defp build_platform_error do
    detected_os = os_type()

    message = """
    ExMacOSControl requires macOS to function.

    Detected OS: #{inspect(detected_os)}

    ExMacOSControl uses AppleScript and macOS-specific system commands that are
    only available on macOS. Please ensure you are running on macOS (darwin).

    If you need to run this code in a cross-platform application, you should
    check the platform first:

        if ExMacOSControl.Platform.macos?() do
          # Your macOS-specific code here
        end

    """

    %PlatformError{
      message: String.trim(message),
      os_type: detected_os
    }
  end

  defp build_osascript_error do
    message =
      if macos?() do
        """
        The osascript command was not found on your system.

        This is unusual for macOS, as osascript is part of the base system.
        Please check your system configuration and ensure that osascript is
        available in your PATH.
        """
      else
        """
        The osascript command is not available on this platform.

        osascript is a macOS-specific command for executing AppleScript and
        JavaScript for Automation (JXA). It is only available on macOS.

        Detected OS: #{inspect(os_type())}

        Please ensure you are running on macOS, or check the platform before
        attempting to use osascript:

            if ExMacOSControl.Platform.osascript_available?() do
              # Your osascript code here
            end
        """
      end

    %PlatformError{
      message: String.trim(message),
      os_type: os_type()
    }
  end
end
