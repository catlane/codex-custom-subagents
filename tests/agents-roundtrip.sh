#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE="$ROOT/tests/fixtures/models-cache.json"
export CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL=gpt-5.6-sol

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-agents-roundtrip.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

DEVELOPER_PLUGIN="$TEMP_ROOT/deepseek-developer"
REVIEWER_PLUGIN="$TEMP_ROOT/reviewer-agent"
mkdir -p "$DEVELOPER_PLUGIN/.codex-plugin" "$REVIEWER_PLUGIN/.codex-plugin"
cp "$ROOT/plugins/deepseek-developer/.codex-plugin/plugin.json" "$DEVELOPER_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$DEVELOPER_PLUGIN/agent-spec.json"
printf '%s\n' '{"name":"reviewer-agent"}' >"$REVIEWER_PLUGIN/.codex-plugin/plugin.json"
cp "$ROOT/tests/fixtures/agent-spec.json" "$REVIEWER_PLUGIN/agent-spec.json"

run_lifecycle() {
  test_home=$1
  plugin_root=$2
  shift 2
  CUSTOM_SUBAGENT_HOME="$test_home" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$plugin_root" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$plugin_root/agent-spec.json" \
  CUSTOM_SUBAGENT_ALLOW_HTTP=1 \
  sh "$ROOT/shared/lifecycle.sh" "$@"
}

assert_state_shape() {
  shape_state=$1
  shape_expected=$2
  actual=$(/usr/bin/osascript -l JavaScript -e \
    'ObjC.import("Foundation"); function run(argv) { const text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null)); const state = JSON.parse(text); return state.initial_agents_shape; }' \
    "$shape_state")
  assert_equals "$shape_expected" "$actual"
  if grep -E 'initial_agents_(content|text|bytes)|agents_(content|text|bytes)' "$shape_state" >/dev/null 2>&1; then
    fail "state persisted AGENTS.md content: $shape_state"
  fi
}

assert_missing_shape_rejected() {
  operation=$1
  output=$2
  shift 2
  if "$@" >"$output" 2>&1; then
    fail "$operation accepted state without initial_agents_shape"
  fi
  assert_contains "$output" 'state registry is missing initial AGENTS shape; restore from backup or reconfigure custom subagents'
}

assert_tree_bytes_unchanged() {
  expected_tree=$1
  actual_tree=$2
  diff -r "$expected_tree" "$actual_tree" >/dev/null 2>&1 ||
    fail "tree changed after rejected lifecycle operation: $actual_tree"
}

exercise_shape() {
  shape=$1
  case_home="$TEMP_ROOT/$shape/home"
  expected_path="$TEMP_ROOT/$shape/expected"
  mkdir -p "$case_home"
  cp "$ROOT/tests/fixtures/config-minimal.toml" "$case_home/config.toml"
  case "$shape" in
    absent)
      : >"$expected_path"
      ;;
    empty)
      : >"$case_home/AGENTS.md"
      : >"$expected_path"
      ;;
    ends-newline)
      printf '%s\n' 'Existing instructions.' >"$case_home/AGENTS.md"
      cp "$case_home/AGENTS.md" "$expected_path"
      ;;
    no-final-newline)
      printf '%s' 'Existing instructions.' >"$case_home/AGENTS.md"
      cp "$case_home/AGENTS.md" "$expected_path"
      ;;
    *)
      fail "unknown test shape: $shape"
      ;;
  esac

  run_lifecycle "$case_home" "$DEVELOPER_PLUGIN" \
    install deepseek-developer development deepseek http://localhost:11434 fixture-model
  assert_state_shape "$case_home/custom-subagents/state.json" "$shape"

  run_lifecycle "$case_home" "$REVIEWER_PLUGIN" \
    install reviewer-agent review volcengine http://localhost:11434 fixture-model-2
  assert_state_shape "$case_home/custom-subagents/state.json" "$shape"

  run_lifecycle "$case_home" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
  assert_state_shape "$case_home/custom-subagents/state.json" "$shape"
  run_lifecycle "$case_home" "$REVIEWER_PLUGIN" uninstall reviewer-agent

  if [ "$shape" = absent ]; then
    assert_not_file "$case_home/AGENTS.md"
  else
    assert_same_file "$expected_path" "$case_home/AGENTS.md"
  fi
}

for shape in absent empty ends-newline no-final-newline; do
  exercise_shape "$shape"
done

