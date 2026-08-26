#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-keychain.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
TEST_HOME="$TEMP_ROOT/home"
CAPTURED="$TEMP_ROOT/captured"
FAKE_DIALOG="$ROOT/tests/helpers/fake-osascript.sh"
FAKE_STATE="$TEMP_ROOT/fake-security-state"
FAKE_LOG="$CAPTURED/security.log"
FAKE_DIALOG_SCRIPT_LOG="$CAPTURED/dialog-scripts.log"
SENTINEL='SECRET_MUST_NOT_APPEAR_7F31'
AGENT='deepseek-agent'
SERVICE="codex-custom-subagent/$AGENT"

mkdir -p "$TEST_HOME/custom-subagents/backups" "$CAPTURED"
printf '%s\n' 'model = "fixture"' >"$TEST_HOME/config.toml"
: >"$TEST_HOME/custom-subagents/state.json"
: >"$TEST_HOME/custom-subagents/backups/placeholder"
: >"$FAKE_STATE"
: >"$FAKE_LOG"
: >"$FAKE_DIALOG_SCRIPT_LOG"

run_keychain() {
  CUSTOM_SUBAGENT_SECURITY_BIN="$ROOT/tests/helpers/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_DIALOG" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
  FAKE_SECURITY_FAIL="${FAKE_SECURITY_FAIL-}" \
  FAKE_SECURITY_FAIL_STATUS="${FAKE_SECURITY_FAIL_STATUS-}" \
  FAKE_DIALOG_VALUE="${FAKE_DIALOG_VALUE-}" \
  FAKE_DIALOG_MODE="${FAKE_DIALOG_MODE-accept}" \
  sh -c '. "$1"; "$2" "$3"' sh "$ROOT/shared/keychain.sh" "$@"
}

run_keychain_prompt_with_trace() {
  CUSTOM_SUBAGENT_SECURITY_BIN="$ROOT/tests/helpers/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_DIALOG" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
  FAKE_DIALOG_VALUE="$SENTINEL" \
  FAKE_DIALOG_MODE=accept \
  sh -x -c '. "$1"; keychain_prompt_store "$2"' sh "$ROOT/shared/keychain.sh" "$AGENT"
}

run_failed_prompt_then_trace() {
  CUSTOM_SUBAGENT_SECURITY_BIN="$ROOT/tests/helpers/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_DIALOG" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
  FAKE_DIALOG_MODE=fail-sensitive \
  sh -c '
    . "$1"
    keychain_secret=preexisting-value
    if keychain_prompt_store "$2"; then
      exit 70
    else
      prompt_status=$?
    fi
    set -x
    : "${keychain_prompt_response-}" "${keychain_secret-}"
    set +x
    [ -z "${keychain_prompt_response-}" ] || exit 71
    [ -z "${keychain_secret-}" ] || exit 72
    exit "$prompt_status"
  ' sh "$ROOT/shared/keychain.sh" "$AGENT"
}

assert_empty_file() {
  [ ! -s "$1" ] || fail "expected empty file: $1"
}

# Store creates the single required generic-password item and sends the value on stdin.
printf '%s' "$SENTINEL" | run_keychain keychain_store "$AGENT" >"$CAPTURED/create.out" 2>"$CAPTURED/create.err"
assert_empty_file "$CAPTURED/create.out"
assert_empty_file "$CAPTURED/create.err"
assert_contains "$FAKE_STATE" "$SERVICE|api-key"
assert_contains "$FAKE_LOG" "add|$SERVICE|api-key"
assert_equals 1 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"

# A second store replaces the same item instead of creating a duplicate.
printf '%s' 'replacement-value' | run_keychain keychain_store "$AGENT" >"$CAPTURED/replace.out" 2>"$CAPTURED/replace.err"
assert_empty_file "$CAPTURED/replace.out"
assert_empty_file "$CAPTURED/replace.err"
assert_equals 1 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"

# Existence is a silent lookup and never asks security to return the password.
run_keychain keychain_exists "$AGENT" >"$CAPTURED/exists.out" 2>"$CAPTURED/exists.err"
assert_empty_file "$CAPTURED/exists.out"
assert_empty_file "$CAPTURED/exists.err"
assert_contains "$FAKE_LOG" "find|$SERVICE|api-key"

# Delete targets only this service/account pair.
printf '%s\n' 'codex-custom-subagent/other-agent|api-key' >>"$FAKE_STATE"
printf '%s\n' "$SERVICE|other-account" >>"$FAKE_STATE"
run_keychain keychain_delete "$AGENT" >"$CAPTURED/delete.out" 2>"$CAPTURED/delete.err"
assert_empty_file "$CAPTURED/delete.out"
assert_empty_file "$CAPTURED/delete.err"
if grep -F -x -- "$SERVICE|api-key" "$FAKE_STATE" >/dev/null 2>&1; then
  fail 'delete left the target Keychain item behind'
