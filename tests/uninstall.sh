#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-uninstall.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

make_plugin() {
  plugin_root=$1
  plugin_name=$2
  mkdir -p "$plugin_root/.codex-plugin"
  printf '%s\n' "{\"name\":\"$plugin_name\"}" >"$plugin_root/.codex-plugin/plugin.json"
  cp "$ROOT/tests/fixtures/agent-spec.json" "$plugin_root/agent-spec.json"
}

DEEPSEEK_PLUGIN="$TEMP_ROOT/deepseek-agent"
VOLCENGINE_PLUGIN="$TEMP_ROOT/volcengine-agent"
make_plugin "$DEEPSEEK_PLUGIN" deepseek-agent
make_plugin "$VOLCENGINE_PLUGIN" volcengine-agent

run_for() {
  test_home=$1
  plugin_root=$2
  shift 2
  CUSTOM_SUBAGENT_HOME="$test_home" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$plugin_root" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$plugin_root/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

assert_not_contains() {
  file=$1
  needle=$2
  if [ -f "$file" ] && grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    fail "unexpected '$needle' in $file"
  fi
}

snapshot_home() {
  source_home=$1
  snapshot=$2
  mkdir -p "$snapshot"
  cp -Rp "$source_home/." "$snapshot/"
}

assert_rejected_unchanged() {
  label=$1
  test_home=$2
  shift 2
  before="$TEMP_ROOT/$label.before"
  snapshot_home "$test_home" "$before"
  if "$@" >"$TEMP_ROOT/$label.out" 2>"$TEMP_ROOT/$label.err"; then
    fail "$label unexpectedly succeeded"
  fi
  diff -r "$before" "$test_home" >/dev/null 2>&1 ||
    fail "$label mutated the home"
}

# Removing one provider removes all three owned profiles and preserves the
# other provider's complete unit and all shared/unrelated files.
PRESERVE_HOME="$TEMP_ROOT/preserve/home"
mkdir -p "$PRESERVE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$PRESERVE_HOME/config.toml"
printf '%s\n' 'Unrelated workflow instruction.' >"$PRESERVE_HOME/AGENTS.md"
printf '%s\n' 'unrelated file' >"$PRESERVE_HOME/unrelated.txt"
run_for "$PRESERVE_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 deepseek-model
run_for "$PRESERVE_HOME" "$VOLCENGINE_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 volcengine-model
cp "$PRESERVE_HOME/config.toml" "$TEMP_ROOT/preserve.config"
cp "$PRESERVE_HOME/custom-subagents/models-v1.json" "$TEMP_ROOT/preserve.catalog"
for role in general developer reviewer; do
  cp "$PRESERVE_HOME/agents/volcengine_${role}.toml" "$TEMP_ROOT/volcengine-$role.before"
done

run_for "$PRESERVE_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent
for role in general developer reviewer; do
  assert_not_file "$PRESERVE_HOME/agents/deepseek_${role}.toml"
  assert_file "$PRESERVE_HOME/agents/volcengine_${role}.toml"
  assert_same_file "$TEMP_ROOT/volcengine-$role.before" "$PRESERVE_HOME/agents/volcengine_${role}.toml"
done
assert_not_contains "$PRESERVE_HOME/custom-subagents/state.json" '"id": "deepseek-agent"'
assert_contains "$PRESERVE_HOME/custom-subagents/state.json" '"id": "volcengine-agent"'
assert_not_contains "$PRESERVE_HOME/AGENTS.md" 'deepseek_general'
assert_contains "$PRESERVE_HOME/AGENTS.md" 'volcengine_general, volcengine_developer, volcengine_reviewer'
assert_same_file "$TEMP_ROOT/preserve.config" "$PRESERVE_HOME/config.toml"
assert_same_file "$TEMP_ROOT/preserve.catalog" "$PRESERVE_HOME/custom-subagents/models-v1.json"
assert_contains "$PRESERVE_HOME/unrelated.txt" 'unrelated file'

# The last uninstall restores every original AGENTS.md/config shape exactly.
for shape in absent empty ends-newline no-final-newline; do
  SHAPE_HOME="$TEMP_ROOT/shape-$shape/home"
  mkdir -p "$SHAPE_HOME"
  cp "$ROOT/tests/fixtures/config-existing-catalog.toml" "$SHAPE_HOME/config.toml"
  cp "$SHAPE_HOME/config.toml" "$TEMP_ROOT/shape-$shape.config"
  case "$shape" in
    absent) ;;
    empty) : >"$SHAPE_HOME/AGENTS.md"; : >"$TEMP_ROOT/shape-$shape.AGENTS" ;;
    ends-newline) printf '%s\n' 'Existing workflow.' >"$SHAPE_HOME/AGENTS.md"; cp "$SHAPE_HOME/AGENTS.md" "$TEMP_ROOT/shape-$shape.AGENTS" ;;
    no-final-newline) printf '%s' 'Existing workflow.' >"$SHAPE_HOME/AGENTS.md"; cp "$SHAPE_HOME/AGENTS.md" "$TEMP_ROOT/shape-$shape.AGENTS" ;;
  esac
  run_for "$SHAPE_HOME" "$DEEPSEEK_PLUGIN" \
    install deepseek-agent deepseek http://localhost:11434 fixture-model
  run_for "$SHAPE_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent
  assert_same_file "$TEMP_ROOT/shape-$shape.config" "$SHAPE_HOME/config.toml"
  if [ "$shape" = absent ]; then
    assert_not_file "$SHAPE_HOME/AGENTS.md"
  else
    assert_same_file "$TEMP_ROOT/shape-$shape.AGENTS" "$SHAPE_HOME/AGENTS.md"
  fi
  assert_not_file "$SHAPE_HOME/custom-subagents/state.json"
  assert_not_file "$SHAPE_HOME/custom-subagents/models-v1.json"
  assert_not_file "$SHAPE_HOME/custom-subagents/base-model-catalog.json"
  for role in general developer reviewer; do
    assert_not_file "$SHAPE_HOME/agents/deepseek_${role}.toml"
  done
