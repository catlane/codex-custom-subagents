#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-install.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

make_plugin() {
  plugin_root=$1
  plugin_name=$2
  mkdir -p "$plugin_root/.codex-plugin"
  printf '%s\n' "{\"name\":\"$plugin_name\"}" >"$plugin_root/.codex-plugin/plugin.json"
  cp "$ROOT/tests/fixtures/agent-spec.json" "$plugin_root/agent-spec.json"
}

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

assert_rejected() {
  label=$1
  shift
  if "$@" >"$TEMP_ROOT/$label.out" 2>"$TEMP_ROOT/$label.err"; then
    fail "$label was accepted"
  fi
}

assert_not_contains() {
  file=$1
  needle=$2
  if [ -f "$file" ] && grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    fail "unexpected '$needle' in $file"
  fi
}

snapshot_tree() {
  source_tree=$1
  snapshot=$2
  mkdir -p "$snapshot"
  cp -Rp "$source_tree/." "$snapshot/"
}

DEEPSEEK_PLUGIN="$TEMP_ROOT/deepseek-agent"
VOLCENGINE_PLUGIN="$TEMP_ROOT/volcengine-agent"
make_plugin "$DEEPSEEK_PLUGIN" deepseek-agent
make_plugin "$VOLCENGINE_PLUGIN" volcengine-agent

TEST_HOME="$TEMP_ROOT/home"
mkdir -p "$TEST_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
printf '%s\n' 'Unrelated instructions remain byte-for-byte.' >"$TEST_HOME/AGENTS.md"
cp "$TEST_HOME/config.toml" "$TEMP_ROOT/config.before"
cp "$TEST_HOME/AGENTS.md" "$TEMP_ROOT/AGENTS.before"

run_for "$TEST_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model

STATE="$TEST_HOME/custom-subagents/state.json"
CATALOG="$TEST_HOME/custom-subagents/models-v1.json"
BASE_CATALOG="$TEST_HOME/custom-subagents/base-model-catalog.json"
BACKUPS="$TEST_HOME/custom-subagents/backups"
assert_file "$STATE"
assert_file "$CATALOG"
assert_file "$BASE_CATALOG"
assert_dir "$BACKUPS"
assert_contains "$STATE" '"version": 1'
assert_contains "$STATE" '"id": "deepseek-agent"'
assert_contains "$STATE" '"provider": "deepseek"'
assert_contains "$STATE" '"endpoint": "http://localhost:11434"'
assert_contains "$STATE" '"model": "fixture-model"'
assert_equals 1 "$(grep -c '"id": "deepseek-agent"' "$STATE")"
if grep -F '"role":' "$STATE" >/dev/null 2>&1; then
  fail 'provider state persisted a fixed role'
fi
assert_same_file "$ROOT/tests/fixtures/models-cache.json" "$BASE_CATALOG"
assert_contains "$CATALOG" '"slug": "gpt-5.6-sol"'
assert_contains "$CATALOG" '"multi_agent_version": "v1"'
assert_contains "$CATALOG" '"slug": "unrelated-model"'
if grep -F 'deepseek:fixture-model' "$CATALOG" >/dev/null 2>&1; then
  fail 'custom provider replaced the official model catalog'
fi

for role in general developer reviewer; do
  assert_file "$TEST_HOME/agents/deepseek_${role}.toml"
  assert_contains "$TEST_HOME/agents/deepseek_${role}.toml" "name = \"deepseek_$role\""
  assert_contains "$TEST_HOME/agents/deepseek_${role}.toml" '"codex-custom-subagent/deepseek-agent"'
done
assert_contains "$TEST_HOME/agents/deepseek_reviewer.toml" 'sandbox_mode = "read-only"'
assert_contains "$TEST_HOME/agents/deepseek_reviewer.toml" 'approval_policy = "never"'
for role in general developer; do
  if grep -E '^(sandbox_mode|approval_policy)[[:space:]]*=' "$TEST_HOME/agents/deepseek_${role}.toml" >/dev/null 2>&1; then
    fail "$role profile received reviewer-only restrictions"
  fi
done

