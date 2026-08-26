#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_APPROVAL=custom-subagents-isolated-test-harness
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-uninstall.XXXXXX)
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
  config_fixture=$2
  agents_shape=$3
  CASE_ROOT="$TEMP_ROOT/$case_name"
  TEST_HOME="$CASE_ROOT/home"
  FAKE_STATE="$CASE_ROOT/keychain-state"
  FAKE_LOG="$CASE_ROOT/security.log"
  DIALOG_LOG="$CASE_ROOT/dialog.log"
  mkdir -p "$TEST_HOME"
  cp "$config_fixture" "$TEST_HOME/config.toml"
  case "$agents_shape" in
    absent) ;;
    empty) : >"$TEST_HOME/AGENTS.md" ;;
    ends-newline) printf '%s\n' 'Unrelated workflow instruction.' >"$TEST_HOME/AGENTS.md" ;;
    no-final-newline) printf '%s' 'Unrelated workflow instruction.' >"$TEST_HOME/AGENTS.md" ;;
    *) fail "unknown AGENTS shape: $agents_shape" ;;
  esac
  printf '%s\n' 'unrelated file' >"$TEST_HOME/unrelated.txt"
  : >"$FAKE_STATE"
  : >"$FAKE_LOG"
  : >"$DIALOG_LOG"
}

configure_deepseek_from() {
  plugin_root=$1
  plugin_marketplace_root=$(CDPATH= cd -- "$plugin_root/../.." && pwd)
  plugin_fake_security="$plugin_marketplace_root/tests/helpers/fake-security.sh"
  plugin_fake_osascript="$plugin_marketplace_root/tests/helpers/fake-osascript.sh"
  CODEX_HOME="$TEST_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$plugin_fake_security" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$plugin_fake_osascript" FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
  FAKE_DIALOG_MODE=accept FAKE_DIALOG_VALUE='fixture-dialog-value' \
  sh "$plugin_root/scripts/configure.sh" --model deepseek-chat >/dev/null
}

configure_deepseek() {
  configure_deepseek_from "$DEEPSEEK_ROOT"
}

configure_volcengine() {
  CODEX_HOME="$TEST_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$FAKE_SECURITY" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_OSASCRIPT" FAKE_SECURITY_STATE="$FAKE_STATE" \
  FAKE_SECURITY_LOG="$FAKE_LOG" FAKE_DIALOG_SCRIPT_LOG="$DIALOG_LOG" \
  FAKE_DIALOG_MODE=accept FAKE_DIALOG_VALUE='fixture-dialog-value' \
  sh "$VOLCENGINE_ROOT/scripts/configure.sh" --endpoint https://ark.example.invalid/api/v3 \
    --model ep-review-fixture >/dev/null
}

uninstall_deepseek_from() {
  plugin_root=$1
  plugin_marketplace_root=$(CDPATH= cd -- "$plugin_root/../.." && pwd)
  plugin_fake_security="$plugin_marketplace_root/tests/helpers/fake-security.sh"
  plugin_fake_osascript="$plugin_marketplace_root/tests/helpers/fake-osascript.sh"
  CODEX_HOME="$TEST_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$plugin_fake_security" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$plugin_fake_osascript" \
  FAKE_SECURITY_STATE="$FAKE_STATE" FAKE_SECURITY_LOG="$FAKE_LOG" \
  sh "$plugin_root/scripts/uninstall.sh"
}

uninstall_deepseek() {
  uninstall_deepseek_from "$DEEPSEEK_ROOT"
}

uninstall_volcengine() {
  CODEX_HOME="$TEST_HOME" CUSTOM_SUBAGENT_SECURITY_BIN="$FAKE_SECURITY" \
  CUSTOM_SUBAGENT_OSASCRIPT_BIN="$FAKE_OSASCRIPT" \
  FAKE_SECURITY_STATE="$FAKE_STATE" FAKE_SECURITY_LOG="$FAKE_LOG" \
  sh "$VOLCENGINE_ROOT/scripts/uninstall.sh"
}

snapshot_home() {
  source_home=$1
  snapshot=$2
  mkdir -p "$snapshot"
  cp -R "$source_home/." "$snapshot/"
}

assert_home_unchanged() {
  expected=$1
  actual=$2
  diff -r "$expected" "$actual" >/dev/null 2>&1 || fail "home mutated after rejected operation: $actual"
}

assert_rejected_unchanged() {
  label=$1
  recovery_text=$2
  shift 2
  before="$CASE_ROOT/$label.before"
  output="$CASE_ROOT/$label.err"
  snapshot_home "$TEST_HOME" "$before"
  cp "$FAKE_STATE" "$CASE_ROOT/$label.keychain.before"
  cp "$FAKE_LOG" "$CASE_ROOT/$label.security-log.before"
  set +e
  "$@" >"$CASE_ROOT/$label.out" 2>"$output"
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$label unexpectedly succeeded"
  assert_home_unchanged "$before" "$TEST_HOME"
  assert_same_file "$CASE_ROOT/$label.keychain.before" "$FAKE_STATE"
  assert_same_file "$CASE_ROOT/$label.security-log.before" "$FAKE_LOG"
  assert_contains "$output" "$recovery_text"
}

