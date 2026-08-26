#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-state.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

STATE="$TEMP_ROOT/state.json"
STATE_TARGET="$TEMP_ROOT/state-target.json"
STATE_LINK="$TEMP_ROOT/state-link.json"
ENDPOINT='https://example.test/v1'
OTHER_ENDPOINT='https://other.example.test/v1'

printf '%s\n' '{"version":1,"catalog_path":"/tmp/models-v1.json","base_catalog_path":"/tmp/base-model-catalog.json","base_catalog_source":"/tmp/models-cache.json","base_catalog_source_kind":"test-override","primary_model":"gpt-5.6-sol","initial_agents_shape":"absent","initial_config_shape":"ends-newline","original_model_catalog_line":null,"agents":[{"id":"deepseek-agent","provider":"deepseek","endpoint":"https://example.test/v1","model":"fixture-model"}]}' >"$STATE"

state_status() {
  /usr/bin/osascript -l JavaScript "$ROOT/shared/state.js" \
    keychain-binding-status "$1" "$2" "$3"
}

state_command() {
  /usr/bin/osascript -l JavaScript "$ROOT/shared/state.js" "$@"
}

assert_rejected_without_endpoint() {
  label=$1
  forbidden_endpoint=$2
  shift 2
  if "$@" >"$TEMP_ROOT/$label.out" 2>"$TEMP_ROOT/$label.err"; then
    fail "$label was accepted"
  fi
  if grep -F -- "$forbidden_endpoint" "$TEMP_ROOT/$label.out" "$TEMP_ROOT/$label.err" >/dev/null 2>&1; then
    fail "$label leaked endpoint"
  fi
  [ ! -s "$TEMP_ROOT/$label.out" ] || fail "$label wrote stdout"
}

assert_equals match "$(state_status "$STATE" deepseek-agent "$ENDPOINT")"
assert_equals mismatch "$(state_status "$STATE" deepseek-agent "$OTHER_ENDPOINT")"
assert_equals absent "$(state_status "$STATE" missing-provider "$ENDPOINT")"
assert_equals 1 "$(state_command provider-present "$STATE" deepseek-agent)"
assert_equals 0 "$(state_command provider-present "$STATE" missing-provider)"
state_command validate-provider-input deepseek-agent deepseek "$ENDPOINT" fixture-model >/dev/null

# State keeps exactly one record per provider; fixed-role records and duplicate IDs fail closed.
printf '%s\n' '{"version":1,"catalog_path":"/tmp/models-v1.json","base_catalog_path":"/tmp/base-model-catalog.json","base_catalog_source":"/tmp/models-cache.json","base_catalog_source_kind":"test-override","primary_model":"gpt-5.6-sol","initial_agents_shape":"absent","initial_config_shape":"ends-newline","original_model_catalog_line":null,"agents":[{"id":"deepseek-agent","role":"development","provider":"deepseek","endpoint":"https://example.test/v1","model":"fixture-model"}]}' >"$TEMP_ROOT/fixed-role.json"
assert_rejected_without_endpoint fixed-role-state "$ENDPOINT" state_command read "$TEMP_ROOT/fixed-role.json"

printf '%s\n' '{"version":1,"catalog_path":"/tmp/models-v1.json","base_catalog_path":"/tmp/base-model-catalog.json","base_catalog_source":"/tmp/models-cache.json","base_catalog_source_kind":"test-override","primary_model":"gpt-5.6-sol","initial_agents_shape":"absent","initial_config_shape":"ends-newline","original_model_catalog_line":null,"agents":[{"id":"deepseek-agent","provider":"deepseek","endpoint":"https://example.test/v1","model":"fixture-model"},{"id":"deepseek-agent","provider":"deepseek","endpoint":"https://example.test/v1","model":"other-model"}]}' >"$TEMP_ROOT/duplicate.json"
assert_rejected_without_endpoint duplicate-provider "$ENDPOINT" state_command read "$TEMP_ROOT/duplicate.json"

printf '%s\n' '{not-json' >"$TEMP_ROOT/malformed.json"
assert_rejected_without_endpoint malformed-state "$ENDPOINT" state_status "$TEMP_ROOT/malformed.json" deepseek-agent "$ENDPOINT"
assert_rejected_without_endpoint missing-state "$ENDPOINT" state_status "$TEMP_ROOT/missing.json" deepseek-agent "$ENDPOINT"

mkdir "$TEMP_ROOT/state-directory"
assert_rejected_without_endpoint state-read-error "$ENDPOINT" state_status "$TEMP_ROOT/state-directory" deepseek-agent "$ENDPOINT"

cp "$STATE" "$STATE_TARGET"
ln -s "$STATE_TARGET" "$STATE_LINK"
assert_rejected_without_endpoint symlink-state "$ENDPOINT" state_status "$STATE_LINK" deepseek-agent "$ENDPOINT"

assert_rejected_without_endpoint invalid-requested-endpoint 'https://user:password@example.test' \
  state_status "$STATE" deepseek-agent 'https://user:password@example.test'

printf '%s\n' 'PASS: lifecycle provider state commands'
