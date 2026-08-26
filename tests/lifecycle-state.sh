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

printf '%s\n' '{"version":1,"catalog_path":"/tmp/models-v1.json","base_catalog_path":"/tmp/base-model-catalog.json","base_catalog_source":"/tmp/models-cache.json","base_catalog_source_kind":"test-override","primary_model":"gpt-5.6-sol","initial_agents_shape":"absent","initial_config_shape":"ends-newline","original_model_catalog_line":null,"agents":[{"id":"deepseek-developer","role":"development","provider":"deepseek","endpoint":"https://example.test/v1","model":"fixture-model"}]}' >"$STATE"

state_status() {
  /usr/bin/osascript -l JavaScript "$ROOT/shared/state.js" \
    keychain-binding-status "$1" "$2" "$3"
}

assert_equals match "$(state_status "$STATE" deepseek-developer "$ENDPOINT")"
assert_equals mismatch "$(state_status "$STATE" deepseek-developer "$OTHER_ENDPOINT")"
assert_equals absent "$(state_status "$STATE" missing-agent "$ENDPOINT")"

assert_rejected_without_endpoint() {
  label=$1
  forbidden_endpoint=$2
  stdout_file=$3
  stderr_file=$4
  shift 4
  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    fail "$label was accepted"
  fi
  if grep -F -- "$forbidden_endpoint" "$stdout_file" "$stderr_file" >/dev/null 2>&1; then
    fail "$label leaked endpoint"
  fi
  [ ! -s "$stdout_file" ] || fail "$label wrote stdout"
}

printf '%s\n' '{not-json' >"$TEMP_ROOT/malformed.json"
assert_rejected_without_endpoint malformed-state "$ENDPOINT" \
  "$TEMP_ROOT/malformed.out" "$TEMP_ROOT/malformed.err" \
  state_status "$TEMP_ROOT/malformed.json" deepseek-developer "$ENDPOINT"

assert_rejected_without_endpoint missing-state "$ENDPOINT" \
  "$TEMP_ROOT/missing.out" "$TEMP_ROOT/missing.err" \
  state_status "$TEMP_ROOT/missing.json" deepseek-developer "$ENDPOINT"

mkdir "$TEMP_ROOT/state-directory"
assert_rejected_without_endpoint state-read-error "$ENDPOINT" \
  "$TEMP_ROOT/read-error.out" "$TEMP_ROOT/read-error.err" \
  state_status "$TEMP_ROOT/state-directory" deepseek-developer "$ENDPOINT"

cp "$STATE" "$STATE_TARGET"
ln -s "$STATE_TARGET" "$STATE_LINK"
assert_rejected_without_endpoint symlink-state "$ENDPOINT" \
  "$TEMP_ROOT/symlink.out" "$TEMP_ROOT/symlink.err" \
  state_status "$STATE_LINK" deepseek-developer "$ENDPOINT"

assert_rejected_without_endpoint invalid-requested-endpoint 'https://user:password@example.test' \
  "$TEMP_ROOT/invalid-endpoint.out" "$TEMP_ROOT/invalid-endpoint.err" \
  state_status "$STATE" deepseek-developer 'https://user:password@example.test'

printf '%s\n' 'PASS: lifecycle state commands'
