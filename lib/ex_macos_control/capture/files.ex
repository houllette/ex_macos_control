defmodule ExMacOSControl.Capture.Files do
  @moduledoc "A frozen Finder selection. Capturing paths does not copy or read their contents."
  @enforce_keys [:paths, :source, :captured_at]
  defstruct [:paths, :source, :captured_at]
end
