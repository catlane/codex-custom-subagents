#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-production-hooks.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

PLUGIN_ROOT="$TEMP_ROOT/deepseek-agent"
mkdir -p "$PLUGIN_ROOT/.codex-plugin"
cp "$ROOT/plugins/deepseek-agent/.codex-plugin/plugin.json" "$PLUGIN_ROOT/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$PLUGIN_ROOT/agent-spec.json"

snapshot_tree() {
  find "$1" -type f -exec cksum {} \; | sed "s|$1||" | sort >"$2"
  find "$1" -type d | sed "s|$1||" | sort >>"$2"
}

reject_production_hook() {
  hook_name=$1
  hook_value=$2
  hook_home="$TEMP_ROOT/$hook_name-home"
  mkdir -p "$hook_home"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$hook_home/config.toml"
  cp "$ROOT/tests/fixtures/models-cache.json" "$hook_home/models_cache.json"
  snapshot_tree "$hook_home" "$TEMP_ROOT/$hook_name.before"

  set +e
  env CUSTOM_SUBAGENT_HOME="$hook_home" \
    CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
    CUSTOM_SUBAGENT_PRODUCTION_MODE=1 \
    "$hook_name=$hook_value" \
    sh "$ROOT/shared/lifecycle.sh" \
      install deepseek-agent deepseek https://example.test/v1 fixture-model \
      >"$TEMP_ROOT/$hook_name.out" 2>"$TEMP_ROOT/$hook_name.err"
  hook_status=$?
  set -e

  [ "$hook_status" -ne 0 ] || fail "$hook_name was accepted in production mode"
  snapshot_tree "$hook_home" "$TEMP_ROOT/$hook_name.after"
  assert_same_file "$TEMP_ROOT/$hook_name.before" "$TEMP_ROOT/$hook_name.after"
  assert_contains "$TEMP_ROOT/$hook_name.err" 'test hooks are forbidden in production mode'
}

reject_production_hook CUSTOM_SUBAGENT_TEST_MODE 1
reject_production_hook CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE "$ROOT/tests/fixtures/models-cache.json"
reject_production_hook CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL gpt-5.6-sol
reject_production_hook CUSTOM_SUBAGENT_ALLOW_HTTP 1

HTTPS_HOME="$TEMP_ROOT/https-home"
mkdir -p "$HTTPS_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$HTTPS_HOME/config.toml"
cp "$ROOT/tests/fixtures/models-cache.json" "$HTTPS_HOME/models_cache.json"
CUSTOM_SUBAGENT_HOME="$HTTPS_HOME" \
CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
CUSTOM_SUBAGENT_PRODUCTION_MODE=1 \
sh "$ROOT/shared/lifecycle.sh" \
  install deepseek-agent deepseek https://example.test/v1 fixture-model
assert_file "$HTTPS_HOME/custom-subagents/state.json"
for profile in general developer reviewer; do
  assert_file "$HTTPS_HOME/agents/deepseek_$profile.toml"
done

HTTP_HOME="$TEMP_ROOT/http-home"
mkdir -p "$HTTP_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$HTTP_HOME/config.toml"
cp "$ROOT/tests/fixtures/models-cache.json" "$HTTP_HOME/models_cache.json"
set +e
CUSTOM_SUBAGENT_HOME="$HTTP_HOME" \
CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
CUSTOM_SUBAGENT_PRODUCTION_MODE=1 \
sh "$ROOT/shared/lifecycle.sh" \
  install deepseek-agent deepseek http://localhost:11434 fixture-model \
  >"$TEMP_ROOT/http.out" 2>"$TEMP_ROOT/http.err"
http_status=$?
set -e
[ "$http_status" -ne 0 ] || fail 'HTTP endpoint was accepted in production mode'
assert_not_file "$HTTP_HOME/custom-subagents/state.json"

printf '%s\n' 'PASS: lifecycle production hooks'
