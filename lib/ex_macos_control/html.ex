defmodule ExMacOSControl.HTML do
  @moduledoc false
  def escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
    |> String.replace("\n", "<br>")
  end
end
