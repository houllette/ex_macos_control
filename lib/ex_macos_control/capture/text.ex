defmodule ExMacOSControl.Capture.Text do
  @moduledoc "Immutable plain text with a title, source identity and capture time."
  @enforce_keys [:title, :text, :source, :captured_at]
  defstruct [:title, :text, :source, :captured_at]
end
