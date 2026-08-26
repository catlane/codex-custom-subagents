#!/bin/sh

set -eu
: "${PATH_PROBE_LOG:?PATH_PROBE_LOG must be set}"
command_name=$(basename "$0")
printf '%s\n' "$command_name" >>"$PATH_PROBE_LOG"
case "$command_name" in
  dirname) exec /usr/bin/dirname "$@" ;;
  sh) exec /bin/sh "$@" ;;
  security) exit 99 ;;
  *) exit 99 ;;
esac
