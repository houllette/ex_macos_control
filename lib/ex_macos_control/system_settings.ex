defmodule ExMacOSControl.SystemSettings do
  @moduledoc "Discovers and reveals System Settings panes and anchors. Individual setting toggles are not a universal scripting API."
  alias ExMacOSControl.{Automation, Resources}
  @app "com.apple.systempreferences"
  def list_panes(opts \\ []), do: Resources.list(@app, "app.panes", [id: "o.id()", name: "o.name()"], %{}, opts)

  def list_anchors(id, opts \\ []),
    do: Resources.list(@app, "byId(app.panes,input.id).anchors", [name: "o.name()"], %{id: id}, opts)

  def reveal(id, opts \\ []) do
    with :ok <- Automation.required_string(id, "Pane ID"),
         :ok <- Automation.options(opts, [:anchor, :timeout, :max_output_bytes]) do
      Automation.action(
        @app,
        "var pane=byId(app.panes,input.id); var target=input.anchor?pane.anchors.byName(input.anchor):pane; app.reveal(target); app.activate();",
        %{id: id, anchor: opts[:anchor]},
        Automation.execution_options(opts)
      )
    end
  end
end
