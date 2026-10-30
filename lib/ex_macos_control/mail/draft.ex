defmodule ExMacOSControl.Mail.Draft do
  @moduledoc """
  A verified saved message in Mail's Drafts mailbox. Its id addresses the saved
  message; outgoing_id is the transient compose object returned during creation.
  Subject and message_id are checked before reading or deleting through this reference.
  """
  @enforce_keys [:id, :outgoing_id, :subject, :created_at]
  defstruct [:id, :outgoing_id, :subject, :message_id, :created_at]
  @type t :: %__MODULE__{}
end
