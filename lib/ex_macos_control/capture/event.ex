defmodule ExMacOSControl.Capture.Event do
  @moduledoc "Immutable Calendar event details and original calendar/event identities."
  @enforce_keys [:title, :start_at, :end_at, :source, :captured_at]
  defstruct [:title, :start_at, :end_at, :location, :description, :url, :source, :captured_at]
end
