defmodule ExMacOSControl.OSAScriptAdapter do
  @behaviour ExMacOSControl.Adapter

  @impl true
  def run_applescript(script) do
    {output, exit} = System.cmd("osascript", ["-e", script])

    case exit do
      0 -> {:ok, String.trim(output)}
      _ -> {:error, {:exit_code, exit, output}}
    end
  end

  @impl true
  def run_shortcut(name) do
    script = ~s(tell application "Shortcuts Events" to run shortcut "#{name}")

    case run_applescript(script) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
