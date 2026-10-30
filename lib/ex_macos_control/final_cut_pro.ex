defmodule ExMacOSControl.FinalCutPro do
  @moduledoc "Reads Final Cut Pro library, event, project and sequence identities. Its scripting surface does not provide general timeline editing."
  alias ExMacOSControl.{Automation, Resources}
  @app "com.apple.FinalCut"
  @projects "byId(byId(app.libraries,input.library_id).events,input.event_id).projects"
  def list_libraries(opts \\ []), do: Resources.list(@app, "app.libraries", [id: "o.id()", name: "o.name()"], %{}, opts)

  def list_events(library_id, opts \\ []),
    do:
      Resources.list(
        @app,
        "byId(app.libraries,input.library_id).events",
        [id: "o.id()", name: "o.name()"],
        %{library_id: library_id},
        opts
      )

  def list_projects(library_id, event_id, opts \\ []),
    do:
      Resources.list(
        @app,
        @projects,
        [id: "o.id()", name: "o.name()"],
        %{library_id: library_id, event_id: event_id},
        opts
      )

  def get_project(library_id, event_id, id, opts \\ []),
    do:
      Resources.get(
        @app,
        @projects,
        [id: "o.id()", name: "o.name()", essential_properties: "o.essentialProperties()"],
        id,
        %{library_id: library_id, event_id: event_id},
        opts
      )

  def get_sequence(library_id, event_id, project_id, opts \\ []) do
    Automation.query(
      @app,
      "var o=byId(#{@projects},input.id).sequence();return {id:o.id(),name:o.name(),start_time:o.startTime(),duration:o.duration(),frame_duration:o.frameDuration(),timecode_format:o.timecodeFormat(),essential_properties:o.essentialProperties()};",
      %{library_id: library_id, event_id: event_id, id: project_id},
      opts
    )
  end
end
