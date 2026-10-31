defmodule ExMacOSControl.Safari.Page do
  @moduledoc """
  A Safari window ID and 1-based tab index. Acquired pages also bind to the
  running PID and launch time. Owned pages use dedicated windows. pin_document/2
  additionally guards the URL and a per-document token, including same-URL reloads.

  Safari does not expose stable tab IDs. References become stale if tabs are
  closed or reordered. Operations on owned pages reject windows with additional
  tabs, including cleanup, so unrelated tabs are left available for recovery.
  """
  @enforce_keys [:window_id, :tab_index]
  defstruct [
    :window_id,
    :tab_index,
    :url,
    :application_pid,
    :application_started_at,
    :document_token,
    :expected_url,
    owned: false
  ]

  @type t :: %__MODULE__{
          window_id: pos_integer(),
          tab_index: pos_integer(),
          url: String.t() | nil,
          owned: boolean(),
          application_pid: pos_integer() | nil,
          application_started_at: number() | nil,
          document_token: String.t() | nil,
          expected_url: String.t() | nil
        }
end
