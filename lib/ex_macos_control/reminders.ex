defmodule ExMacOSControl.Reminders do
  @moduledoc "Accounts, lists and reminders with explicit list IDs, dates, priorities and completion state."
  alias ExMacOSControl.{Automation, Resources}
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

  defp priority(attrs) do
    with :ok <- Automation.options(attrs, Keyword.keys(@schema)) do
      if Keyword.get(attrs, :priority, 0) in 0..9,
        do: :ok,
        else: Automation.invalid("Priority must be an integer from 0 to 9")
    end
  end
end
