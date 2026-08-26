#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-fresh-catalog.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

PLUGIN_ROOT="$TEMP_ROOT/deepseek-agent"
mkdir -p "$PLUGIN_ROOT/.codex-plugin"
printf '%s\n' '{"name":"deepseek-agent"}' >"$PLUGIN_ROOT/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$PLUGIN_ROOT/agent-spec.json"

FAKE_CODEX="$TEMP_ROOT/codex"
apply_fixture_cli() {
  mode=$1
  cat >"$FAKE_CODEX" <<'EOF'
#!/bin/sh
[ "$1" = debug ] && [ "$2" = models ] && [ "$3" = --bundled ] || exit 64
[ -z "${FAKE_CODEX_CALLS:-}" ] || printf '%s\n' "$*" >>"$FAKE_CODEX_CALLS"
case "${FAKE_CODEX_MODE:-valid}" in
  valid) cat "$FAKE_CODEX_CATALOG" ;;
  invalid) printf '%s\n' '{"models":[]}' ;;
  fail) exit 9 ;;
esac
EOF
  chmod +x "$FAKE_CODEX"
  FAKE_CODEX_MODE=$mode
  export FAKE_CODEX_MODE
}

run_install() {
  test_home=$1
  CUSTOM_SUBAGENT_HOME="$test_home" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/agent-spec.json" \
  CUSTOM_SUBAGENT_TEST_MODE=1 \
  CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
  CUSTOM_SUBAGENT_TEST_CODEX_BIN="$FAKE_CODEX" \
  FAKE_CODEX_CATALOG="$ROOT/tests/fixtures/models-cache.json" \
  FAKE_CODEX_CALLS="${FAKE_CODEX_CALLS-}" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" install \
    deepseek-agent deepseek http://localhost:11434 fixture-model
}

apply_fixture_cli valid
FRESH_HOME="$TEMP_ROOT/fresh-home"
mkdir -p "$FRESH_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$FRESH_HOME/config.toml"
run_install "$FRESH_HOME"
assert_file "$FRESH_HOME/custom-subagents/base-model-catalog.json"
assert_same_file "$ROOT/tests/fixtures/models-cache.json" "$FRESH_HOME/custom-subagents/base-model-catalog.json"
assert_contains "$FRESH_HOME/custom-subagents/state.json" '"base_catalog_source_kind": "codex-bundled"'
assert_contains "$FRESH_HOME/custom-subagents/models-v1.json" '"multi_agent_version": "v1"'

apply_fixture_cli invalid
INVALID_HOME="$TEMP_ROOT/invalid-home"
mkdir -p "$INVALID_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$INVALID_HOME/config.toml"
cp -Rp "$INVALID_HOME" "$TEMP_ROOT/invalid-before"
set +e
run_install "$INVALID_HOME" >"$TEMP_ROOT/invalid.out" 2>"$TEMP_ROOT/invalid.err"
invalid_status=$?
set -e
[ "$invalid_status" -ne 0 ] || fail 'invalid bundled catalog was accepted'
diff -r "$TEMP_ROOT/invalid-before" "$INVALID_HOME" >/dev/null 2>&1 ||
  fail 'invalid bundled catalog mutated Codex home'

apply_fixture_cli valid
EXPLICIT_HOME="$TEMP_ROOT/explicit-home"
FAKE_CODEX_CALLS="$TEMP_ROOT/explicit-codex.calls"
export FAKE_CODEX_CALLS
mkdir -p "$EXPLICIT_HOME"
printf '%s\n' \
  'model = "gpt-5.6-sol"' \
  "model_catalog_json = \"$TEMP_ROOT/explicit-missing.json\"" \
  >"$EXPLICIT_HOME/config.toml"
cp -Rp "$EXPLICIT_HOME" "$TEMP_ROOT/explicit-before"
: >"$FAKE_CODEX_CALLS"
set +e
run_install "$EXPLICIT_HOME" >"$TEMP_ROOT/explicit.out" 2>"$TEMP_ROOT/explicit.err"
explicit_status=$?
set -e
[ "$explicit_status" -ne 0 ] || fail 'missing explicit catalog was accepted'
[ ! -s "$FAKE_CODEX_CALLS" ] || fail 'explicit catalog failure invoked Codex bundled fallback'
diff -r "$TEMP_ROOT/explicit-before" "$EXPLICIT_HOME" >/dev/null 2>&1 ||
  fail 'explicit catalog failure mutated Codex home'

printf '%s\n' 'PASS: fresh-home bundled catalog fallback'
