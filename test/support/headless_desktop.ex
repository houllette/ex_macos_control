defmodule ExMacOSControl.HeadlessDesktop do
  @moduledoc false
  @behaviour ExMacOSControl.Desktop.Session
  @impl true
  def snapshot(identities), do: {:ok, %{"apps" => Map.new(identities, &{&1, %{}}), "focus" => nil}}
  @impl true
  def prepare(_identity, _before), do: {:ok, []}
  @impl true
  def close(_ref), do: raise("Headless tests cannot acquire real UI")
  @impl true
  def restore(_before), do: :ok
end
