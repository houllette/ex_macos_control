#!/usr/bin/env python3
"""Stateful protocol fixture; never accesses an application or EventKit."""
import json
import pathlib
import sys
request = json.load(sys.stdin)
root = pathlib.Path(__file__).parent
state_path = root / "state.json"
state = json.loads(state_path.read_text()) if state_path.exists() else {"items": {}, "mutations": 0}
op, args = request["operation"], request["arguments"]
error, result = None, None
if op == "status":
    result = {"event": "not_determined", "reminder": "not_determined"}
elif op in ["create_event", "update_event"]:
    identifier = "event-" + str(len(state["items"]) + 1) if op == "create_event" else args["ref"]["id"]
    calendar_id = args["calendar"]["id"] if op == "create_event" else args["ref"]["calendar_id"]
    attrs = args["attributes"]
    ref = {"backend": "eventkit", "kind": "event", "id": identifier, "calendar_id": calendar_id, "start_at": attrs["start_at"], "occurrence_at": attrs["start_at"]}
    result = dict(attrs, ref=ref, recurrence=False, detached=False)
    state["items"][identifier] = result
    state["mutations"] += 1
elif op == "get_event":
    item = state["items"].get(args["ref"]["id"])
    if item and item["ref"] == args["ref"]:
        result = item
    else:
        error = {"type": "not_found", "message": "Missing occurrence", "outcome": "not_started"}
elif op == "delete_event":
    state["items"].pop(args["ref"]["id"], None)
    state["mutations"] += 1
    result = True
elif op == "events":
    result = [v for v in state["items"].values() if v["ref"]["calendar_id"] == args["calendar"]["id"] and args["from"] <= v["start_at"] < args["to"]]
elif op == "create_reminders":
    result = []
    for item in args["items"]:
        identifier = "native-" + str(len(state["items"]) + 1)
        ref = {"backend": "eventkit", "kind": "reminder", "id": identifier, "calendar_id": args["list"]["id"]}
        value = {"ref": ref, "title": item["title"], "body": item.get("body", ""), "priority": item.get("priority", 0), "completed": False}
        state["items"][identifier] = value
        result.append(value)
    state["mutations"] += 1
elif op == "complete_reminders":
    for ref in args["refs"]:
        state["items"][ref["id"]]["completed"] = True
    state["mutations"] += 1
    result = [state["items"][r["id"]] for r in args["refs"]]
elif op == "get_reminders":
    result = [state["items"][r["id"]] for r in args["refs"]]
else:
    error = {"type": "permission_denied", "message": "No fixture access", "outcome": "not_started"}
state_path.write_text(json.dumps(state))
mode = (root / "mode").read_text().strip() if (root / "mode").exists() else "normal"
if mode == "lost_reply" and op in ["create_reminders", "complete_reminders", "create_event", "update_event", "delete_event"]:
    print("malformed after persistence")
    sys.exit(0)
if mode == "wrong_event_calendar" and op == "create_event":
    result["ref"]["calendar_id"] = "wrong"
if mode == "wrong_identity" and op == "complete_reminders":
    result[0]["ref"]["id"] = "wrong"
response = {"version": 1, "request_id": request["request_id"], "ok": error is None}
response["error" if error else "result"] = error or result
if mode == "wrong_request":
    response["request_id"] = "0" * 32
print(json.dumps(response))
