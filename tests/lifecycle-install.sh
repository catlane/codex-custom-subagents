#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-install.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
TEST_HOME="$TEMP_ROOT/home"
LIVE_HOME="$TEMP_ROOT/live-home"
PLUGIN_ROOT="$TEMP_ROOT/deepseek-developer"
mkdir -p "$TEST_HOME" "$LIVE_HOME/.codex" "$PLUGIN_ROOT/.codex-plugin"
cp "$ROOT/plugins/deepseek-developer/.codex-plugin/plugin.json" "$PLUGIN_ROOT/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$PLUGIN_ROOT/agent-spec.json"
export CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
printf '%s\n' 'live Codex sentinel' >"$LIVE_HOME/.codex/sentinel"
cp "$LIVE_HOME/.codex/sentinel" "$TEMP_ROOT/live-sentinel.before"
printf '%s\n' 'Unrelated instructions remain byte-for-byte.' >"$TEST_HOME/AGENTS.md"
cp "$TEST_HOME/config.toml" "$TEMP_ROOT/config.before"

run_lifecycle() {
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  HOME="$LIVE_HOME" \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

run_lifecycle install deepseek-developer development deepseek http://localhost:11434 fixture-model

STATE="$TEST_HOME/custom-subagents/state.json"
CATALOG="$TEST_HOME/custom-subagents/models-v1.json"
BASE_CATALOG="$TEST_HOME/custom-subagents/base-model-catalog.json"
AGENT="$TEST_HOME/agents/deepseek_developer.toml"
BACKUPS="$TEST_HOME/custom-subagents/backups"
assert_file "$STATE"
assert_file "$CATALOG"
assert_file "$BASE_CATALOG"
assert_file "$AGENT"
assert_dir "$BACKUPS"
assert_contains "$STATE" '"version": 1'
assert_contains "$STATE" '"id": "deepseek-developer"'
assert_contains "$STATE" '"endpoint": "http://localhost:11434"'
assert_contains "$STATE" '"primary_model": "gpt-5.6-sol"'
assert_contains "$STATE" '"base_catalog_source_kind": "test-override"'
assert_same_file "$ROOT/tests/fixtures/models-cache.json" "$BASE_CATALOG"
assert_contains "$CATALOG" '"slug": "gpt-5.6-sol"'
assert_contains "$CATALOG" '"multi_agent_version": "v1"'
assert_contains "$CATALOG" '"slug": "unrelated-model"'
assert_contains "$CATALOG" '"id": "official:unrelated-model"'
assert_contains "$CATALOG" '"rank": 7'
assert_contains "$CATALOG" '"client_version": "0.147.0"'
if grep -F 'deepseek:fixture-model' "$CATALOG" >/dev/null 2>&1; then
  fail 'custom agent replaced the official model catalog'
fi
assert_contains "$AGENT" 'name = "deepseek_developer"'
assert_contains "$AGENT" 'developer_instructions = "'
assert_contains "$AGENT" 'model_catalog_json = "'
assert_contains "$AGENT" 'wire_api = "responses"'
assert_contains "$AGENT" 'requires_openai_auth = false'
assert_contains "$AGENT" 'command = "/usr/bin/security"'
assert_contains "$AGENT" '"codex-custom-subagent/deepseek-developer"'
if grep -F '[agent]' "$AGENT" >/dev/null 2>&1; then
  fail 'legacy agent table was generated'
fi
if grep -E '(api_key|api-key)[[:space:]]*=' "$AGENT" >/dev/null 2>&1; then
  fail 'plaintext key field was generated'
fi
assert_contains "$TEST_HOME/AGENTS.md" '<!-- BEGIN custom-subagents managed workflow -->'
assert_contains "$TEST_HOME/AGENTS.md" 'Unrelated instructions remain byte-for-byte.'
assert_contains "$TEST_HOME/AGENTS.md" 'Explicit no-subagents requests stay in the main task.'
assert_contains "$TEST_HOME/AGENTS.md" 'Official subagents use GPT default, worker, or explorer roles in the same V1 task.'
assert_contains "$TEST_HOME/AGENTS.md" 'development agent type: deepseek_developer'
assert_contains "$TEST_HOME/config.toml" 'model_catalog_json = "'
assert_contains "$TEST_HOME/config.toml" 'base_url = "https://example.com"'
assert_not_file "$TEMP_ROOT/escaped"
assert_same_file "$TEMP_ROOT/live-sentinel.before" "$LIVE_HOME/.codex/sentinel"
if find "$TEST_HOME/custom-subagents" -name '.custom-subagents.*' -print -quit | grep -q .; then
  fail 'atomic write temporary file was left behind'
fi

STATE_FIRST=$(cksum "$STATE")
CONFIG_FIRST=$(cksum "$TEST_HOME/config.toml")
run_lifecycle install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_equals "$STATE_FIRST" "$(cksum "$STATE")"
assert_equals "$CONFIG_FIRST" "$(cksum "$TEST_HOME/config.toml")"

SECOND_PLUGIN="$TEMP_ROOT/reviewer-agent"
mkdir -p "$SECOND_PLUGIN/.codex-plugin"
printf '%s\n' '{"name":"reviewer-agent"}' >"$SECOND_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$SECOND_PLUGIN/agent-spec.json"
run_second_lifecycle() {
  CUSTOM_SUBAGENT_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$SECOND_PLUGIN" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$SECOND_PLUGIN/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  HOME="$LIVE_HOME" \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}
run_second_lifecycle install reviewer-agent review volcengine http://localhost:11434 fixture-model-2
SECOND_AGENT="$TEST_HOME/agents/reviewer_agent.toml"
assert_file "$SECOND_AGENT"
assert_contains "$STATE" '"id": "deepseek-developer"'
assert_contains "$STATE" '"id": "reviewer-agent"'
assert_contains "$CATALOG" '"id": "official:gpt-5.6-sol"'
assert_contains "$CATALOG" '"id": "official:unrelated-model"'
if grep -E 'deepseek:fixture-model|volcengine:fixture-model-2' "$CATALOG" >/dev/null 2>&1; then
  fail 'custom agent was added to the official model catalog'
fi
assert_contains "$TEST_HOME/AGENTS.md" 'development agent type: deepseek_developer'
assert_contains "$TEST_HOME/AGENTS.md" 'review agent type: reviewer_agent'
assert_contains "$STATE" '"original_model_catalog_line": null'
run_lifecycle uninstall deepseek-developer
assert_not_file "$AGENT"
assert_contains "$TEST_HOME/AGENTS.md" 'review agent type: reviewer_agent'
if grep -F 'development agent type: deepseek_developer' "$TEST_HOME/AGENTS.md" >/dev/null 2>&1; then
  fail 'reviewer-only workflow claimed a custom developer'
fi
run_second_lifecycle uninstall reviewer-agent

if CUSTOM_SUBAGENT_HOME="$TEST_HOME" CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://example.test fixture-model >/dev/null 2>&1; then
  fail 'non-HTTPS endpoint was accepted'
fi
if run_lifecycle install deepseek-developer development deepseek http://localhost:11434 '' >/dev/null 2>&1; then
  fail 'empty model was accepted'
fi

assert_same_file "$TEMP_ROOT/config.before" "$TEST_HOME/config.toml"
assert_not_file "$STATE"
assert_not_file "$CATALOG"
assert_not_file "$BASE_CATALOG"

assert_rejected() {
  description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$description was accepted"
  fi
}

snapshot_tree() {
  find "$1" -print | sed "s|$1||" | sort >"$2"
}

assert_tree_unchanged() {
  snapshot_tree "$2" "$3"
  assert_same_file "$1" "$3"
}

SAFETY_HOME="$TEMP_ROOT/safety-home"
OUTSIDE_HOME="$TEMP_ROOT/outside-home"
mkdir -p "$SAFETY_HOME" "$OUTSIDE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$SAFETY_HOME/config.toml"
ln -s "$OUTSIDE_HOME" "$TEMP_ROOT/home-link"
assert_rejected 'symlinked CUSTOM_SUBAGENT_HOME' env \
  CUSTOM_SUBAGENT_HOME="$TEMP_ROOT/home-link" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_not_file "$OUTSIDE_HOME/custom-subagents/state.json"

ln -s "$OUTSIDE_HOME" "$SAFETY_HOME/custom-subagents"
assert_rejected 'symlinked managed child directory' env \
  CUSTOM_SUBAGENT_HOME="$SAFETY_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_not_file "$OUTSIDE_HOME/custom-subagents/state.json"
rm "$SAFETY_HOME/custom-subagents"

mkdir -p "$SAFETY_HOME/agents" "$SAFETY_HOME/custom-subagents"
printf '%s\n' '# custom-subagents: agent=deepseek-developer' >"$SAFETY_HOME/agents/deepseek_developer.toml"
assert_rejected 'incomplete managed agent envelope' env \
  CUSTOM_SUBAGENT_HOME="$SAFETY_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
rm "$SAFETY_HOME/agents/deepseek_developer.toml"

printf '%s\n' '{"version":1,"agents":[{"id":"deepseek-developer","role":"development","provider":"deepseek","endpoint":"https://example.test","model":"m","unexpected":"x"}]}' >"$SAFETY_HOME/custom-subagents/state.json"
assert_rejected 'state with unknown agent field' env \
  CUSTOM_SUBAGENT_HOME="$SAFETY_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
rm "$SAFETY_HOME/custom-subagents/state.json"

INVALID_HOME="$TEMP_ROOT/invalid-preflight"
mkdir -p "$INVALID_HOME/custom-subagents"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$INVALID_HOME/config.toml"
printf '%s\n' '{"version":1,"agents":[{"id":"deepseek-developer","role":"development","provider":"deepseek","endpoint":"https://example.test","model":"m","token":"bad"}]}' >"$INVALID_HOME/custom-subagents/state.json"
snapshot_tree "$INVALID_HOME" "$TEMP_ROOT/invalid.before"
assert_rejected 'invalid existing state without zero-mutation preflight' env \
  CUSTOM_SUBAGENT_HOME="$INVALID_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/invalid.before" "$INVALID_HOME" "$TEMP_ROOT/invalid.after"

DUPLICATE_HOME="$TEMP_ROOT/duplicate-preflight"
mkdir -p "$DUPLICATE_HOME"
cp "$ROOT/tests/fixtures/config-existing-catalog.toml" "$DUPLICATE_HOME/config.toml"
printf '%s\n' 'model_catalog_json = "second-catalog.json"' >>"$DUPLICATE_HOME/config.toml"
snapshot_tree "$DUPLICATE_HOME" "$TEMP_ROOT/duplicate.before"
assert_rejected 'duplicate catalog setting without zero-mutation preflight' env \
  CUSTOM_SUBAGENT_HOME="$DUPLICATE_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/duplicate.before" "$DUPLICATE_HOME" "$TEMP_ROOT/duplicate.after"

for SECRET_ENDPOINT in \
  'https://user:pass@example.test' \
  'https://example.test/v1?api_key=value' \
  'https://example.test/v1#token=value' \
  'https://example.test/authorization' \
  'https://example.test/bearer'; do
  ENDPOINT_HOME="$TEMP_ROOT/endpoint-$RANDOM"
  mkdir -p "$ENDPOINT_HOME"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$ENDPOINT_HOME/config.toml"
  snapshot_tree "$ENDPOINT_HOME" "$TEMP_ROOT/endpoint.before"
  assert_rejected "credential-bearing endpoint $SECRET_ENDPOINT" env \
    CUSTOM_SUBAGENT_HOME="$ENDPOINT_HOME" \
    CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
    sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek "$SECRET_ENDPOINT" fixture-model
  assert_tree_unchanged "$TEMP_ROOT/endpoint.before" "$ENDPOINT_HOME" "$TEMP_ROOT/endpoint.after"
done

reject_clean_input() {
  label=$1
  endpoint=$2
  role=$3
  provider=$4
  model=$5
  INPUT_HOME="$TEMP_ROOT/input-$RANDOM"
  mkdir -p "$INPUT_HOME"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$INPUT_HOME/config.toml"
  snapshot_tree "$INPUT_HOME" "$TEMP_ROOT/input.before"
  assert_rejected "$label" env \
    CUSTOM_SUBAGENT_HOME="$INPUT_HOME" \
    CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
    sh "$ROOT/shared/lifecycle.sh" install deepseek-developer "$role" "$provider" "$endpoint" "$model"
  assert_tree_unchanged "$TEMP_ROOT/input.before" "$INPUT_HOME" "$TEMP_ROOT/input.after"
}

reject_clean_input 'quoted role' 'http://localhost:11434' 'review"' deepseek fixture-model
reject_clean_input 'backslash provider' 'http://localhost:11434' development 'deep\seek' fixture-model
reject_clean_input 'newline model' 'http://localhost:11434' development deepseek "fixture
model"
reject_clean_input 'multiline endpoint' "https://example.test
/v1" development deepseek fixture-model

UNINSTALL_HOME="$TEMP_ROOT/uninstall-preflight"
mkdir -p "$UNINSTALL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$UNINSTALL_HOME/config.toml"
env CUSTOM_SUBAGENT_HOME="$UNINSTALL_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
sed 's/"model": "fixture-model"/"model": "fixture-model", "token": "bad"/' "$UNINSTALL_HOME/custom-subagents/state.json" >"$UNINSTALL_HOME/custom-subagents/state.json.tmp"
mv "$UNINSTALL_HOME/custom-subagents/state.json.tmp" "$UNINSTALL_HOME/custom-subagents/state.json"
snapshot_tree "$UNINSTALL_HOME" "$TEMP_ROOT/uninstall-invalid.before"
assert_rejected 'malformed state uninstall without zero-mutation preflight' env \
  CUSTOM_SUBAGENT_HOME="$UNINSTALL_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  sh "$ROOT/shared/lifecycle.sh" uninstall deepseek-developer
assert_tree_unchanged "$TEMP_ROOT/uninstall-invalid.before" "$UNINSTALL_HOME" "$TEMP_ROOT/uninstall-invalid.after"

sed 's/"token": "bad"/"model": "fixture-model"/' "$UNINSTALL_HOME/custom-subagents/state.json" >"$UNINSTALL_HOME/custom-subagents/state.json.tmp"
mv "$UNINSTALL_HOME/custom-subagents/state.json.tmp" "$UNINSTALL_HOME/custom-subagents/state.json"
sed 's#http://localhost:11434#https://user:pass@example.test#' "$UNINSTALL_HOME/custom-subagents/state.json" >"$UNINSTALL_HOME/custom-subagents/state.json.tmp"
mv "$UNINSTALL_HOME/custom-subagents/state.json.tmp" "$UNINSTALL_HOME/custom-subagents/state.json"
snapshot_tree "$UNINSTALL_HOME" "$TEMP_ROOT/uninstall-endpoint.before"
assert_rejected 'legacy credential endpoint on update' env \
  CUSTOM_SUBAGENT_HOME="$UNINSTALL_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_rejected 'legacy credential endpoint on uninstall' env \
  CUSTOM_SUBAGENT_HOME="$UNINSTALL_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  sh "$ROOT/shared/lifecycle.sh" uninstall deepseek-developer
assert_tree_unchanged "$TEMP_ROOT/uninstall-endpoint.before" "$UNINSTALL_HOME" "$TEMP_ROOT/uninstall-endpoint.after"

TOML_HOME="$TEMP_ROOT/toml-preflight"
mkdir -p "$TOML_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TOML_HOME/config.toml"
env CUSTOM_SUBAGENT_HOME="$TOML_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
sed 's#base_url = "http://localhost:11434"#base_url = "https://user:pass@example.test"#' "$TOML_HOME/agents/deepseek_developer.toml" >"$TOML_HOME/agents/deepseek_developer.toml.tmp"
mv "$TOML_HOME/agents/deepseek_developer.toml.tmp" "$TOML_HOME/agents/deepseek_developer.toml"
snapshot_tree "$TOML_HOME" "$TEMP_ROOT/toml-reinstall.before"
assert_rejected 'credential-bearing managed TOML on reinstall' env \
  CUSTOM_SUBAGENT_HOME="$TOML_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/toml-reinstall.before" "$TOML_HOME" "$TEMP_ROOT/toml-reinstall.after"

TOML_UNINSTALL_HOME="$TEMP_ROOT/toml-uninstall-preflight"
mkdir -p "$TOML_UNINSTALL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TOML_UNINSTALL_HOME/config.toml"
env CUSTOM_SUBAGENT_HOME="$TOML_UNINSTALL_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
sed 's/model = "fixture-model"/model = "review"/' "$TOML_UNINSTALL_HOME/agents/deepseek_developer.toml" >"$TOML_UNINSTALL_HOME/agents/deepseek_developer.toml.tmp"
mv "$TOML_UNINSTALL_HOME/agents/deepseek_developer.toml.tmp" "$TOML_UNINSTALL_HOME/agents/deepseek_developer.toml"
snapshot_tree "$TOML_UNINSTALL_HOME" "$TEMP_ROOT/toml-uninstall.before"
assert_rejected 'registry-mismatched managed TOML on uninstall' env \
  CUSTOM_SUBAGENT_HOME="$TOML_UNINSTALL_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  sh "$ROOT/shared/lifecycle.sh" uninstall deepseek-developer
assert_tree_unchanged "$TEMP_ROOT/toml-uninstall.before" "$TOML_UNINSTALL_HOME" "$TEMP_ROOT/toml-uninstall.after"

sed 's/"wire_api": "responses"/"wire_api": "responses", "secret": "bad"/' "$PLUGIN_ROOT/agent-spec.json" >"$PLUGIN_ROOT/bad-agent-spec.json"
SPEC_HOME="$TEMP_ROOT/spec-preflight"
mkdir -p "$SPEC_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$SPEC_HOME/config.toml"
snapshot_tree "$SPEC_HOME" "$TEMP_ROOT/spec.before"
assert_rejected 'spec with secret field' env \
  CUSTOM_SUBAGENT_HOME="$SPEC_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/bad-agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/spec.before" "$SPEC_HOME" "$TEMP_ROOT/spec.after"

EXTRA_TOML_HOME="$TEMP_ROOT/extra-toml-preflight"
mkdir -p "$EXTRA_TOML_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$EXTRA_TOML_HOME/config.toml"
env CUSTOM_SUBAGENT_HOME="$EXTRA_TOML_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
printf '%s\n' 'secret = "bad"' >>"$EXTRA_TOML_HOME/agents/deepseek_developer.toml"
snapshot_tree "$EXTRA_TOML_HOME" "$TEMP_ROOT/extra-toml.before"
assert_rejected 'extra TOML secret field' env \
  CUSTOM_SUBAGENT_HOME="$EXTRA_TOML_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/extra-toml.before" "$EXTRA_TOML_HOME" "$TEMP_ROOT/extra-toml.after"

MISSING_STATE_HOME="$TEMP_ROOT/missing-state-preflight"
mkdir -p "$MISSING_STATE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MISSING_STATE_HOME/config.toml"
env CUSTOM_SUBAGENT_HOME="$MISSING_STATE_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
rm "$MISSING_STATE_HOME/custom-subagents/state.json"
snapshot_tree "$MISSING_STATE_HOME" "$TEMP_ROOT/missing-state.before"
assert_rejected 'managed TOML without state on reinstall' env \
  CUSTOM_SUBAGENT_HOME="$MISSING_STATE_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/missing-state.before" "$MISSING_STATE_HOME" "$TEMP_ROOT/missing-state.after"

INCOMPLETE_STATE_HOME="$TEMP_ROOT/incomplete-state-preflight"
mkdir -p "$INCOMPLETE_STATE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$INCOMPLETE_STATE_HOME/config.toml"
env CUSTOM_SUBAGENT_HOME="$INCOMPLETE_STATE_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
printf '%s\n' '{"version":1,"agents":[]}' >"$INCOMPLETE_STATE_HOME/custom-subagents/state.json"
snapshot_tree "$INCOMPLETE_STATE_HOME" "$TEMP_ROOT/incomplete-state.before"
assert_rejected 'managed artifacts with incomplete state on reinstall' env \
  CUSTOM_SUBAGENT_HOME="$INCOMPLETE_STATE_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_unchanged "$TEMP_ROOT/incomplete-state.before" "$INCOMPLETE_STATE_HOME" "$TEMP_ROOT/incomplete-state.after"

FAKE_PLUGIN="$TEMP_ROOT/fake-deepseek-developer"
mkdir -p "$FAKE_PLUGIN/.codex-plugin"
cp "$PLUGIN_ROOT/.codex-plugin/plugin.json" "$FAKE_PLUGIN/.codex-plugin/plugin.json"
sed 's/"name": "deepseek-developer"/"name": "wrong-agent"/' "$FAKE_PLUGIN/.codex-plugin/plugin.json" >"$FAKE_PLUGIN/.codex-plugin/plugin.json.tmp"
mv "$FAKE_PLUGIN/.codex-plugin/plugin.json.tmp" "$FAKE_PLUGIN/.codex-plugin/plugin.json"
assert_rejected 'mismatched plugin manifest name' env \
  CUSTOM_SUBAGENT_HOME="$SAFETY_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$FAKE_PLUGIN" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install deepseek-developer development deepseek http://localhost:11434 fixture-model

mkdir -p "$LIVE_HOME/.codex"
assert_rejected 'live home without production approval' env \
  HOME="$LIVE_HOME" \
  CUSTOM_SUBAGENT_HOME="$LIVE_HOME/.codex" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  sh "$ROOT/shared/lifecycle.sh" status
env -u CUSTOM_SUBAGENT_TEST_MODE \
  -u CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE \
  -u CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL \
  HOME="$LIVE_HOME" \
  CUSTOM_SUBAGENT_HOME="$LIVE_HOME/.codex" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_PRODUCTION_MODE=1 \
  CUSTOM_SUBAGENT_PRODUCTION_APPROVAL=custom-subagents-live-home \
  sh "$ROOT/shared/lifecycle.sh" status >/dev/null

printf '%s\n' 'PASS: lifecycle install'
