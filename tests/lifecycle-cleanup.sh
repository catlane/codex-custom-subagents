#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-cleanup.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

DEVELOPER_PLUGIN="$TEMP_ROOT/deepseek-developer"
REVIEWER_PLUGIN="$TEMP_ROOT/reviewer-agent"
mkdir -p "$DEVELOPER_PLUGIN/.codex-plugin" "$REVIEWER_PLUGIN/.codex-plugin"
cp "$ROOT/plugins/deepseek-developer/.codex-plugin/plugin.json" "$DEVELOPER_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$DEVELOPER_PLUGIN/agent-spec.json"
printf '%s\n' '{"name":"reviewer-agent"}' >"$REVIEWER_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$REVIEWER_PLUGIN/agent-spec.json"

run_lifecycle() {
  cleanup_home=$1
  cleanup_plugin=$2
  shift 2
  CUSTOM_SUBAGENT_HOME="$cleanup_home" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$cleanup_plugin" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$cleanup_plugin/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

install_developer() {
  run_lifecycle "$1" "$DEVELOPER_PLUGIN" \
    install deepseek-developer development deepseek http://localhost:11434 fixture-model
}

assert_active_lifecycle_same() {
  expected_dir=$1
  actual_home=$2
  assert_same_file "$expected_dir/config.toml" "$actual_home/config.toml"
  assert_same_file "$expected_dir/AGENTS.md" "$actual_home/AGENTS.md"
  assert_same_file "$expected_dir/state.json" "$actual_home/custom-subagents/state.json"
  assert_same_file "$expected_dir/models-v1.json" "$actual_home/custom-subagents/models-v1.json"
  assert_same_file "$expected_dir/base-model-catalog.json" "$actual_home/custom-subagents/base-model-catalog.json"
  assert_same_file "$expected_dir/deepseek_developer.toml" "$actual_home/agents/deepseek_developer.toml"
}

assert_uninstall_rejected_unchanged() {
  reject_label=$1
  reject_home=$2
  reject_before="$TEMP_ROOT/$reject_label.before"
  cp -Rp "$reject_home" "$reject_before"
  if run_lifecycle "$reject_home" "$DEVELOPER_PLUGIN" uninstall deepseek-developer \
    >"$TEMP_ROOT/$reject_label.err" 2>&1; then
    fail "$reject_label unexpectedly allowed idempotent uninstall"
  fi
  diff -r "$reject_before" "$reject_home" >/dev/null 2>&1 ||
    fail "$reject_label mutated the home"
}

assert_recovery_output() {
  recovery_label=$1
  recovery_reason=$2
  recovery_output="$TEMP_ROOT/$recovery_label.err"
  assert_contains "$recovery_output" "$recovery_reason"
  assert_equals 'custom-subagents: restore from backup or reconfigure custom subagents' \
    "$(tail -n 1 "$recovery_output")"
}

copy_home() {
  copy_source=$1
  copy_target=$2
  mkdir -p "$(dirname "$copy_target")"
  cp -Rp "$copy_source" "$copy_target"
}

clone_active_home() {
  clone_source=$1
  clone_target=$2
  copy_home "$clone_source" "$clone_target"
  for clone_file in \
    "$clone_target/config.toml" \
    "$clone_target/custom-subagents/state.json" \
    "$clone_target/agents"/*.toml; do
    [ -f "$clone_file" ] || continue
    sed "s|$clone_source|$clone_target|g" "$clone_file" >"$clone_file.cloned"
    mv "$clone_file.cloned" "$clone_file"
  done
}

CYCLE_HOME="$TEMP_ROOT/cycle/home"
mkdir -p "$CYCLE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$CYCLE_HOME/config.toml"
printf '%s' 'Original workflow instructions.' >"$CYCLE_HOME/AGENTS.md"
cp "$CYCLE_HOME/config.toml" "$TEMP_ROOT/cycle/config.original"
cp "$CYCLE_HOME/AGENTS.md" "$TEMP_ROOT/cycle/AGENTS.original"
install_developer "$CYCLE_HOME"
run_lifecycle "$CYCLE_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
assert_same_file "$TEMP_ROOT/cycle/config.original" "$CYCLE_HOME/config.toml"
assert_same_file "$TEMP_ROOT/cycle/AGENTS.original" "$CYCLE_HOME/AGENTS.md"
assert_not_file "$CYCLE_HOME/agents/deepseek_developer.toml"
assert_not_file "$CYCLE_HOME/custom-subagents/state.json"
assert_not_file "$CYCLE_HOME/custom-subagents/models-v1.json"
assert_not_file "$CYCLE_HOME/custom-subagents/base-model-catalog.json"
assert_dir "$CYCLE_HOME/custom-subagents/backups"

run_lifecycle "$CYCLE_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
install_developer "$CYCLE_HOME"
assert_file "$CYCLE_HOME/custom-subagents/state.json"
assert_file "$CYCLE_HOME/custom-subagents/models-v1.json"
assert_file "$CYCLE_HOME/custom-subagents/base-model-catalog.json"
assert_file "$CYCLE_HOME/agents/deepseek_developer.toml"
run_lifecycle "$CYCLE_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer

TWO_HOME="$TEMP_ROOT/two-agent/home"
mkdir -p "$TWO_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$TWO_HOME/config.toml"
install_developer "$TWO_HOME"
run_lifecycle "$TWO_HOME" "$REVIEWER_PLUGIN" \
  install reviewer-agent review volcengine http://localhost:11434 fixture-model-2
run_lifecycle "$TWO_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
assert_file "$TWO_HOME/custom-subagents/state.json"
assert_file "$TWO_HOME/custom-subagents/models-v1.json"
assert_file "$TWO_HOME/agents/reviewer_agent.toml"
assert_not_file "$TWO_HOME/agents/deepseek_developer.toml"
assert_contains "$TWO_HOME/custom-subagents/state.json" '"id": "reviewer-agent"'
assert_contains "$TWO_HOME/custom-subagents/models-v1.json" '"id": "official:gpt-5.6-sol"'
assert_contains "$TWO_HOME/custom-subagents/models-v1.json" '"id": "official:unrelated-model"'
assert_contains "$TWO_HOME/AGENTS.md" 'review agent type: reviewer_agent'

TWO_NOOP_BEFORE="$TEMP_ROOT/two-agent/noop-before"
copy_home "$TWO_HOME" "$TWO_NOOP_BEFORE"
run_lifecycle "$TWO_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
diff -r "$TWO_NOOP_BEFORE" "$TWO_HOME" >/dev/null 2>&1 ||
  fail 'valid target-absent uninstall with another agent mutated the home'

REGISTRY_MISMATCH_HOME="$TEMP_ROOT/registry-mismatch/home"
clone_active_home "$TWO_HOME" "$REGISTRY_MISMATCH_HOME"
printf '%s\n' 'unregistered target agent residue' >"$REGISTRY_MISMATCH_HOME/agents/deepseek_developer.toml"
assert_uninstall_rejected_unchanged registry-mismatch "$REGISTRY_MISMATCH_HOME"

DANGLING_AGENT_HOME="$TEMP_ROOT/dangling-agent/home"
clone_active_home "$TWO_HOME" "$DANGLING_AGENT_HOME"
ln -s "$TEMP_ROOT/missing-agent-target" "$DANGLING_AGENT_HOME/agents/deepseek_developer.toml"
assert_uninstall_rejected_unchanged dangling-agent "$DANGLING_AGENT_HOME"

SYMLINK_STATE_HOME="$TEMP_ROOT/symlink-state/home"
clone_active_home "$TWO_HOME" "$SYMLINK_STATE_HOME"
cp "$SYMLINK_STATE_HOME/custom-subagents/state.json" "$TEMP_ROOT/symlink-state-target.json"
rm "$SYMLINK_STATE_HOME/custom-subagents/state.json"
ln -s "$TEMP_ROOT/symlink-state-target.json" "$SYMLINK_STATE_HOME/custom-subagents/state.json"
assert_uninstall_rejected_unchanged symlink-state "$SYMLINK_STATE_HOME"

MISSING_SHAPE_HOME="$TEMP_ROOT/noop-missing-shape/home"
clone_active_home "$TWO_HOME" "$MISSING_SHAPE_HOME"
sed '/"initial_agents_shape":/d' "$MISSING_SHAPE_HOME/custom-subagents/state.json" \
  >"$MISSING_SHAPE_HOME/custom-subagents/state.json.invalid"
mv "$MISSING_SHAPE_HOME/custom-subagents/state.json.invalid" \
  "$MISSING_SHAPE_HOME/custom-subagents/state.json"
assert_uninstall_rejected_unchanged noop-missing-shape "$MISSING_SHAPE_HOME"
assert_recovery_output noop-missing-shape 'state registry is missing initial AGENTS shape'

CATALOG_MISMATCH_HOME="$TEMP_ROOT/noop-catalog-mismatch/home"
clone_active_home "$TWO_HOME" "$CATALOG_MISMATCH_HOME"
sed 's/unrelated-model/altered-model/g' "$CATALOG_MISMATCH_HOME/custom-subagents/models-v1.json" \
  >"$CATALOG_MISMATCH_HOME/custom-subagents/models-v1.json.invalid"
mv "$CATALOG_MISMATCH_HOME/custom-subagents/models-v1.json.invalid" \
  "$CATALOG_MISMATCH_HOME/custom-subagents/models-v1.json"
assert_uninstall_rejected_unchanged noop-catalog-mismatch "$CATALOG_MISMATCH_HOME"
assert_recovery_output noop-catalog-mismatch 'managed catalog does not match state'

CONFIG_MISMATCH_HOME="$TEMP_ROOT/noop-config-mismatch/home"
clone_active_home "$TWO_HOME" "$CONFIG_MISMATCH_HOME"
sed 's#models-v1.json#other-models.json#' "$CONFIG_MISMATCH_HOME/config.toml" \
  >"$CONFIG_MISMATCH_HOME/config.toml.invalid"
mv "$CONFIG_MISMATCH_HOME/config.toml.invalid" "$CONFIG_MISMATCH_HOME/config.toml"
assert_uninstall_rejected_unchanged noop-config-mismatch "$CONFIG_MISMATCH_HOME"

WORKFLOW_MISMATCH_HOME="$TEMP_ROOT/noop-workflow-mismatch/home"
clone_active_home "$TWO_HOME" "$WORKFLOW_MISMATCH_HOME"
sed 's/review agent type: reviewer_agent/review agent type: altered_agent/' \
  "$WORKFLOW_MISMATCH_HOME/AGENTS.md" >"$WORKFLOW_MISMATCH_HOME/AGENTS.md.invalid"
mv "$WORKFLOW_MISMATCH_HOME/AGENTS.md.invalid" "$WORKFLOW_MISMATCH_HOME/AGENTS.md"
assert_uninstall_rejected_unchanged noop-workflow-mismatch "$WORKFLOW_MISMATCH_HOME"

DUPLICATE_MARKER_HOME="$TEMP_ROOT/noop-duplicate-marker/home"
clone_active_home "$TWO_HOME" "$DUPLICATE_MARKER_HOME"
printf '%s\n' '<!-- BEGIN custom-subagents managed workflow -->' >>"$DUPLICATE_MARKER_HOME/AGENTS.md"
assert_uninstall_rejected_unchanged noop-duplicate-marker "$DUPLICATE_MARKER_HOME"
assert_recovery_output noop-duplicate-marker 'duplicate or malformed managed workflow markers'

MALFORMED_STATE_HOME="$TEMP_ROOT/malformed-state/home"
mkdir -p "$MALFORMED_STATE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MALFORMED_STATE_HOME/config.toml"
install_developer "$MALFORMED_STATE_HOME"
printf '%s\n' '{not-json' >"$MALFORMED_STATE_HOME/custom-subagents/state.json"
assert_uninstall_rejected_unchanged malformed-state "$MALFORMED_STATE_HOME"
assert_recovery_output malformed-state 'state registry is not valid JSON'

MALFORMED_CATALOG_HOME="$TEMP_ROOT/malformed-catalog/home"
mkdir -p "$MALFORMED_CATALOG_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MALFORMED_CATALOG_HOME/config.toml"
install_developer "$MALFORMED_CATALOG_HOME"
printf '%s\n' '{not-json' >"$MALFORMED_CATALOG_HOME/custom-subagents/models-v1.json"
assert_uninstall_rejected_unchanged malformed-catalog "$MALFORMED_CATALOG_HOME"
assert_recovery_output malformed-catalog 'managed catalog is not valid JSON'

MISSING_BACKUPS_HOME="$TEMP_ROOT/missing-backups/home"
mkdir -p "$MISSING_BACKUPS_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MISSING_BACKUPS_HOME/config.toml"
install_developer "$MISSING_BACKUPS_HOME"
rm -rf "$MISSING_BACKUPS_HOME/custom-subagents/backups"
assert_uninstall_rejected_unchanged missing-backups "$MISSING_BACKUPS_HOME"
assert_recovery_output missing-backups 'managed backup history is missing'

EMPTY_BACKUPS_HOME="$TEMP_ROOT/empty-backups/home"
mkdir -p "$EMPTY_BACKUPS_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$EMPTY_BACKUPS_HOME/config.toml"
install_developer "$EMPTY_BACKUPS_HOME"
rm -rf "$EMPTY_BACKUPS_HOME/custom-subagents/backups"
mkdir -p "$EMPTY_BACKUPS_HOME/custom-subagents/backups"
assert_uninstall_rejected_unchanged empty-backups "$EMPTY_BACKUPS_HOME"
assert_recovery_output empty-backups 'managed backup history is missing'

for boundary in 1 2 3 4 5 6; do
  FAILURE_HOME="$TEMP_ROOT/failure-$boundary/home"
  FAILURE_BEFORE="$TEMP_ROOT/failure-$boundary/before"
  mkdir -p "$FAILURE_HOME" "$FAILURE_BEFORE"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$FAILURE_HOME/config.toml"
  printf '%s\n' 'Rollback workflow instructions.' >"$FAILURE_HOME/AGENTS.md"
  install_developer "$FAILURE_HOME"
  cp "$FAILURE_HOME/config.toml" "$FAILURE_BEFORE/config.toml"
  cp "$FAILURE_HOME/AGENTS.md" "$FAILURE_BEFORE/AGENTS.md"
  cp "$FAILURE_HOME/custom-subagents/state.json" "$FAILURE_BEFORE/state.json"
  cp "$FAILURE_HOME/custom-subagents/models-v1.json" "$FAILURE_BEFORE/models-v1.json"
  cp "$FAILURE_HOME/custom-subagents/base-model-catalog.json" "$FAILURE_BEFORE/base-model-catalog.json"
  cp "$FAILURE_HOME/agents/deepseek_developer.toml" "$FAILURE_BEFORE/deepseek_developer.toml"

  if ( CUSTOM_SUBAGENT_FAIL_AFTER_WRITE="$boundary" \
    run_lifecycle "$FAILURE_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer ) \
    >/dev/null 2>&1; then
    fail "final uninstall failure boundary $boundary unexpectedly succeeded"
  fi
  assert_active_lifecycle_same "$FAILURE_BEFORE" "$FAILURE_HOME"
done

RESIDUE_HOME="$TEMP_ROOT/residue/home"
RESIDUE_BEFORE="$TEMP_ROOT/residue/before"
mkdir -p "$RESIDUE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$RESIDUE_HOME/config.toml"
install_developer "$RESIDUE_HOME"
rm "$RESIDUE_HOME/custom-subagents/state.json"
cp -Rp "$RESIDUE_HOME" "$RESIDUE_BEFORE"
if run_lifecycle "$RESIDUE_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer \
  >"$TEMP_ROOT/residue/uninstall.err" 2>&1; then
  fail 'state-absent uninstall with managed residue unexpectedly succeeded'
fi
assert_contains "$TEMP_ROOT/residue/uninstall.err" \
  'managed artifacts exist without lifecycle state; restore from backup or reconfigure custom subagents'
diff -r "$RESIDUE_BEFORE" "$RESIDUE_HOME" >/dev/null 2>&1 ||
  fail 'state-absent residue rejection mutated the home'

printf '%s\n' 'PASS: lifecycle cleanup'
