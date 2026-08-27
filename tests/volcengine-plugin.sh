#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE_TEST_HELPERS="$ROOT/tests/helpers"
TEST_HELPERS=$SOURCE_TEST_HELPERS
. "$TEST_HELPERS/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

assert_not_contains() {
  file=$1
  needle=$2
  if [ -f "$file" ] && grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    fail "unexpected text in $file: $needle"
  fi
}

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-volcengine-plugin.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
PLUGIN_ROOT="$ROOT/plugins/volcengine-agent"
SOURCE_PLUGIN_ROOT=$PLUGIN_ROOT
SOURCE_DEEPSEEK_ROOT="$ROOT/plugins/deepseek-agent"
DEEPSEEK_ROOT=$SOURCE_DEEPSEEK_ROOT
CONFIGURE="$PLUGIN_ROOT/scripts/configure.sh"
UNINSTALL="$PLUGIN_ROOT/scripts/uninstall.sh"
VENDOR="$PLUGIN_ROOT/scripts/vendor"
[ -x "$CONFIGURE" ] || fail 'Volcengine configure entrypoint is not executable'
[ -x "$UNINSTALL" ] || fail 'Volcengine uninstall entrypoint is not executable'
TEST_HOME="$TEMP_ROOT/codex-home"
CAPTURED="$TEMP_ROOT/captured"
FAKE_STATE="$TEMP_ROOT/keychain-state"
FAKE_LOG="$CAPTURED/security.log"
FAKE_DIALOG_SCRIPT_LOG="$CAPTURED/dialog-scripts.log"
ENDPOINT='https://ark.example.volces.com/api/v3'
MODEL='ep-20250825-review'
SENTINEL='SECRET_MUST_NOT_APPEAR_TASK5_74B1'
SERVICE='codex-custom-subagent/volcengine-agent'
DEEPSEEK_SERVICE='codex-custom-subagent/deepseek-agent'

mkdir -p "$TEST_HOME" "$CAPTURED"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TEST_HOME/config.toml"
: >"$FAKE_STATE"
: >"$FAKE_LOG"
: >"$FAKE_DIALOG_SCRIPT_LOG"

run_configure() {
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
  FAKE_SECURITY_FAIL="${FAKE_SECURITY_FAIL-}" \
  FAKE_SECURITY_FAIL_STATUS="${FAKE_SECURITY_FAIL_STATUS-}" \
  FAKE_DIALOG_VALUE="${FAKE_DIALOG_VALUE-}" \
  FAKE_DIALOG_MODE="${FAKE_DIALOG_MODE-accept}" \
  CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="${CUSTOM_SUBAGENT_FAIL_AFTER_WRITE-}" \
  sh "$CONFIGURE" --endpoint "${1:-$ENDPOINT}" --model "${2:-$MODEL}"
}

run_uninstall() {
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
  FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_SECURITY_FAIL="${FAKE_SECURITY_FAIL-}" \
  FAKE_SECURITY_FAIL_STATUS="${FAKE_SECURITY_FAIL_STATUS-}" \
  sh "$UNINSTALL"
}

run_deepseek_configure() {
  CODEX_HOME="$TEST_HOME" \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
  FAKE_SECURITY_STATE="$FAKE_STATE" FAKE_SECURITY_LOG="$FAKE_LOG" \
  FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_DIALOG_VALUE=deepseek-test-secret \
  sh "$DEEPSEEK_ROOT/scripts/configure.sh" --model deepseek-chat
}

PATH_PROBE_BIN="$TEMP_ROOT/path-probe-bin"
PATH_PROBE_LOG="$CAPTURED/path-probe.log"
mkdir -p "$PATH_PROBE_BIN"
: >"$PATH_PROBE_LOG"
for command_name in dirname sh security; do
  cp "$TEST_HELPERS/path-probe.sh" "$PATH_PROBE_BIN/$command_name"
  chmod +x "$PATH_PROBE_BIN/$command_name"
done
for source_entry in "$SOURCE_PLUGIN_ROOT/scripts/configure.sh" "$SOURCE_PLUGIN_ROOT/scripts/uninstall.sh"; do
  set +e
  PATH="$PATH_PROBE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" PATH_PROBE_LOG="$PATH_PROBE_LOG" \
  CODEX_HOME="$TEST_HOME" CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1 \
    /bin/sh "$source_entry" >"$CAPTURED/path-probe.out" 2>"$CAPTURED/path-probe.err"
  path_probe_status=$?
  set -e
  [ "$path_probe_status" -ne 0 ] || fail 'production entry accepted a lifecycle test hook under malicious PATH'
done
assert_equals 0 "$(wc -l <"$PATH_PROBE_LOG" | tr -d ' ')"

FORGED_MARKETPLACE="$TEMP_ROOT/forged-marketplace"
FORGED_PLUGIN="$FORGED_MARKETPLACE/plugins/volcengine-agent"
FORGED_HELPERS_ROOT="$FORGED_MARKETPLACE/tests/helpers"
mkdir -p "$FORGED_MARKETPLACE/plugins" "$FORGED_MARKETPLACE/tests"
cp -R "$SOURCE_PLUGIN_ROOT" "$FORGED_PLUGIN"
cp -R "$TEST_HELPERS" "$FORGED_HELPERS_ROOT"

FORGED_CONFIG_HOME="$TEMP_ROOT/forged-config-home"
FORGED_CONFIG_STATE="$TEMP_ROOT/forged-config-keychain"
FORGED_CONFIG_LOG="$CAPTURED/forged-config-security.log"
mkdir -p "$FORGED_CONFIG_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$FORGED_CONFIG_HOME/config.toml"
: >"$FORGED_CONFIG_STATE"
: >"$FORGED_CONFIG_LOG"
forged_config_before=$(cksum "$FORGED_CONFIG_HOME/config.toml")
set +e
CODEX_HOME="$FORGED_CONFIG_HOME" CUSTOM_SUBAGENT_TEST_MODE=1 \
CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol \
CUSTOM_SUBAGENT_SECURITY_BIN="$FORGED_HELPERS_ROOT/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FORGED_HELPERS_ROOT/fake-osascript.sh" \
FAKE_SECURITY_STATE="$FORGED_CONFIG_STATE" FAKE_SECURITY_LOG="$FORGED_CONFIG_LOG" \
FAKE_DIALOG_VALUE=forged-secret sh "$FORGED_PLUGIN/scripts/configure.sh" --endpoint "$ENDPOINT" --model "$MODEL" \
  >"$CAPTURED/forged-config.out" 2>"$CAPTURED/forged-config.err"
forged_config_status=$?
set -e
[ "$forged_config_status" -ne 0 ] || fail 'production configure accepted a complete forged marketplace harness'
assert_equals "$forged_config_before" "$(cksum "$FORGED_CONFIG_HOME/config.toml")"
assert_not_file "$FORGED_CONFIG_HOME/custom-subagents/state.json"
assert_equals 0 "$(wc -l <"$FORGED_CONFIG_LOG" | tr -d ' ')"

