#!/usr/bin/env python3
"""A launch acknowledgement fixture; does not open or control applications."""
import json
import pathlib
import sys
root = pathlib.Path(__file__).parent
with (root / "calls").open("a") as log:
    log.write("launch\n")
request = json.loads((pathlib.Path(sys.argv[-1]).parent / "request.json").read_text())
mode = (root / "mode").read_text() if (root / "mode").exists() else "normal"
if mode == "startup_failure":
    pathlib.Path(request["failed"]).write_text(json.dumps({"token": request["token"], "ok": False}))
    sys.exit(0)
token = "wrong" if mode == "wrong_token" else request["token"]
result = {"token": token, "ok": True, "output": {"exit_status": 7 if mode == "command_failure" else 0, "stdout": "output", "stderr": ""}}
cleanup = {"token": token, "ok": mode != "cleanup_failure", "status": "closed"}
pathlib.Path(request["result"]).write_text("lost reply" if mode == "lost_reply" else json.dumps(result))
pathlib.Path(request["cleanup"]).write_text(json.dumps(cleanup))
