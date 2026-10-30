defmodule ExMacOSControl.Safari.Page do
  @moduledoc """
  A Safari window ID and 1-based tab index. Owned pages use dedicated windows.

  Safari does not expose stable tab IDs. References become stale if tabs are
  closed or reordered. Operations on owned pages reject windows with additional
  tabs, including cleanup, so unrelated tabs are left available for recovery.
  """
  @enforce_keys [:window_id, :tab_index]
  defstruct [:window_id, :tab_index, :url, owned: false]

  @type t :: %__MODULE__{window_id: pos_integer(), tab_index: pos_integer(), url: String.t() | nil, owned: boolean()}
end