FORGED_UNINSTALL_HOME="$TEMP_ROOT/forged-uninstall-home"
FORGED_UNINSTALL_STATE="$TEMP_ROOT/forged-uninstall-keychain"
FORGED_UNINSTALL_LOG="$CAPTURED/forged-uninstall-security.log"
mkdir -p "$FORGED_UNINSTALL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$FORGED_UNINSTALL_HOME/config.toml"
printf '%s\n' "$SERVICE|api-key" >"$FORGED_UNINSTALL_STATE"
: >"$FORGED_UNINSTALL_LOG"
set +e
CODEX_HOME="$FORGED_UNINSTALL_HOME" CUSTOM_SUBAGENT_TEST_MODE=1 \
CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
CUSTOM_SUBAGENT_SECURITY_BIN="$FORGED_HELPERS_ROOT/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FORGED_HELPERS_ROOT/fake-osascript.sh" \
FAKE_SECURITY_STATE="$FORGED_UNINSTALL_STATE" FAKE_SECURITY_LOG="$FORGED_UNINSTALL_LOG" \
sh "$FORGED_PLUGIN/scripts/uninstall.sh" >"$CAPTURED/forged-uninstall.out" 2>"$CAPTURED/forged-uninstall.err"
forged_uninstall_status=$?
set -e
[ "$forged_uninstall_status" -ne 0 ] || fail 'production uninstall accepted a complete forged marketplace harness'
assert_contains "$FORGED_UNINSTALL_STATE" "$SERVICE|api-key"
assert_equals 0 "$(wc -l <"$FORGED_UNINSTALL_LOG" | tr -d ' ')"

TEST_MARKETPLACE="$TEMP_ROOT/test-marketplace"
PLUGIN_ROOT="$TEST_MARKETPLACE/plugins/volcengine-agent"
TEST_HELPERS="$TEST_MARKETPLACE/tests/helpers"
mkdir -p "$TEST_MARKETPLACE/plugins" "$TEST_MARKETPLACE/tests"
cp -R "$SOURCE_PLUGIN_ROOT" "$PLUGIN_ROOT"
DEEPSEEK_ROOT="$TEST_MARKETPLACE/plugins/deepseek-agent"
cp -R "$SOURCE_DEEPSEEK_ROOT" "$DEEPSEEK_ROOT"
cp -R "$SOURCE_TEST_HELPERS" "$TEST_HELPERS"
cp "$ROOT/tests/fixtures/plugin-test-runtime-gate.sh" "$PLUGIN_ROOT/scripts/runtime-gate.sh"
cp "$ROOT/tests/fixtures/plugin-test-runtime-gate.sh" "$DEEPSEEK_ROOT/scripts/runtime-gate.sh"
CONFIGURE="$PLUGIN_ROOT/scripts/configure.sh"
UNINSTALL="$PLUGIN_ROOT/scripts/uninstall.sh"
VENDOR="$PLUGIN_ROOT/scripts/vendor"

assert_configure_gate_rejects() {
  case_name=$1
  gate_home="$TEMP_ROOT/gate-$case_name-home"
  gate_state="$TEMP_ROOT/gate-$case_name-keychain"
  gate_log="$CAPTURED/gate-$case_name-security.log"
  mkdir -p "$gate_home"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$gate_home/config.toml"
  : >"$gate_state"
  : >"$gate_log"
  gate_config_before=$(cksum "$gate_home/config.toml")
  shift
  set +e
  env CODEX_HOME="$gate_home" FAKE_SECURITY_STATE="$gate_state" FAKE_SECURITY_LOG="$gate_log" \
    FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_DIALOG_VALUE=gate-secret \
    "$@" sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" \
    >"$CAPTURED/gate-$case_name.out" 2>"$CAPTURED/gate-$case_name.err"
  gate_status=$?
  set -e
  [ "$gate_status" -ne 0 ] || fail "configure harness gate accepted $case_name"
  assert_contains "$CAPTURED/gate-$case_name.err" 'test harness'
  assert_equals "$gate_config_before" "$(cksum "$gate_home/config.toml")"
  assert_not_file "$gate_home/custom-subagents/state.json"
  assert_equals 0 "$(wc -l <"$gate_log" | tr -d ' ')"
}

assert_configure_gate_rejects missing-approval \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL= \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh"
assert_configure_gate_rejects partial-override \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" CUSTOM_SUBAGENT_OSASCRIPT_BIN=
assert_configure_gate_rejects uncontrolled-helpers \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_SECURITY_BIN=/usr/bin/true \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN=/usr/bin/false
FORGED_HELPERS="$TEMP_ROOT/evil/tests/helpers"
mkdir -p "$FORGED_HELPERS"
cp "$TEST_HELPERS/fake-security.sh" "$FORGED_HELPERS/fake-security.sh"
cp "$TEST_HELPERS/fake-osascript.sh" "$FORGED_HELPERS/fake-osascript.sh"
chmod +x "$FORGED_HELPERS/fake-security.sh" "$FORGED_HELPERS/fake-osascript.sh"
assert_configure_gate_rejects forged-tests-helpers \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_SECURITY_BIN="$FORGED_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FORGED_HELPERS/fake-osascript.sh"
assert_configure_gate_rejects production-hooks \
  CUSTOM_SUBAGENT_TEST_MODE= CUSTOM_SUBAGENT_TEST_APPROVAL= \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
  CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1 CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

assert_uninstall_gate_rejects() {
  case_name=$1
  gate_home="$TEMP_ROOT/uninstall-gate-$case_name-home"
  gate_state="$TEMP_ROOT/uninstall-gate-$case_name-keychain"
  gate_log="$CAPTURED/uninstall-gate-$case_name-security.log"
  mkdir -p "$gate_home"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$gate_home/config.toml"
  printf '%s\n' "$SERVICE|api-key" >"$gate_state"
  : >"$gate_log"
  gate_config_before=$(cksum "$gate_home/config.toml")
  shift
  set +e
  env CODEX_HOME="$gate_home" FAKE_SECURITY_STATE="$gate_state" FAKE_SECURITY_LOG="$gate_log" \
    "$@" sh "$UNINSTALL" >"$CAPTURED/uninstall-gate-$case_name.out" 2>"$CAPTURED/uninstall-gate-$case_name.err"
  gate_status=$?
  set -e
  [ "$gate_status" -ne 0 ] || fail "uninstall harness gate accepted $case_name"
  assert_contains "$CAPTURED/uninstall-gate-$case_name.err" 'test harness'
  assert_equals "$gate_config_before" "$(cksum "$gate_home/config.toml")"
  assert_contains "$gate_state" "$SERVICE|api-key"
  assert_equals 0 "$(wc -l <"$gate_log" | tr -d ' ')"
}

