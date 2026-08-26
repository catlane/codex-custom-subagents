#!/bin/sh

[ "${1:-}" = -l ] && [ "${2:-}" = JavaScript ] && [ -n "${3:-}" ] &&
[ -n "${4:-}" ] && [ -n "${5:-}" ] && [ -n "${6:-}" ] || {
  printf '%s\n' 'fake-osascript: expected -l JavaScript SCRIPT EXPECT_HELPER SERVICE ACCOUNT' >&2
  exit 64
}

if [ -n "${FAKE_DIALOG_SCRIPT_LOG:-}" ]; then
  printf '%s\n' "$3" >>"$FAKE_DIALOG_SCRIPT_LOG"
fi

case "${FAKE_DIALOG_MODE:-accept}" in
  accept)
    [ -n "${FAKE_DIALOG_VALUE-}" ] || { printf '%s\n' empty; exit 1; }
    if [ -n "${FAKE_SECURITY_STATE:-}" ] && [ -n "${FAKE_SECURITY_LOG:-}" ]; then
      printf '%s|%s|%s\n' add "$5" "$6" >>"$FAKE_SECURITY_LOG"
      grep -F -x -- "$5|$6" "$FAKE_SECURITY_STATE" >/dev/null 2>&1 ||
        printf '%s|%s\n' "$5" "$6" >>"$FAKE_SECURITY_STATE"
    fi
    if [ -n "${BLOCK_SECURITY_GATE:-}" ] &&
       [ "${BLOCK_SECURITY_COMMAND:-}" = add-generic-password ] &&
       [ "${BLOCK_SECURITY_PHASE:-before}" = after ]; then
      : >"$BLOCK_SECURITY_GATE.entered"
      while [ ! -e "$BLOCK_SECURITY_GATE.release" ]; do /bin/sleep 0.05; done
    fi
    printf '%s\n' stored
    ;;
  cancel) printf '%s\n' cancelled ;;
  fail-sensitive)
    printf '%s\n' stored
    exit 1
    ;;
  *) printf '%s\n' 'fake-osascript: invalid mode' >&2; exit 64 ;;
esac