fi
assert_contains "$FAKE_STATE" 'codex-custom-subagent/other-agent|api-key'
assert_contains "$FAKE_STATE" "$SERVICE|other-account"
assert_contains "$FAKE_LOG" "delete|$SERVICE|api-key"

# A missing generic password is 44; an operational Keychain error is preserved.
state_before_absent=$(cksum "$FAKE_STATE")
set +e
run_keychain keychain_exists "$AGENT" >"$CAPTURED/absent.out" 2>"$CAPTURED/absent.err"
absent_status=$?
set -e
assert_equals 44 "$absent_status"
assert_equals "$state_before_absent" "$(cksum "$FAKE_STATE")"

FAKE_SECURITY_FAIL=find-generic-password
FAKE_SECURITY_FAIL_STATUS=36
set +e
run_keychain keychain_exists other-agent >"$CAPTURED/locked.out" 2>"$CAPTURED/locked.err"
locked_status=$?
set -e
FAKE_SECURITY_FAIL=
FAKE_SECURITY_FAIL_STATUS=
assert_equals 36 "$locked_status"
assert_equals "$state_before_absent" "$(cksum "$FAKE_STATE")"

# Cancellation is distinct from accepting an intentionally empty value.
FAKE_DIALOG_MODE=cancel
set +e
run_keychain keychain_prompt_store "$AGENT" >"$CAPTURED/cancel.out" 2>"$CAPTURED/cancel.err"
cancel_status=$?
set -e
assert_equals 2 "$cancel_status"
assert_empty_file "$CAPTURED/cancel.out"
assert_empty_file "$CAPTURED/cancel.err"

FAKE_DIALOG_MODE=accept
FAKE_DIALOG_VALUE=
empty_state_before=$(cksum "$FAKE_STATE")
empty_log_before=$(cksum "$FAKE_LOG")
set +e
run_keychain keychain_prompt_store "$AGENT" >"$CAPTURED/empty.out" 2>"$CAPTURED/empty.err"
empty_status=$?
set -e
assert_equals 1 "$empty_status"
assert_equals "$empty_state_before" "$(cksum "$FAKE_STATE")"
assert_equals "$empty_log_before" "$(cksum "$FAKE_LOG")"
assert_contains "$CAPTURED/empty.err" "service=$SERVICE account=api-key"

# The documented prompt-script environment variable is passed to osascript unchanged.
CUSTOM_PROMPT="$TEMP_ROOT/configured-prompt.applescript"
: >"$CUSTOM_PROMPT"
FAKE_DIALOG_VALUE=configured-prompt-value
CUSTOM_SUBAGENT_PROMPT_SECRET_SCRIPT="$CUSTOM_PROMPT" \
  run_keychain keychain_prompt_store "$AGENT" >"$CAPTURED/configured-prompt.out" 2>"$CAPTURED/configured-prompt.err"
assert_contains "$FAKE_DIALOG_SCRIPT_LOG" "$CUSTOM_PROMPT"

# The wrapper disables inherited shell tracing before receiving the dialog answer.
run_keychain_prompt_with_trace >"$CAPTURED/trace.out" 2>"$CAPTURED/trace.err"

# A failed dialog must discard its stdout before later shell diagnostics run.
set +e
run_failed_prompt_then_trace >"$CAPTURED/failed-dialog.out" 2>"$CAPTURED/failed-dialog.err"
failed_dialog_status=$?
set -e
assert_equals 1 "$failed_dialog_status"
if grep -F -- "$SENTINEL" "$CAPTURED/failed-dialog.out" "$CAPTURED/failed-dialog.err" >/dev/null 2>&1; then
  fail 'failed dialog response survived into later xtrace diagnostics'
fi

# Backend failures report identifiers only, even when the input is a secret.
FAKE_SECURITY_FAIL=add-generic-password
set +e
printf '%s' "$SENTINEL" | run_keychain keychain_store "$AGENT" >"$CAPTURED/failure.out" 2>"$CAPTURED/failure.err"
failure_status=$?
set -e
FAKE_SECURITY_FAIL=
[ "$failure_status" -ne 0 ] || fail 'injected Keychain store failure was accepted'
assert_contains "$CAPTURED/failure.err" "service=$SERVICE account=api-key"

# Search every secret-bearing test surface: all captured streams plus state/config/backups.
if grep -R -F -- "$SENTINEL" "$CAPTURED" "$FAKE_STATE" "$TEST_HOME/config.toml" "$TEST_HOME/custom-subagents/state.json" "$TEST_HOME/custom-subagents/backups" >/dev/null 2>&1; then
  fail 'sentinel secret appeared in captured output, state, config, or backups'
fi

printf '%s\n' 'keychain tests passed'