exercise_config_shape() {
  config_shape=$1
  config_home="$TEMP_ROOT/config-$config_shape/home"
  config_expected="$TEMP_ROOT/config-$config_shape/expected"
  mkdir -p "$config_home"
  case "$config_shape" in
    absent)
      :
      ;;
    empty)
      : >"$config_home/config.toml"
      : >"$config_expected"
      ;;
    ends-newline)
      cp "$ROOT/tests/fixtures/config-minimal.toml" "$config_home/config.toml"
      cp "$config_home/config.toml" "$config_expected"
      ;;
    no-final-newline)
      printf '%s' 'model = "gpt-5.6-sol"' >"$config_home/config.toml"
      cp "$config_home/config.toml" "$config_expected"
      ;;
    *)
      fail "unknown config shape: $config_shape"
      ;;
  esac

  run_lifecycle "$config_home" "$DEVELOPER_PLUGIN" \
    install deepseek-developer development deepseek http://localhost:11434 fixture-model
  assert_contains "$config_home/custom-subagents/state.json" \
    "\"initial_config_shape\": \"$config_shape\""
  run_lifecycle "$config_home" "$DEVELOPER_PLUGIN" uninstall deepseek-developer

  if [ "$config_shape" = absent ]; then
    assert_not_file "$config_home/config.toml"
  else
    assert_same_file "$config_expected" "$config_home/config.toml"
  fi
}

for config_shape in absent empty ends-newline no-final-newline; do
  exercise_config_shape "$config_shape"
done

SUFFIX_HOME="$TEMP_ROOT/post-install-suffix/home"
SUFFIX_EXPECTED="$TEMP_ROOT/post-install-suffix/expected"
mkdir -p "$SUFFIX_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$SUFFIX_HOME/config.toml"
printf '%s\n' 'Existing instructions.' >"$SUFFIX_HOME/AGENTS.md"
run_lifecycle "$SUFFIX_HOME" "$DEVELOPER_PLUGIN" \
  install deepseek-developer development deepseek http://localhost:11434 fixture-model
printf '%s\n' 'User prefix added after install.' >"$SUFFIX_HOME/AGENTS.md.with-prefix"
cat "$SUFFIX_HOME/AGENTS.md" >>"$SUFFIX_HOME/AGENTS.md.with-prefix"
mv "$SUFFIX_HOME/AGENTS.md.with-prefix" "$SUFFIX_HOME/AGENTS.md"
printf '%s' 'User suffix added after install.' >>"$SUFFIX_HOME/AGENTS.md"
printf '%s\n%s\n%s' \
  'User prefix added after install.' \
  'Existing instructions.' \
  'User suffix added after install.' >"$SUFFIX_EXPECTED"

run_lifecycle "$SUFFIX_HOME" "$REVIEWER_PLUGIN" \
  install reviewer-agent review volcengine http://localhost:11434 fixture-model-2
assert_state_shape "$SUFFIX_HOME/custom-subagents/state.json" ends-newline
run_lifecycle "$SUFFIX_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
run_lifecycle "$SUFFIX_HOME" "$REVIEWER_PLUGIN" uninstall reviewer-agent
assert_same_file "$SUFFIX_EXPECTED" "$SUFFIX_HOME/AGENTS.md"

MISSING_SHAPE_HOME="$TEMP_ROOT/missing-shape/home"
MISSING_SHAPE_BEFORE="$TEMP_ROOT/missing-shape/before"
mkdir -p "$MISSING_SHAPE_HOME"
cp "$ROOT/tests/fixtures/config-minimal.toml" "$MISSING_SHAPE_HOME/config.toml"
run_lifecycle "$MISSING_SHAPE_HOME" "$DEVELOPER_PLUGIN" \
  install deepseek-developer development deepseek http://localhost:11434 fixture-model
sed '/"initial_agents_shape":/d' \
  "$MISSING_SHAPE_HOME/custom-subagents/state.json" \
  >"$MISSING_SHAPE_HOME/custom-subagents/state.json.without-shape"
mv "$MISSING_SHAPE_HOME/custom-subagents/state.json.without-shape" \
  "$MISSING_SHAPE_HOME/custom-subagents/state.json"
cp -Rp "$MISSING_SHAPE_HOME" "$MISSING_SHAPE_BEFORE"

assert_missing_shape_rejected reinstall "$TEMP_ROOT/missing-shape/reinstall.err" \
  run_lifecycle "$MISSING_SHAPE_HOME" "$DEVELOPER_PLUGIN" \
  install deepseek-developer development deepseek http://localhost:11434 fixture-model
assert_tree_bytes_unchanged "$MISSING_SHAPE_BEFORE" "$MISSING_SHAPE_HOME"

assert_missing_shape_rejected uninstall "$TEMP_ROOT/missing-shape/uninstall.err" \
  run_lifecycle "$MISSING_SHAPE_HOME" "$DEVELOPER_PLUGIN" uninstall deepseek-developer
assert_tree_bytes_unchanged "$MISSING_SHAPE_BEFORE" "$MISSING_SHAPE_HOME"

printf '%s\n' 'PASS: AGENTS round-trip'
