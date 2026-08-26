#!/bin/sh

if [ -n "${FAKE_DIALOG_SCRIPT_LOG:-}" ]; then
  printf '%s\n' "${1:-}" >>"$FAKE_DIALOG_SCRIPT_LOG"
fi

case "${FAKE_DIALOG_MODE:-accept}" in
  accept) printf '%s\n' "accepted:${FAKE_DIALOG_VALUE-}" ;;
  cancel) printf '%s\n' cancelled ;;
  fail-sensitive)
    printf '%s\n' 'accepted:SECRET_MUST_NOT_APPEAR_7F31'
    exit 1
    ;;
  *) printf '%s\n' 'fake-osascript: invalid mode' >&2; exit 64 ;;
esac
