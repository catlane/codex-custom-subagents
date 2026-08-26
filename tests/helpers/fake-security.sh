#!/bin/sh

set -eu

: "${FAKE_SECURITY_STATE:?FAKE_SECURITY_STATE must be set}"
: "${FAKE_SECURITY_LOG:?FAKE_SECURITY_LOG must be set}"

command_name=${1:?missing security command}
shift
service=
account=
password_from_stdin=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -s) service=${2:?missing service}; shift 2 ;;
    -a) account=${2:?missing account}; shift 2 ;;
    -w) [ "$#" = 1 ] || { printf '%s\n' 'fake-security: password prompt must be last' >&2; exit 64; }
        password_from_stdin=1; shift ;;
    -U) shift ;;
    *) printf '%s\n' "fake-security: unsupported argument $1" >&2; exit 64 ;;
  esac
done

[ -n "$service" ] && [ -n "$account" ] || {
  printf '%s\n' 'fake-security: missing service or account' >&2
  exit 64
}

case "$command_name" in
  add-generic-password)
    [ "$password_from_stdin" = 1 ] || {
      printf '%s\n' 'fake-security: password must be stdin' >&2
      exit 64
    }
    if [ "${FAKE_SECURITY_FAIL:-}" = add-generic-password ]; then
      cat >/dev/null
      printf '%s\n' 'fake-security: injected add failure' >&2
      exit "${FAKE_SECURITY_FAIL_STATUS:-1}"
    fi
    # Deliberately discard secret input: test state must never retain it.
    cat >/dev/null
    printf '%s|%s|%s\n' add "$service" "$account" >>"$FAKE_SECURITY_LOG"
    grep -F -x -- "$service|$account" "$FAKE_SECURITY_STATE" >/dev/null 2>&1 ||
      printf '%s|%s\n' "$service" "$account" >>"$FAKE_SECURITY_STATE"
    ;;
  find-generic-password)
    printf '%s|%s|%s\n' find "$service" "$account" >>"$FAKE_SECURITY_LOG"
    if [ "${FAKE_SECURITY_FAIL:-}" = find-generic-password ]; then
      exit "${FAKE_SECURITY_FAIL_STATUS:-36}"
    fi
    if grep -F -x -- "$service|$account" "$FAKE_SECURITY_STATE" >/dev/null 2>&1; then
      exit 0
    fi
    exit 44
    ;;
  delete-generic-password)
    printf '%s|%s|%s\n' delete "$service" "$account" >>"$FAKE_SECURITY_LOG"
    if [ "${FAKE_SECURITY_FAIL:-}" = delete-generic-password ]; then
      exit "${FAKE_SECURITY_FAIL_STATUS:-1}"
    fi
    temporary="$FAKE_SECURITY_STATE.tmp"
    awk -v target="$service|$account" '$0 != target' "$FAKE_SECURITY_STATE" >"$temporary"
    if cmp -s "$FAKE_SECURITY_STATE" "$temporary"; then
      rm -f "$temporary"
      exit 44
    fi
    mv "$temporary" "$FAKE_SECURITY_STATE"
    ;;
  *)
    printf '%s\n' "fake-security: unsupported command $command_name" >&2
    exit 64
    ;;
esac
