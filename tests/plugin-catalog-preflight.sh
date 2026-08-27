#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-plugin-catalog-preflight.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

MARKETPLACE="$TEMP_ROOT/test-marketplace"
PLUGIN_ROOT="$MARKETPLACE/plugins/deepseek-agent"
HELPERS="$MARKETPLACE/tests/helpers"
TEST_HOME="$TEMP_ROOT/home"
FAKE_STATE="$TEMP_ROOT/keychain-state"
FAKE_LOG="$TEMP_ROOT/security.log"
DIALOG_LOG="$TEMP_ROOT/dialog.log"
FAKE_CODEX="$TEMP_ROOT/codex"

mkdir -p "$MARKETPLACE/plugins" "$MARKETPLACE/tests" "$TEST_HOME"
cp -R "$ROOT/plugins/deepseek-agent" "$PLUGIN_ROOT"
cp -R "$ROOT/tests/helpers" "$HELPERS"
cp "$ROOT/tests/fixtures/plugin-test-runtime-gate.sh" "$PLUGIN_ROOT/scripts/runtime-gate.sh"
chmod +x "$HELPERS/fake-security.sh" "$HELPERS/fake-osascript.sh"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
: >"$FAKE_STATE"
: >"$FAKE_LOG"
: >"$DIALOG_LOG"

cat >"$FAKE_CODEX" <<'EOF'
#!/bin/sh
[ "$1" = debug ] && [ "$2" = models ] && [ "$3" = --bundled ] || exit 64
printf '%s\n' '{"models":[]}'
EOF
chmod +x "$FAKE_CODEX"

set +e
CODEX_HOME="$TEST_HOME" \
CUSTOM_SUBAGENT_TEST_MODE=1 \
CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE= \
CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
CUSTOM_SUBAGENT_TEST_CODEX_BIN="$FAKE_CODEX" \
CUSTOM_SUBAGENT_SECURITY_BIN="$HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$FAKE_STATE" \
FAKE_SECURITY_LOG="$FAKE_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
FAKE_DIALOG_VALUE=fixture-secret \
sh "$PLUGIN_ROOT/scripts/configure.sh" --model deepseek-chat \
  >"$TEMP_ROOT/configure.out" 2>"$TEMP_ROOT/configure.err"
configure_status=$?
set -e

[ "$configure_status" -ne 0 ] || fail 'invalid bundled catalog was accepted'
assert_contains "$FAKE_LOG" 'add|codex-custom-subagent/deepseek-agent|api-key'
assert_contains "$FAKE_LOG" 'delete|codex-custom-subagent/deepseek-agent|api-key'
assert_contains "$DIALOG_LOG" "$PLUGIN_ROOT/scripts/vendor/prompt-secret.js"
assert_equals 0 "$(wc -c <"$FAKE_STATE" | tr -d ' ')"
assert_not_file "$TEST_HOME/custom-subagents/state.json"
assert_same_file "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"

RACE_HOME="$TEMP_ROOT/race-home"
RACE_CALLS="$TEMP_ROOT/race.calls"
mkdir -p "$RACE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$RACE_HOME/config.toml"
: >"$FAKE_STATE"
: >"$FAKE_LOG"
: >"$DIALOG_LOG"
: >"$RACE_CALLS"
cat >"$FAKE_CODEX" <<'EOF'
#!/bin/sh
[ "$1" = debug ] && [ "$2" = models ] && [ "$3" = --bundled ] || exit 64
printf '%s\n' call >>"$RACE_CALLS"
if [ "$(wc -l <"$RACE_CALLS" | tr -d ' ')" = 1 ]; then
  cat "$FAKE_CODEX_CATALOG"
else
  printf '%s\n' '{"models":[]}'
fi
EOF
chmod +x "$FAKE_CODEX"

CODEX_HOME="$RACE_HOME" \
CUSTOM_SUBAGENT_TEST_MODE=1 \
CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE= \
CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
CUSTOM_SUBAGENT_TEST_CODEX_BIN="$FAKE_CODEX" \
CUSTOM_SUBAGENT_SECURITY_BIN="$HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$HELPERS/fake-osascript.sh" \
FAKE_CODEX_CATALOG="$ROOT/tests/fixtures/models-cache.json" \
RACE_CALLS="$RACE_CALLS" \
FAKE_SECURITY_STATE="$FAKE_STATE" \
FAKE_SECURITY_LOG="$FAKE_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
FAKE_DIALOG_VALUE=fixture-secret \
sh "$PLUGIN_ROOT/scripts/configure.sh" --model deepseek-chat

assert_equals 1 "$(wc -l <"$RACE_CALLS" | tr -d ' ')"
assert_file "$RACE_HOME/custom-subagents/state.json"
assert_contains "$FAKE_STATE" 'codex-custom-subagent/deepseek-agent|api-key'

printf '%s\n' 'PASS: plugin catalog preflight precedes credential prompt'
