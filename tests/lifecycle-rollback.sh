#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

make_case() {
  case_root=$1
  CASE_HOME="$case_root/home"
  CASE_PLUGIN="$case_root/deepseek-agent"
  mkdir -p "$CASE_HOME" "$CASE_PLUGIN/.codex-plugin"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$CASE_HOME/config.toml"
  printf '%s\n' 'Unrelated workflow instruction.' >"$CASE_HOME/AGENTS.md"
  printf '%s\n' 'unrelated file' >"$CASE_HOME/unrelated.txt"
  printf '%s\n' '{"name":"deepseek-agent"}' >"$CASE_PLUGIN/.codex-plugin/plugin.json"
  cp "$ROOT/tests/fixtures/agent-spec.json" "$CASE_PLUGIN/agent-spec.json"
}

run_case() {
  CUSTOM_SUBAGENT_HOME="$CASE_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$CASE_PLUGIN" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$CASE_PLUGIN/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

snapshot_active() {
  destination=$1
  mkdir -p "$destination/agents" "$destination/custom-subagents"
  cp "$CASE_HOME/config.toml" "$destination/config.toml"
  cp "$CASE_HOME/AGENTS.md" "$destination/AGENTS.md"
  cp "$CASE_HOME/unrelated.txt" "$destination/unrelated.txt"
  for role in general developer reviewer; do
    cp "$CASE_HOME/agents/deepseek_${role}.toml" "$destination/agents/deepseek_${role}.toml"
  done
  cp "$CASE_HOME/custom-subagents/state.json" "$destination/custom-subagents/state.json"
  cp "$CASE_HOME/custom-subagents/models-v1.json" "$destination/custom-subagents/models-v1.json"
  cp "$CASE_HOME/custom-subagents/base-model-catalog.json" "$destination/custom-subagents/base-model-catalog.json"
}

assert_active_equals() {
  expected=$1
  assert_same_file "$expected/config.toml" "$CASE_HOME/config.toml"
  assert_same_file "$expected/AGENTS.md" "$CASE_HOME/AGENTS.md"
  assert_same_file "$expected/unrelated.txt" "$CASE_HOME/unrelated.txt"
  for role in general developer reviewer; do
    assert_same_file "$expected/agents/deepseek_${role}.toml" "$CASE_HOME/agents/deepseek_${role}.toml"
  done
  assert_same_file "$expected/custom-subagents/state.json" "$CASE_HOME/custom-subagents/state.json"
  assert_same_file "$expected/custom-subagents/models-v1.json" "$CASE_HOME/custom-subagents/models-v1.json"
  assert_same_file "$expected/custom-subagents/base-model-catalog.json" "$CASE_HOME/custom-subagents/base-model-catalog.json"
}

# Fresh install has eight write boundaries: base catalog, three profiles,
# state, generated catalog, config, and workflow. Every boundary rolls back.
for boundary in 1 2 3 4 5 6 7 8; do
  CASE_ROOT=$(mktemp -d /private/tmp/custom-subagents-fresh-rollback.XXXXXX)
  make_case "$CASE_ROOT"
  cp "$CASE_HOME/config.toml" "$CASE_ROOT/config.before"
  cp "$CASE_HOME/AGENTS.md" "$CASE_ROOT/AGENTS.before"
  cp "$CASE_HOME/unrelated.txt" "$CASE_ROOT/unrelated.before"
  if ( export CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="$boundary"; run_case \
    install deepseek-agent deepseek http://localhost:11434 fixture-model ) >/dev/null 2>&1; then
    fail "fresh install failure boundary $boundary unexpectedly succeeded"
  fi
  assert_same_file "$CASE_ROOT/config.before" "$CASE_HOME/config.toml"
  assert_same_file "$CASE_ROOT/AGENTS.before" "$CASE_HOME/AGENTS.md"
  assert_same_file "$CASE_ROOT/unrelated.before" "$CASE_HOME/unrelated.txt"
  for role in general developer reviewer; do
    assert_not_file "$CASE_HOME/agents/deepseek_${role}.toml"
  done
  assert_not_file "$CASE_HOME/custom-subagents/state.json"
  assert_not_file "$CASE_HOME/custom-subagents/models-v1.json"
  assert_not_file "$CASE_HOME/custom-subagents/base-model-catalog.json"
  rm -rf "$CASE_ROOT"
done

# Reconfiguration writes three profiles plus state/catalog/config/workflow.
for boundary in 1 2 3 4 5 6 7; do
  CASE_ROOT=$(mktemp -d /private/tmp/custom-subagents-reinstall-rollback.XXXXXX)
  make_case "$CASE_ROOT"
  run_case install deepseek-agent deepseek http://localhost:11434 fixture-model
  snapshot_active "$CASE_ROOT/before"
  if ( export CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="$boundary"; run_case \
    install deepseek-agent deepseek http://localhost:11434 fixture-model ) >/dev/null 2>&1; then
    fail "reinstall failure boundary $boundary unexpectedly succeeded"
  fi
  assert_active_equals "$CASE_ROOT/before"
  rm -rf "$CASE_ROOT"
done

# Last-provider uninstall removes all three profiles transactionally with the
# config, workflow, state, and both catalogs.
for boundary in 1 2 3 4 5 6 7 8; do
  CASE_ROOT=$(mktemp -d /private/tmp/custom-subagents-uninstall-rollback.XXXXXX)
  make_case "$CASE_ROOT"
  run_case install deepseek-agent deepseek http://localhost:11434 fixture-model
  snapshot_active "$CASE_ROOT/before"
  if ( export CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="$boundary"; run_case uninstall deepseek-agent ) >/dev/null 2>&1; then
    fail "uninstall failure boundary $boundary unexpectedly succeeded"
  fi
  assert_active_equals "$CASE_ROOT/before"
  rm -rf "$CASE_ROOT"
done

printf '%s\n' 'PASS: provider lifecycle rollback'