assert_uninstall_gate_rejects missing-approval \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL= \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh"
assert_uninstall_gate_rejects partial-override \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" CUSTOM_SUBAGENT_OSASCRIPT_BIN=
assert_uninstall_gate_rejects uncontrolled-helpers \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_SECURITY_BIN=/usr/bin/true \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN=/usr/bin/false
assert_uninstall_gate_rejects forged-tests-helpers \
  CUSTOM_SUBAGENT_TEST_MODE=1 CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness \
  CUSTOM_SUBAGENT_SECURITY_BIN="$FORGED_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FORGED_HELPERS/fake-osascript.sh"
assert_uninstall_gate_rejects production-hooks \
  CUSTOM_SUBAGENT_TEST_MODE= CUSTOM_SUBAGENT_TEST_APPROVAL= \
  CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
  CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1 CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json" \
  CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

assert_legacy_guard_rejects() {
  operation=$1
  residue=$2
  legacy_plugin=$3
  legacy_home="$TEMP_ROOT/legacy-$legacy_plugin-$operation-$residue-home"
  legacy_keychain="$TEMP_ROOT/legacy-$legacy_plugin-$operation-$residue-keychain"
  legacy_log="$CAPTURED/legacy-$legacy_plugin-$operation-$residue-security.log"
  legacy_err="$CAPTURED/legacy-$legacy_plugin-$operation-$residue.err"
  mkdir -p "$legacy_home/custom-subagents" "$legacy_home/agents"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$legacy_home/config.toml"
  case "$legacy_plugin:$residue" in
    deepseek-developer:state)
      printf '%s\n' '{"version":1,"catalog_path":"/private/tmp/models-v1.json","base_catalog_path":"/private/tmp/base-model-catalog.json","base_catalog_source":"/private/tmp/models-cache.json","base_catalog_source_kind":"test-override","primary_model":"gpt-5.6-sol","initial_agents_shape":"absent","initial_config_shape":"ends-newline","original_model_catalog_line":null,"agents":[{"id":"deepseek-developer","role":"development","provider":"deepseek","endpoint":"https://legacy.example/v1","model":"legacy-model"}]}' >"$legacy_home/custom-subagents/state.json"
      legacy_target="$legacy_home/custom-subagents/state.json"
      ;;
    volcengine-reviewer:state)
      printf '%s\n' '{"version":1,"catalog_path":"/private/tmp/models-v1.json","base_catalog_path":"/private/tmp/base-model-catalog.json","base_catalog_source":"/private/tmp/models-cache.json","base_catalog_source_kind":"test-override","primary_model":"gpt-5.6-sol","initial_agents_shape":"absent","initial_config_shape":"ends-newline","original_model_catalog_line":null,"agents":[{"id":"volcengine-reviewer","role":"review","provider":"volcengine","endpoint":"https://legacy.example/v1","model":"legacy-model"}]}' >"$legacy_home/custom-subagents/state.json"
      legacy_target="$legacy_home/custom-subagents/state.json"
      ;;
    deepseek-developer:file)
      printf '%s\n' \
        '# BEGIN custom-subagents managed agent id=deepseek-developer plugin=deepseek-developer' \
        '# legacy fixed-role managed agent' \
        '# END custom-subagents managed agent id=deepseek-developer plugin=deepseek-developer' \
        >"$legacy_home/agents/deepseek_developer.toml"
      legacy_target="$legacy_home/agents/deepseek_developer.toml"
      ;;
    volcengine-reviewer:file)
      printf '%s\n' \
        '# BEGIN custom-subagents managed agent id=volcengine-reviewer plugin=volcengine-reviewer' \
        '# legacy fixed-role managed agent' \
        '# END custom-subagents managed agent id=volcengine-reviewer plugin=volcengine-reviewer' \
        >"$legacy_home/agents/volcengine_reviewer.toml"
      legacy_target="$legacy_home/agents/volcengine_reviewer.toml"
      ;;
    *) fail "unknown legacy residue: $legacy_plugin/$residue" ;;
  esac
  printf '%s\n' 'codex-custom-subagent/volcengine-agent|api-key' >"$legacy_keychain"
  : >"$legacy_log"
  legacy_config_before=$(cksum "$legacy_home/config.toml")
  legacy_target_before=$(cksum "$legacy_target")
  legacy_dialog_before=$(cksum "$FAKE_DIALOG_SCRIPT_LOG")
  set +e
  case "$operation" in
    configure)
      CODEX_HOME="$legacy_home" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
      CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
      FAKE_SECURITY_STATE="$legacy_keychain" FAKE_SECURITY_LOG="$legacy_log" \
      FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_DIALOG_VALUE=legacy-secret \
      sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" \
        >"$CAPTURED/legacy-$legacy_plugin-$operation-$residue.out" 2>"$legacy_err"
      ;;
    uninstall)
      CODEX_HOME="$legacy_home" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
      CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
      FAKE_SECURITY_STATE="$legacy_keychain" FAKE_SECURITY_LOG="$legacy_log" \
      sh "$UNINSTALL" >"$CAPTURED/legacy-$legacy_plugin-$operation-$residue.out" 2>"$legacy_err"
      ;;
  esac
  legacy_status=$?
  set -e
  [ "$legacy_status" -ne 0 ] || fail "$operation accepted legacy $residue"
  assert_equals "volcengine-agent: migration required legacy-plugin=$legacy_plugin" "$(cat "$legacy_err")"
  assert_equals "$legacy_config_before" "$(cksum "$legacy_home/config.toml")"
  assert_equals "$legacy_target_before" "$(cksum "$legacy_target")"
  assert_equals "$legacy_dialog_before" "$(cksum "$FAKE_DIALOG_SCRIPT_LOG")"
  assert_equals 0 "$(grep -E -c -- '^(add|delete)[|]' "$legacy_log" || true)"
  assert_contains "$legacy_keychain" 'codex-custom-subagent/volcengine-agent|api-key'
  assert_not_file "$legacy_home/.custom-subagents-lifecycle.lock"
}

for legacy_plugin in deepseek-developer volcengine-reviewer; do
  for legacy_operation in configure uninstall; do
    for legacy_residue in state file; do
      assert_legacy_guard_rejects "$legacy_operation" "$legacy_residue" "$legacy_plugin"
    done
  done
done

assert_lock_precedes_legacy_guard() {
  operation=$1
  lock_home="$TEMP_ROOT/legacy-busy-$operation-home"
  lock_keychain="$TEMP_ROOT/legacy-busy-$operation-keychain"
  lock_log="$CAPTURED/legacy-busy-$operation-security.log"
  lock_err="$CAPTURED/legacy-busy-$operation.err"
  mkdir -p "$lock_home/agents" "$lock_home/.custom-subagents-lifecycle.lock"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$lock_home/config.toml"
  printf '%s\n' \
    '# BEGIN custom-subagents managed agent id=deepseek-developer plugin=deepseek-developer' \
    '# END custom-subagents managed agent id=deepseek-developer plugin=deepseek-developer' \
    >"$lock_home/agents/deepseek_developer.toml"
  printf '%s\n' 'codex-custom-subagent/volcengine-agent|api-key' >"$lock_keychain"
  : >"$lock_log"
  set +e
  case "$operation" in
    configure)
      CODEX_HOME="$lock_home" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
      CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
      FAKE_SECURITY_STATE="$lock_keychain" FAKE_SECURITY_LOG="$lock_log" \
      FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_DIALOG_VALUE=legacy-secret \
      sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" \
        >"$CAPTURED/legacy-busy-$operation.out" 2>"$lock_err"
      ;;
    uninstall)
      CODEX_HOME="$lock_home" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
      CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
      FAKE_SECURITY_STATE="$lock_keychain" FAKE_SECURITY_LOG="$lock_log" \
      sh "$UNINSTALL" >"$CAPTURED/legacy-busy-$operation.out" 2>"$lock_err"
      ;;
  esac
  lock_status=$?
  set -e
  assert_equals 75 "$lock_status"
  assert_contains "$lock_err" 'another lifecycle operation is active'
  assert_not_contains "$lock_err" 'migration required'
  assert_equals 0 "$(grep -E -c -- '^(add|delete)[|]' "$lock_log" || true)"
}

