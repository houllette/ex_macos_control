defmodule ExMacOSControl.Capture.Event do
  @moduledoc "Immutable Calendar event details and original calendar/event identities."
  @enforce_keys [:title, :start_at, :end_at, :source, :captured_at]
  defstruct [:title, :start_at, :end_at, :all_day, :recurrence, :location, :description, :url, :source, :captured_at]
end
