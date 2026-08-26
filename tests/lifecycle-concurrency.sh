#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-concurrency.XXXXXX)
FIRST_PID=
trap '[ -z "$FIRST_PID" ] || kill "$FIRST_PID" 2>/dev/null || true; rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

TEST_HOME="$TEMP_ROOT/home"
FIRST_PLUGIN="$TEMP_ROOT/deepseek-agent"
SECOND_PLUGIN="$TEMP_ROOT/volcengine-agent"
GATE_DIR="$TEMP_ROOT/gate"
TEST_SHARED="$TEMP_ROOT/shared"
mkdir -p "$TEST_HOME" "$FIRST_PLUGIN/.codex-plugin" "$SECOND_PLUGIN/.codex-plugin" "$GATE_DIR" "$TEST_SHARED"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
cp "$ROOT/plugins/deepseek-agent/.codex-plugin/plugin.json" "$FIRST_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$FIRST_PLUGIN/agent-spec.json"
cp "$ROOT/plugins/volcengine-agent/.codex-plugin/plugin.json" "$SECOND_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$SECOND_PLUGIN/agent-spec.json"
cp "$ROOT/shared/state.js" "$TEST_SHARED/state.js"
cp "$ROOT/shared/operation-lock.sh" "$TEST_SHARED/operation-lock.sh"
sed 's|install) acquire_lock; install "\$@" ;;|install) acquire_lock; : >"\$LIFECYCLE_TEST_GATE.entered"; while [ ! -e "\$LIFECYCLE_TEST_GATE.release" ]; do /bin/sleep 0.05; done; install "\$@" ;;|' \
  "$ROOT/shared/lifecycle.sh" >"$TEST_SHARED/lifecycle.sh"

run_lifecycle() {
  plugin_root=$1
  shift
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$plugin_root" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$plugin_root/agent-spec.json" \
  CUSTOM_SUBAGENT_TEST_MODE=1 \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

snapshot_tree() {
  find "$1" -type f -exec cksum {} \; | sed "s|$1||" | sort >"$2"
  find "$1" -type d | sed "s|$1||" | sort >>"$2"
}

CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
CUSTOM_SUBAGENT_PLUGIN_ROOT="$FIRST_PLUGIN" \
CUSTOM_SUBAGENT_AGENT_SPEC="$FIRST_PLUGIN/agent-spec.json" \
CUSTOM_SUBAGENT_TEST_MODE=1 \
CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
LIFECYCLE_TEST_GATE="$GATE_DIR" \
sh "$TEST_SHARED/lifecycle.sh" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model \
  >"$TEMP_ROOT/first.out" 2>"$TEMP_ROOT/first.err" &
FIRST_PID=$!

wait_count=0
while [ ! -e "$GATE_DIR.entered" ]; do
  wait_count=$((wait_count + 1))
  [ "$wait_count" -lt 200 ] || fail 'first lifecycle operation did not reach the controlled write boundary'
  sleep 0.05
done

snapshot_tree "$TEST_HOME" "$TEMP_ROOT/before-second"
set +e
run_lifecycle "$SECOND_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2 \
  >"$TEMP_ROOT/second.out" 2>"$TEMP_ROOT/second.err"
second_status=$?
set -e
snapshot_tree "$TEST_HOME" "$TEMP_ROOT/after-second"
: >"$GATE_DIR.release"
wait "$FIRST_PID"
FIRST_PID=

[ "$second_status" -ne 0 ] || fail 'concurrent second lifecycle operation unexpectedly succeeded'
assert_same_file "$TEMP_ROOT/before-second" "$TEMP_ROOT/after-second"
assert_contains "$TEMP_ROOT/second.err" 'another lifecycle operation is active'
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

run_lifecycle "$SECOND_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2
assert_contains "$TEST_HOME/custom-subagents/state.json" '"id": "deepseek-agent"'
assert_contains "$TEST_HOME/custom-subagents/state.json" '"id": "volcengine-agent"'
for profile in general developer reviewer; do
  assert_file "$TEST_HOME/agents/deepseek_$profile.toml"
  assert_file "$TEST_HOME/agents/volcengine_$profile.toml"
done

set +e
CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1 run_lifecycle "$SECOND_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2 \
  >"$TEMP_ROOT/failure.out" 2>"$TEMP_ROOT/failure.err"
failure_status=$?
set -e
unset CUSTOM_SUBAGENT_FAIL_AFTER_WRITE
[ "$failure_status" -ne 0 ] || fail 'injected lifecycle failure unexpectedly succeeded'
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"
run_lifecycle "$SECOND_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2

set +e
run_lifecycle "$SECOND_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 '' \
  >"$TEMP_ROOT/preflight-failure.out" 2>"$TEMP_ROOT/preflight-failure.err"
preflight_status=$?
set -e
[ "$preflight_status" -ne 0 ] || fail 'invalid lifecycle input unexpectedly succeeded'
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"
run_lifecycle "$SECOND_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2

mkdir "$TEST_HOME/.custom-subagents-lifecycle.lock"
snapshot_tree "$TEST_HOME" "$TEMP_ROOT/before-stale"
set +e
run_lifecycle "$SECOND_PLUGIN" uninstall volcengine-agent \
  >"$TEMP_ROOT/stale.out" 2>"$TEMP_ROOT/stale.err"
stale_status=$?
set -e
snapshot_tree "$TEST_HOME" "$TEMP_ROOT/after-stale"
[ "$stale_status" -ne 0 ] || fail 'stale lifecycle lock was ignored'
assert_same_file "$TEMP_ROOT/before-stale" "$TEMP_ROOT/after-stale"
assert_contains "$TEMP_ROOT/stale.err" 'confirm no lifecycle operation is running, then remove'
rmdir "$TEST_HOME/.custom-subagents-lifecycle.lock"

printf '%s\n' 'PASS: lifecycle concurrency'
