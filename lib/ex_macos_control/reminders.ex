defmodule ExMacOSControl.Reminders do
  @moduledoc "Accounts, lists and reminders with explicit list IDs, dates, priorities and completion state. For long GUI workflows, Applications.open/2 with background: true establishes normal UI startup; a launch-only app can automatically terminate without windows."
  alias ExMacOSControl.{Automation, Composition, Error, Resources, Validation}
  @app "com.apple.reminders"
  @fields [
    id: "o.id()",
    title: "o.name()",
    body: "o.body()",
    completed: "o.completed()",
    due_at: "iso(o.dueDate())",
    reminder_at: "iso(o.remindMeDate())",
    priority: "o.priority()",
    flagged: "o.flagged()"
  ]
  @schema [
    title: {"name", :string},
    body: {"body", :string},
    completed: {"completed", :boolean},
    due_at: {"dueDate", :date},
    reminder_at: {"remindMeDate", :date},
    priority: {"priority", :integer},
    flagged: {"flagged", :boolean}
  ]
  def list_accounts(opts \\ []), do: Resources.list(@app, "app.accounts", [id: "o.id()", name: "o.name()"], %{}, opts)
  def list_lists(opts \\ []), do: Resources.list(@app, "app.lists", [id: "o.id()", name: "o.name()"], %{}, opts)

  def list_reminders(list_id, opts \\ []) do
    with :ok <- Automation.options(opts, [:limit, :offset, :timeout, :max_output_bytes]),
         {:ok, paging} <- Automation.page(opts) do
      Automation.query(
        @app,
        """
        var r=byId(app.lists,input.list_id).reminders;
        var columns={id:r.id(),title:r.name(),body:r.body(),completed:r.completed(),
          due_at:r.dueDate(),reminder_at:r.remindMeDate(),priority:r.priority(),flagged:r.flagged()};
        var keys=Object.keys(columns),ids=columns.id;
        if(keys.some(function(k){return columns[k].length!==ids.length;}) || JSON.stringify(ids)!==JSON.stringify(r.id()))
          throw new Error('Reminder list changed during bulk read');
        var indices=ids.map(function(id,i){return i;});
        return page(indices).map(function(i){var row={};keys.forEach(function(k){row[k]=(k==='due_at'||k==='reminder_at')?iso(columns[k][i]):columns[k][i];});return row;});
        """,
        Map.put(paging, :list_id, list_id),
        Automation.execution_options(opts)
      )
    end
  end

  def get_reminder(id, opts \\ []) do
    with :ok <- Automation.options(opts, [:list_id, :timeout, :max_output_bytes]),
         :ok <- optional_list(opts[:list_id]) do
      Resources.get(
        @app,
        reminder_collection(opts[:list_id]),
        @fields,
        id,
        %{list_id: opts[:list_id]},
        Keyword.delete(opts, :list_id)
      )
    end
  end

  def create_reminder(list_id, attrs, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "List ID"),
         :ok <- Automation.options(attrs, Keyword.keys(@schema)),
         :ok <- Automation.required_string(attrs[:title], "Reminder title"),
         :ok <- priority(attrs) do
      Resources.create(
        @app,
        "byId(app.lists, input.list_id).reminders",
        "Reminder",
        @schema,
        attrs,
        %{list_id: list_id},
        opts
      )
    end
  end

  def update_reminder(id, attrs, opts \\ []) do
    with :ok <- Automation.options(opts, [:list_id, :timeout, :max_output_bytes]),
         :ok <- optional_list(opts[:list_id]),
         :ok <- priority(attrs) do
      Resources.update(
        @app,
        reminder_collection(opts[:list_id]),
        @schema,
        id,
        attrs,
        %{list_id: opts[:list_id]},
        Keyword.delete(opts, :list_id)
      )
    end
  end

  def complete_reminder(id, opts \\ []), do: update_reminder(id, [completed: true], opts)
  @doc "Creates a Reminder from captured text, retaining page URLs and selected text."
  def create_from(list_id, capture, opts \\ []) do
    with :ok <- Automation.options(opts, Keyword.keys(@schema) ++ [:timeout, :max_output_bytes]) do
      attrs =
        opts
        |> Keyword.take(Keyword.keys(@schema))
        |> Keyword.put_new(:title, ExMacOSControl.Capture.title(capture))
        |> Keyword.put_new(:body, ExMacOSControl.Capture.render(capture, :reference))

      create_reminder(list_id, attrs, Keyword.take(opts, [:timeout, :max_output_bytes]))
    end
  end

  def delete_reminder(id, opts \\ []) do
    with :ok <- Automation.options(opts, [:list_id, :timeout, :max_output_bytes]),
         :ok <- optional_list(opts[:list_id]) do
      Resources.delete(
        @app,
        reminder_collection(opts[:list_id]),
        id,
        %{list_id: opts[:list_id]},
        Keyword.delete(opts, :list_id)
      )
    end
  end

  def create_list(name, opts \\ []) do
    with :ok <- Automation.options(opts, [:account_id, :timeout, :max_output_bytes]),
         :ok <- Automation.required_string(name, "List name") do
      collection =
        if opts[:account_id], do: "byId(app.accounts,input.account_id).lists", else: "app.defaultAccount().lists"

      Resources.create(
        @app,
        collection,
        "List",
        [name: {"name", :string}],
        [name: name],
        %{account_id: opts[:account_id]},
        Automation.execution_options(opts)
      )
    end
  end

  def rename_list(id, name, opts \\ []) do
    with :ok <- Automation.required_string(name, "List name") do
      Resources.update(@app, "app.lists", [name: {"name", :string}], id, [name: name], %{}, opts)
    end
  end

  def delete_list(id, opts \\ []), do: Resources.delete(@app, "app.lists", id, %{}, opts)

  @doc "Creates a validated batch in order. Errors retain IDs created before a later failure."
  def create_many(list_id, items, opts \\ []) do
    with :ok <- Automation.required_string(list_id, "List ID"),
         :ok <- Validation.items(items),
         :ok <- Validation.all(items, &validate_reminder/1) do
      Composition.run(
        fn ->
          Composition.map_effects(items, :create_reminder, &create_reminder(list_id, &1),
            resource: :reminder,
            identity: %{list_id: list_id}
          )
        end,
        opts
      )
    end
  end

  @doc """
  Completes explicit reminder IDs once. With list_id, one native batch targets
  at most 10 unique IDs at a time and reads back completion state. Small chunks
  retain acknowledged progress when large accounts exhaust the total budget. Durable intent includes every
  requested ID; an interrupted batch requires observation, never replay.
  """
  def complete_many(ids, opts \\ []) do
    with :ok <- Automation.options(opts, [:list_id, :timeout, :max_output_bytes, :trace_to, :journal, :run_id]),
         :ok <- optional_list(opts[:list_id]),
         :ok <- Validation.items(ids),
         :ok <- Validation.all(ids, &Automation.required_string(&1, "Reminder ID")),
         :ok <- unique_ids(ids) do
      Composition.run(
        fn -> do_complete_many(ids, opts[:list_id]) end,
        Keyword.delete(opts, :list_id)
      )
    end
  end

  defp validate_reminder(attrs) do
    with :ok <- priority(attrs),
         :ok <- Automation.required_string(attrs[:title], "Reminder title"),
         {:ok, _, _} <- Resources.properties(attrs, @schema),
         do: :ok
  end

  defp priority(attrs) do
    with :ok <- Automation.options(attrs, Keyword.keys(@schema)) do
      if Keyword.get(attrs, :priority, 0) in 0..9,
        do: :ok,
        else: Automation.invalid("Priority must be an integer from 0 to 9")
    end
  end

  defp optional_list(nil), do: :ok
  defp optional_list(id), do: Automation.required_string(id, "List ID")

  defp reminder_collection(nil), do: "app.reminders"
  defp reminder_collection(_id), do: "byId(app.lists,input.list_id).reminders"

  defp unique_ids(ids) do
    if Enum.uniq(ids) == ids, do: :ok, else: Automation.invalid("Reminder IDs must be distinct")
  end

  defp do_complete_many(ids, list_id) do
    if list_id, do: complete_scoped(ids, list_id), else: complete_individually(ids)
  end

  defp complete_scoped(ids, list_id) do
    with {:ok, _} <- Composition.map(Enum.chunk_every(ids, 10), :complete_chunk, &complete_scoped_chunk(&1, list_id)),
         do: {:ok, ids}
  end

  defp complete_scoped_chunk(ids, list_id) do
    with {:ok, _} <-
           Composition.effect(:complete_reminders, fn -> native_complete(ids, list_id) end,
             resource: :reminder,
             identity: %{list_id: list_id, ids: ids}
           ),
         :ok <- Composition.verify(:completed_reminders, &completed?(ids, list_id, &1)) do
      {:ok, ids}
    end
  end

  defp native_complete(ids, list_id) do
    source = """
    on run argv
      tell application id "com.apple.reminders"
        try
          set targetList to first list whose id is item 1 of argv
          set wantedIDs to items 2 thru -1 of argv
          set knownIDs to id of every reminder of targetList
          repeat with wantedID in wantedIDs
            if knownIDs does not contain (wantedID as text) then return "EXMC_MISSING"
          end repeat
        on error messageText number errorNumber
          return "EXMC_PREFLIGHT:" & (errorNumber as text)
        end try
        repeat with wantedID in wantedIDs
          set completed of reminder id (wantedID as text) of targetList to true
        end repeat
        return count of wantedIDs
      end tell
    end run
    """

    case ExMacOSControl.run_applescript(source, args: [list_id | ids]) do
      {:ok, "EXMC_MISSING"} ->
        {:error, Error.not_found("Reminder IDs are missing or duplicated in the specified list", outcome: :not_started)}

      {:ok, "EXMC_PREFLIGHT:" <> code} ->
        {:error, completion_preflight_error(code)}

      {:ok, value} ->
        if String.trim(value) == Integer.to_string(length(ids)),
          do: {:ok, ids},
          else: {:error, Error.execution_error("Reminder batch identity changed during completion", outcome: :unknown)}

      error ->
        error
    end
  end

  defp completion_preflight_error("-1712"),
    do: Error.timeout("Reminders completion preflight", outcome: :not_started, error_code: -1712)

  defp completion_preflight_error("-1728"),
    do: Error.not_found("Reminder list is unavailable", outcome: :not_started, error_code: -1728)

  defp completion_preflight_error("-1743"),
    do: Error.permission_denied("Reminders completion preflight", outcome: :not_started, error_code: -1743)

  defp completion_preflight_error(code),
    do: Error.execution_error("Reminders completion preflight failed", outcome: :not_started, native_error_code: code)

  defp completed?(ids, list_id, remaining) do
    Automation.query(
      @app,
      """
      var r=byId(app.lists,input.list_id).reminders, ids=r.id(), flags=r.completed();
      if(ids.length!==flags.length || JSON.stringify(ids)!==JSON.stringify(r.id()))return false;
      return input.ids.every(function(id){var index=ids.indexOf(id);return index>=0&&flags[index]===true;});
      """,
      %{list_id: list_id, ids: ids},
      timeout: remaining
    )
  end

  defp complete_individually(ids) do
    Composition.map_effects(
      ids,
      :complete_reminder,
      fn id ->
        with :ok <- complete_reminder(id), do: {:ok, id}
      end,
      resource: :reminder,
      identity: fn id -> %{id: id} end
    )
  end
end
