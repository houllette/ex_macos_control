import Foundation
import EventKit

func instant(_ value: Any?) throws -> Date {
    guard let value = value as? String else { throw BridgeFailure("execution_error", "Expected an absolute timestamp") }
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = format.date(from: value) { return date }
    format.formatOptions = [.withInternetDateTime]
    guard let date = format.date(from: value) else { throw BridgeFailure("execution_error", "Invalid absolute timestamp") }
    return date
}

func timestamp(_ date: Date) -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.string(from: date)
}

extension Bridge {
    func eventReference(_ event: EKEvent) -> [String: Any] {
        var ref: [String: Any] = ["backend": "eventkit", "kind": "event", "id": event.eventIdentifier ?? "",
            "calendar_id": event.calendar.calendarIdentifier, "start_at": timestamp(event.startDate),
            "occurrence_at": timestamp(event.occurrenceDate ?? event.startDate)]
        if let external = event.calendarItemExternalIdentifier { ref["external_id"] = external }
        return ref
    }

    func eventData(_ event: EKEvent) -> [String: Any] {
        return ["ref": eventReference(event), "title": event.title ?? "", "body": event.notes ?? "",
            "location": event.location ?? "", "url": event.url?.absoluteString ?? "",
            "start_at": timestamp(event.startDate), "end_at": timestamp(event.endDate),
            "time_zone": event.timeZone?.identifier ?? "", "all_day": event.isAllDay,
            "recurrence": event.hasRecurrenceRules, "detached": event.isDetached]
    }

    func event(_ value: Any?) throws -> EKEvent {
        guard let ref = value as? [String: Any], ref["backend"] as? String == "eventkit", ref["kind"] as? String == "event" else {
            throw BridgeFailure("execution_error", "Expected a typed EventKit event reference")
        }
        let id = try text(ref["id"], "event ID"), calendarID = try text(ref["calendar_id"], "calendar ID")
        let start = try instant(ref["start_at"]), occurrence = try instant(ref["occurrence_at"])
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw BridgeFailure("not_found", "Calendar no longer exists") }
        // EventKit can collapse a predicate confined to a repeated DST hour. Fetch a
        // surrounding day, then select the exact absolute instant and identity.
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-86400), end: start.addingTimeInterval(86400), calendars: [calendar])
        let matches = store.events(matching: predicate).filter {
            $0.eventIdentifier == id && abs($0.startDate.timeIntervalSince(start)) < 0.001 &&
            abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince(occurrence)) < 0.001 &&
            (ref["external_id"] == nil || $0.calendarItemExternalIdentifier == ref["external_id"] as? String)
        }
        guard matches.count == 1 else { throw BridgeFailure("not_found", "Event occurrence identity changed or is ambiguous") }
        return matches[0]
    }

    func eventAttributes(_ value: Any?) throws -> [String: Any] {
        guard let attrs = value as? [String: Any], Set(attrs.keys).isSubset(of: ["title", "body", "location", "url", "start_at", "end_at", "all_day", "time_zone"]) else {
            throw BridgeFailure("execution_error", "Unknown event fields")
        }
        _ = try text(attrs["title"], "event title")
        let start = try instant(attrs["start_at"]), end = try instant(attrs["end_at"])
        guard end > start, end.timeIntervalSince(start) <= 366 * 86400,
              let zone = attrs["time_zone"] as? String, TimeZone(identifier: zone) != nil,
              attrs["all_day"] is Bool else { throw BridgeFailure("execution_error", "Invalid event interval or time zone") }
        for key in ["body", "location", "url"] {
            guard attrs[key] is String else { throw BridgeFailure("execution_error", "Invalid event text fields") }
        }
        if let url = attrs["url"] as? String, !url.isEmpty {
            guard let parsed = URL(string: url), parsed.scheme != nil else { throw BridgeFailure("execution_error", "Invalid event URL") }
        }
        return attrs
    }

    func applyEvent(_ attrs: [String: Any], to item: EKEvent) throws {
        item.title = attrs["title"] as? String; item.notes = attrs["body"] as? String
        item.location = attrs["location"] as? String
        item.url = (attrs["url"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        item.timeZone = TimeZone(identifier: attrs["time_zone"] as! String)
        item.isAllDay = attrs["all_day"] as! Bool
        item.startDate = try instant(attrs["start_at"]); item.endDate = try instant(attrs["end_at"])
    }

    func calendarOperation(_ op: String, _ input: [String: Any]) throws -> Any {
        try requireAccess(.event)
        switch op {
        case "events":
            let target = try calendar(input["calendar"], kind: .event)
            let from = try instant(input["from"]), to = try instant(input["to"])
            guard to > from, to.timeIntervalSince(from) <= 366 * 86400 else { throw BridgeFailure("execution_error", "Calendar reads require a range of at most 366 days") }
            let values = store.events(matching: store.predicateForEvents(withStart: from.addingTimeInterval(-86400), end: to.addingTimeInterval(86400), calendars: [target])).filter { $0.endDate > from && $0.startDate < to }
            guard values.count <= 1000 else { throw BridgeFailure("execution_error", "Range exceeds the 1000-event result bound") }
            return values.sorted { $0.startDate < $1.startDate }.map(eventData)
        case "get_event": return eventData(try event(input["ref"]))
        case "create_event":
            let attrs = try eventAttributes(input["attributes"])
            let target = try calendar(input["calendar"], kind: .event); try writable(target)
            let item = EKEvent(eventStore: store); item.calendar = target; try applyEvent(attrs, to: item)
            try store.save(item, span: .thisEvent, commit: false); try commit(); return eventData(item)
        case "update_event":
            let attrs = try eventAttributes(input["attributes"]), item = try event(input["ref"])
            try writable(item.calendar)
            guard !item.hasRecurrenceRules && !item.isDetached else { throw BridgeFailure("execution_error", "Recurring changes require an explicit occurrence scope") }
            try applyEvent(attrs, to: item)
            try store.save(item, span: .thisEvent, commit: false); try commit(); return eventData(item)
        case "delete_event":
            let item = try event(input["ref"]); try writable(item.calendar)
            guard !item.hasRecurrenceRules && !item.isDetached else { throw BridgeFailure("execution_error", "Recurring deletion requires an explicit occurrence scope") }
            try store.remove(item, span: .thisEvent, commit: false); try commit(); return true
        default: throw BridgeFailure("execution_error", "Unknown EventKit operation")
        }
    }
}
