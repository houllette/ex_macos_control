# Optional EventKit transport

`ExMacOSControl.Calendar` and `ExMacOSControl.Reminders` use Apple events.
`ExMacOSControl.EventKit.Calendar` and `ExMacOSControl.EventKit.Reminders` are an
explicit, optional native transport with separate permissions and identities.
The library never switches transports or retries a mutation through another one.

## Install the helper

The included Swift helper targets macOS 14 or later. Building requires Apple's
command-line developer tools (`xcrun`, `swiftc`, and `codesign`). Installation
compiles and ad-hoc signs a new `.app` bundle; ordinary app APIs never do this
automatically.

```elixir
alias ExMacOSControl.EventKit

helper_path = Path.expand("tmp/EventKitBridge.app")
{:ok, ^helper_path} = EventKit.install(helper_path, timeout: 120_000)
Application.put_env(:ex_macos_control, :eventkit_helper, helper_path)
```

Choose a stable new destination when using it beyond a local trial; replacing
the helper or changing its identity can affect macOS consent. Instead of global
configuration, pass `helper: helper_path` to individual EventKit calls. There is
no fallback if the configured helper is missing.

## Request entity access explicitly

```elixir
{:ok, status} = EventKit.status()
IO.inspect(status)

# Deliberate consent operations; run these from your logged-in macOS session.
EventKit.authorize(:event, timeout: 60_000)
EventKit.authorize(:reminder, timeout: 60_000)
```

`status/1` does not prompt. `authorize/2` requests full access for one entity and
may display macOS consent. Access belongs to the native helper, separately from
Automation permission for Calendar or Reminders.

## Discover and select native references

```elixir
alias ExMacOSControl.EventKit.Calendar, as: EKCalendar
alias ExMacOSControl.EventKit.Reminders, as: EKReminders

{:ok, calendars} = EKCalendar.list_calendars()
{:ok, lists} = EKReminders.list_lists()
{:ok, event_sources} = EventKit.sources(:event)
{:ok, reminder_sources} = EventKit.sources(:reminder)
```

Inspect returned records and select an appropriate writable resource. Records
include a `ref` containing an `%ExMacOSControl.EventKit.Reference{}`. Use that
reference for subsequent operations. Apple-event calendar/reminder IDs and URLs
are not interchangeable with EventKit references.

Creating a calendar or list requires a chosen source ID:
`EKCalendar.create_calendar/3` or `EKReminders.create_list/3`. The source must
support the operation; the library does not provision accounts.

## Create and observe an event

```elixir
defmodule NativeMeeting do
  alias ExMacOSControl.EventKit.Calendar, as: EKCalendar

  def create(calendar_ref, start_at, end_at) do
    EKCalendar.create_event(calendar_ref, [
      title: "Planning",
      body: "Review the next release",
      start_at: start_at,
      end_at: end_at,
      time_zone: "America/Denver"
    ], timeout: 15_000)
  end
end
```

Timestamps must be `DateTime` values or ISO 8601 strings with offsets. `time_zone`
is an IANA zone, defaulting to `"Etc/UTC"`; naive wall times are rejected.
The EventKit event body field is `:body`; the Apple-event Calendar wrapper uses
`:description`. Creation and updates read back the requested fields before
returning a record with its reference.

`EKCalendar.list_events(calendar_ref, from, to, opts)` requires an absolute,
positive time range no greater than 366 days. Creation supports bounded recurrence
with `:frequency`, `:interval`, and exactly one of `:count` or `:until`.
For example, add `recurrence: [frequency: :weekly, count: 4]` to event attributes.
Recurring updates and deletes require `scope: :occurrence` or `scope: :future`.
`:future` includes the selected occurrence and later occurrences, preserving the
past. References include calendar and occurrence identity; retain the returned
reference when an update changes an event's start time.

## Create and complete reminder batches

```elixir
defmodule NativeTasks do
  alias ExMacOSControl.EventKit.Reminders, as: EKReminders

  def create(list_ref) do
    EKReminders.create_many(list_ref, [
      [title: "Review notes", body: "Read the planning notes", priority: 5],
      [title: "Prepare agenda", priority: 1]
    ], timeout: 15_000)
  end
end
```

This transport supports `:title`, `:body`, and `:priority` for creation, plus
verified completion through `EKReminders.complete_many/2` with reminder
references. It does not mirror all fields of the Apple-event Reminders API;
due dates, alarms, and general update/delete operations are not exposed here.
Use the Apple-event wrapper when you need those fields, without mixing IDs.

Batches preserve acknowledged IDs on partial failure. EventKit writes and their
verification share a deadline and are never replayed automatically. An uncertain
write requires observation before another attempt. See
[captures and recovery](captures_and_recovery.md).
