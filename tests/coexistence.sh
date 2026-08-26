#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-coexistence.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

TEST_MARKETPLACE="$TEMP_ROOT/test-marketplace"
DEEPSEEK_ROOT="$TEST_MARKETPLACE/plugins/deepseek-developer"
VOLCENGINE_ROOT="$TEST_MARKETPLACE/plugins/volcengine-reviewer"
TEST_HELPERS="$TEST_MARKETPLACE/tests/helpers"
mkdir -p "$TEST_MARKETPLACE/plugins" "$TEST_MARKETPLACE/tests"
cp -R "$ROOT/plugins/deepseek-developer" "$DEEPSEEK_ROOT"
cp -R "$ROOT/plugins/volcengine-reviewer" "$VOLCENGINE_ROOT"
cp -R "$ROOT/tests/helpers" "$TEST_HELPERS"
cp "$ROOT/tests/fixtures/plugin-test-runtime-gate.sh" "$DEEPSEEK_ROOT/scripts/runtime-gate.sh"
cp "$ROOT/tests/fixtures/plugin-test-runtime-gate.sh" "$VOLCENGINE_ROOT/scripts/runtime-gate.sh"
FAKE_SECURITY="$TEST_HELPERS/fake-security.sh"
FAKE_OSASCRIPT="$TEST_HELPERS/fake-osascript.sh"
DEEPSEEK_SERVICE='codex-custom-subagent/deepseek-developer|api-key'
VOLCENGINE_SERVICE='codex-custom-subagent/volcengine-reviewer|api-key'

assert_not_contains() {
  file=$1
  needle=$2
  if [ -f "$file" ] && grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    fail "unexpected '$needle' in $file"
  fi
}

new_case() {
  case_name=$1
  CASE_ROOT="$TEMP_ROOT/$case_name"
  TEST_HOME="$CASE_ROOT/home"
  FAKE_STATE="$CASE_ROOT/keychain-state"
  FAKE_LOG="$CASE_ROOT/security.log"
  DIALOG_LOG="$CASE_ROOT/dialog.log"
  mkdir -p "$TEST_HOME"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
  printf '%s\n' 'Unrelated workflow instruction.' >"$TEST_HOME/AGENTS.md"
  printf '%s\n' 'unrelated file' >"$TEST_HOME/unrelated.txt"
  : >"$FAKE_STATE"
  : >"$FAKE_LOG"
  : >"$DIALOG_LOG"
}

configure_deepseek() {
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_SECURITY_BIN="$FAKE_SECURITY" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_OSASCRIPT" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
  FAKE_DIALOG_MODE=accept \
  FAKE_DIALOG_VALUE='fixture-dialog-value' \
  sh "$DEEPSEEK_ROOT/scripts/configure.sh" --model deepseek-chat >/dev/null
}

configure_volcengine() {
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_SECURITY_BIN="$FAKE_SECURITY" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_OSASCRIPT" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
  FAKE_DIALOG_MODE=accept \
  FAKE_DIALOG_VALUE='fixture-dialog-value' \
  sh "$VOLCENGINE_ROOT/scripts/configure.sh" \
    --endpoint https://ark.example.invalid/api/v3 \
    --model ep-review-fixture >/dev/null
}

assert_common() {
  assert_file "$TEST_HOME/custom-subagents/state.json"
  assert_file "$TEST_HOME/custom-subagents/models-v1.json"
  assert_contains "$TEST_HOME/custom-subagents/models-v1.json" '"id": "official:gpt-5.6-sol"'
  assert_contains "$TEST_HOME/custom-subagents/models-v1.json" '"slug": "unrelated-model"'
  assert_contains "$TEST_HOME/custom-subagents/models-v1.json" '"multi_agent_version": "v1"'
  assert_not_contains "$TEST_HOME/custom-subagents/models-v1.json" 'deepseek:deepseek-chat'
  assert_not_contains "$TEST_HOME/custom-subagents/models-v1.json" 'volcengine:ep-review-fixture'
  assert_contains "$TEST_HOME/AGENTS.md" 'Unrelated workflow instruction.'
  assert_contains "$TEST_HOME/AGENTS.md" 'Explicit no-subagents requests stay in the main task.'
  assert_contains "$TEST_HOME/AGENTS.md" 'Official subagents use GPT default, worker, or explorer roles in the same V1 task.'
  assert_contains "$TEST_HOME/config.toml" 'base_url = "https://example.com"'
  assert_contains "$TEST_HOME/unrelated.txt" 'unrelated file'
}