done

# A provider is an all-or-nothing owned unit during uninstall and validation.
PARTIAL_HOME="$TEMP_ROOT/partial/home"
mkdir -p "$PARTIAL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$PARTIAL_HOME/config.toml"
run_for "$PARTIAL_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
rm "$PARTIAL_HOME/agents/deepseek_general.toml"
assert_rejected_unchanged partial-validation "$PARTIAL_HOME" \
  run_for "$PARTIAL_HOME" "$DEEPSEEK_PLUGIN" validate-registration deepseek-agent
assert_rejected_unchanged partial-uninstall "$PARTIAL_HOME" \
  run_for "$PARTIAL_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent

UNMANAGED_HOME="$TEMP_ROOT/unmanaged/home"
mkdir -p "$UNMANAGED_HOME/agents"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$UNMANAGED_HOME/config.toml"
printf '%s\n' '# unmanaged provider profile' >"$UNMANAGED_HOME/agents/deepseek_reviewer.toml"
assert_rejected_unchanged unmanaged-residue "$UNMANAGED_HOME" \
  run_for "$UNMANAGED_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent

MISSING_STATE_HOME="$TEMP_ROOT/missing-state/home"
mkdir -p "$MISSING_STATE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MISSING_STATE_HOME/config.toml"
run_for "$MISSING_STATE_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
rm "$MISSING_STATE_HOME/custom-subagents/state.json"
assert_rejected_unchanged missing-state-residue "$MISSING_STATE_HOME" \
  run_for "$MISSING_STATE_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent

MALFORMED_HOME="$TEMP_ROOT/malformed/home"
mkdir -p "$MALFORMED_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MALFORMED_HOME/config.toml"
run_for "$MALFORMED_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
printf '%s\n' '{not-json' >"$MALFORMED_HOME/custom-subagents/state.json"
assert_rejected_unchanged malformed-state "$MALFORMED_HOME" \
  run_for "$MALFORMED_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent

printf '%s\n' 'PASS: provider uninstall'
