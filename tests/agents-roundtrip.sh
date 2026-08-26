#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-agents-roundtrip.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
TEST_HOME="$TEMP_ROOT/home"
PLUGIN_ROOT="$TEMP_ROOT/deepseek-agent"
SPEC="$PLUGIN_ROOT/agent-spec.json"
STATE="$TEST_HOME/custom-subagents/state.json"
CATALOG="$TEST_HOME/custom-subagents/models-v1.json"
SERVICE=codex-custom-subagent/deepseek-agent
mkdir -p "$TEST_HOME" "$PLUGIN_ROOT/.codex-plugin"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
cp "$ROOT/tests/fixtures/agent-spec.json" "$SPEC"
printf '%s\n' '{"name":"deepseek-agent"}' >"$PLUGIN_ROOT/.codex-plugin/plugin.json"

run_lifecycle() {
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$SPEC" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

render_state() {
  spec_path=$1
  role=$2
  /usr/bin/osascript -l JavaScript "$ROOT/shared/state.js" render-agent-spec-state \
    "$spec_path" "$STATE" deepseek-agent "$role" "$CATALOG" "$SERVICE"
}

assert_rejected() {
  label=$1
  shift
  if "$@" >"$TEMP_ROOT/$label.out" 2>"$TEMP_ROOT/$label.err"; then
    fail "$label was accepted"
  fi
}

run_lifecycle install deepseek-agent deepseek http://localhost:11434 fixture-model

for role in general developer reviewer; do
  agent="$TEST_HOME/agents/deepseek_${role}.toml"
  rendered="$TEMP_ROOT/$role.toml"
  assert_file "$agent"
  render_state "$SPEC" "$role" >"$rendered"
  {
    printf '%s\n' "# BEGIN custom-subagents managed agent provider=deepseek-agent role=$role plugin=deepseek-agent"
    cat "$rendered"
    printf '%s\n' "# END custom-subagents managed agent provider=deepseek-agent role=$role plugin=deepseek-agent"
  } >"$TEMP_ROOT/$role.enveloped.toml"
  assert_same_file "$TEMP_ROOT/$role.enveloped.toml" "$agent"
  assert_contains "$agent" "name = \"deepseek_$role\""
  assert_contains "$agent" 'model = "fixture-model"'
  assert_contains "$agent" 'model_provider = "deepseek"'
  assert_contains "$agent" 'base_url = "http://localhost:11434"'
  assert_contains "$agent" "model_catalog_json = \"$CATALOG\""
  assert_contains "$agent" 'wire_api = "responses"'
  assert_contains "$agent" 'requires_openai_auth = false'
  assert_contains "$agent" 'command = "/usr/bin/security"'
  assert_contains "$agent" '"codex-custom-subagent/deepseek-agent"'
done

assert_contains "$TEST_HOME/agents/deepseek_general.toml" 'description = "General custom subagent"'
assert_contains "$TEST_HOME/agents/deepseek_developer.toml" 'description = "Development custom subagent"'
assert_contains "$TEST_HOME/agents/deepseek_reviewer.toml" 'description = "Read-only review custom subagent"'
assert_contains "$TEST_HOME/agents/deepseek_reviewer.toml" 'sandbox_mode = "read-only"'
assert_contains "$TEST_HOME/agents/deepseek_reviewer.toml" 'approval_policy = "never"'
for writable_role in general developer; do
  if grep -E '^(sandbox_mode|approval_policy)[[:space:]]*=' "$TEST_HOME/agents/deepseek_${writable_role}.toml" >/dev/null 2>&1; then
    fail "$writable_role unexpectedly received reviewer-only restrictions"
  fi
done

# Provider and auth settings are byte-identical apart from profile-specific fields.
for role in general developer reviewer; do
  sed -n '/^model = /,/^args = /p' "$TEST_HOME/agents/deepseek_${role}.toml" |
    sed '/^sandbox_mode = /d; /^approval_policy = /d' >"$TEMP_ROOT/$role.shared"
done
assert_same_file "$TEMP_ROOT/general.shared" "$TEMP_ROOT/developer.shared"
assert_same_file "$TEMP_ROOT/general.shared" "$TEMP_ROOT/reviewer.shared"

# The provider schema and each profile schema are closed, and all three roles are mandatory.
printf '%s\n' '{"schema_version":1,"provider_display_name":"Fixture","wire_api":"responses","profiles":{"general":{"description":"g","developer_instructions":"g"},"developer":{"description":"d","developer_instructions":"d"},"reviewer":{"description":"r","developer_instructions":"r","sandbox_mode":"read-only","approval_policy":"never"}},"unexpected":true}' >"$TEMP_ROOT/top-extra.json"
printf '%s\n' '{"schema_version":1,"provider_display_name":"Fixture","wire_api":"responses","profiles":{"general":{"description":"g","developer_instructions":"g"},"developer":{"description":"d","developer_instructions":"d"}}}' >"$TEMP_ROOT/missing-reviewer.json"
printf '%s\n' '{"schema_version":1,"provider_display_name":"Fixture","wire_api":"responses","profiles":{"general":{"description":"g","developer_instructions":"g","sandbox_mode":"read-only"},"developer":{"description":"d","developer_instructions":"d"},"reviewer":{"description":"r","developer_instructions":"r","sandbox_mode":"read-only","approval_policy":"never"}}}' >"$TEMP_ROOT/general-extra.json"
printf '%s\n' '{"schema_version":1,"provider_display_name":"Fixture","wire_api":"responses","profiles":{"general":{"description":"g","developer_instructions":"g"},"developer":{"description":"d","developer_instructions":"d"},"reviewer":{"description":"r","developer_instructions":"r","sandbox_mode":"workspace-write","approval_policy":"never"}}}' >"$TEMP_ROOT/bad-reviewer.json"
printf '%s\n' '{"schema_version":1,"provider_display_name":"Fixture","wire_api":"responses","profiles":{"general":{"description":"g","developer_instructions":"g"},"developer":{"description":"d","developer_instructions":"d"},"reviewer":{"description":"r","developer_instructions":"r","sandbox_mode":"read-only","approval_policy":"never"},"planner":{"description":"p","developer_instructions":"p"}}}' >"$TEMP_ROOT/extra-role.json"

for invalid in top-extra missing-reviewer general-extra bad-reviewer extra-role; do
  assert_rejected "$invalid" render_state "$TEMP_ROOT/$invalid.json" general
done
assert_rejected invalid-role render_state "$SPEC" planner

run_lifecycle validate-registration deepseek-agent
run_lifecycle uninstall deepseek-agent
assert_not_file "$TEST_HOME/agents/deepseek_general.toml"
assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_not_file "$TEST_HOME/agents/deepseek_reviewer.toml"

printf '%s\n' 'PASS: provider agent profiles round-trip'