assert_contains "$TEST_HOME/AGENTS.md" 'Unrelated instructions remain byte-for-byte.'
assert_contains "$TEST_HOME/AGENTS.md" 'Direct user instructions and repository-specific AGENTS.md rules take precedence.'
assert_contains "$TEST_HOME/AGENTS.md" 'A no-subagents request keeps the work in the main task.'
assert_contains "$TEST_HOME/AGENTS.md" 'An official GPT request selects GPT default, worker, or explorer roles.'
assert_contains "$TEST_HOME/AGENTS.md" 'An explicit custom provider and/or role request overrides automatic selection.'
assert_contains "$TEST_HOME/AGENTS.md" 'Otherwise, select an installed provider and general, developer, or reviewer role according to task fit.'
assert_contains "$TEST_HOME/AGENTS.md" 'provider deepseek agent types: deepseek_general, deepseek_developer, deepseek_reviewer.'
assert_contains "$TEST_HOME/AGENTS.md" 'The same provider may be used for separate development and independent review children.'

# Reconfiguration is deterministic and retains one provider record and three profiles.
STATE_FIRST=$(cksum "$STATE")
for role in general developer reviewer; do
  cksum "$TEST_HOME/agents/deepseek_${role}.toml" >"$TEMP_ROOT/$role.first"
done
run_for "$TEST_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
assert_equals "$STATE_FIRST" "$(cksum "$STATE")"
for role in general developer reviewer; do
  assert_equals "$(cat "$TEMP_ROOT/$role.first")" "$(cksum "$TEST_HOME/agents/deepseek_${role}.toml")"
done

# A second provider adds one state record and its complete three-profile unit.
run_for "$TEST_HOME" "$VOLCENGINE_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2
assert_equals 1 "$(grep -c '"id": "deepseek-agent"' "$STATE")"
assert_equals 1 "$(grep -c '"id": "volcengine-agent"' "$STATE")"
for role in general developer reviewer; do
  assert_file "$TEST_HOME/agents/deepseek_${role}.toml"
  assert_file "$TEST_HOME/agents/volcengine_${role}.toml"
done
assert_contains "$TEST_HOME/AGENTS.md" 'provider volcengine agent types: volcengine_general, volcengine_developer, volcengine_reviewer.'
assert_contains "$TEST_HOME/AGENTS.md" 'With multiple providers, roles may be split across providers or one provider may be reused.'

run_for "$TEST_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent
for role in general developer reviewer; do
  assert_not_file "$TEST_HOME/agents/deepseek_${role}.toml"
  assert_file "$TEST_HOME/agents/volcengine_${role}.toml"
done
assert_not_contains "$STATE" '"id": "deepseek-agent"'
assert_contains "$STATE" '"id": "volcengine-agent"'
run_for "$TEST_HOME" "$VOLCENGINE_PLUGIN" uninstall volcengine-agent
assert_same_file "$TEMP_ROOT/config.before" "$TEST_HOME/config.toml"
assert_same_file "$TEMP_ROOT/AGENTS.before" "$TEST_HOME/AGENTS.md"
assert_not_file "$STATE"
assert_not_file "$CATALOG"
assert_not_file "$BASE_CATALOG"

# A normal Codex primary-model switch must refresh the shared catalog and state
# while adding a second provider.
DRIFT_HOME="$TEMP_ROOT/model-drift-home"
mkdir -p "$DRIFT_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$DRIFT_HOME/config.toml"
run_for "$DRIFT_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
sed 's/model = "gpt-5.6-sol"/model = "gpt-5.6-luna"/' \
  "$DRIFT_HOME/config.toml" >"$TEMP_ROOT/config.luna.toml"
mv "$TEMP_ROOT/config.luna.toml" "$DRIFT_HOME/config.toml"
run_for "$DRIFT_HOME" "$VOLCENGINE_PLUGIN" \
  install volcengine-agent volcengine http://localhost:11434 fixture-model-2
assert_contains "$DRIFT_HOME/custom-subagents/state.json" '"primary_model": "gpt-5.6-luna"'
assert_contains "$DRIFT_HOME/custom-subagents/models-v1.json" '"slug": "gpt-5.6-luna"'
assert_contains "$DRIFT_HOME/custom-subagents/models-v1.json" '"multi_agent_version": "v1"'
for role in general developer reviewer; do
  assert_file "$DRIFT_HOME/agents/deepseek_${role}.toml"
  assert_file "$DRIFT_HOME/agents/volcengine_${role}.toml"
done

