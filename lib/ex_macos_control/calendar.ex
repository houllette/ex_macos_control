defmodule ExMacOSControl.Calendar do
  @moduledoc "Calendar discovery and events scoped by calendar ID, with timezone-aware dates and recurrence text."
  alias ExMacOSControl.{Automation, Resources}
  @app "com.apple.iCal"
  @collection "byId(app.calendars, input.calendar_id).events"
  @schema [
    title: {"summary", :string},
    start_at: {"startDate", :date},
    end_at: {"endDate", :date},
    all_day: {"alldayEvent", :boolean},
    description: {"description", :string},
    location: {"location", :string},
    recurrence: {"recurrence", :string},
    url: {"url", :string}
  ]
  @alarm_types %{
    display: {"DisplayAlarm", "displayAlarms"},
    sound: {"SoundAlarm", "soundAlarms"},
    mail: {"MailAlarm", "mailAlarms"}
  }
  @alarm_schema [
    trigger_minutes: {"triggerInterval", :integer},
    trigger_at: {"triggerDate", :date},
    sound_name: {"soundName", :string},
    sound_file: {"soundFile", :string}
  ]

  def list_calendars(opts \\ []),
    do:
      Resources.list(
        @app,
        "app.calendars",
        [id: "o.calendarIdentifier()", name: "o.name()", writable: "o.writable()"],
        %{},
        opts
      )

  def create_calendar(name, opts \\ []) do
    with :ok <- Automation.required_string(name, "Calendar name") do
      Automation.query(
        @app,
        "var o=app.Calendar({name:input.name});app.calendars.push(o);return o.calendarIdentifier();",
        %{name: name},
        opts
      )
    end
  end

  def rename_calendar(id, name, opts \\ []) do
    with :ok <- Automation.required_string(name, "Calendar name") do
      Automation.action(
        @app,
        "var o=byId(app.calendars,input.id);if(!o.writable())throw new Error('Calendar is read-only');o.name=input.name;",
        %{id: id, name: name},
        opts
      )
    end
  end

  def delete_calendar(id, opts \\ []) do
    Automation.action(
      @app,
      "var o=byId(app.calendars,input.id);if(!o.writable())throw new Error('Calendar is read-only');app.delete(o);",
      %{id: id},
      opts
    )
  end

  def list_events(calendar_id, opts \\ []) do
    with :ok <- Automation.options(opts, [:from, :to, :limit, :offset, :timeout, :max_output_bytes]),
         {:ok, from} <- Automation.date(opts[:from]),
         {:ok, to} <- Automation.date(opts[:to]),
         {:ok, paging} <- Automation.page(opts) do
      body = """
      var values = #{@collection}();
      values = values.filter(function(o) { return (!input.from || o.endDate() >= new Date(input.from)) && (!input.to || o.startDate() <= new Date(input.to)); });
      values.sort(function(a,b) { return a.startDate() - b.startDate(); });
      return page(values).map(function(o) { return {id:o.uid(), title:o.summary(), start_at:iso(o.startDate()), end_at:iso(o.endDate()), all_day:o.alldayEvent(), location:o.location()}; });
      """

      Automation.query(
        @app,
        body,
        Map.merge(paging, %{calendar_id: calendar_id, from: from, to: to}),
        Automation.execution_options(opts)
      )
    end
  end

  def get_event(calendar_id, id, opts \\ []) do
    Automation.query(
      @app,
      "var o = #{@collection}.whose({uid: input.id})()[0]; if (!o) throw new Error('Object not found'); return {id:o.uid(),title:o.summary(),start_at:iso(o.startDate()),end_at:iso(o.endDate()),all_day:o.alldayEvent(),description:o.description(),location:o.location(),recurrence:o.recurrence(),url:o.url()};",
      %{calendar_id: calendar_id, id: id},
      opts
    )
  end

  def create_event(calendar_id, attrs, opts \\ []) do
    with :ok <- Automation.options(attrs, Keyword.keys(@schema)),
         :ok <- Automation.required_string(attrs[:title], "Event title"),
         {:ok, start_at} when not is_nil(start_at) <- Automation.date(attrs[:start_at]),
         {:ok, end_at} when not is_nil(end_at) <- Automation.date(attrs[:end_at]),
         true <-
           starts_before_end?(start_at, end_at),
         {:ok, properties, dates} <- Resources.properties(attrs, @schema) do
      Automation.query(
        @app,
        "input.dates.forEach(function(key) { input.properties[key] = new Date(input.properties[key]); }); var c=byId(app.calendars,input.calendar_id); if (!c.writable()) throw new Error('Calendar is read-only'); var o=app.Event(input.properties); c.events.push(o); return o.uid();",
        %{calendar_id: calendar_id, properties: properties, dates: dates},
        opts
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Event end must follow its start")
    end
  end

  def update_event(calendar_id, id, attrs, opts \\ []) do
    with {:ok, properties, dates} <- Resources.properties(attrs, @schema) do
      Automation.action(
        @app,
        """
        var c=byId(app.calendars,input.calendar_id); if (!c.writable()) throw new Error('Calendar is read-only');
        var o=c.events.whose({uid:input.id})()[0]; if (!o) throw new Error('Object not found');
        var start=input.properties.startDate ? new Date(input.properties.startDate) : o.startDate();
        var end=input.properties.endDate ? new Date(input.properties.endDate) : o.endDate();
        if (!(end > start)) throw new Error('Event end must follow its start');
        Object.keys(input.properties).forEach(function(key) { o[key]=input.dates.indexOf(key)>=0 ? new Date(input.properties[key]) : input.properties[key]; });
        """,
        %{calendar_id: calendar_id, id: id, properties: properties, dates: dates},
        opts
      )
    end
  end

  def delete_event(calendar_id, id, opts \\ []) do
    Automation.action(
      @app,
      "var c=byId(app.calendars,input.calendar_id); if (!c.writable()) throw new Error('Calendar is read-only'); var o=c.events.whose({uid:input.id})()[0]; if (!o) throw new Error('Object not found'); app.delete(o);",
      %{calendar_id: calendar_id, id: id},
      opts
    )
  end

  def list_attendees(calendar_id, id, opts \\ []) do
    Automation.query(
      @app,
      "var o=#{@collection}.whose({uid:input.id})()[0]; if (!o) throw new Error('Object not found'); return o.attendees().map(function(a) { return {name:a.displayName(),email:a.email(),status:a.participationStatus()}; });",
      %{calendar_id: calendar_id, id: id},
      opts
    )
  end

  @doc "Lists one alarm type with 1-based indices. Open-file alarms are unsupported by modern Calendar."
  def list_alarms(calendar_id, id, type \\ :display, opts \\ []) do
    with {:ok, {_constructor, collection}} <- alarm_type(type) do
      Automation.query(
        @app,
        "var event=byId(#{@collection},input.id);return event.#{collection}().map(function(a,i){return {index:i+1,trigger_minutes:a.triggerInterval(),trigger_at:iso(a.triggerDate())};});",
        %{calendar_id: calendar_id, id: id},
        opts
      )
    end
  end

  @doc "Creates a display, sound, or mail alarm with exactly one absolute or relative trigger. Returns its 1-based index."
  def create_alarm(calendar_id, id, type, attrs, opts \\ []) do
    with {:ok, {constructor, collection}} <- alarm_type(type),
         {:ok, properties, dates} <- alarm_properties(type, attrs) do
      Automation.query(
        @app,
        "var c=byId(app.calendars,input.calendar_id);if(!c.writable())throw new Error('Calendar is read-only');var event=byId(c.events,input.id);input.dates.forEach(function(k){input.properties[k]=new Date(input.properties[k]);});event.#{collection}.push(app.#{constructor}(input.properties));return event.#{collection}.length;",
        %{calendar_id: calendar_id, id: id, properties: properties, dates: dates},
        opts
      )
    end
  end

  def delete_alarm(calendar_id, id, type, index, opts \\ []) do
    with {:ok, {_constructor, collection}} <- alarm_type(type),
         true <- is_integer(index) and index > 0 do
      Automation.action(
        @app,
        "var c=byId(app.calendars,input.calendar_id);if(!c.writable())throw new Error('Calendar is read-only');var alarms=byId(c.events,input.id).#{collection};if(input.index>alarms.length)throw new Error('Alarm not found');app.delete(alarms[input.index-1]);",
        %{calendar_id: calendar_id, id: id, index: index},
        opts
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Alarm index must be positive")
    end
  end

  def show_event(calendar_id, id, opts \\ []),
    do: Automation.action(@app, "app.show(byId(#{@collection},input.id));", %{calendar_id: calendar_id, id: id}, opts)

  def view_date(date, opts \\ []) do
    case Automation.date(date) do
      {:ok, value} when not is_nil(value) ->
        Automation.action(@app, "app.viewCalendar({at:new Date(input.date)});", %{date: value}, opts)

      {:error, _} = error ->
        error

      _ ->
        Automation.invalid("View date is required")
    end
  end

  def switch_view(view, opts \\ []) when view in [:day, :week, :month],
    do: Automation.action(@app, "app.switchView({to:input.view});", %{view: to_string(view) <> " view"}, opts)

  defp alarm_type(type) do
    case Map.fetch(@alarm_types, type) do
      {:ok, spec} -> {:ok, spec}
      :error -> Automation.invalid("Alarm type must be :display, :sound, or :mail")
    end
  end

  defp alarm_properties(type, attrs) do
    schema = if type == :sound, do: @alarm_schema, else: Keyword.take(@alarm_schema, [:trigger_minutes, :trigger_at])

    with {:ok, properties, dates} <- Resources.properties(attrs, schema),
         true <- is_integer(attrs[:trigger_minutes]) != not is_nil(attrs[:trigger_at]) do
      {:ok, properties, dates}
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Alarm needs exactly one non-null trigger_minutes or trigger_at")
    end
  end

  defp starts_before_end?(start_at, end_at) do
    {:ok, start_date, _} = DateTime.from_iso8601(start_at)
    {:ok, end_date, _} = DateTime.from_iso8601(end_at)
    DateTime.compare(start_date, end_date) == :lt
  end
end
