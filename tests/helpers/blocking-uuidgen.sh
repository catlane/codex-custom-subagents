#!/bin/sh

set -eu

: "${UUIDGEN_GATE:?UUIDGEN_GATE must be set}"
: >"$UUIDGEN_GATE.entered"
while [ ! -e "$UUIDGEN_GATE.release" ]; do
  /bin/sleep 0.05
done
printf '%s\n' '11111111-2222-4333-8444-555555555555'
