#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"
. "$ROOT/shared/operation-lock.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-operation-lock.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
LOCK_HOME="$TEMP_ROOT/home"
mkdir -p "$LOCK_HOME"

CUSTOM_SUBAGENT_LOCK_TOKEN=inherited-forged-token
export CUSTOM_SUBAGENT_LOCK_TOKEN
custom_subagent_lock_acquire "$LOCK_HOME" >"$TEMP_ROOT/acquire.out"
owner_token=$CUSTOM_SUBAGENT_LOCK_TOKEN
[ "$owner_token" != inherited-forged-token ] || fail 'acquire reused inherited lock token'
assert_equals "$owner_token" "$(cat "$TEMP_ROOT/acquire.out")"
assert_equals "$owner_token" "$(cat "$LOCK_HOME/.custom-subagents-lifecycle.lock/owner")"
[ -f "$LOCK_HOME/.custom-subagents-lifecycle.lock/owner" ] || fail 'lock owner is not a regular file'
[ ! -L "$LOCK_HOME/.custom-subagents-lifecycle.lock/owner" ] || fail 'lock owner is a symlink'

set +e
(
  CUSTOM_SUBAGENT_LOCK_TOKEN=another-inherited-token
  export CUSTOM_SUBAGENT_LOCK_TOKEN
  custom_subagent_lock_acquire "$LOCK_HOME"
) >"$TEMP_ROOT/busy.out" 2>"$TEMP_ROOT/busy.err"
busy_status=$?
set -e
assert_equals 75 "$busy_status"
[ ! -s "$TEMP_ROOT/busy.out" ] || fail 'busy acquire wrote stdout'
assert_equals "$owner_token" "$(cat "$LOCK_HOME/.custom-subagents-lifecycle.lock/owner")"

custom_subagent_lock_release "$LOCK_HOME"
assert_not_file "$LOCK_HOME/.custom-subagents-lifecycle.lock"
[ "${CUSTOM_SUBAGENT_LOCK_TOKEN+x}" != x ] || fail 'release retained lock token'

cli_token=$(sh "$ROOT/shared/operation-lock.sh" acquire "$LOCK_HOME")
[ -n "$cli_token" ] || fail 'CLI acquire returned an empty token'
CUSTOM_SUBAGENT_LOCK_TOKEN="$cli_token" sh "$ROOT/shared/operation-lock.sh" release "$LOCK_HOME"
assert_not_file "$LOCK_HOME/.custom-subagents-lifecycle.lock"

# TERM after release removes the owner must not leave an ownerless lock that
# blocks the next operation.
release_token=$(sh "$ROOT/shared/operation-lock.sh" acquire "$LOCK_HOME")
RELEASE_GATE="$TEMP_ROOT/release-gate"
sed "s|/bin/rm|$ROOT/tests/helpers/blocking-rm.sh|g" \
  "$ROOT/shared/operation-lock.sh" >"$TEMP_ROOT/operation-lock-release.sh"
LOCK_RELEASE_GATE="$RELEASE_GATE" CUSTOM_SUBAGENT_LOCK_TOKEN="$release_token" \
  /bin/sh "$TEMP_ROOT/operation-lock-release.sh" release "$LOCK_HOME" \
  >"$TEMP_ROOT/release-signal.out" 2>"$TEMP_ROOT/release-signal.err" &
RELEASE_SIGNAL_PID=$!
wait_count=0
while [ ! -e "$RELEASE_GATE.entered" ]; do
  if ! /bin/kill -0 "$RELEASE_SIGNAL_PID" 2>/dev/null; then
    set +e
    wait "$RELEASE_SIGNAL_PID"
    release_early_status=$?
    set -e
    fail "CLI release exited before signal gate (status $release_early_status)"
  fi
  wait_count=$((wait_count + 1))
  [ "$wait_count" -lt 200 ] || fail 'CLI release did not reach signal gate'
  /bin/sleep 0.05
done
/bin/kill -TERM "$RELEASE_SIGNAL_PID"
: >"$RELEASE_GATE.release"
set +e
wait "$RELEASE_SIGNAL_PID"
release_signal_status=$?
set -e
assert_equals 143 "$release_signal_status"
assert_not_file "$LOCK_HOME/.custom-subagents-lifecycle.lock"
post_signal_token=$(sh "$ROOT/shared/operation-lock.sh" acquire "$LOCK_HOME")
CUSTOM_SUBAGENT_LOCK_TOKEN="$post_signal_token" sh "$ROOT/shared/operation-lock.sh" release "$LOCK_HOME"