assert_lock_precedes_legacy_guard configure
assert_lock_precedes_legacy_guard uninstall

for file in lifecycle.sh operation-lock.sh state.js keychain.sh prompt-secret.js; do
  assert_same_file "$ROOT/shared/$file" "$VENDOR/$file"
done

# Omitting --endpoint uses Volcengine's official Ark endpoint by default.
DEFAULT_ENDPOINT='https://ark.cn-beijing.volces.com/api/plan/v3'
DEFAULT_HOME="$TEMP_ROOT/default-endpoint-home"
DEFAULT_STATE="$TEMP_ROOT/default-endpoint-keychain-state"
DEFAULT_LOG="$CAPTURED/default-endpoint-security.log"
mkdir -p "$DEFAULT_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$DEFAULT_HOME/config.toml"
: >"$DEFAULT_STATE"
: >"$DEFAULT_LOG"
FAKE_DIALOG_VALUE=default-endpoint-secret \
CODEX_HOME="$DEFAULT_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$DEFAULT_STATE" FAKE_SECURITY_LOG="$DEFAULT_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
sh "$CONFIGURE" --model "$MODEL" >"$CAPTURED/default-endpoint.out" 2>"$CAPTURED/default-endpoint.err"
assert_contains "$DEFAULT_HOME/agents/volcengine_developer.toml" "base_url = \"$DEFAULT_ENDPOINT\""
assert_not_contains "$DEFAULT_HOME/agents/volcengine_developer.toml" 'rabbit-api.com'
CODEX_HOME="$DEFAULT_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$DEFAULT_STATE" FAKE_SECURITY_LOG="$DEFAULT_LOG" \
sh "$UNINSTALL" >"$CAPTURED/default-uninstall.out" 2>"$CAPTURED/default-uninstall.err"

# A copied marketplace cache must be standalone and use its vendored prompt.
STANDALONE_MARKETPLACE="$TEMP_ROOT/standalone-marketplace"
COPIED_PLUGIN="$STANDALONE_MARKETPLACE/plugins/volcengine-agent"
STANDALONE_HELPERS="$STANDALONE_MARKETPLACE/tests/helpers"
STANDALONE_HOME="$TEMP_ROOT/standalone-home"
UNRELATED_CWD="$TEMP_ROOT/unrelated-cwd"
mkdir -p "$STANDALONE_MARKETPLACE/plugins" "$STANDALONE_MARKETPLACE/tests"
cp -R "$PLUGIN_ROOT" "$COPIED_PLUGIN"
cp -R "$TEST_HELPERS" "$STANDALONE_HELPERS"
mkdir -p "$STANDALONE_HOME" "$UNRELATED_CWD"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$STANDALONE_HOME/config.toml"
STANDALONE_STATE="$TEMP_ROOT/standalone-keychain-state"
STANDALONE_LOG="$CAPTURED/standalone-security.log"
: >"$STANDALONE_STATE"
: >"$STANDALONE_LOG"
FAKE_DIALOG_VALUE=standalone-secret \
CODEX_HOME="$STANDALONE_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$STANDALONE_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$STANDALONE_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$STANDALONE_STATE" FAKE_SECURITY_LOG="$STANDALONE_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
sh -c 'cd "$1" && sh "$2" --endpoint "$3" --model "$4"' sh "$UNRELATED_CWD" \
  "$COPIED_PLUGIN/scripts/configure.sh" "$ENDPOINT" "$MODEL" \
  >"$CAPTURED/standalone.out" 2>"$CAPTURED/standalone.err"
assert_contains "$FAKE_DIALOG_SCRIPT_LOG" "$COPIED_PLUGIN/scripts/vendor/prompt-secret.js"

# Install DeepSeek first, then Volcengine, to prove provider coexistence.
run_deepseek_configure >"$CAPTURED/deepseek.out" 2>"$CAPTURED/deepseek.err"
sed 's/model = "gpt-5.6-sol"/model = "gpt-5.6-luna"/' \
  "$TEST_HOME/config.toml" >"$CAPTURED/config.luna.toml"
mv "$CAPTURED/config.luna.toml" "$TEST_HOME/config.toml"
FAKE_DIALOG_VALUE=$SENTINEL
run_configure >"$CAPTURED/configure.out" 2>"$CAPTURED/configure.err"

STATE="$TEST_HOME/custom-subagents/state.json"
CATALOG="$TEST_HOME/custom-subagents/models-v1.json"
GENERAL_AGENT="$TEST_HOME/agents/volcengine_general.toml"
DEVELOPER_AGENT="$TEST_HOME/agents/volcengine_developer.toml"
REVIEWER_AGENT="$TEST_HOME/agents/volcengine_reviewer.toml"
AGENT=$REVIEWER_AGENT
DEEPSEEK_GENERAL_AGENT="$TEST_HOME/agents/deepseek_general.toml"
DEEPSEEK_DEVELOPER_AGENT="$TEST_HOME/agents/deepseek_developer.toml"
DEEPSEEK_REVIEWER_AGENT="$TEST_HOME/agents/deepseek_reviewer.toml"

assert_file "$STATE"
assert_file "$CATALOG"
assert_file "$GENERAL_AGENT"
assert_file "$DEVELOPER_AGENT"
assert_file "$REVIEWER_AGENT"
assert_file "$DEEPSEEK_GENERAL_AGENT"
assert_file "$DEEPSEEK_DEVELOPER_AGENT"
assert_file "$DEEPSEEK_REVIEWER_AGENT"
assert_contains "$STATE" '"id": "volcengine-agent"'
assert_not_contains "$STATE" '"role":'
assert_contains "$STATE" '"provider": "volcengine"'
assert_contains "$STATE" "\"endpoint\": \"$ENDPOINT\""
assert_contains "$STATE" "\"model\": \"$MODEL\""
assert_contains "$STATE" '"id": "deepseek-agent"'
assert_contains "$CATALOG" '"id": "official:gpt-5.6-sol"'
assert_contains "$CATALOG" '"id": "official:gpt-5.6-luna"'
assert_contains "$CATALOG" '"slug": "unrelated-model"'
assert_contains "$CATALOG" '"multi_agent_version": "v1"'
assert_not_contains "$CATALOG" "volcengine:$MODEL"
assert_contains "$TEST_HOME/AGENTS.md" 'provider deepseek agent types: deepseek_general, deepseek_developer, deepseek_reviewer.'
assert_contains "$TEST_HOME/AGENTS.md" 'provider volcengine agent types: volcengine_general, volcengine_developer, volcengine_reviewer.'
assert_contains "$TEST_HOME/AGENTS.md" 'An explicit custom provider and/or role request overrides automatic selection.'