# Removing one plugin preserves the other agent, credential identity, V1 catalog,
# workflow route, and every unrelated setting/file.
new_case preserve-reviewer "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
configure_volcengine
cp "$TEST_HOME/unrelated.txt" "$CASE_ROOT/unrelated.before"
cp "$TEST_HOME/config.toml" "$CASE_ROOT/config.active"
cp "$TEST_HOME/custom-subagents/models-v1.json" "$CASE_ROOT/catalog.active"
cp "$TEST_HOME/agents/volcengine_reviewer.toml" "$CASE_ROOT/reviewer.active"
uninstall_deepseek >/dev/null
assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_file "$TEST_HOME/agents/volcengine_reviewer.toml"
assert_not_contains "$TEST_HOME/custom-subagents/state.json" '"id": "deepseek-developer"'
assert_contains "$TEST_HOME/custom-subagents/state.json" '"id": "volcengine-reviewer"'
assert_not_contains "$TEST_HOME/custom-subagents/models-v1.json" 'deepseek:deepseek-chat'
assert_not_contains "$TEST_HOME/custom-subagents/models-v1.json" 'volcengine:ep-review-fixture'
assert_same_file "$CASE_ROOT/catalog.active" "$TEST_HOME/custom-subagents/models-v1.json"
assert_not_contains "$TEST_HOME/AGENTS.md" 'deepseek_developer'
assert_contains "$TEST_HOME/AGENTS.md" 'review agent type: volcengine_reviewer'
assert_not_contains "$FAKE_STATE" "$DEEPSEEK_SERVICE"
assert_contains "$FAKE_STATE" "$VOLCENGINE_SERVICE"
assert_contains "$TEST_HOME/config.toml" 'base_url = "https://example.com"'
assert_same_file "$CASE_ROOT/unrelated.before" "$TEST_HOME/unrelated.txt"
assert_same_file "$CASE_ROOT/config.active" "$TEST_HOME/config.toml"
assert_same_file "$CASE_ROOT/reviewer.active" "$TEST_HOME/agents/volcengine_reviewer.toml"

new_case preserve-developer "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
configure_volcengine
cp "$TEST_HOME/config.toml" "$CASE_ROOT/config.active"
cp "$TEST_HOME/custom-subagents/models-v1.json" "$CASE_ROOT/catalog.active"
cp "$TEST_HOME/agents/deepseek_developer.toml" "$CASE_ROOT/developer.active"
uninstall_volcengine >/dev/null
assert_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_not_file "$TEST_HOME/agents/volcengine_reviewer.toml"
assert_contains "$TEST_HOME/custom-subagents/state.json" '"id": "deepseek-developer"'
assert_not_contains "$TEST_HOME/custom-subagents/state.json" '"id": "volcengine-reviewer"'
assert_not_contains "$TEST_HOME/custom-subagents/models-v1.json" 'deepseek:deepseek-chat'
assert_not_contains "$TEST_HOME/custom-subagents/models-v1.json" 'volcengine:ep-review-fixture'
assert_same_file "$CASE_ROOT/catalog.active" "$TEST_HOME/custom-subagents/models-v1.json"
assert_contains "$TEST_HOME/AGENTS.md" 'development agent type: deepseek_developer'
assert_not_contains "$TEST_HOME/AGENTS.md" 'volcengine_reviewer'
assert_contains "$FAKE_STATE" "$DEEPSEEK_SERVICE"
assert_not_contains "$FAKE_STATE" "$VOLCENGINE_SERVICE"
assert_same_file "$CASE_ROOT/config.active" "$TEST_HOME/config.toml"
assert_same_file "$CASE_ROOT/developer.active" "$TEST_HOME/agents/deepseek_developer.toml"

# Last uninstall restores the exact original catalog setting and all four
# pre-install AGENTS.md shapes.
for shape in absent empty ends-newline no-final-newline; do
  new_case "restore-existing-$shape" "$ROOT/tests/fixtures/config-existing-catalog.toml" "$shape"
  cp "$TEST_HOME/config.toml" "$CASE_ROOT/config.before"
  [ ! -e "$TEST_HOME/AGENTS.md" ] || cp "$TEST_HOME/AGENTS.md" "$CASE_ROOT/AGENTS.before"
  configure_deepseek
  uninstall_deepseek >/dev/null
  assert_same_file "$CASE_ROOT/config.before" "$TEST_HOME/config.toml"
  case "$shape" in
    absent) assert_not_file "$TEST_HOME/AGENTS.md" ;;
    *) assert_same_file "$CASE_ROOT/AGENTS.before" "$TEST_HOME/AGENTS.md" ;;
  esac
  assert_not_file "$TEST_HOME/custom-subagents/state.json"
  assert_not_file "$TEST_HOME/custom-subagents/models-v1.json"
done

