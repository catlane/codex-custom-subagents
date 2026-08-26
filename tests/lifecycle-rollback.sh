#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"

for boundary in 1 2 3 4 5 6; do
  FRESH_ROOT=$(mktemp -d /private/tmp/custom-subagents-fresh-rollback.XXXXXX)
  FRESH_HOME="$FRESH_ROOT/home"
  FRESH_PLUGIN="$FRESH_ROOT/deepseek-developer"
  mkdir -p "$FRESH_HOME" "$FRESH_PLUGIN/.codex-plugin"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$FRESH_HOME/config.toml"
  cp "$FRESH_HOME/config.toml" "$FRESH_ROOT/config.before"
  cp "$ROOT/plugins/deepseek-developer/.codex-plugin/plugin.json" "$FRESH_PLUGIN/.codex-plugin/plugin.json"
  cp "$ROOT/tests/fixtures/agent-spec.json" "$FRESH_PLUGIN/agent-spec.json"

  if CUSTOM_SUBAGENT_HOME="$FRESH_HOME" \
    CUSTOM_SUBAGENT_PLUGIN_ROOT="$FRESH_PLUGIN" \
    CUSTOM_SUBAGENT_AGENT_SPEC="$FRESH_PLUGIN/agent-spec.json" \
    CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
    CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="$boundary" \
    sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model \
    >/dev/null 2>&1; then
    fail "fresh install failure boundary $boundary unexpectedly succeeded"
  fi

  assert_same_file "$FRESH_ROOT/config.before" "$FRESH_HOME/config.toml"
  assert_not_file "$FRESH_HOME/custom-subagents/state.json"
  assert_not_file "$FRESH_HOME/custom-subagents/models-v1.json"
  assert_not_file "$FRESH_HOME/custom-subagents/base-model-catalog.json"
  assert_not_file "$FRESH_HOME/agents/deepseek_developer.toml"
  assert_not_file "$FRESH_HOME/AGENTS.md"
  rm -rf "$FRESH_ROOT"
done

for boundary in 1 2 3 4 5; do
  TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-rollback.XXXXXX)
  TEST_HOME="$TEMP_ROOT/home"
  PLUGIN_ROOT="$TEMP_ROOT/deepseek-developer"
  mkdir -p "$PLUGIN_ROOT/.codex-plugin"
  cp "$ROOT/plugins/deepseek-developer/.codex-plugin/plugin.json" "$PLUGIN_ROOT/.codex-plugin/plugin.json"
  cp "$ROOT/tests/fixtures/agent-spec.json" "$PLUGIN_ROOT/agent-spec.json"
  mkdir -p "$TEST_HOME/agents" "$TEST_HOME/custom-subagents"
  cp "$ROOT/tests/fixtures/config-existing-catalog.toml" "$TEST_HOME/config.toml"
  printf '%s\n' 'Existing unmanaged instructions.' >"$TEST_HOME/AGENTS.md"
  printf '%s\n' '# unrelated agent' >"$TEST_HOME/agents/other.toml"
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
  cp "$TEST_HOME/config.toml" "$TEMP_ROOT/config.before"
  cp "$TEST_HOME/AGENTS.md" "$TEMP_ROOT/agents.before"
  cp "$TEST_HOME/agents/other.toml" "$TEMP_ROOT/other.before"
  cp "$TEST_HOME/agents/deepseek_developer.toml" "$TEMP_ROOT/managed-agent.before"
  cp "$TEST_HOME/custom-subagents/state.json" "$TEMP_ROOT/state.before"
  cp "$TEST_HOME/custom-subagents/models-v1.json" "$TEMP_ROOT/catalog.before"
  cp "$TEST_HOME/custom-subagents/base-model-catalog.json" "$TEMP_ROOT/base-catalog.before"

  if CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
    CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
    CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
    CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="$boundary" \
    sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model >/dev/null 2>&1; then
    fail "injected failure after boundary $boundary unexpectedly succeeded"
  fi

  assert_same_file "$TEMP_ROOT/config.before" "$TEST_HOME/config.toml"
  assert_same_file "$TEMP_ROOT/agents.before" "$TEST_HOME/AGENTS.md"
  assert_same_file "$TEMP_ROOT/other.before" "$TEST_HOME/agents/other.toml"
  assert_same_file "$TEMP_ROOT/managed-agent.before" "$TEST_HOME/agents/deepseek_developer.toml"
  assert_same_file "$TEMP_ROOT/state.before" "$TEST_HOME/custom-subagents/state.json"
  assert_same_file "$TEMP_ROOT/catalog.before" "$TEST_HOME/custom-subagents/models-v1.json"
  assert_same_file "$TEMP_ROOT/base-catalog.before" "$TEST_HOME/custom-subagents/base-model-catalog.json"
  rm -rf "$TEMP_ROOT"
done

printf '%s\n' 'PASS: lifecycle rollback'