for role in general developer reviewer; do
  profile_agent="$TEST_HOME/agents/volcengine_${role}.toml"
  expected_agent=$(/usr/bin/osascript -l JavaScript "$VENDOR/state.js" render-agent-spec-state \
    "$PLUGIN_ROOT/templates/agent-spec.json" "$STATE" volcengine-agent "$role" "$CATALOG" "$SERVICE")
  expected_envelope=$(printf '%s\n%s\n%s' \
    "# BEGIN custom-subagents managed agent provider=volcengine-agent role=$role plugin=volcengine-agent" \
    "$expected_agent" \
    "# END custom-subagents managed agent provider=volcengine-agent role=$role plugin=volcengine-agent")
  assert_equals "$expected_envelope" "$(cat "$profile_agent")"
  assert_contains "$profile_agent" "name = \"volcengine_$role\""
  assert_contains "$profile_agent" 'model_provider = "volcengine"'
  assert_contains "$profile_agent" "base_url = \"$ENDPOINT\""
  assert_contains "$profile_agent" 'wire_api = "responses"'
  assert_contains "$profile_agent" 'requires_openai_auth = false'
  assert_contains "$profile_agent" 'args = ["find-generic-password", "-w", "-s", "codex-custom-subagent/volcengine-agent", "-a", "api-key"]'
  assert_not_contains "$profile_agent" '[agent]'
done
assert_not_contains "$GENERAL_AGENT" 'sandbox_mode = "read-only"'
assert_not_contains "$GENERAL_AGENT" 'approval_policy = "never"'
assert_not_contains "$DEVELOPER_AGENT" 'sandbox_mode = "read-only"'
assert_not_contains "$DEVELOPER_AGENT" 'approval_policy = "never"'
assert_contains "$REVIEWER_AGENT" 'sandbox_mode = "read-only"'
assert_contains "$REVIEWER_AGENT" 'approval_policy = "never"'
assert_contains "$REVIEWER_AGENT" 'read-only'
assert_contains "$REVIEWER_AGENT" 'findings first'
assert_contains "$REVIEWER_AGENT" 'severity'
assert_contains "$REVIEWER_AGENT" 'file and line evidence'
assert_contains "$REVIEWER_AGENT" 'correctness, security, data integrity, and regression'
assert_contains "$REVIEWER_AGENT" 'remaining test gaps'
assert_contains "$REVIEWER_AGENT" 'Do not edit files'

# Existing credentials are reused without re-prompting or replacement.
state_sum=$(cksum "$STATE")
general_agent_sum=$(cksum "$GENERAL_AGENT")
developer_agent_sum=$(cksum "$DEVELOPER_AGENT")
reviewer_agent_sum=$(cksum "$REVIEWER_AGENT")
dialog_sum=$(cksum "$FAKE_DIALOG_SCRIPT_LOG")
FAKE_DIALOG_VALUE='SECOND_SECRET_MUST_NOT_BE_USED'
run_configure >"$CAPTURED/reconfigure.out" 2>"$CAPTURED/reconfigure.err"
assert_equals "$state_sum" "$(cksum "$STATE")"
assert_equals "$general_agent_sum" "$(cksum "$GENERAL_AGENT")"
assert_equals "$developer_agent_sum" "$(cksum "$DEVELOPER_AGENT")"
assert_equals "$reviewer_agent_sum" "$(cksum "$REVIEWER_AGENT")"
assert_equals "$dialog_sum" "$(cksum "$FAKE_DIALOG_SCRIPT_LOG")"
assert_equals 1 "$(grep -F -c -- "add|$SERVICE|api-key" "$FAKE_LOG" || true)"

# The same endpoint may reuse the existing credential while changing only model.
UPDATED_MODEL='ep-20250825-review-v2'
run_configure "$ENDPOINT" "$UPDATED_MODEL" >"$CAPTURED/model-change.out" 2>"$CAPTURED/model-change.err"
assert_contains "$STATE" "\"endpoint\": \"$ENDPOINT\""
assert_contains "$STATE" "\"model\": \"$UPDATED_MODEL\""
for profile_agent in "$GENERAL_AGENT" "$DEVELOPER_AGENT" "$REVIEWER_AGENT"; do
  assert_contains "$profile_agent" "model = \"$UPDATED_MODEL\""
done
assert_equals "$dialog_sum" "$(cksum "$FAKE_DIALOG_SCRIPT_LOG")"
assert_equals 1 "$(grep -F -c -- "add|$SERVICE|api-key" "$FAKE_LOG" || true)"

# An existing credential cannot be rebound to a different or unknown endpoint.
state_before=$(cksum "$STATE")
catalog_before=$(cksum "$CATALOG")
agent_before=$(cksum "$AGENT")
config_before=$(cksum "$TEST_HOME/config.toml")
workflow_before=$(cksum "$TEST_HOME/AGENTS.md")
DIFFERENT_ENDPOINT='https://different.volces.example/api/v3'
set +e
run_configure "$DIFFERENT_ENDPOINT" "$UPDATED_MODEL" >"$CAPTURED/endpoint-change.out" 2>"$CAPTURED/endpoint-change.err"
endpoint_change_status=$?
set -e
[ "$endpoint_change_status" -ne 0 ] || fail 'existing Volcengine credential was rebound to a different endpoint'
assert_equals "$state_before" "$(cksum "$STATE")"
assert_equals "$catalog_before" "$(cksum "$CATALOG")"
assert_equals "$agent_before" "$(cksum "$AGENT")"
assert_equals "$config_before" "$(cksum "$TEST_HOME/config.toml")"
assert_equals "$workflow_before" "$(cksum "$TEST_HOME/AGENTS.md")"
assert_equals 1 "$(grep -F -c -- "add|$SERVICE|api-key" "$FAKE_LOG" || true)"
assert_equals 0 "$(grep -F -c -- "delete|$SERVICE|api-key" "$FAKE_LOG" || true)"
assert_contains "$CAPTURED/endpoint-change.err" "$SERVICE"
assert_contains "$CAPTURED/endpoint-change.err" 'uninstall'
assert_contains "$CAPTURED/endpoint-change.err" 'fresh hidden-dialog key'
assert_not_contains "$CAPTURED/endpoint-change.err" "$ENDPOINT"
assert_not_contains "$CAPTURED/endpoint-change.err" "$DIFFERENT_ENDPOINT"

