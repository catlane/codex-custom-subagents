#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"
. "$ROOT/shared/operation-lock.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-borrowed-lock.XXXXXX)
LOCK_HELD=0
trap '[ "$LOCK_HELD" = 0 ] || custom_subagent_lock_release "$TEST_HOME" >/dev/null 2>&1 || true; rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

TEST_HOME="$TEMP_ROOT/home"
PLUGIN_ROOT="$TEMP_ROOT/deepseek-developer"
mkdir -p "$TEST_HOME" "$PLUGIN_ROOT/.codex-plugin"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
cp "$ROOT/plugins/deepseek-developer/.codex-plugin/plugin.json" "$PLUGIN_ROOT/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$PLUGIN_ROOT/agent-spec.json"

run_lifecycle() {
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_TEST_MODE=1 \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

snapshot_tree() {
  find "$1" -type f -exec cksum {} \; | sed "s|$1||" | sort >"$2"
  find "$1" -type d | sed "s|$1||" | sort >>"$2"
}

custom_subagent_lock_acquire "$TEST_HOME" >"$TEMP_ROOT/outer-token"
LOCK_HELD=1
outer_token=$CUSTOM_SUBAGENT_LOCK_TOKEN
run_lifecycle install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_dir "$TEST_HOME/.custom-subagents-lifecycle.lock"
assert_equals "$outer_token" "$(cat "$TEST_HOME/.custom-subagents-lifecycle.lock/owner")"

snapshot_tree "$TEST_HOME" "$TEMP_ROOT/before-busy"
set +e
env -u CUSTOM_SUBAGENT_LOCK_TOKEN \
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_TEST_MODE=1 \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" uninstall deepseek-developer \
  >"$TEMP_ROOT/busy.out" 2>"$TEMP_ROOT/busy.err"
busy_status=$?
set -e
assert_equals 75 "$busy_status"
snapshot_tree "$TEST_HOME" "$TEMP_ROOT/after-busy"
assert_same_file "$TEMP_ROOT/before-busy" "$TEMP_ROOT/after-busy"

set +e
CUSTOM_SUBAGENT_LOCK_TOKEN=forged-token run_lifecycle uninstall deepseek-developer \
  >"$TEMP_ROOT/mismatch.out" 2>"$TEMP_ROOT/mismatch.err"
mismatch_status=$?
set -e
assert_equals 76 "$mismatch_status"
assert_file "$TEST_HOME/custom-subagents/state.json"
assert_equals "$outer_token" "$(cat "$TEST_HOME/.custom-subagents-lifecycle.lock/owner")"
CUSTOM_SUBAGENT_LOCK_TOKEN=$outer_token
export CUSTOM_SUBAGENT_LOCK_TOKEN

custom_subagent_lock_release "$TEST_HOME"
LOCK_HELD=0
assert_not_file "$TEST_HOME/.custom-subagents-lifecycle.lock"

FORGED_HOME="$TEMP_ROOT/forged-home"
mkdir -p "$FORGED_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$FORGED_HOME/config.toml"
set +e
CUSTOM_SUBAGENT_LOCK_TOKEN=forged-inherited-token \
CUSTOM_SUBAGENT_HOME="$FORGED_HOME" \
CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
CUSTOM_SUBAGENT_TEST_MODE=1 \
CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model \
  >"$TEMP_ROOT/forged.out" 2>"$TEMP_ROOT/forged.err"
forged_status=$?
set -e
assert_equals 76 "$forged_status"
assert_not_file "$FORGED_HOME/.custom-subagents-lifecycle.lock"
assert_not_file "$FORGED_HOME/custom-subagents/state.json"

printf '%s\n' 'PASS: lifecycle borrowed lock'
