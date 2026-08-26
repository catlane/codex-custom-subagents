#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-coexistence.XXXXXX)
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

new_home() {
  home_name=$1
  TEST_HOME="$TEMP_ROOT/$home_name/home"
  mkdir -p "$TEST_HOME"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
  printf '%s\n' 'Repository-owned workflow instruction.' >"$TEST_HOME/AGENTS.md"
}

run_for() {
  plugin_root=$1
  shift
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$plugin_root" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$plugin_root/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

install_deepseek() {
  run_for "$DEEPSEEK_PLUGIN" install deepseek-agent deepseek http://localhost:11434 deepseek-model
}

install_volcengine() {
  run_for "$VOLCENGINE_PLUGIN" install volcengine-agent volcengine http://localhost:11434 volcengine-model
}

assert_not_contains() {
  file=$1
  needle=$2
  if [ -f "$file" ] && grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    fail "unexpected '$needle' in $file"
  fi
}

assert_precedence() {
  workflow=$1
  user_line=$(grep -n -F 'Direct user instructions and repository-specific AGENTS.md rules take precedence.' "$workflow" | cut -d: -f1)
  none_line=$(grep -n -F 'A no-subagents request keeps the work in the main task.' "$workflow" | cut -d: -f1)
  official_line=$(grep -n -F 'An official GPT request selects GPT default, worker, or explorer roles.' "$workflow" | cut -d: -f1)
  explicit_line=$(grep -n -F 'An explicit custom provider and/or role request overrides automatic selection.' "$workflow" | cut -d: -f1)
  automatic_line=$(grep -n -F 'Otherwise, select an installed provider and general, developer, or reviewer role according to task fit.' "$workflow" | cut -d: -f1)
  [ "$user_line" -lt "$none_line" ] && [ "$none_line" -lt "$official_line" ] &&
    [ "$official_line" -lt "$explicit_line" ] && [ "$explicit_line" -lt "$automatic_line" ] ||
    fail 'workflow routing precedence is incorrect'
}

assert_provider_profiles() {
  provider=$1
  assert_file "$TEST_HOME/agents/${provider}_general.toml"
  assert_file "$TEST_HOME/agents/${provider}_developer.toml"
  assert_file "$TEST_HOME/agents/${provider}_reviewer.toml"
  assert_contains "$TEST_HOME/AGENTS.md" \
    "provider $provider agent types: ${provider}_general, ${provider}_developer, ${provider}_reviewer."
}

# One provider may supply separate development and independent review children.
new_home deepseek-only
install_deepseek
assert_provider_profiles deepseek
assert_precedence "$TEST_HOME/AGENTS.md"
assert_contains "$TEST_HOME/AGENTS.md" 'The same provider may be used for separate development and independent review children.'
assert_not_contains "$TEST_HOME/AGENTS.md" 'provider volcengine agent types:'

new_home volcengine-only
install_volcengine
assert_provider_profiles volcengine
assert_precedence "$TEST_HOME/AGENTS.md"
assert_contains "$TEST_HOME/AGENTS.md" 'The same provider may be used for separate development and independent review children.'
assert_not_contains "$TEST_HOME/AGENTS.md" 'provider deepseek agent types:'

# Two providers permit cross-model routing or repeated use of either provider,
# while explicit user provider/role choices remain above automatic selection.
new_home deepseek-then-volcengine
install_deepseek
install_volcengine
assert_provider_profiles deepseek
assert_provider_profiles volcengine
assert_precedence "$TEST_HOME/AGENTS.md"
assert_contains "$TEST_HOME/AGENTS.md" 'With multiple providers, roles may be split across providers or one provider may be reused.'
deepseek_line=$(grep -n -F 'provider deepseek agent types:' "$TEST_HOME/AGENTS.md" | cut -d: -f1)
volcengine_line=$(grep -n -F 'provider volcengine agent types:' "$TEST_HOME/AGENTS.md" | cut -d: -f1)
[ "$deepseek_line" -lt "$volcengine_line" ] || fail 'provider workflow entries are not deterministic'
assert_not_contains "$TEST_HOME/AGENTS.md" 'DeepSeek handles development'
assert_not_contains "$TEST_HOME/AGENTS.md" 'Volcengine performs review'

new_home volcengine-then-deepseek
install_volcengine
install_deepseek
assert_provider_profiles deepseek
assert_provider_profiles volcengine
assert_precedence "$TEST_HOME/AGENTS.md"
assert_equals 1 "$(grep -c '"id": "deepseek-agent"' "$TEST_HOME/custom-subagents/state.json")"
assert_equals 1 "$(grep -c '"id": "volcengine-agent"' "$TEST_HOME/custom-subagents/state.json")"

# Repeated configuration does not duplicate provider records, profiles, or routes.
install_deepseek
install_volcengine
assert_equals 1 "$(grep -c '"id": "deepseek-agent"' "$TEST_HOME/custom-subagents/state.json")"
assert_equals 1 "$(grep -c '"id": "volcengine-agent"' "$TEST_HOME/custom-subagents/state.json")"
assert_equals 1 "$(grep -c 'provider deepseek agent types:' "$TEST_HOME/AGENTS.md")"
assert_equals 1 "$(grep -c 'provider volcengine agent types:' "$TEST_HOME/AGENTS.md")"
assert_equals 1 "$(grep -c '<!-- BEGIN custom-subagents managed workflow -->' "$TEST_HOME/AGENTS.md")"
assert_equals 1 "$(grep -c '<!-- END custom-subagents managed workflow -->' "$TEST_HOME/AGENTS.md")"

printf '%s\n' 'PASS: provider coexistence and routing'
