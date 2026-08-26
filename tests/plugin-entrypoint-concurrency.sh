#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-plugin-concurrency.XXXXXX)
FIRST_PID=
cleanup() {
  cleanup_status=$?
  trap - EXIT HUP INT TERM
  [ -z "$FIRST_PID" ] || kill "$FIRST_PID" 2>/dev/null || true
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
  LEGACY_PREFLIGHT_GATE="${LEGACY_PREFLIGHT_GATE-}" \
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

snapshot_tree() {
  find "$1" -type f -exec cksum {} \; | sed "s|$1||" | sort >"$2"
  find "$1" -type d | sed "s|$1||" | sort >>"$2"
}

write_other_provider_legacy_residue() {
  mkdir -p "$TEST_HOME/custom-subagents" "$TEST_HOME/agents"
  printf '%s\n' '{"agents":[{"id":"volcengine-reviewer"}]}' \
    >"$TEST_HOME/custom-subagents/state.json"
  cat >"$TEST_HOME/agents/volcengine_reviewer.toml" <<'EOF'
# BEGIN custom-subagents managed agent id=volcengine-reviewer plugin=volcengine-reviewer
# END custom-subagents managed agent id=volcengine-reviewer plugin=volcengine-reviewer
EOF
}

assert_legacy_preflight_left_no_mutation() {
  assert_equals 0 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
  assert_equals 0 "$(wc -c <"$FAKE_LOG" | tr -d ' ')"
  assert_equals 0 "$(wc -c <"$DIALOG_LOG" | tr -d ' ')"
  assert_same_file "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
  assert_not_file "$TEST_HOME/custom-subagents/models-v1.json"
  assert_not_file "$TEST_HOME/custom-subagents/base-model-catalog.json"
  assert_not_file "$TEST_HOME/agents/deepseek_general.toml"
  assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
  assert_not_file "$TEST_HOME/agents/deepseek_reviewer.toml"
  assert_not_file "$TEST_HOME/AGENTS.md"
}

wait_for_gate() {
  wait_count=0
  while [ ! -e "$GATE.entered" ]; do
    if ! kill -0 "$FIRST_PID" 2>/dev/null; then
      set +e
      wait "$FIRST_PID"
      first_status=$?
      set -e
      FIRST_PID=
      /bin/cat "$CASE_ROOT/first.err" >&2
      fail "configure exited before the controlled Keychain boundary (status $first_status)"
    fi
    wait_count=$((wait_count + 1))
    [ "$wait_count" -lt 200 ] || fail 'configure did not reach the controlled Keychain boundary'
    /bin/sleep 0.05
  done
}

start_blocked_configure() {
  BLOCK_SECURITY_GATE="$GATE"
  export BLOCK_SECURITY_GATE
  run_entry "$CONFIGURE" --model deepseek-chat \
    >"$CASE_ROOT/first.out" 2>"$CASE_ROOT/first.err" &
  FIRST_PID=$!
  unset BLOCK_SECURITY_GATE
  wait_for_gate
}

finish_blocked_configure() {
  : >"$GATE.release"
  wait "$FIRST_PID"
  FIRST_PID=
}

start_legacy_preflight_gate() {
  LEGACY_PREFLIGHT_GATE="$GATE"
  export LEGACY_PREFLIGHT_GATE
  run_entry "$CONFIGURE" --model deepseek-chat \
    >"$CASE_ROOT/legacy.out" 2>"$CASE_ROOT/legacy.err" &
  FIRST_PID=$!
  unset LEGACY_PREFLIGHT_GATE
  wait_for_gate
}

finish_legacy_preflight_gate() {
  : >"$GATE.release"
  set +e
  wait "$FIRST_PID"
  legacy_status=$?
  set -e
  FIRST_PID=
  assert_equals 1 "$legacy_status"
}

# A second configure must be rejected before any Keychain or lifecycle change.
new_case configure-configure
start_blocked_configure
set +e
run_entry "$CONFIGURE" --model deepseek-chat >"$CASE_ROOT/second.out" 2>"$CASE_ROOT/second.err"
second_status=$?
set -e
[ "$second_status" -ne 0 ] || fail 'concurrent configure unexpectedly succeeded'
assert_contains "$CASE_ROOT/second.err" 'another lifecycle operation is active'
finish_blocked_configure
assert_file "$TEST_HOME/custom-subagents/state.json"
assert_file "$TEST_HOME/agents/deepseek_general.toml"
assert_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_file "$TEST_HOME/agents/deepseek_reviewer.toml"
assert_contains "$FAKE_STATE" 'codex-custom-subagent/deepseek-agent|api-key'
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

# Uninstall must not interleave while configure owns the Keychain/lifecycle transaction.
new_case configure-uninstall
run_entry "$CONFIGURE" --model deepseek-chat >/dev/null
start_blocked_configure
set +e
run_entry "$UNINSTALL" >"$CASE_ROOT/uninstall.out" 2>"$CASE_ROOT/uninstall.err"
uninstall_status=$?
set -e
[ "$uninstall_status" -ne 0 ] || fail 'concurrent uninstall unexpectedly succeeded'
assert_contains "$CASE_ROOT/uninstall.err" 'another lifecycle operation is active'
finish_blocked_configure
assert_file "$TEST_HOME/custom-subagents/state.json"
assert_file "$TEST_HOME/agents/deepseek_general.toml"
assert_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_file "$TEST_HOME/agents/deepseek_reviewer.toml"
assert_contains "$FAKE_STATE" 'codex-custom-subagent/deepseek-agent|api-key'
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

# Legacy preflight is state-sensitive and must not run before the shared
# owner-token lock. A busy operation wins without any Keychain or file change.
new_case legacy-preflight-busy
write_other_provider_legacy_residue
. "$PLUGIN_ROOT/scripts/vendor/operation-lock.sh"
custom_subagent_lock_acquire "$TEST_HOME" >/dev/null
snapshot_tree "$TEST_HOME" "$CASE_ROOT/busy.before"
set +e
run_entry "$CONFIGURE" --model deepseek-chat >"$CASE_ROOT/busy.out" 2>"$CASE_ROOT/busy.err"
busy_status=$?
set -e
assert_equals 75 "$busy_status"
assert_contains "$CASE_ROOT/busy.err" 'another lifecycle operation is active'
if grep -F -- 'migration required legacy-plugin=' "$CASE_ROOT/busy.err" >/dev/null 2>&1; then
  fail 'busy configure ran the legacy migration preflight outside the shared lock'
fi
snapshot_tree "$TEST_HOME" "$CASE_ROOT/busy.after"
assert_same_file "$CASE_ROOT/busy.before" "$CASE_ROOT/busy.after"
assert_legacy_preflight_left_no_mutation
custom_subagent_lock_release "$TEST_HOME"

# Hold the transaction immediately after acquiring its shared lock, then add
# legacy residue from the other provider. The guard must reject it before the
# dialog, Keychain mutation, or managed lifecycle write can begin.
new_case legacy-preflight-under-lock
sed '/OPERATION_LOCK_HELD=1/a\
  [ -z "${LEGACY_PREFLIGHT_GATE:-}" ] || { : >"$LEGACY_PREFLIGHT_GATE.entered"; while [ ! -e "$LEGACY_PREFLIGHT_GATE.release" ]; do /bin/sleep 0.05; done; }' \
  "$CONFIGURE" >"$CONFIGURE.gated"
mv "$CONFIGURE.gated" "$CONFIGURE"
chmod +x "$CONFIGURE"
start_legacy_preflight_gate
write_other_provider_legacy_residue
finish_legacy_preflight_gate
assert_equals 'deepseek-agent: migration required legacy-plugin=volcengine-reviewer' \
  "$(cat "$CASE_ROOT/legacy.err")"
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"
assert_legacy_preflight_left_no_mutation

printf '%s\n' 'PASS: plugin entrypoint concurrency'