UNKNOWN_HOME="$TEMP_ROOT/unknown-binding-home"
mkdir -p "$UNKNOWN_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$UNKNOWN_HOME/config.toml"
UNKNOWN_KEYCHAIN="$TEMP_ROOT/unknown-binding-keychain-state"
UNKNOWN_LOG="$CAPTURED/unknown-binding-security.log"
printf '%s\n' "$SERVICE|api-key" >"$UNKNOWN_KEYCHAIN"
: >"$UNKNOWN_LOG"
unknown_config_before=$(cksum "$UNKNOWN_HOME/config.toml")
set +e
CODEX_HOME="$UNKNOWN_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$UNKNOWN_KEYCHAIN" FAKE_SECURITY_LOG="$UNKNOWN_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" >"$CAPTURED/unknown-binding.out" 2>"$CAPTURED/unknown-binding.err"
unknown_binding_status=$?
set -e
[ "$unknown_binding_status" -ne 0 ] || fail 'unregistered Volcengine credential was bound to an endpoint'
assert_equals "$unknown_config_before" "$(cksum "$UNKNOWN_HOME/config.toml")"
assert_not_file "$UNKNOWN_HOME/custom-subagents/state.json"
assert_contains "$UNKNOWN_KEYCHAIN" "$SERVICE|api-key"
assert_equals 0 "$(grep -E -c -- "^(add|delete)\\|$SERVICE\\|api-key$" "$UNKNOWN_LOG" || true)"
assert_contains "$CAPTURED/unknown-binding.err" "$SERVICE"
assert_contains "$CAPTURED/unknown-binding.err" 'uninstall'
assert_contains "$CAPTURED/unknown-binding.err" 'fresh hidden-dialog key'

MALFORMED_HOME="$TEMP_ROOT/malformed-binding-home"
mkdir -p "$MALFORMED_HOME/custom-subagents"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MALFORMED_HOME/config.toml"
printf '%s\n' '{"schema_version":1,"agents":"invalid"}' >"$MALFORMED_HOME/custom-subagents/state.json"
MALFORMED_KEYCHAIN="$TEMP_ROOT/malformed-binding-keychain-state"
MALFORMED_LOG="$CAPTURED/malformed-binding-security.log"
printf '%s\n' "$SERVICE|api-key" >"$MALFORMED_KEYCHAIN"
: >"$MALFORMED_LOG"
malformed_state_before=$(cksum "$MALFORMED_HOME/custom-subagents/state.json")
malformed_config_before=$(cksum "$MALFORMED_HOME/config.toml")
set +e
CODEX_HOME="$MALFORMED_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$MALFORMED_KEYCHAIN" FAKE_SECURITY_LOG="$MALFORMED_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" >"$CAPTURED/malformed-binding.out" 2>"$CAPTURED/malformed-binding.err"
malformed_binding_status=$?
set -e
[ "$malformed_binding_status" -ne 0 ] || fail 'malformed state allowed existing Volcengine credential reuse'
assert_equals "$malformed_state_before" "$(cksum "$MALFORMED_HOME/custom-subagents/state.json")"
assert_equals "$malformed_config_before" "$(cksum "$MALFORMED_HOME/config.toml")"
assert_contains "$MALFORMED_KEYCHAIN" "$SERVICE|api-key"
assert_equals 0 "$(grep -E -c -- "^(add|delete)\\|$SERVICE\\|api-key$" "$MALFORMED_LOG" || true)"

# Operational Keychain lookup failures stop before dialog or lifecycle mutation.
LOCKED_HOME="$TEMP_ROOT/locked-home"
mkdir -p "$LOCKED_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$LOCKED_HOME/config.toml"
LOCKED_STATE="$TEMP_ROOT/locked-keychain-state"
LOCKED_LOG="$CAPTURED/locked-security.log"
: >"$LOCKED_STATE"
: >"$LOCKED_LOG"
locked_before=$(cksum "$LOCKED_HOME/config.toml")
dialog_before=$(cksum "$FAKE_DIALOG_SCRIPT_LOG")
set +e
CODEX_HOME="$LOCKED_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$LOCKED_STATE" FAKE_SECURITY_LOG="$LOCKED_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_SECURITY_FAIL=find-generic-password FAKE_SECURITY_FAIL_STATUS=36 \
sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" >"$CAPTURED/locked.out" 2>"$CAPTURED/locked.err"
locked_status=$?
set -e
[ "$locked_status" -ne 0 ] || fail 'locked Keychain lookup unexpectedly configured the plugin'
assert_equals "$locked_before" "$(cksum "$LOCKED_HOME/config.toml")"
assert_equals "$dialog_before" "$(cksum "$FAKE_DIALOG_SCRIPT_LOG")"
assert_equals 0 "$(grep -F -c -- "add|$SERVICE|api-key" "$LOCKED_LOG" || true)"
assert_not_file "$LOCKED_HOME/custom-subagents/state.json"

# Empty accepted input is rejected without creating state or a Keychain item.
EMPTY_HOME="$TEMP_ROOT/empty-home"
mkdir -p "$EMPTY_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$EMPTY_HOME/config.toml"
EMPTY_STATE="$TEMP_ROOT/empty-keychain-state"
EMPTY_LOG="$CAPTURED/empty-security.log"
: >"$EMPTY_STATE"
: >"$EMPTY_LOG"
set +e
CODEX_HOME="$EMPTY_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$EMPTY_STATE" FAKE_SECURITY_LOG="$EMPTY_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_DIALOG_VALUE= \
sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" >"$CAPTURED/empty.out" 2>"$CAPTURED/empty.err"
empty_status=$?
set -e
[ "$empty_status" -ne 0 ] || fail 'empty dialog response unexpectedly configured the plugin'
assert_equals 0 "$(grep -F -c -- "add|$SERVICE|api-key" "$EMPTY_LOG" || true)"
assert_not_file "$EMPTY_HOME/custom-subagents/state.json"

# Existing items survive lifecycle failure; fresh items are rolled back.
set +e
( CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1; run_configure >"$CAPTURED/existing-failure.out" 2>"$CAPTURED/existing-failure.err" )
existing_failure_status=$?
set -e
[ "$existing_failure_status" -ne 0 ] || fail 'existing-item lifecycle failure unexpectedly succeeded'
assert_contains "$FAKE_STATE" "$SERVICE|api-key"
assert_equals 0 "$(grep -F -c -- "delete|$SERVICE|api-key" "$FAKE_LOG" || true)"

FAIL_HOME="$TEMP_ROOT/failing-home"
mkdir -p "$FAIL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$FAIL_HOME/config.toml"
FAIL_STATE="$TEMP_ROOT/failing-keychain-state"
FAIL_LOG="$CAPTURED/failing-security.log"
: >"$FAIL_STATE"
: >"$FAIL_LOG"
set +e
CODEX_HOME="$FAIL_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$FAIL_STATE" FAKE_SECURITY_LOG="$FAIL_LOG" FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" \
FAKE_DIALOG_VALUE="$SENTINEL" CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1 \
sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" >"$CAPTURED/failing.out" 2>"$CAPTURED/failing.err"
failure_status=$?
set -e
[ "$failure_status" -ne 0 ] || fail 'fresh-item lifecycle failure unexpectedly succeeded'
assert_not_contains "$FAIL_STATE" "$SERVICE|api-key"
assert_contains "$FAIL_LOG" "delete|$SERVICE|api-key"

