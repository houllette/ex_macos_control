defmodule ExMacOSControl.Capture.Page do
  @moduledoc "Immutable Safari content and its original target identity."
  @enforce_keys [:title, :url, :text, :selection, :source, :captured_at]
  defstruct [:title, :url, :text, :selection, :source, :captured_at]
end
