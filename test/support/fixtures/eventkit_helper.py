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
if mode == "lost_reply" and op in ["create_reminders", "complete_reminders"]:
    print("malformed after persistence")
    sys.exit(0)
if mode == "wrong_identity" and op == "complete_reminders":
    result[0]["ref"]["id"] = "wrong"
response = {"version": 1, "request_id": request["request_id"], "ok": error is None}
response["error" if error else "result"] = error or result
if mode == "wrong_request":
    response["request_id"] = "0" * 32
print(json.dumps(response))
