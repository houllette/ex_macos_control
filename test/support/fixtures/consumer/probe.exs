defmodule ConsumerAdapter do
  @behaviour ExMacOSControl.Adapter
  def run_javascript(source), do: run_javascript(source, [])

  def run_javascript(source, opts) do
    input = Jason.decode!(hd(opts[:args]))

    Agent.get_and_update(ConsumerState, fn state ->
      {result, state} = dispatch(input, source, state)
      {{:ok, Jason.encode!(%{exmc: 1, result: result})}, state}
    end)
  end

  defp dispatch(%{"__bundle_id" => "com.apple.Safari", "code" => _}, _, state),
    do:
      {%{title: "", url: "https://fixture.invalid", text: "雪 <body>", selection: ""}, %{state | reads: state.reads + 1}}

  defp dispatch(%{"__bundle_id" => "com.apple.Safari"}, _, state),
    do: {%{window_id: 1, tab_index: 1, url: "https://fixture.invalid"}, %{state | reads: state.reads + 1}}

  defp dispatch(%{"__bundle_id" => app, "properties" => properties}, _, state) do
    id = "resource-#{length(state.writes) + 1}"
    {id, %{state | writes: state.writes ++ [%{id: id, app: app, properties: properties}]}}
  end

  def run_applescript(_), do: {:error, :unsupported}
  def run_applescript(_, _), do: {:error, :unsupported}
  def run_script_file(_, _), do: {:error, :unsupported}
  def run_shortcut(_), do: {:error, :unsupported}
  def run_shortcut(_, _), do: {:error, :unsupported}
  def list_shortcuts, do: {:error, :unsupported}
end

alias ExMacOSControl.{Capture, Composition, Notes, Reminders}
{:ok, _} = Agent.start_link(fn -> %{reads: 0, writes: []} end, name: ConsumerState)
Application.put_env(:ex_macos_control, :adapter, ConsumerAdapter)
{:ok, supervisor} = Task.Supervisor.start_link()
journal = Path.expand("tmp/journal")

{:ok, _} =
  Composition.run(
    fn ->
      {:ok, capture} = Capture.current_page()
      context = Composition.capture_context()

      note =
        Task.Supervisor.async(supervisor, fn ->
          Composition.with_context(context, fn ->
            if ExMacOSControl.execution_options()[:max_output_bytes] != 4000, do: raise("output limit lost")
            Composition.effect(:note, fn -> Notes.create_from(capture) end, resource: :note)
          end)
        end)

      {:ok, _} = Task.await(note)
      Composition.effect(:reminder, fn -> Reminders.create_from("explicit-list", capture) end, resource: :reminder)
    end,
    timeout: 5000,
    max_output_bytes: 4000,
    journal: journal
  )

state = Agent.get(ConsumerState, & &1)
if state.reads != 2 or length(state.writes) != 2, do: raise("source reread or destination missing")
if Enum.any?(state.writes, &(&1.properties["name"] != "https://fixture.invalid")), do: raise("title fallback lost")
[path] = Path.wildcard(Path.join(journal, "*.jsonl"))
{:ok, %{status: :complete, resources: resources}} = Composition.Journal.inspect_run(path)
if length(resources) != 2, do: raise("resource identity lost")
IO.puts(Jason.encode!(%{reads: state.reads, writes: length(state.writes), status: :passed}))
