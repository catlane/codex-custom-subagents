#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-model-discovery.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
TEST_HOME="$TEMP_ROOT/codex-home"
STATE="$TEMP_ROOT/keychain-state"
LOG="$TEMP_ROOT/security.log"
CURL_LOG="$TEMP_ROOT/curl.log"
mkdir -p "$TEST_HOME"
: >"$STATE"
: >"$LOG"
: >"$CURL_LOG"

export FAKE_SECURITY_STATE="$STATE"
export FAKE_SECURITY_LOG="$LOG"
export FAKE_SECURITY_SECRET='test-secret-never-in-response'
export FAKE_CURL_LOG="$CURL_LOG"
export FAKE_MODEL_DISCOVERY_MODE=success
export CUSTOM_SUBAGENT_SECURITY_BIN="$ROOT/tests/helpers/fake-security.sh"
export CUSTOM_SUBAGENT_CURL_BIN="$ROOT/tests/helpers/fake-curl.sh"
export KEYCHAIN_SECURITY_BIN="$CUSTOM_SUBAGENT_SECURITY_BIN"
export MODEL_DISCOVERY_CURL_BIN="$CUSTOM_SUBAGENT_CURL_BIN"

. "$ROOT/shared/keychain.sh"
. "$ROOT/shared/model-discovery.sh"

assert_contains_text() {
  case "$1" in *"$2"*) ;; *) fail "missing '$2' in text" ;; esac
}

printf '%s|%s\n' 'codex-custom-subagent/deepseek-agent' api-key >"$STATE"
response=$(model_discovery_fetch 'https://api.deepseek.com' deepseek-agent)
assert_contains_text "$response" 'deepseek-v4-flash'
assert_contains_text "$response" 'deepseek-v4-pro'
models_json=$(model_discovery_parse "$response" "$ROOT/shared/model-discovery.js")
assert_equals '["deepseek-v4-flash","deepseek-v4-pro"]' "$models_json"
expected_lines=$(printf '%s\n%s' deepseek-v4-flash deepseek-v4-pro)
assert_equals "$expected_lines" "$(model_discovery_lines "$models_json" "$ROOT/shared/model-discovery.js")"
assert_contains "$CURL_LOG" 'https://api.deepseek.com/models'
assert_contains "$LOG" 'find|codex-custom-subagent/deepseek-agent|api-key'

export CUSTOM_SUBAGENT_TEST_MODE=1
export CUSTOM_SUBAGENT_TEST_SELECTED_MODEL=deepseek-v4-pro
assert_equals deepseek-v4-pro "$(model_discovery_resolve 'https://api.deepseek.com' deepseek-agent "$ROOT/shared/model-discovery.js" "$ROOT/shared/choose-model.js")"
unset CUSTOM_SUBAGENT_TEST_SELECTED_MODEL

set +e
FAKE_MODEL_DISCOVERY_MODE=unsupported model_discovery_resolve 'https://api.deepseek.com' deepseek-agent "$ROOT/shared/model-discovery.js" "$ROOT/shared/choose-model.js" >/dev/null 2>&1
unsupported_status=$?
FAKE_MODEL_DISCOVERY_MODE=malformed model_discovery_resolve 'https://api.deepseek.com' deepseek-agent "$ROOT/shared/model-discovery.js" "$ROOT/shared/choose-model.js" >/dev/null 2>&1
malformed_status=$?
set -e
assert_equals 78 "$unsupported_status"
assert_equals 78 "$malformed_status"

printf '%s\n' 'PASS: model discovery'