# TERM during a direct CLI acquire must abort the pending lock and exit 143.
CLI_SIGNAL_HOME="$TEMP_ROOT/cli-signal-home"
CLI_UUID_GATE="$TEMP_ROOT/cli-uuid-gate"
mkdir -p "$CLI_SIGNAL_HOME"
sed "s|/usr/bin/uuidgen|$ROOT/tests/helpers/blocking-uuidgen.sh|" \
  "$ROOT/shared/operation-lock.sh" >"$TEMP_ROOT/operation-lock-cli.sh"
UUIDGEN_GATE="$CLI_UUID_GATE"
export UUIDGEN_GATE
/bin/sh "$TEMP_ROOT/operation-lock-cli.sh" acquire "$CLI_SIGNAL_HOME" >"$TEMP_ROOT/cli-signal.out" 2>"$TEMP_ROOT/cli-signal.err" &
CLI_SIGNAL_PID=$!
wait_count=0
while [ ! -e "$CLI_UUID_GATE.entered" ]; do
  if ! /bin/kill -0 "$CLI_SIGNAL_PID" 2>/dev/null; then
    set +e
    wait "$CLI_SIGNAL_PID"
    cli_early_status=$?
    set -e
    fail "CLI acquire exited before signal gate (status $cli_early_status)"
  fi
  wait_count=$((wait_count + 1))
  [ "$wait_count" -lt 200 ] || fail 'CLI acquire did not reach signal gate'
  /bin/sleep 0.05
done
/bin/kill -TERM "$CLI_SIGNAL_PID"
: >"$CLI_UUID_GATE.release"
set +e
wait "$CLI_SIGNAL_PID"
cli_signal_status=$?
set -e
unset UUIDGEN_GATE
assert_equals 143 "$cli_signal_status"
assert_not_file "$CLI_SIGNAL_HOME/.custom-subagents-lifecycle.lock"

# A signal after acquire succeeds but before the CLI process exits must still
# release the canonical lock.
CLI_POST_HOME="$TEMP_ROOT/cli-post-acquire-home"
CLI_POST_GATE="$TEMP_ROOT/cli-post-acquire-gate"
mkdir -p "$CLI_POST_HOME"
sed '/if \[ "$custom_subagent_lock_cli_pending_signal" != 0 \]; then/i\
      : >"$CLI_POST_ACQUIRE_GATE.entered"\
      while [ ! -e "$CLI_POST_ACQUIRE_GATE.release" ]; do /bin/sleep 0.05; done' \
  "$ROOT/shared/operation-lock.sh" >"$TEMP_ROOT/operation-lock-cli-post.sh"
CLI_POST_ACQUIRE_GATE="$CLI_POST_GATE" \
  /bin/sh "$TEMP_ROOT/operation-lock-cli-post.sh" acquire "$CLI_POST_HOME" \
  >"$TEMP_ROOT/cli-post.out" 2>"$TEMP_ROOT/cli-post.err" &
CLI_POST_PID=$!
wait_count=0
while [ ! -e "$CLI_POST_GATE.entered" ]; do
  if ! /bin/kill -0 "$CLI_POST_PID" 2>/dev/null; then
    set +e
    wait "$CLI_POST_PID"
    cli_post_early_status=$?
    set -e
    fail "CLI post-acquire exited before signal gate (status $cli_post_early_status)"
  fi
  wait_count=$((wait_count + 1))
  [ "$wait_count" -lt 200 ] || fail 'CLI post-acquire did not reach signal gate'
  /bin/sleep 0.05
done
/bin/kill -TERM "$CLI_POST_PID"
: >"$CLI_POST_GATE.release"
set +e
wait "$CLI_POST_PID"
cli_post_status=$?
set -e
assert_equals 143 "$cli_post_status"
assert_not_file "$CLI_POST_HOME/.custom-subagents-lifecycle.lock"

mkdir -p "$LOCK_HOME/.custom-subagents-lifecycle.lock"
ln -s "$TEMP_ROOT/outside-owner" "$LOCK_HOME/.custom-subagents-lifecycle.lock/owner"
CUSTOM_SUBAGENT_LOCK_TOKEN=forged
export CUSTOM_SUBAGENT_LOCK_TOKEN
set +e
custom_subagent_lock_release "$LOCK_HOME" >"$TEMP_ROOT/symlink.out" 2>"$TEMP_ROOT/symlink.err"
symlink_status=$?
set -e
assert_equals 76 "$symlink_status"
[ -L "$LOCK_HOME/.custom-subagents-lifecycle.lock/owner" ] || fail 'unsafe owner symlink was removed'

printf '%s\n' 'PASS: operation lock'
