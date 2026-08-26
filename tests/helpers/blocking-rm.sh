#!/bin/sh

set -eu

/bin/rm "$@"

if [ -n "${LOCK_RELEASE_GATE-}" ]; then
  : >"$LOCK_RELEASE_GATE.entered"
  while [ ! -e "$LOCK_RELEASE_GATE.release" ]; do
    /bin/sleep 0.05
  done
fi
