import Foundation
import EventKit

struct BridgeFailure: Error {
    let type: String
    let message: String
    init(_ type: String, _ message: String) { self.type = type; self.message = message }
}

func text(_ value: Any?, _ name: String) throws -> String {
    guard let result = value as? String, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !result.contains("\0"), result.utf8.count <= 4096 else {
        throw BridgeFailure("execution_error", "Invalid \(name)")
    }
    return result
}

func rows(_ value: Any?) throws -> [[String: Any]] {
    guard let result = value as? [[String: Any]], !result.isEmpty, result.count <= 1000 else {
        throw BridgeFailure("execution_error", "Expected 1 through 1000 items")
    }
    return result
}

func statusName(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "not_determined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .fullAccess: return "full_access"
    case .writeOnly: return "write_only"
    @unknown default: return "unknown"
    }
}

func entity(_ value: Any?) throws -> EKEntityType {
    switch value as? String {
    case "event": return .event
    case "reminder": return .reminder
    default: throw BridgeFailure("execution_error", "Unknown entity")
    }
}

func awaitResult<T>(_ start: (@escaping (T) -> Void) -> Void) -> T {
    var result: T?
    let lock = NSLock()
    start { value in lock.lock(); result = value; lock.unlock() }
    while true {
        lock.lock(); let snapshot = result; lock.unlock()
        if let snapshot = snapshot { return snapshot }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
}

final class Bridge {
    lazy var store = EKEventStore()
    var mutationStarted = false

    func requireAccess(_ kind: EKEntityType) throws {
        guard EKEventStore.authorizationStatus(for: kind) == .fullAccess else {
            throw BridgeFailure("permission_denied", "Full EventKit access is required; request it explicitly")
        }
    }

    func reference(_ calendar: EKCalendar, _ kind: String) -> [String: Any] {
        return ["backend": "eventkit", "kind": kind, "id": calendar.calendarIdentifier]
    }

    func reference(_ reminder: EKReminder) -> [String: Any] {
        var value: [String: Any] = ["backend": "eventkit", "kind": "reminder", "id": reminder.calendarItemIdentifier,
                                   "calendar_id": reminder.calendar.calendarIdentifier]
        if let external = reminder.calendarItemExternalIdentifier { value["external_id"] = external }
        return value
    }

    func reminderData(_ reminder: EKReminder) -> [String: Any] {
        return ["ref": reference(reminder), "title": reminder.title ?? "", "body": reminder.notes ?? "",
                "completed": reminder.isCompleted, "priority": reminder.priority]
    }

    func calendar(_ value: Any?, kind: EKEntityType) throws -> EKCalendar {
        guard let ref = value as? [String: Any], ref["backend"] as? String == "eventkit",
              ref["kind"] as? String == (kind == .event ? "calendar" : "reminder_list") else {
            throw BridgeFailure("execution_error", "Expected a typed EventKit calendar reference")
        }
        let id = try text(ref["id"], "calendar ID")
        guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(kind == .event ? .event : .reminder) else {
            throw BridgeFailure("not_found", "EventKit calendar is missing or belongs to another entity")
        }
        return calendar
    }

    func writable(_ calendar: EKCalendar) throws {
        guard calendar.allowsContentModifications else { throw BridgeFailure("permission_denied", "Calendar is read-only") }
    }

    func reminder(_ ref: [String: Any]) throws -> EKReminder {
        guard ref["backend"] as? String == "eventkit", ref["kind"] as? String == "reminder" else {
            throw BridgeFailure("execution_error", "Expected a typed EventKit reminder reference")
        }
        let id = try text(ref["id"], "reminder ID")
        let calendarID = try text(ref["calendar_id"], "calendar ID")
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder,
              item.calendar.calendarIdentifier == calendarID else {
            throw BridgeFailure("not_found", "Reminder identity or calendar changed")
        }
        if let external = ref["external_id"] as? String, item.calendarItemExternalIdentifier != external {
            throw BridgeFailure("not_found", "Reminder external identity changed")
        }
        return item
    }

    func commit() throws {
        mutationStarted = true; try store.commit()
        // A one-shot client must service deferred EventKit change delivery before exit.
        // State is independently verified by the caller; this is not a retry.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    }

    func run(_ op: String, _ input: [String: Any]) throws -> Any {
        switch op {
        case "status":
            return ["event": statusName(EKEventStore.authorizationStatus(for: .event)),
                    "reminder": statusName(EKEventStore.authorizationStatus(for: .reminder))]
        case "authorize":
            let kind = try entity(input["entity"])
            let value: (Bool, Error?) = awaitResult { done in
                if kind == .event { store.requestFullAccessToEvents { done(($0, $1)) } }
                else { store.requestFullAccessToReminders { done(($0, $1)) } }
            }
            guard value.0 else { throw BridgeFailure("permission_denied", "EventKit access was not granted") }
            return ["entity": kind == .event ? "event" : "reminder", "status": statusName(EKEventStore.authorizationStatus(for: kind))]
        case "sources":
            let kind = try entity(input["entity"]); try requireAccess(kind)
            let defaultSource = kind == .event ? store.defaultCalendarForNewEvents?.source.sourceIdentifier : store.defaultCalendarForNewReminders()?.source.sourceIdentifier
            return store.sources.map { ["id": $0.sourceIdentifier, "name": $0.title, "type": $0.sourceType.rawValue,
                                        "default": $0.sourceIdentifier == defaultSource] as [String: Any] }
        case "calendars":
            let kind = try entity(input["entity"]); try requireAccess(kind)
            return store.calendars(for: kind).map { ["ref": reference($0, kind == .event ? "calendar" : "reminder_list"),
                "name": $0.title, "source_id": $0.source.sourceIdentifier, "writable": $0.allowsContentModifications] as [String: Any] }
        case "create_calendar":
            let kind = try entity(input["entity"]); try requireAccess(kind)
            let title = try text(input["name"], "calendar name"), sourceID = try text(input["source_id"], "source ID")
            guard let source = store.sources.first(where: { $0.sourceIdentifier == sourceID }) else { throw BridgeFailure("not_found", "Source not found") }
            let item = EKCalendar(for: kind, eventStore: store); item.title = title; item.source = source
            try store.saveCalendar(item, commit: false); try commit()
            return ["ref": reference(item, kind == .event ? "calendar" : "reminder_list"), "name": item.title]
        case "delete_calendar":
            let kind = try entity(input["entity"]); try requireAccess(kind)
            let item = try calendar(input["ref"], kind: kind); try writable(item)
            try store.removeCalendar(item, commit: false); try commit(); return true
        case "create_reminders":
            try requireAccess(.reminder)
            let target = try calendar(input["list"], kind: .reminder); try writable(target)
            let items = try rows(input["items"])
            // Validate every item before staging any changes.
            for item in items {
                _ = try text(item["title"], "reminder title")
                if let priority = item["priority"], !(priority is Int && (0...9).contains(priority as! Int)) { throw BridgeFailure("execution_error", "Invalid priority") }
                if let body = item["body"], !(body is String) { throw BridgeFailure("execution_error", "Invalid reminder body") }
                guard Set(item.keys).isSubset(of: ["title", "body", "priority"]) else { throw BridgeFailure("execution_error", "Unknown reminder fields") }
            }
            var created: [EKReminder] = []
            for data in items {
                let item = EKReminder(eventStore: store); item.calendar = target; item.title = data["title"] as? String
                item.notes = data["body"] as? String; item.priority = data["priority"] as? Int ?? 0
                try store.save(item, commit: false); created.append(item)
            }
            try commit(); return created.map(reminderData)
        case "reminders":
            try requireAccess(.reminder)
            let list = try calendar(input["list"], kind: .reminder)
            let predicate = store.predicateForReminders(in: [list])
            let fetched: [EKReminder]? = awaitResult { done in store.fetchReminders(matching: predicate) { done($0) } }
            guard let fetched = fetched else { throw BridgeFailure("execution_error", "Reminders fetch failed") }
            guard fetched.count <= 1000 else { throw BridgeFailure("execution_error", "List exceeds the 1000-item result bound") }
            return fetched.sorted { $0.calendarItemIdentifier < $1.calendarItemIdentifier }.map(reminderData)
        case "get_reminder":
            try requireAccess(.reminder)
            guard let ref = input["ref"] as? [String: Any] else { throw BridgeFailure("execution_error", "Missing reference") }
            return reminderData(try reminder(ref))
        case "get_reminders":
            try requireAccess(.reminder)
            return try rows(input["refs"]).map { reminderData(try reminder($0)) }
        case "complete_reminders":
            try requireAccess(.reminder)
            let refs = try rows(input["refs"])
            let ids = try refs.map { try text($0["id"], "reminder ID") }
            guard Set(ids).count == ids.count else { throw BridgeFailure("execution_error", "Duplicate reminder IDs") }
            let items = try refs.map(reminder)
            for item in items { try writable(item.calendar) }
            let pending = items.filter { !$0.isCompleted }
            for item in pending { item.isCompleted = true; try store.save(item, commit: false) }
            if !pending.isEmpty { try commit() }; return items.map(reminderData)
        default: return try calendarOperation(op, input)
        }
    }
}

let bridge = Bridge()
var requestID = ""
var response: [String: Any]
do {
    let input = FileHandle.standardInput.readData(ofLength: 1_048_577)
    guard input.count <= 1_048_576,
          let request = try JSONSerialization.jsonObject(with: input) as? [String: Any],
          request["version"] as? Int == 1,
          let id = request["request_id"] as? String, id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
          let op = request["operation"] as? String,
          let arguments = request["arguments"] as? [String: Any] else { throw BridgeFailure("execution_error", "Invalid request envelope") }
    requestID = id
    response = ["version": 1, "request_id": id, "ok": true, "result": try bridge.run(op, arguments)]
} catch let failure as BridgeFailure {
    response = ["version": 1, "request_id": requestID, "ok": false, "error": ["type": failure.type, "message": failure.message,
        "outcome": bridge.mutationStarted ? "unknown" : "not_started"]]
} catch {
    let native = error as NSError
    response = ["version": 1, "request_id": requestID, "ok": false, "error": ["type": "execution_error", "message": "EventKit operation failed",
        "domain": native.domain, "code": native.code, "outcome": bridge.mutationStarted ? "unknown" : "not_started"]]
}
if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) {
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
}
