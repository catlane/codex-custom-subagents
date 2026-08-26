#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-plugin-signals.XXXXXX)
ENTRY_PID=
cleanup() {
  cleanup_status=$?
  trap - EXIT HUP INT TERM
  [ -z "$ENTRY_PID" ] || /bin/kill "$ENTRY_PID" 2>/dev/null || true
  if [ "$cleanup_status" -eq 0 ]; then
    rm -rf "$TEMP_ROOT"
  else
    printf '%s\n' "Artifacts preserved: $TEMP_ROOT" >&2
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT HUP INT TERM

MARKETPLACE="$TEMP_ROOT/test-marketplace"
PLUGIN_ROOT="$MARKETPLACE/plugins/deepseek-agent"
HELPERS="$MARKETPLACE/tests/helpers"
CONFIGURE="$PLUGIN_ROOT/scripts/configure.sh"
UNINSTALL="$PLUGIN_ROOT/scripts/uninstall.sh"
mkdir -p "$MARKETPLACE/plugins" "$MARKETPLACE/tests" "$HELPERS"
cp -R "$ROOT/plugins/deepseek-agent" "$PLUGIN_ROOT"
cp "$ROOT/tests/fixtures/plugin-test-runtime-gate.sh" "$PLUGIN_ROOT/scripts/runtime-gate.sh"
cp "$ROOT/tests/helpers/blocking-security.sh" "$HELPERS/fake-security.sh"
cp "$ROOT/tests/helpers/fake-security.sh" "$HELPERS/fake-security-base.sh"
cp "$ROOT/tests/helpers/fake-osascript.sh" "$HELPERS/fake-osascript.sh"
chmod +x "$HELPERS/fake-security.sh" "$HELPERS/fake-security-base.sh" "$HELPERS/fake-osascript.sh"

run_entry() {
  entry=$1
  shift
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_TEST_MODE=1 \
  CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
  CUSTOM_SUBAGENT_SECURITY_BIN="$HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$HELPERS/fake-osascript.sh" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
  FAKE_DIALOG_VALUE=fixture-secret \
  BLOCK_SECURITY_GATE="${BLOCK_SECURITY_GATE-}" \
  BLOCK_SECURITY_COMMAND="${BLOCK_SECURITY_COMMAND-}" \
  BLOCK_SECURITY_PHASE="${BLOCK_SECURITY_PHASE-}" \
  LIFECYCLE_POST_COMMIT_GATE="${LIFECYCLE_POST_COMMIT_GATE-}" \
  /bin/sh "$entry" "$@"
}

new_case() {
  case_name=$1
  CASE_ROOT="$TEMP_ROOT/$case_name"
  TEST_HOME="$CASE_ROOT/home"
  FAKE_STATE="$CASE_ROOT/keychain-state"
  FAKE_LOG="$CASE_ROOT/security.log"
  DIALOG_LOG="$CASE_ROOT/dialog.log"
  GATE="$CASE_ROOT/gate"
  mkdir -p "$TEST_HOME"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
  : >"$FAKE_STATE"
  : >"$FAKE_LOG"
  : >"$DIALOG_LOG"
}

wait_for_gate() {
  wait_count=0
  while [ ! -e "$GATE.entered" ]; do
    if ! /bin/kill -0 "$ENTRY_PID" 2>/dev/null; then
      set +e
      wait "$ENTRY_PID"
      entry_status=$?
      set -e
      ENTRY_PID=
      /bin/cat "$CASE_ROOT/entry.err" >&2
      fail "entrypoint exited before signal gate (status $entry_status)"
    fi
    wait_count=$((wait_count + 1))
    [ "$wait_count" -lt 200 ] || fail 'entrypoint did not reach signal gate'
    /bin/sleep 0.05
  done
}

start_blocked_entry() {
  entry=$1
  gate_command=$2
  shift 2
  BLOCK_SECURITY_GATE="$GATE"
  BLOCK_SECURITY_COMMAND="$gate_command"
  BLOCK_SECURITY_PHASE=after
  /usr/bin/env \
    CODEX_HOME="$TEST_HOME" \
    CUSTOM_SUBAGENT_TEST_MODE=1 \
    CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
    CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
    CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
    CUSTOM_SUBAGENT_SECURITY_BIN="$HELPERS/fake-security.sh" \
    CUSTOM_SUBAGENT_OSASCRIPT_BIN="$HELPERS/fake-osascript.sh" \
    FAKE_SECURITY_STATE="$FAKE_STATE" \
    FAKE_SECURITY_LOG="$FAKE_LOG" \
    FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
    FAKE_DIALOG_VALUE=fixture-secret \
    BLOCK_SECURITY_GATE="$BLOCK_SECURITY_GATE" \
    BLOCK_SECURITY_COMMAND="$BLOCK_SECURITY_COMMAND" \
    BLOCK_SECURITY_PHASE="$BLOCK_SECURITY_PHASE" \
    /bin/sh "$entry" "$@" >"$CASE_ROOT/entry.out" 2>"$CASE_ROOT/entry.err" &
  ENTRY_PID=$!
  wait_for_gate
}

terminate_blocked_entry() {
  /bin/kill -TERM "$ENTRY_PID"
  : >"$GATE.release"
  set +e
  wait "$ENTRY_PID"
  terminated_status=$?
  set -e
  ENTRY_PID=
  [ "$terminated_status" -ne 0 ] || fail 'TERM was reported as successful completion'
}

# The exact Keychain item created before interruption must be rolled back when
# lifecycle registration has not committed.
new_case configure-after-keychain-store
start_blocked_entry "$CONFIGURE" add-generic-password --model deepseek-chat
terminate_blocked_entry
assert_not_file "$TEST_HOME/custom-subagents/state.json"
assert_equals 0 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

# A signal delivered after lifecycle commit must remain nonzero but must not
# delete the credential required by the already-committed registration.
new_case configure-after-lifecycle-commit
sed 's#COMMITTED=1; cleanup_generated_catalog; trap - EXIT HUP INT TERM; release_lock#COMMITTED=1; cleanup_generated_catalog; [ -z "${LIFECYCLE_POST_COMMIT_GATE:-}" ] || { : >"$LIFECYCLE_POST_COMMIT_GATE.entered"; while [ ! -e "$LIFECYCLE_POST_COMMIT_GATE.release" ]; do /bin/sleep 0.05; done; }; trap - EXIT HUP INT TERM; release_lock#' \
  "$ROOT/shared/lifecycle.sh" >"$PLUGIN_ROOT/scripts/vendor/lifecycle.sh"
/usr/bin/env \
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_TEST_MODE=1 \
  CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
  CUSTOM_SUBAGENT_SECURITY_BIN="$HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$HELPERS/fake-osascript.sh" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
  FAKE_DIALOG_VALUE=fixture-secret \
  LIFECYCLE_POST_COMMIT_GATE="$GATE" \
  /bin/sh "$CONFIGURE" --model deepseek-chat >"$CASE_ROOT/entry.out" 2>"$CASE_ROOT/entry.err" &
ENTRY_PID=$!
wait_for_gate
terminate_blocked_entry
assert_file "$TEST_HOME/custom-subagents/state.json"
assert_file "$TEST_HOME/agents/deepseek_general.toml"
assert_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_file "$TEST_HOME/agents/deepseek_reviewer.toml"
assert_contains "$FAKE_STATE" 'codex-custom-subagent/deepseek-agent|api-key'
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"
cp "$ROOT/shared/lifecycle.sh" "$PLUGIN_ROOT/scripts/vendor/lifecycle.sh"

# A matching state record alone is not a commit proof. If another managed
# artifact is malformed, lifecycle failure must remove the just-created key.
new_case malformed-existing-registration
run_entry "$CONFIGURE" --model deepseek-chat >/dev/null
: >"$FAKE_STATE"
printf '%s\n' 'model_catalog_json = "/invalid/duplicate.json"' >>"$TEST_HOME/config.toml"
set +e
run_entry "$CONFIGURE" --model deepseek-chat >"$CASE_ROOT/reconfigure.out" 2>"$CASE_ROOT/reconfigure.err"
malformed_status=$?
set -e
[ "$malformed_status" -ne 0 ] || fail 'malformed registration accepted a fresh credential'
assert_equals 0 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

# If lifecycle removal committed before interruption, uninstall must finish the
# exact credential cleanup and still report interruption as nonzero.
new_case uninstall-after-lifecycle
run_entry "$CONFIGURE" --model deepseek-chat >/dev/null
start_blocked_entry "$UNINSTALL" find-generic-password
terminate_blocked_entry
assert_not_file "$TEST_HOME/custom-subagents/state.json"
assert_not_file "$TEST_HOME/agents/deepseek_general.toml"
assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_not_file "$TEST_HOME/agents/deepseek_reviewer.toml"
assert_equals 0 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

printf '%s\n' 'PASS: plugin entrypoint signals'
