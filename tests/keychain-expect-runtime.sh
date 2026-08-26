#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

if [ "${CUSTOM_SUBAGENT_REAL_KEYCHAIN_TEST:-}" != 1 ]; then
  printf '%s\n' 'SKIP: set CUSTOM_SUBAGENT_REAL_KEYCHAIN_TEST=1 for temporary-Keychain integration'
  exit 0
fi

HELPER="$ROOT/shared/store-keychain.exp"
TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-expect.XXXXXX)
KEYCHAIN="$HOME/Library/Keychains/custom-subagents-expect-test-$$.keychain-db"
KEYCHAIN_PASSWORD='temporary-keychain-password'
DUMMY_SECRET='DUMMY_EXPECT_SECRET_5A19'
SERVICE='codex-custom-subagent/runtime-expect-test'
ACCOUNT='api-key'
ORIGINAL_DEFAULT=$(/usr/bin/security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
DEFAULT_CHANGED=0

cleanup() {
  if [ "$DEFAULT_CHANGED" = 1 ] && [ -n "$ORIGINAL_DEFAULT" ]; then
    /usr/bin/security default-keychain -d user -s "$ORIGINAL_DEFAULT" >/dev/null 2>&1 || true
  fi
  /usr/bin/security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

[ -x "$HELPER" ] || fail 'missing executable shared/store-keychain.exp'
/usr/bin/security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
/usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
/usr/bin/security default-keychain -d user -s "$KEYCHAIN"
DEFAULT_CHANGED=1

printf '%s\n' "$DUMMY_SECRET" | "$HELPER" "$SERVICE" "$ACCOUNT" \
  >"$TEMP_ROOT/store.out" 2>"$TEMP_ROOT/store.err"
[ ! -s "$TEMP_ROOT/store.out" ] || fail 'expect helper wrote stdout'
[ ! -s "$TEMP_ROOT/store.err" ] || fail 'expect helper wrote stderr'

stored=$(/usr/bin/security find-generic-password -w -s "$SERVICE" -a "$ACCOUNT" "$KEYCHAIN" 2>/dev/null)
assert_equals "$DUMMY_SECRET" "$stored"

printf '%s\n' 'replacement-dummy' | "$HELPER" "$SERVICE" "$ACCOUNT" \
  >"$TEMP_ROOT/replace.out" 2>"$TEMP_ROOT/replace.err"
stored=$(/usr/bin/security find-generic-password -w -s "$SERVICE" -a "$ACCOUNT" "$KEYCHAIN" 2>/dev/null)
assert_equals 'replacement-dummy' "$stored"

if ps -axo command | grep -F "$DUMMY_SECRET" | grep -v grep >/dev/null 2>&1; then
  fail 'dummy secret appeared in a process command line'
fi

printf '%s\n' 'PASS: private expect Keychain transport'
