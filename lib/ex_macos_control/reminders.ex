defmodule ExMacOSControl.Reminders do
  @moduledoc "Accounts, lists and reminders with explicit list IDs, dates, priorities and completion state."
  alias ExMacOSControl.{Automation, Composition, Resources, Validation}
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

  def list_reminders(list_id, opts \\ []),
    do: Resources.list(@app, "byId(app.lists, input.list_id).reminders", @fields, %{list_id: list_id}, opts)

  def get_reminder(id, opts \\ []), do: Resources.get(@app, "app.reminders", @fields, id, %{}, opts)

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
    with :ok <- priority(attrs), do: Resources.update(@app, "app.reminders", @schema, id, attrs, %{}, opts)
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

  def delete_reminder(id, opts \\ []), do: Resources.delete(@app, "app.reminders", id, %{}, opts)

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
      Composition.run(fn -> Composition.map(items, :create_reminder, &create_reminder(list_id, &1)) end, opts)
    end
  end

  @doc "Completes a batch of explicit reminder IDs without retrying mutations."
  def complete_many(ids, opts \\ []) do
    with :ok <- Validation.items(ids),
         :ok <- Validation.all(ids, &Automation.required_string(&1, "Reminder ID")) do
      Composition.run(
        fn -> do_complete_many(ids) end,
        opts
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

  defp do_complete_many(ids) do
    Composition.map(ids, :complete_reminder, fn id ->
      with :ok <- complete_reminder(id), do: {:ok, id}
    end)
  end
end