# A managed catalog-path change is still rejected even when primary-model drift is valid.
PATH_TAMPER_HOME="$TEMP_ROOT/model-drift-path-tamper-home"
mkdir -p "$PATH_TAMPER_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$PATH_TAMPER_HOME/config.toml"
run_for "$PATH_TAMPER_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
sed 's/model_catalog_json = ".*"/model_catalog_json = "\/tmp\/foreign-models.json"/' \
  "$PATH_TAMPER_HOME/config.toml" >"$TEMP_ROOT/config.path-tampered.toml"
mv "$TEMP_ROOT/config.path-tampered.toml" "$PATH_TAMPER_HOME/config.toml"
path_tamper_state=$(cksum "$PATH_TAMPER_HOME/custom-subagents/state.json")
path_tamper_catalog=$(cksum "$PATH_TAMPER_HOME/custom-subagents/models-v1.json")
assert_rejected model-drift-path-tamper run_for "$PATH_TAMPER_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
assert_equals "$path_tamper_state" "$(cksum "$PATH_TAMPER_HOME/custom-subagents/state.json")"
assert_equals "$path_tamper_catalog" "$(cksum "$PATH_TAMPER_HOME/custom-subagents/models-v1.json")"

# Every profile is preflighted before the first managed write.
UNMANAGED_HOME="$TEMP_ROOT/unmanaged-home"
mkdir -p "$UNMANAGED_HOME/agents"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$UNMANAGED_HOME/config.toml"
printf '%s\n' '# user-owned profile' >"$UNMANAGED_HOME/agents/deepseek_developer.toml"
snapshot_tree "$UNMANAGED_HOME" "$TEMP_ROOT/unmanaged.before"
assert_rejected unmanaged-profile run_for "$UNMANAGED_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
diff -r "$TEMP_ROOT/unmanaged.before" "$UNMANAGED_HOME" >/dev/null 2>&1 ||
  fail 'unmanaged profile rejection mutated the home'

PARTIAL_HOME="$TEMP_ROOT/partial-home"
mkdir -p "$PARTIAL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$PARTIAL_HOME/config.toml"
run_for "$PARTIAL_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
rm "$PARTIAL_HOME/agents/deepseek_developer.toml"
snapshot_tree "$PARTIAL_HOME" "$TEMP_ROOT/partial.before"
assert_rejected partial-reinstall run_for "$PARTIAL_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
assert_rejected partial-uninstall run_for "$PARTIAL_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent
diff -r "$TEMP_ROOT/partial.before" "$PARTIAL_HOME" >/dev/null 2>&1 ||
  fail 'partial provider unit rejection mutated the home'

TAMPER_HOME="$TEMP_ROOT/tamper-home"
mkdir -p "$TAMPER_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TAMPER_HOME/config.toml"
run_for "$TAMPER_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
sed 's/model = "fixture-model"/model = "tampered"/' \
  "$TAMPER_HOME/agents/deepseek_reviewer.toml" >"$TAMPER_HOME/agents/deepseek_reviewer.toml.tmp"
mv "$TAMPER_HOME/agents/deepseek_reviewer.toml.tmp" "$TAMPER_HOME/agents/deepseek_reviewer.toml"
snapshot_tree "$TAMPER_HOME" "$TEMP_ROOT/tamper.before"
assert_rejected tampered-validation run_for "$TAMPER_HOME" "$DEEPSEEK_PLUGIN" validate-registration deepseek-agent
assert_rejected tampered-uninstall run_for "$TAMPER_HOME" "$DEEPSEEK_PLUGIN" uninstall deepseek-agent
diff -r "$TEMP_ROOT/tamper.before" "$TAMPER_HOME" >/dev/null 2>&1 ||
  fail 'tampered provider unit rejection mutated the home'

INVALID_HOME="$TEMP_ROOT/invalid-home"
mkdir -p "$INVALID_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$INVALID_HOME/config.toml"
assert_rejected old-five-argument-interface run_for "$INVALID_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent development deepseek http://localhost:11434 fixture-model
assert_rejected empty-model run_for "$INVALID_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 ''
assert_rejected credential-endpoint run_for "$INVALID_HOME" "$DEEPSEEK_PLUGIN" \
  install deepseek-agent deepseek 'https://user:password@example.test' fixture-model
assert_rejected mismatched-owner run_for "$INVALID_HOME" "$VOLCENGINE_PLUGIN" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model
assert_not_file "$INVALID_HOME/custom-subagents/state.json"

printf '%s\n' 'PASS: transactional provider lifecycle install'
