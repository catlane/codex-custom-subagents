#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GATE=${BLOCK_SECURITY_GATE:-}
GATE_COMMAND=${BLOCK_SECURITY_COMMAND:-find-generic-password}
GATE_PHASE=${BLOCK_SECURITY_PHASE:-before}

wait_at_gate() {
  : >"$GATE.entered"
  while [ ! -e "$GATE.release" ]; do
    /bin/sleep 0.05
  done
}

if [ -n "$GATE" ] && [ "${1:-}" = "$GATE_COMMAND" ] && [ "$GATE_PHASE" = before ]; then
  wait_at_gate
fi

set +e
"$SCRIPT_DIR/fake-security-base.sh" "$@"
security_status=$?
set -e

if [ "$security_status" = 0 ] && [ -n "$GATE" ] && [ "${1:-}" = "$GATE_COMMAND" ] && [ "$GATE_PHASE" = after ]; then
  wait_at_gate
fi

exit "$security_status"