DELETE_FAIL_HOME="$TEMP_ROOT/delete-fail-home"
mkdir -p "$DELETE_FAIL_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$DELETE_FAIL_HOME/config.toml"
DELETE_FAIL_STATE="$TEMP_ROOT/delete-fail-keychain-state"
DELETE_FAIL_LOG="$CAPTURED/delete-fail-security.log"
: >"$DELETE_FAIL_STATE"
: >"$DELETE_FAIL_LOG"
set +e
CODEX_HOME="$DELETE_FAIL_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$DELETE_FAIL_STATE" FAKE_SECURITY_LOG="$DELETE_FAIL_LOG" \
FAKE_DIALOG_SCRIPT_LOG="$FAKE_DIALOG_SCRIPT_LOG" FAKE_DIALOG_VALUE="$SENTINEL" \
FAKE_SECURITY_FAIL=delete-generic-password CUSTOM_SUBAGENT_FAIL_AFTER_WRITE=1 \
sh "$CONFIGURE" --endpoint "$ENDPOINT" --model "$MODEL" >"$CAPTURED/delete-fail.out" 2>"$CAPTURED/delete-fail.err"
delete_fail_status=$?
set -e
[ "$delete_fail_status" -ne 0 ] || fail 'rollback deletion failure unexpectedly succeeded'
assert_contains "$DELETE_FAIL_STATE" "$SERVICE|api-key"
assert_contains "$DELETE_FAIL_LOG" "delete|$SERVICE|api-key"
assert_contains "$CAPTURED/delete-fail.err" 'cleanup incomplete'
assert_contains "$CAPTURED/delete-fail.err" "$SERVICE"

# Provider uninstall removes all Volcengine profiles and preserves DeepSeek.
run_uninstall >"$CAPTURED/uninstall.out" 2>"$CAPTURED/uninstall.err"
assert_not_file "$GENERAL_AGENT"
assert_not_file "$DEVELOPER_AGENT"
assert_not_file "$REVIEWER_AGENT"
assert_file "$DEEPSEEK_GENERAL_AGENT"
assert_file "$DEEPSEEK_DEVELOPER_AGENT"
assert_file "$DEEPSEEK_REVIEWER_AGENT"
assert_contains "$STATE" '"id": "deepseek-agent"'
assert_not_contains "$STATE" '"id": "volcengine-agent"'
assert_contains "$TEST_HOME/AGENTS.md" 'provider deepseek agent types: deepseek_general, deepseek_developer, deepseek_reviewer.'
assert_not_contains "$TEST_HOME/AGENTS.md" 'provider volcengine agent types:'
assert_contains "$FAKE_STATE" "$DEEPSEEK_SERVICE|api-key"
assert_not_contains "$FAKE_STATE" "$SERVICE|api-key"

# The credential-only retry path must remain fail-closed for managed residue.
DANGLING_HOME="$TEMP_ROOT/dangling-agent-home"
cp -R "$TEST_HOME" "$DANGLING_HOME"
ln -s "$TEMP_ROOT/missing-reviewer-agent" "$DANGLING_HOME/agents/volcengine_reviewer.toml"
DANGLING_KEYCHAIN="$TEMP_ROOT/dangling-keychain-state"
DANGLING_LOG="$CAPTURED/dangling-security.log"
cp "$FAKE_STATE" "$DANGLING_KEYCHAIN"
printf '%s\n' "$SERVICE|api-key" >>"$DANGLING_KEYCHAIN"
: >"$DANGLING_LOG"
dangling_config_before=$(cksum "$DANGLING_HOME/config.toml")
dangling_state_before=$(cksum "$DANGLING_HOME/custom-subagents/state.json")
dangling_workflow_before=$(cksum "$DANGLING_HOME/AGENTS.md")
set +e
CODEX_HOME="$DANGLING_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$DANGLING_KEYCHAIN" FAKE_SECURITY_LOG="$DANGLING_LOG" \
sh "$UNINSTALL" >"$CAPTURED/dangling-uninstall.out" 2>"$CAPTURED/dangling-uninstall.err"
dangling_status=$?
set -e
[ "$dangling_status" -ne 0 ] || fail 'dangling reviewer agent symlink bypassed lifecycle validation'
[ -L "$DANGLING_HOME/agents/volcengine_reviewer.toml" ] || fail 'dangling reviewer agent symlink was mutated'
assert_equals "$dangling_config_before" "$(cksum "$DANGLING_HOME/config.toml")"
assert_equals "$dangling_state_before" "$(cksum "$DANGLING_HOME/custom-subagents/state.json")"
assert_equals "$dangling_workflow_before" "$(cksum "$DANGLING_HOME/AGENTS.md")"
assert_contains "$DANGLING_KEYCHAIN" "$SERVICE|api-key"
assert_equals 0 "$(grep -F -c -- "delete|$SERVICE|api-key" "$DANGLING_LOG" || true)"

SYMLINK_STATE_HOME="$TEMP_ROOT/symlink-state-home"
cp -R "$TEST_HOME" "$SYMLINK_STATE_HOME"
SYMLINK_STATE_TARGET="$TEMP_ROOT/symlink-state-target.json"
mv "$SYMLINK_STATE_HOME/custom-subagents/state.json" "$SYMLINK_STATE_TARGET"
ln -s "$SYMLINK_STATE_TARGET" "$SYMLINK_STATE_HOME/custom-subagents/state.json"
SYMLINK_KEYCHAIN="$TEMP_ROOT/symlink-keychain-state"
SYMLINK_LOG="$CAPTURED/symlink-security.log"
cp "$FAKE_STATE" "$SYMLINK_KEYCHAIN"
printf '%s\n' "$SERVICE|api-key" >>"$SYMLINK_KEYCHAIN"
: >"$SYMLINK_LOG"
symlink_target_before=$(cksum "$SYMLINK_STATE_TARGET")
symlink_config_before=$(cksum "$SYMLINK_STATE_HOME/config.toml")
symlink_workflow_before=$(cksum "$SYMLINK_STATE_HOME/AGENTS.md")
set +e
CODEX_HOME="$SYMLINK_STATE_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$SYMLINK_KEYCHAIN" FAKE_SECURITY_LOG="$SYMLINK_LOG" \
sh "$UNINSTALL" >"$CAPTURED/symlink-state-uninstall.out" 2>"$CAPTURED/symlink-state-uninstall.err"
symlink_state_status=$?
set -e
[ "$symlink_state_status" -ne 0 ] || fail 'symlinked lifecycle state bypassed fail-closed validation'
[ -L "$SYMLINK_STATE_HOME/custom-subagents/state.json" ] || fail 'symlinked lifecycle state was mutated'
assert_equals "$symlink_target_before" "$(cksum "$SYMLINK_STATE_TARGET")"
assert_equals "$symlink_config_before" "$(cksum "$SYMLINK_STATE_HOME/config.toml")"
assert_equals "$symlink_workflow_before" "$(cksum "$SYMLINK_STATE_HOME/AGENTS.md")"
assert_contains "$SYMLINK_KEYCHAIN" "$SERVICE|api-key"
assert_equals 0 "$(grep -F -c -- "delete|$SERVICE|api-key" "$SYMLINK_LOG" || true)"

