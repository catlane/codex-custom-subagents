#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-lifecycle-signals.XXXXXX)
LIFECYCLE_PID=
cleanup() {
  cleanup_status=$?
  trap - EXIT HUP INT TERM
  [ -z "$LIFECYCLE_PID" ] || /bin/kill "$LIFECYCLE_PID" 2>/dev/null || true
  if [ "$cleanup_status" -eq 0 ]; then
    rm -rf "$TEMP_ROOT"
  else
    printf '%s\n' "Artifacts preserved: $TEMP_ROOT" >&2
  fi
  exit "$cleanup_status"
}
trap cleanup EXIT HUP INT TERM

PLUGIN_ROOT="$TEMP_ROOT/deepseek-agent"
mkdir -p "$PLUGIN_ROOT/.codex-plugin"
cp "$ROOT/plugins/deepseek-agent/.codex-plugin/plugin.json" "$PLUGIN_ROOT/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$PLUGIN_ROOT/agent-spec.json"

new_case() {
  case_name=$1
  CASE_ROOT="$TEMP_ROOT/$case_name"
  TEST_HOME="$CASE_ROOT/home"
  TEST_SHARED="$CASE_ROOT/shared"
  GATE="$CASE_ROOT/gate"
  mkdir -p "$TEST_HOME" "$TEST_SHARED"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
  cp "$ROOT/shared/state.js" "$TEST_SHARED/state.js"
  cp "$ROOT/shared/lifecycle.sh" "$TEST_SHARED/lifecycle.sh"
  cp "$ROOT/shared/operation-lock.sh" "$TEST_SHARED/operation-lock.sh"
  cp "$TEST_HOME/config.toml" "$CASE_ROOT/config.before"
}

wait_for_gate() {
  wait_count=0
  while [ ! -e "$GATE.entered" ]; do
    if ! /bin/kill -0 "$LIFECYCLE_PID" 2>/dev/null; then
      set +e
      wait "$LIFECYCLE_PID"
      lifecycle_status=$?
      set -e
      LIFECYCLE_PID=
      /bin/cat "$CASE_ROOT/lifecycle.err" >&2
      fail "lifecycle exited before signal gate (status $lifecycle_status)"
    fi
    wait_count=$((wait_count + 1))
    [ "$wait_count" -lt 200 ] || fail 'lifecycle did not reach signal gate'
    /bin/sleep 0.05
  done
}

terminate_lifecycle() {
  /bin/kill -TERM "$LIFECYCLE_PID"
  : >"$GATE.release"
  set +e
  wait "$LIFECYCLE_PID"
  lifecycle_status=$?
  set -e
  LIFECYCLE_PID=
  assert_equals 143 "$lifecycle_status"
  assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"
}

start_lifecycle() {
  /usr/bin/env \
    CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
    CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
    CUSTOM_SUBAGENT_TEST_MODE=1 \
    CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
    CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
    UUIDGEN_GATE="${UUIDGEN_GATE-}" \
    LIFECYCLE_SIGNAL_GATE="${LIFECYCLE_SIGNAL_GATE-}" \
    /bin/sh "$TEST_SHARED/lifecycle.sh" install deepseek-agent deepseek \
      http://localhost:11434 fixture-model >"$CASE_ROOT/lifecycle.out" 2>"$CASE_ROOT/lifecycle.err" &
  LIFECYCLE_PID=$!
  wait_for_gate
}

# TERM during UUID generation is deferred until acquire either owns and releases
# the lock or fails cleanly; it must never leave an ownerless directory.
new_case acquire
sed "s|/usr/bin/uuidgen|$ROOT/tests/helpers/blocking-uuidgen.sh|" \
  "$ROOT/shared/operation-lock.sh" >"$TEST_SHARED/operation-lock.sh"
UUIDGEN_GATE="$GATE"
export UUIDGEN_GATE
start_lifecycle
unset UUIDGEN_GATE
terminate_lifecycle
assert_same_file "$CASE_ROOT/config.before" "$TEST_HOME/config.toml"
assert_not_file "$TEST_HOME/custom-subagents/state.json"

# TERM after the first managed write must use the fixed signal status and roll
# back all touched targets before releasing the directly-owned lock.
new_case write-boundary
sed '/WRITE_COUNT=$((WRITE_COUNT + 1))/a\
  [ "$WRITE_COUNT" != 1 ] || { : >"$LIFECYCLE_SIGNAL_GATE.entered"; while [ ! -e "$LIFECYCLE_SIGNAL_GATE.release" ]; do /bin/sleep 0.05; done; }' \
  "$ROOT/shared/lifecycle.sh" >"$TEST_SHARED/lifecycle.sh"
LIFECYCLE_SIGNAL_GATE="$GATE"
export LIFECYCLE_SIGNAL_GATE
start_lifecycle
unset LIFECYCLE_SIGNAL_GATE
terminate_lifecycle
assert_same_file "$CASE_ROOT/config.before" "$TEST_HOME/config.toml"
assert_not_file "$TEST_HOME/custom-subagents/state.json"
assert_not_file "$TEST_HOME/custom-subagents/models-v1.json"
assert_not_file "$TEST_HOME/agents/deepseek_general.toml"
assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_not_file "$TEST_HOME/agents/deepseek_reviewer.toml"
assert_not_file "$TEST_HOME/AGENTS.md"

printf '%s\n' 'PASS: lifecycle signals'
