defmodule ExMacOSControl.Capture.Message do
  @moduledoc "Immutable Mail message text and provenance; attachments are not downloaded."
  @enforce_keys [:subject, :sender, :content, :source, :captured_at]
  defstruct [:subject, :sender, :content, :source, :captured_at]
end