MARKER_HOME="$TEMP_ROOT/duplicate-marker-home"
cp -R "$TEST_HOME" "$MARKER_HOME"
printf '%s\n' '<!-- BEGIN custom-subagents managed workflow -->' '<!-- END custom-subagents managed workflow -->' >>"$MARKER_HOME/AGENTS.md"
MARKER_KEYCHAIN="$TEMP_ROOT/marker-keychain-state"
MARKER_LOG="$CAPTURED/marker-security.log"
cp "$FAKE_STATE" "$MARKER_KEYCHAIN"
printf '%s\n' "$SERVICE|api-key" >>"$MARKER_KEYCHAIN"
: >"$MARKER_LOG"
marker_config_before=$(cksum "$MARKER_HOME/config.toml")
marker_state_before=$(cksum "$MARKER_HOME/custom-subagents/state.json")
marker_workflow_before=$(cksum "$MARKER_HOME/AGENTS.md")
set +e
CODEX_HOME="$MARKER_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$TEST_HELPERS/fake-security.sh" \
CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEST_HELPERS/fake-osascript.sh" \
FAKE_SECURITY_STATE="$MARKER_KEYCHAIN" FAKE_SECURITY_LOG="$MARKER_LOG" \
sh "$UNINSTALL" >"$CAPTURED/marker-uninstall.out" 2>"$CAPTURED/marker-uninstall.err"
marker_status=$?
set -e
[ "$marker_status" -ne 0 ] || fail 'duplicate managed workflow markers bypassed fail-closed validation'
assert_equals "$marker_config_before" "$(cksum "$MARKER_HOME/config.toml")"
assert_equals "$marker_state_before" "$(cksum "$MARKER_HOME/custom-subagents/state.json")"
assert_equals "$marker_workflow_before" "$(cksum "$MARKER_HOME/AGENTS.md")"
assert_contains "$MARKER_KEYCHAIN" "$SERVICE|api-key"
assert_equals 0 "$(grep -F -c -- "delete|$SERVICE|api-key" "$MARKER_LOG" || true)"

# Delete failure can be retried, followed by clean reinstall and idempotent cleanup.
FAKE_DIALOG_VALUE=retry-secret
run_configure >"$CAPTURED/reinstall-before-retry.out" 2>"$CAPTURED/reinstall-before-retry.err"
set +e
FAKE_SECURITY_FAIL=delete-generic-password run_uninstall >"$CAPTURED/uninstall-delete-fail.out" 2>"$CAPTURED/uninstall-delete-fail.err"
uninstall_delete_fail_status=$?
set -e
[ "$uninstall_delete_fail_status" -ne 0 ] || fail 'uninstall delete failure unexpectedly succeeded'
assert_contains "$FAKE_STATE" "$SERVICE|api-key"
FAKE_SECURITY_FAIL=
run_uninstall >"$CAPTURED/uninstall-retry.out" 2>"$CAPTURED/uninstall-retry.err"
assert_not_contains "$FAKE_STATE" "$SERVICE|api-key"
FAKE_DIALOG_VALUE=reinstall-secret
run_configure >"$CAPTURED/reinstall.out" 2>"$CAPTURED/reinstall.err"
assert_file "$GENERAL_AGENT"
assert_file "$DEVELOPER_AGENT"
assert_file "$REVIEWER_AGENT"
run_uninstall >"$CAPTURED/final-uninstall.out" 2>"$CAPTURED/final-uninstall.err"
run_uninstall >"$CAPTURED/idempotent-uninstall.out" 2>"$CAPTURED/idempotent-uninstall.err"

SETUP_SKILL="$PLUGIN_ROOT/skills/volcengine-agent-setup/SKILL.md"
UNINSTALL_SKILL="$PLUGIN_ROOT/skills/volcengine-agent-uninstall/SKILL.md"
assert_contains "$SETUP_SKILL" 'configuring or checking status'
assert_contains "$SETUP_SKILL" 'scripts/vendor/lifecycle.sh" status'
assert_contains "$SETUP_SKILL" "provider's ID, provider name, endpoint, model"
assert_contains "$SETUP_SKILL" 'Do not call Keychain, configure, or uninstall.'
assert_contains "$SETUP_SKILL" 'other restoration'
assert_contains "$SETUP_SKILL" 'Do not accept, quote, retain, or reuse an API key pasted in chat.'
assert_contains "$SETUP_SKILL" 'native hidden dialog'
assert_contains "$SETUP_SKILL" 'explicit approval'
assert_contains "$SETUP_SKILL" '`volcengine_reviewer`'
assert_contains "$SETUP_SKILL" '`volcengine_general`'
assert_contains "$SETUP_SKILL" '`volcengine_developer`'
assert_contains "$SETUP_SKILL" '`model_provider` equal to `volcengine`'
assert_contains "$SETUP_SKILL" '`multi_agent_version` equal to `v1`'
assert_contains "$SETUP_SKILL" 'The user and Codex must not provide a key'
assert_contains "$SETUP_SKILL" "adapter's private pipe"
assert_contains "$SETUP_SKILL" 'same endpoint'
assert_contains "$SETUP_SKILL" 'https://ark.cn-beijing.volces.com/api/plan/v3'
assert_contains "$SETUP_SKILL" 'requests a relay'
assert_contains "$SETUP_SKILL" 'changing only the model or deployment is'
assert_contains "$SETUP_SKILL" "plugin's uninstall cleanup first"
assert_contains "$SETUP_SKILL" 'general, developer, and reviewer'
assert_contains "$SETUP_SKILL" 'automatic scheduling'
assert_contains "$SETUP_SKILL" 'explicit provider or role'
assert_contains "$SETUP_SKILL" '`codex-custom-subagent/volcengine-agent`'
assert_contains "$UNINSTALL_SKILL" 'codex plugin remove volcengine-agent@custom-subagents'
assert_contains "$UNINSTALL_SKILL" 'restore the same `volcengine-agent@custom-subagents` package'

if grep -R -F -- "$SENTINEL" "$CAPTURED" "$FAKE_STATE" "$FAIL_STATE" "$DELETE_FAIL_STATE" "$TEST_HOME" "$FAIL_HOME" "$DELETE_FAIL_HOME" "$PLUGIN_ROOT" "$COPIED_PLUGIN" >/dev/null 2>&1; then
  fail 'secret sentinel appeared in plugin output or managed files'
fi

printf '%s\n' 'PASS: Volcengine provider plugin'