new_case restore-absent-catalog "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
cp "$TEST_HOME/config.toml" "$CASE_ROOT/config.before"
configure_volcengine
uninstall_volcengine >/dev/null
assert_same_file "$CASE_ROOT/config.before" "$TEST_HOME/config.toml"
assert_not_contains "$TEST_HOME/config.toml" 'model_catalog_json'

# Corrupt/missing recovery inputs must fail closed, preserve the entire home,
# and identify backup restoration as the operator path.
new_case malformed-state "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
printf '%s\n' '{not-json' >"$TEST_HOME/custom-subagents/state.json"
assert_rejected_unchanged malformed-state 'restore from backup' uninstall_deepseek

new_case missing-backups "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
rm -rf "$TEST_HOME/custom-subagents/backups"
assert_rejected_unchanged missing-backups 'backup' uninstall_deepseek

new_case empty-backups "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
rm -rf "$TEST_HOME/custom-subagents/backups"
mkdir "$TEST_HOME/custom-subagents/backups"
assert_rejected_unchanged empty-backups 'backup' uninstall_deepseek

new_case duplicate-markers "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
printf '%s\n' '<!-- BEGIN custom-subagents managed workflow -->' >>"$TEST_HOME/AGENTS.md"
assert_rejected_unchanged duplicate-markers 'restore from a backup' uninstall_deepseek

new_case state-missing-residue "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
configure_deepseek
rm "$TEST_HOME/custom-subagents/state.json"
assert_rejected_unchanged state-missing-residue 'restore from backup or reconfigure custom subagents' uninstall_deepseek

# Raw package removal leaves managed files and Keychain untouched because the
# cleanup entry point disappeared with the package. Reinstalling that same
# package restores the cleanup entry point and permits a normal exact uninstall.
new_case raw-package-removal "$ROOT/tests/fixtures/config-minimal.toml" ends-newline
COPIED_MARKETPLACE="$CASE_ROOT/source-marketplace"
COPIED_PLUGIN="$COPIED_MARKETPLACE/plugins/deepseek-developer"
QUARANTINED_PLUGIN="$CASE_ROOT/quarantine/deepseek-developer"
mkdir -p "$(dirname "$COPIED_PLUGIN")" "$COPIED_MARKETPLACE/tests/helpers" "$(dirname "$QUARANTINED_PLUGIN")"
cp -R "$DEEPSEEK_ROOT" "$COPIED_PLUGIN"
cp "$FAKE_SECURITY" "$COPIED_MARKETPLACE/tests/helpers/fake-security.sh"
cp "$FAKE_OSASCRIPT" "$COPIED_MARKETPLACE/tests/helpers/fake-osascript.sh"
cp "$TEST_HOME/config.toml" "$CASE_ROOT/config.before"
cp "$TEST_HOME/AGENTS.md" "$CASE_ROOT/AGENTS.before"
cp "$TEST_HOME/unrelated.txt" "$CASE_ROOT/unrelated.before"
configure_deepseek_from "$COPIED_PLUGIN"

snapshot_home "$TEST_HOME" "$CASE_ROOT/raw-removal.home.before"
cp "$FAKE_STATE" "$CASE_ROOT/raw-removal.keychain.before"
cp "$FAKE_LOG" "$CASE_ROOT/raw-removal.security-log.before"
mv "$COPIED_PLUGIN" "$QUARANTINED_PLUGIN"
assert_not_file "$COPIED_PLUGIN/scripts/uninstall.sh"
set +e
sh "$COPIED_PLUGIN/scripts/uninstall.sh" >"$CASE_ROOT/raw-removal.out" 2>"$CASE_ROOT/raw-removal.err"
raw_remove_status=$?
set -e
[ "$raw_remove_status" -ne 0 ] || fail 'removed package cleanup path unexpectedly remained callable'
assert_home_unchanged "$CASE_ROOT/raw-removal.home.before" "$TEST_HOME"
assert_same_file "$CASE_ROOT/raw-removal.keychain.before" "$FAKE_STATE"
assert_same_file "$CASE_ROOT/raw-removal.security-log.before" "$FAKE_LOG"
assert_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_file "$TEST_HOME/custom-subagents/state.json"
assert_contains "$FAKE_STATE" "$DEEPSEEK_SERVICE"

mv "$QUARANTINED_PLUGIN" "$COPIED_PLUGIN"
uninstall_deepseek_from "$COPIED_PLUGIN" >/dev/null
assert_not_file "$TEST_HOME/agents/deepseek_developer.toml"
assert_not_file "$TEST_HOME/custom-subagents/state.json"
assert_not_file "$TEST_HOME/custom-subagents/models-v1.json"
assert_not_contains "$FAKE_STATE" "$DEEPSEEK_SERVICE"
assert_same_file "$CASE_ROOT/config.before" "$TEST_HOME/config.toml"
assert_same_file "$CASE_ROOT/AGENTS.before" "$TEST_HOME/AGENTS.md"
assert_same_file "$CASE_ROOT/unrelated.before" "$TEST_HOME/unrelated.txt"

printf '%s\n' 'uninstall tests passed'