assert_deepseek_present() {
  assert_file "$TEST_HOME/agents/deepseek_developer.toml"
  assert_contains "$TEST_HOME/custom-subagents/state.json" '"id": "deepseek-developer"'
  assert_contains "$TEST_HOME/AGENTS.md" 'development agent type: deepseek_developer'
  assert_contains "$FAKE_STATE" "$DEEPSEEK_SERVICE"
}

assert_volcengine_present() {
  assert_file "$TEST_HOME/agents/volcengine_reviewer.toml"
  assert_contains "$TEST_HOME/custom-subagents/state.json" '"id": "volcengine-reviewer"'
  assert_contains "$TEST_HOME/AGENTS.md" 'review agent type: volcengine_reviewer'
  assert_contains "$FAKE_STATE" "$VOLCENGINE_SERVICE"
}

# Each independently installed plugin must generate a self-consistent V1 setup.
new_case deepseek-only
configure_deepseek
assert_common
assert_deepseek_present
assert_not_file "$TEST_HOME/agents/volcengine_reviewer.toml"
assert_not_contains "$TEST_HOME/AGENTS.md" 'volcengine_reviewer'
assert_equals 1 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"

new_case volcengine-only
configure_volcengine
assert_common
assert_volcengine_present
assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_not_contains "$TEST_HOME/AGENTS.md" 'deepseek_developer'
assert_equals 1 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"

# Both installation orders must converge on the same registry and routing policy.
new_case deepseek-then-volcengine
configure_deepseek
configure_volcengine
assert_common
assert_deepseek_present
assert_volcengine_present
assert_equals 2 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
deepseek_line=$(grep -n -F 'development agent type: deepseek_developer' "$TEST_HOME/AGENTS.md" | cut -d: -f1)
review_line=$(grep -n -F 'review agent type: volcengine_reviewer' "$TEST_HOME/AGENTS.md" | cut -d: -f1)
[ "$deepseek_line" -lt "$review_line" ] || fail 'development is not routed before independent review'

new_case volcengine-then-deepseek
configure_volcengine
configure_deepseek
assert_common
assert_deepseek_present
assert_volcengine_present
assert_equals 2 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
assert_equals 1 "$(grep -c '"id": "deepseek-developer"' "$TEST_HOME/custom-subagents/state.json")"
assert_equals 1 "$(grep -c '"id": "volcengine-reviewer"' "$TEST_HOME/custom-subagents/state.json")"

# Reconfiguration is idempotent for registry, workflow markers, and Keychain identity.
new_case repeated-install
configure_deepseek
configure_volcengine
configure_deepseek
configure_volcengine
assert_common
assert_deepseek_present
assert_volcengine_present
assert_equals 2 "$(wc -l <"$FAKE_STATE" | tr -d ' ')"
assert_equals 1 "$(grep -c '<!-- BEGIN custom-subagents managed workflow -->' "$TEST_HOME/AGENTS.md")"
assert_equals 1 "$(grep -c '<!-- END custom-subagents managed workflow -->' "$TEST_HOME/AGENTS.md")"
assert_equals 1 "$(grep -c '"id": "deepseek-developer"' "$TEST_HOME/custom-subagents/state.json")"
assert_equals 1 "$(grep -c '"id": "volcengine-reviewer"' "$TEST_HOME/custom-subagents/state.json")"
assert_equals 1 "$(grep -c '^model_catalog_json = ' "$TEST_HOME/config.toml")"

printf '%s\n' 'coexistence tests passed'
