defmodule ExMacOSControl.Capture.StagedFiles do
  @moduledoc """
  Private copied files and their SHA256 manifest. Staging compares source identity
  and two content reads, then verifies the copies. This detects observed changes;
  it is not an atomic filesystem snapshot. Copies contain file bytes, without
  extended attributes or resource forks. Verify again before handing paths to a
  destination. Cleanup refuses changed files, replaced directories and foreign entries.
  """
  @enforce_keys [:id, :root, :paths, :entries, :root_identity, :source, :captured_at, :staged_at]
  defstruct [:id, :root, :paths, :entries, :root_identity, :source, :captured_at, :staged_at]
end
