#!/bin/bash
# Keep the command and its ordinary descendants in a separate process group.
# All user data arrives as positional arguments; none is evaluated as shell code.
exec 2> "$1"
shift
input=$1
shift
set -m
"$@" < "$input" &
child=$!
cleanup() {
  kill -TERM -- -"$child" 2>/dev/null || true
  kill -KILL -- -"$child" 2>/dev/null || true
  wait "$child" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM INT HUP
wait "$child"
status=$?
exit "$status"
