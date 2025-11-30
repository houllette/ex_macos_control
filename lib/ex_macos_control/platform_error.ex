defmodule ExMacOSControl.PlatformError do
  @moduledoc """
  Exception raised when platform requirements are not met.

  This exception is raised when ExMacOSControl is used on a non-macOS platform
  or when required commands (like `osascript`) are not available.

  ## Fields

    * `:message` - A human-readable error message describing the problem
    * `:os_type` - The detected OS type tuple from `:os.type/0` (optional)
    * `:details` - Additional details about the error (optional)

  ## Examples

      iex> raise ExMacOSControl.PlatformError, message: "Not on macOS"
      ** (ExMacOSControl.PlatformError) Not on macOS

      iex> raise ExMacOSControl.PlatformError,
      ...>   message: "Unsupported platform",
      ...>   os_type: {:unix, :linux}
      ** (ExMacOSControl.PlatformError) Unsupported platform

  """

  @type t :: %__MODULE__{
          message: String.t(),
          os_type: {atom(), atom()} | nil,
          details: String.t() | nil
        }

  defexception [:message, :os_type, :details]

  @impl true
  def exception(opts) when is_list(opts) do
    message = Keyword.get(opts, :message, "Platform error")
    os_type = Keyword.get(opts, :os_type)
    details = Keyword.get(opts, :details)

    %__MODULE__{
      message: message,
      os_type: os_type,
      details: details
    }
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message}
  end
end
